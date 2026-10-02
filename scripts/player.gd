extends CharacterBody3D
## Third-person police officer: over-the-shoulder camera, sprint, crouch, aim (zoom + aim assist),
## shoot, reload, weapon swap (rifle / Glock / sniper rifle with scope).

const Person = preload("res://scripts/person.gd")
const Fx = preload("res://scripts/fx.gd")

signal shot_fired(pos: Vector3)

var main: Node
var model: Node3D
var anim: AnimationPlayer
var pivot: Node3D
var spring: SpringArm3D
var cam: Camera3D
var gun: Node3D
var muzzle: Marker3D
var shape: CollisionShape3D
var yaw := 0.0
var pitch := -0.1
var hp := 100.0
var alive := true
var ammo := 30
var reserve := 150
## fov: camera field of view while aiming (smaller = more zoom)
const WEAPONS := {
	"rifle": {"name": "RM-277", "mag": 30, "cd": 0.08, "dmg": 34.0, "spread": 0.02, "reload": 2.0, "sound": "rifle", "kick": 0.009, "fov": 22.0, "auto": true},
	"pistol": {"name": "Glock 17", "mag": 17, "cd": 0.2, "dmg": 30.0, "spread": 0.014, "reload": 1.3, "sound": "pistol", "kick": 0.02, "fov": 50.0, "auto": false},
	"sniper": {"name": "M24", "mag": 5, "cd": 1.25, "dmg": 220.0, "spread": 0.05, "reload": 2.6, "sound": "sniper", "kick": 0.05, "fov": 11.0, "auto": false},
}
var weapon := "rifle"
var primary := "rifle"
var bag := {"rifle": [30, 150], "pistol": [17, 68], "sniper": [5, 25]}
var switch_t := 0.0
var _semi_ready := true
var fire_cd := 0.0
var reload_t := 0.0
var aim := 0.0
var last_hit := -10.0
var recoil := 0.0
var bloom := 0.0              # extra spread from firing / moving (drives the crosshair too)
var crouch := false
var crouch_k := 0.0
var scoped := false
var on_target := false        # crosshair is over a gunman
var assist_t := 0.0
var assist_yaw := 0.0
var assist_pitch := 0.0
var cur_anim := ""
var active := true
var step_t := 0.0
var face := 0.0          # model yaw relative to the camera heading
var leg := 0.0           # hips/legs yaw under a torso that keeps facing the sights (strafing)
var lean := 0.0
var stride := 0.0
var air_t := 0.0
var land_dip := 0.0
var stats := {"shots": 0, "hits": 0, "kills": 0, "heads": 0}
var _cap: CapsuleShape3D

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	floor_max_angle = deg_to_rad(58.0)   # curbs and steps don't stop you
	floor_snap_length = 0.35
	shape = CollisionShape3D.new()
	_cap = CapsuleShape3D.new(); _cap.radius = 0.35; _cap.height = 1.8
	shape.shape = _cap; shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	model = Person.new("swat", 1)
	add_child(model)
	anim = model.anim
	gun = model.gun
	muzzle = model.muzzle
	pivot = Node3D.new(); pivot.position = Vector3(0.55, 1.6, 0)
	add_child(pivot)
	spring = SpringArm3D.new(); spring.spring_length = 2.8; spring.margin = 0.2
	spring.collision_mask = 1
	pivot.add_child(spring)
	spring.add_excluded_object(get_rid())
	cam = Camera3D.new(); cam.fov = 68; cam.far = 1200
	spring.add_child(cam)

func set_active(on: bool) -> void:
	active = on
	visible = on
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = not on
	if on:
		cam.current = true

## Sniper missions: the long rifle replaces the assault rifle (the Glock stays as sidearm).
func give_sniper() -> void:
	primary = "sniper"
	if weapon != "sniper":
		bag[weapon] = [ammo, reserve]
		weapon = "sniper"
		ammo = bag.sniper[0]; reserve = bag.sniper[1]
		model.set_weapon("sniper")
		gun = model.gun
		muzzle = model.muzzle

func _frozen() -> bool:
	return main != null and main.get("cutscene_t") != null and main.cutscene_t > 0.0

func _physics_process(dt: float) -> void:
	if not active:
		return
	fire_cd -= dt
	if not alive:
		velocity = Vector3.ZERO
		return
	if _frozen():
		velocity.x = 0; velocity.z = 0
		if not is_on_floor():
			velocity.y -= 9.8 * dt
		move_and_slide()
		model.play("Idle")
		Controls.consume_look()
		return
	var w: Dictionary = WEAPONS[weapon]
	var aiming := Controls.held("aim")
	# fine aim: slower look while zoomed (proportional to zoom)
	var look := Controls.consume_look() * lerpf(1.0, cam.fov / 68.0 * 1.25, aim)
	yaw -= look.x
	pitch = clampf(pitch - look.y, -1.2, 0.85)
	# aim assist: pressing aim snaps gently onto a gunman near the crosshair
	if Controls.just("aim"):
		_aim_assist()
	if assist_t > 0.0:
		assist_t -= dt
		var k := 1.0 - exp(-dt * 18.0)
		yaw = lerp_angle(yaw, assist_yaw, k)
		pitch = lerpf(pitch, assist_pitch, k)
	rotation.y = yaw
	pivot.rotation.x = pitch
	aim = lerpf(aim, 1.0 if aiming else 0.0, 1.0 - exp(-dt * 12.0))
	# crouch toggle
	if Controls.just("crouch"):
		crouch = not crouch
		if not crouch and not _can_stand():
			crouch = true
	crouch_k = move_toward(crouch_k, 1.0 if crouch else 0.0, dt * 5.0)
	_cap.height = lerpf(1.8, 1.2, crouch_k)
	shape.position.y = _cap.height * 0.5
	model.set_crouch(crouch_k)
	# sights up = looking through the optic: the rifle has a 4x combat sight, the M24 its long scope;
	# the Glock keeps the over-the-shoulder zoom
	scoped = weapon != "pistol" and aim > 0.75
	spring.spring_length = 0.0 if scoped else lerpf(2.8, 1.25, aim)
	pivot.position.x = 0.0 if scoped else lerpf(0.55, 0.72, aim)
	# scoped while crouched = rifle rested on the parapet / cover, eye just over it
	pivot.position.y = lerpf(1.6, 1.12, crouch_k) if not scoped else lerpf(1.62, 1.38, crouch_k)
	cam.fov = lerpf(68.0, float(w.fov), aim)
	model.visible = not scoped
	var mv := Controls.move_vector()
	var mag := mv.length()
	var sprint := Controls.held("sprint") and mv.y > 0.3 and aim < 0.3 and not Controls.held("fire")
	if sprint and crouch:
		crouch = not _can_stand()
	# three real gaits: a walk on a light stick push, a jog on a full push, a sprint on top
	var spd := 6.6 if sprint else (2.0 if mag < 0.62 else 4.0)
	if mv.y < -0.3 and not sprint:
		spd = minf(spd, 2.6)          # nobody jogs backwards
	if crouch_k > 0.5:
		spd = 1.9
	if aim > 0.5:
		spd = minf(spd, 2.0 if weapon != "sniper" else 1.2)
	var dir := (-transform.basis.z * mv.y + transform.basis.x * mv.x)
	if mag > 0.05:
		dir = dir.normalized()
	else:
		dir = Vector3.ZERO
	var target := dir * spd
	# weight: it takes a moment to get going and a moment to stop; less grip in the air
	var hv := Vector3(velocity.x, 0, velocity.z)
	var rate := (11.0 if target.length() > hv.length() else 16.0) if is_on_floor() else 3.0
	hv = hv.move_toward(target, rate * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if air_t > 0.25:
			land_dip = minf(0.12, air_t * 0.2)      # knees absorb the landing
			Sfx.play("step", -8.0, 0.8)
		air_t = 0.0
		if Controls.just("jump"):
			if crouch:
				crouch = not _can_stand()
			else:
				velocity.y = 4.8
	else:
		air_t += dt
		velocity.y -= 9.8 * dt
	var pre := global_position
	move_and_slide()
	_step_up(dir, pre, dt)
	var hs := Vector2(velocity.x, velocity.z).length()
	# the body turns into the direction of travel (like a real person running), and squares up
	# with the camera again as soon as the weapon comes up
	var armed := aim > 0.15 or fire_cd > -0.7 or reload_t > 0.0
	var face_target := 0.0
	if hs > 0.5 and mag > 0.1 and not armed:
		face_target = atan2(-mv.x, mv.y)
	face = lerp_angle(face, face_target, 1.0 - exp(-dt * (16.0 if armed else 9.0)))
	model.rotation.y = face
	# weapon up and moving sideways or backwards: the legs turn toward the way you are going while
	# the chest and rifle stay on the sights; walking backwards plays the stride in reverse
	var leg_target := 0.0
	var backpedal := false
	if armed and hs > 0.5 and mag > 0.1:
		var th := atan2(-mv.x, mv.y)
		if absf(th) > deg_to_rad(112.0):
			backpedal = true
			th = wrapf(th + PI, -PI, PI)
		leg_target = clampf(th, -1.15, 1.15)
	leg = lerp_angle(leg, leg_target, 1.0 - exp(-dt * 10.0))
	model.set_leg_yaw(leg)
	# lean into the run a little
	lean = lerpf(lean, clampf(hs / 6.6, 0.0, 1.0) * (0.12 if not armed else 0.03), 1.0 - exp(-dt * 6.0))
	model.rotation.x = -lean
	# footsteps + head bob follow the stride
	if is_on_floor() and hs > 0.6:
		stride += dt * (hs / (1.45 if hs < 2.8 else 2.3))
		if stride >= 1.0:
			stride -= 1.0
			Sfx.play("step", (-17.0 if hs < 2.8 else (-13.0 if hs < 5.0 else -10.0)) - crouch_k * 6.0, randf_range(0.85, 1.15))
	else:
		stride = 0.0
	var bob := sin(stride * TAU) * clampf(hs / 6.6, 0.0, 1.0) * 0.045 * (1.0 - aim * 0.7)
	land_dip = move_toward(land_dip, 0.0, dt * 0.5)
	pivot.position.y += bob - land_dip
	if sprint:
		cam.fov += 5.0 * clampf((hs - 4.0) / 2.6, 0.0, 1.0)
	var want := "Idle"
	if hs > 2.9:
		want = "Run"
	elif hs > 0.35:
		want = "Walk"
	model.play(want, (clampf(hs / (5.4 if want == "Run" else 1.7), 0.72, 1.35) * (-1.0 if backpedal else 1.0)) if want != "Idle" else 1.0)
	# spread bloom: moving and firing open the crosshair, standing still / crouching closes it
	var bloom_rest := clampf(hs / 6.0, 0.0, 1.0) * 0.6 * (1.0 - crouch_k * 0.5)
	bloom = lerpf(bloom, bloom_rest, 1.0 - exp(-dt * 5.0))
	# weapon
	model.set_aim(lerpf(model.aim_pitch, pitch * 0.8 if (aim > 0.2 or fire_cd > -0.8) and absf(face) < 0.5 else -0.35, 1.0 - exp(-dt * 12.0)))
	if reload_t > 0.0:
		reload_t -= dt
		gun.rotation.z = sin(reload_t * 4.0) * 0.5
		if reload_t <= 0.0:
			var take: int = mini(int(w.mag) - ammo, reserve)
			ammo += take; reserve -= take
			gun.rotation.z = 0.0
	if not Controls.held("fire"):
		_semi_ready = true
	if switch_t > 0.0:
		switch_t -= dt
	elif Controls.just("switch") and reload_t <= 0.0:
		switch_weapon()
	elif reload_t > 0.0:
		pass
	elif Controls.just("reload") and ammo < int(w.mag) and reserve > 0:
		_reload()
	elif Controls.held("fire") and fire_cd <= 0.0 and not sprint and (bool(w.auto) or _semi_ready):
		if ammo > 0:
			_semi_ready = false
			_shoot()
		elif reserve > 0:
			_reload()
		elif bag["pistol" if weapon != "pistol" else primary][0] > 0:
			switch_weapon()
	_update_on_target()
	if Time.get_ticks_msec() / 1000.0 - last_hit > 5.0 and hp < 100.0:
		hp = minf(100.0, hp + 12.0 * dt)

## Small ledges (curbs, steps up to 40 cm): if we walked into one, hop onto it.
func _step_up(dir: Vector3, pre: Vector3, _dt: float) -> void:
	if dir.length() < 0.2 or not is_on_wall():
		return
	var moved := Vector2(global_position.x - pre.x, global_position.z - pre.z).length()
	if moved > 0.02:
		return
	var fwd := Vector3(dir.x, 0, dir.z).normalized() * 0.3
	var up := Transform3D(global_basis, global_position + Vector3(0, 0.42, 0))
	if test_move(global_transform, Vector3(0, 0.42, 0)):
		return
	if test_move(up, fwd):
		return
	global_position += Vector3(0, 0.42, 0) + fwd
	velocity.y = 0.0

func _can_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.3; cap.height = 1.7
	q.shape = cap
	q.transform = Transform3D(Basis(), global_position + Vector3(0, 0.95, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func _aim_assist() -> void:
	if not main:
		return
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	var best = null
	var best_a := deg_to_rad(9.0 if Controls.is_touch else 5.0)
	if weapon == "sniper":
		best_a = deg_to_rad(3.0)
	for e in main.enemies:
		if e.dead or e.surrendered:
			continue
		var tp: Vector3 = e.global_position + Vector3(0, 1.25, 0)
		var to := tp - from
		if to.length() > 90.0:
			continue
		var a := fwd.angle_to(to)
		if a < best_a:
			var q := PhysicsRayQueryParameters3D.create(from, tp, 1 | 8)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				best_a = a; best = tp
	if best != null:
		var to: Vector3 = best - cam.global_position
		assist_yaw = atan2(-to.x, -to.z)
		assist_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.2, 0.85)
		assist_t = 0.18

func _update_on_target() -> void:
	on_target = false
	if aim < 0.3 or not main:
		return
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 150.0, 1 | 2 | 8)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider and hit.collider.get("side") == "enemy" and not hit.collider.dead and not hit.collider.surrendered:
		on_target = true

func _reload() -> void:
	reload_t = float(WEAPONS[weapon].reload)
	Sfx.play("reload", -6.0, 1.2 if weapon == "pistol" else (0.85 if weapon == "sniper" else 1.0))

## Primary (rifle or sniper) <-> Glock. Each weapon keeps its own magazine and reserve.
func switch_weapon() -> void:
	bag[weapon] = [ammo, reserve]
	weapon = "pistol" if weapon != "pistol" else primary
	ammo = bag[weapon][0]; reserve = bag[weapon][1]
	switch_t = 0.45
	fire_cd = maxf(fire_cd, 0.45)
	model.set_weapon(weapon)
	gun = model.gun
	muzzle = model.muzzle
	Sfx.play("cuff", -10.0, 0.8)

func _shoot() -> void:
	var w: Dictionary = WEAPONS[weapon]
	fire_cd = float(w.cd)
	ammo -= 1
	stats.shots += 1
	var spread := lerpf(float(w.spread), 0.004 if weapon != "sniper" else 0.0004, aim) * (1.0 + bloom) * (1.0 - crouch_k * 0.3)
	bloom = minf(bloom + (0.25 if bool(w.auto) else 0.5), 2.0)
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	fwd = (fwd + cam.global_basis.x * randf_range(-spread, spread) + cam.global_basis.y * randf_range(-spread, spread)).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 400.0, 1 | 2 | 8 | 32)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + fwd * 400.0
	var mpos := muzzle.global_position
	if hit:
		end = hit.position
		var col: Object = hit.collider
		if col and col.has_method("take_hit"):
			var head: bool = hit.position.y - col.global_position.y > 1.48
			var killed: bool = col.take_hit(float(w.dmg) * (3.2 if head else 1.0), head, self)
			stats.hits += 1
			if main:
				main.on_player_hit(killed, head)
			if col is AnimatableBody3D:
				Fx.particles(main, hit.position, hit.normal, "spark", 10)
				Sfx.play_3d("crash_small", hit.position, -14.0, 2.2)
			else:
				Fx.blood_hit(main, hit.position, fwd, hit.normal)
				Sfx.play_3d("flesh", hit.position, -4.0)
		else:
			Fx.particles(main, hit.position, hit.normal, "spark", 8)
			Fx.particles(main, hit.position, hit.normal, "dust", 4)
			if col is StaticBody3D:
				Fx.bullet_hole(main, hit.position, hit.normal)
	if not scoped:
		Fx.tracer(main, mpos, end)
		Fx.flash(main, mpos, 3.0)
		Fx.muzzle(main, muzzle)
	elif weapon == "rifle":
		# through the optic you still see the shot go and the flash light up what is near
		Fx.tracer(main, from + fwd * 2.5 - cam.global_basis.y * 0.12, end)
		Fx.flash(main, from + fwd * 0.8, 2.0)
	Sfx.play(str(w.sound), -4.0 if weapon != "sniper" else 0.0, randf_range(0.95, 1.05))
	pitch += float(w.kick)
	yaw += randf_range(-0.006, 0.006) * (3.0 if weapon == "sniper" else 1.0)
	if weapon == "sniper":
		get_tree().create_timer(0.45).timeout.connect(func(): Sfx.play("bolt", -6.0))
	else:
		shot_fired.emit(global_position)   # the suppressed sniper rifle doesn't give the shooter away

func take_hit(dmg: float, _head := false, from: Node3D = null) -> bool:
	if not alive:
		return false
	hp -= dmg
	last_hit = Time.get_ticks_msec() / 1000.0
	if main:
		main.on_player_damaged(from)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		model.visible = true
		Controls.aim_toggle = false
		model.collapse(1.0)
		if main:
			get_tree().create_timer(0.9).timeout.connect(func(): Fx.blood_pool(main, model.fallen_center()))
		if main:
			main.on_player_dead()
		return true
	return false

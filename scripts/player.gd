extends CharacterBody3D
## Third-person police officer: over-the-shoulder camera, sprint, aim, shoot, reload.

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
var yaw := 0.0
var pitch := -0.1
var hp := 100.0
var alive := true
var ammo := 30
var reserve := 150
## weapons: rifle (auto) and Glock sidearm (semi-auto, quick to reload)
const WEAPONS := {
	"rifle": {"name": "RM-277", "mag": 30, "cd": 0.08, "dmg": 34.0, "spread": 0.02, "reload": 2.0, "sound": "rifle", "kick": 0.012},
	"pistol": {"name": "Glock 17", "mag": 17, "cd": 0.2, "dmg": 30.0, "spread": 0.014, "reload": 1.3, "sound": "pistol", "kick": 0.02},
}
var weapon := "rifle"
var bag := {"rifle": [30, 150], "pistol": [17, 68]}
var switch_t := 0.0
var _semi_ready := true
var fire_cd := 0.0
var reload_t := 0.0
var aim := 0.0
var last_hit := -10.0
var recoil := 0.0
var cur_anim := ""
var active := true
var step_t := 0.0
var stats := {"shots": 0, "hits": 0, "kills": 0, "heads": 0}

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.8
	cs.shape = cap; cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
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

func _physics_process(dt: float) -> void:
	if not active:
		return
	fire_cd -= dt
	if not alive:
		velocity = Vector3.ZERO
		return
	var look := Controls.consume_look()
	yaw -= look.x
	pitch = clampf(pitch - look.y + recoil * dt * 0.0, -1.2, 0.85)
	rotation.y = yaw
	pivot.rotation.x = pitch
	var aiming := Controls.held("aim")
	aim = lerpf(aim, 1.0 if aiming else 0.0, 1.0 - exp(-dt * 12.0))
	spring.spring_length = lerpf(2.8, 1.35, aim)
	pivot.position.x = lerpf(0.55, 0.7, aim)
	cam.fov = lerpf(68.0, 50.0, aim)
	var mv := Controls.move_vector()
	var sprint := Controls.held("sprint") and mv.y > 0.3 and aim < 0.3 and not Controls.held("fire")
	var spd := 7.2 if sprint else 4.2
	if aim > 0.5:
		spd = 2.6
	var dir := (-transform.basis.z * mv.y + transform.basis.x * mv.x)
	var target := dir * spd
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-dt * 10.0))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-dt * 10.0))
	if is_on_floor():
		if Controls.just("jump"):
			velocity.y = 4.8
	else:
		velocity.y -= 9.8 * dt
	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	# footsteps
	if is_on_floor() and hs > 0.6:
		step_t -= dt
		if step_t <= 0.0:
			step_t = 0.3 if hs > 5.0 else 0.48
			Sfx.play("step", -16.0 if hs < 5.0 else -11.0, randf_range(0.85, 1.15))
	var want := "Idle"
	if hs > 4.6:
		want = "Run"
	elif hs > 0.4:
		want = "Walk"
	model.play(want, clampf(hs / (5.5 if want == "Run" else 1.6), 0.7, 1.6) if want != "Idle" else 1.0)
	# weapon
	model.set_aim(lerpf(model.aim_pitch, pitch * 0.8 if aim > 0.2 or fire_cd > -0.8 else -0.35, 1.0 - exp(-dt * 12.0)))
	if reload_t > 0.0:
		reload_t -= dt
		gun.rotation.z = sin(reload_t * 4.0) * 0.5
		if reload_t <= 0.0:
			var take: int = mini(int(WEAPONS[weapon].mag) - ammo, reserve)
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
	elif Controls.just("reload") and ammo < int(WEAPONS[weapon].mag) and reserve > 0:
		_reload()
	elif Controls.held("fire") and fire_cd <= 0.0 and not sprint and (weapon == "rifle" or _semi_ready):
		if ammo > 0:
			_semi_ready = false
			_shoot()
		elif reserve > 0:
			_reload()
		elif bag["pistol" if weapon == "rifle" else "rifle"][0] > 0:
			switch_weapon()
	if Time.get_ticks_msec() / 1000.0 - last_hit > 5.0 and hp < 100.0:
		hp = minf(100.0, hp + 12.0 * dt)

func _reload() -> void:
	reload_t = float(WEAPONS[weapon].reload)
	Sfx.play("reload", -6.0, 1.2 if weapon == "pistol" else 1.0)

## Rifle <-> Glock. Each weapon keeps its own magazine and reserve.
func switch_weapon() -> void:
	bag[weapon] = [ammo, reserve]
	weapon = "pistol" if weapon == "rifle" else "rifle"
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
	var spread := lerpf(float(w.spread), 0.004, aim)
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	fwd = (fwd + cam.global_basis.x * randf_range(-spread, spread) + cam.global_basis.y * randf_range(-spread, spread)).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 250.0, 1 | 2 | 8 | 32)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + fwd * 250.0
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
	Fx.tracer(main, mpos, end)
	Fx.flash(main, mpos, 3.0)
	Fx.muzzle(main, muzzle)
	Sfx.play(str(w.sound), -4.0, randf_range(0.95, 1.05))
	pitch += float(w.kick)
	yaw += randf_range(-0.006, 0.006)
	shot_fired.emit(global_position)

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
		model.anim.pause()
		model.set_mode("none")
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", -PI / 2, 0.6)
		if main:
			get_tree().create_timer(0.7).timeout.connect(func(): Fx.blood_pool(main, global_position))
		if main:
			main.on_player_dead()
		return true
	return false

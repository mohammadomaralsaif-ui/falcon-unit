extends CharacterBody3D
## Third-person police officer: over-the-shoulder camera, sprint, aim, shoot, reload.

const Humanoid = preload("res://scripts/humanoid.gd")
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
var fire_cd := 0.0
var reload_t := 0.0
var aim := 0.0
var last_hit := -10.0
var recoil := 0.0
var cur_anim := ""
var active := true
var stats := {"shots": 0, "hits": 0, "kills": 0, "heads": 0}

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.8
	cs.shape = cap; cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	model = Humanoid.soldier(Color(0.75, 0.8, 0.92))
	add_child(model)
	anim = Humanoid.anim(model)
	gun = Humanoid.rifle("m4")
	gun.position = Vector3(0.16, 1.22, -0.32)
	add_child(gun)
	muzzle = gun.get_node("Muzzle")
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
	var sprint := Controls.held("sprint") and mv.y > 0.3 and aim < 0.3
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
	var want := "Idle"
	if hs > 4.6:
		want = "Run"
	elif hs > 0.4:
		want = "Walk"
	if anim and want != cur_anim:
		anim.play(want, 0.25)
		cur_anim = want
	if anim:
		anim.speed_scale = clampf(hs / (5.5 if want == "Run" else 1.6), 0.7, 1.6) if want != "Idle" else 1.0
	# weapon
	gun.rotation.x = lerpf(gun.rotation.x, pitch * 0.8 if aim > 0.2 or fire_cd > -0.8 else -0.5, 1.0 - exp(-dt * 12.0))
	if reload_t > 0.0:
		reload_t -= dt
		gun.rotation.z = sin(reload_t * 4.0) * 0.5
		if reload_t <= 0.0:
			var take: int = mini(30 - ammo, reserve)
			ammo += take; reserve -= take
			gun.rotation.z = 0.0
	elif Controls.just("reload") and ammo < 30 and reserve > 0:
		reload_t = 2.0
		Sfx.play("click")
	elif Controls.held("fire") and fire_cd <= 0.0 and not sprint:
		if ammo > 0:
			_shoot()
		elif reserve > 0:
			reload_t = 2.0
	if Time.get_ticks_msec() / 1000.0 - last_hit > 5.0 and hp < 100.0:
		hp = minf(100.0, hp + 12.0 * dt)

func _shoot() -> void:
	fire_cd = 0.08
	ammo -= 1
	stats.shots += 1
	var spread := lerpf(0.02, 0.004, aim)
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
			var killed: bool = col.take_hit(34.0 * (3.2 if head else 1.0), head, self)
			stats.hits += 1
			if main:
				main.on_player_hit(killed, head)
			Fx.particles(main, hit.position, hit.normal, "blood", 10)
		else:
			Fx.particles(main, hit.position, hit.normal, "spark", 8)
			Fx.particles(main, hit.position, hit.normal, "dust", 4)
	Fx.tracer(main, mpos, end)
	Fx.flash(main, mpos, 3.0)
	Sfx.play("rifle", -4.0, randf_range(0.95, 1.05))
	pitch += 0.012
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
		if anim:
			anim.stop()
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", -PI / 2, 0.6)
		if main:
			main.on_player_dead()
		return true
	return false

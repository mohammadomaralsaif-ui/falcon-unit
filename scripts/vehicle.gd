extends VehicleBody3D
## Drivable SWAT SUV: real suspension physics, chase camera, siren lights + sound.

const CarMesh = preload("res://scripts/car_mesh.gd")
const Fx = preload("res://scripts/fx.gd")

var main: Node
var driving := false
var cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.22
var look_t := 0.0
var siren_on := true
var flashers := {}
var light_r: OmniLight3D
var light_b: OmniLight3D
var engine_snd: AudioStreamPlayer3D
var siren_snd: AudioStreamPlayer3D
var flip_t := 0.0
var speed_kmh := 0.0
var _flash_t := 0.0
var prev_vel := Vector3.ZERO
var crash_cd := 0.0
var health := 100.0
var smoke_t := 0.0
var screech_snd: AudioStreamPlayer3D

const MAX_FORCE := 5200.0
const MAX_BRAKE := 60.0
const TOP_SPEED := 32.0  # m/s (~115 km/h)

func _ready() -> void:
	mass = 2100.0
	collision_layer = 8
	collision_mask = 1 | 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.25, 0.1)
	linear_damp = 0.05
	angular_damp = 0.6
	contact_monitor = true
	max_contacts_reported = 4
	var body := CarMesh.compact(CarMesh.build("swat", Color(), false))
	add_child(body)
	flashers = body.get_meta("flashers")
	var s: Dictionary = body.get_meta("spec")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(s.W - 0.05, s.roof - 0.55, s.L - 0.1)
	cs.shape = bs
	cs.position = Vector3(0, 0.55 + (s.roof - 0.55) * 0.5, 0)
	add_child(cs)
	var r: float = s.r
	for wzp in [s.wz, -s.wz]:
		for sd in [-1.0, 1.0]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(sd * (s.W * 0.5 - 0.15), r + 0.1, wzp)
			w.wheel_radius = r
			w.wheel_rest_length = 0.18
			w.suspension_travel = 0.22
			w.suspension_stiffness = 48.0
			w.suspension_max_force = 12000.0
			w.damping_compression = 0.9
			w.damping_relaxation = 1.4
			w.wheel_friction_slip = 2.6
			w.wheel_roll_influence = 0.04
			w.use_as_steering = wzp > 0
			w.use_as_traction = true
			add_child(w)
			if not body.has_meta("custom"):
				CarMesh.wheel(w, r, 0.3)
	# siren lights
	var bar_z: float = (s.ws1 + s.re) * 0.5 + 0.3
	light_r = OmniLight3D.new(); light_r.light_color = Color(1, 0.1, 0.1); light_r.omni_range = 14.0
	light_r.position = Vector3(-0.5, s.roof + 0.4, bar_z)
	light_b = OmniLight3D.new(); light_b.light_color = Color(0.15, 0.35, 1); light_b.omni_range = 14.0
	light_b.position = Vector3(0.5, s.roof + 0.4, bar_z)
	add_child(light_r); add_child(light_b)
	engine_snd = AudioStreamPlayer3D.new(); engine_snd.stream = Sfx.streams["engine"]; engine_snd.unit_size = 8.0
	siren_snd = AudioStreamPlayer3D.new(); siren_snd.stream = Sfx.streams["siren"]; siren_snd.unit_size = 14.0; siren_snd.volume_db = -6.0
	add_child(engine_snd); add_child(siren_snd)
	engine_snd.play(); siren_snd.play()
	screech_snd = AudioStreamPlayer3D.new(); screech_snd.stream = Sfx.streams["screech"]; screech_snd.unit_size = 10.0; screech_snd.volume_db = -60.0
	add_child(screech_snd)
	screech_snd.play()
	cam = Camera3D.new()
	cam.fov = 70; cam.far = 1500
	cam.top_level = true
	add_child(cam)

func set_driving(on: bool) -> void:
	driving = on
	if on:
		cam_yaw = 0.0
		cam.global_transform = _cam_target()
		cam.current = true
	else:
		engine_force = 0.0
		brake = 40.0
		steering = 0.0

func _cam_target() -> Transform3D:
	var fwd := global_transform.basis.z
	fwd.y = 0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	var base_yaw := atan2(fwd.x, fwd.z)
	var yaw := base_yaw + cam_yaw + PI
	var dist := 7.5 + clampf(speed_kmh / 120.0, 0.0, 1.0) * 1.5
	var dir := Vector3(sin(yaw) * cos(cam_pitch), -sin(cam_pitch), cos(yaw) * cos(cam_pitch))
	var target := global_position + Vector3(0, 1.7, 0)
	var pos := target + dir * dist
	# keep camera out of walls
	var q := PhysicsRayQueryParameters3D.create(target, pos, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		pos = hit.position + (target - pos).normalized() * 0.4
	return Transform3D(Basis(), pos).looking_at(target + Vector3(0, 0.3, 0), Vector3.UP)

func _physics_process(dt: float) -> void:
	var v := linear_velocity
	var fwd := global_transform.basis.z
	var fwd_speed := v.dot(fwd)
	speed_kmh = abs(fwd_speed) * 3.6
	# siren
	_flash_t += dt
	if siren_on:
		var ph := fmod(_flash_t * 3.2, 1.0)
		var red_on := ph < 0.5
		# real lights only while driving (the Mobile renderer has a small per-mesh light budget)
		light_r.light_energy = (3.0 if red_on else 0.0) if driving else 0.0
		light_b.light_energy = (0.0 if red_on else 3.0) if driving else 0.0
		if flashers.has("red"):
			flashers.red.emission_energy_multiplier = 6.0 if red_on else 0.3
			flashers.blue.emission_energy_multiplier = 0.3 if red_on else 6.0
		if not siren_snd.playing:
			siren_snd.play()
	else:
		light_r.light_energy = 0.0; light_b.light_energy = 0.0
		if siren_snd.playing:
			siren_snd.stop()
	# --- crashes: sudden change of velocity while touching something
	var dv := (prev_vel - v).length()
	prev_vel = v
	crash_cd -= dt
	if dv > 3.2 and crash_cd <= 0.0 and get_contact_count() > 0:
		crash_cd = 0.35
		_crash(dv)
	# --- damage smoke
	if health < 60.0:
		smoke_t -= dt
		if smoke_t <= 0.0:
			smoke_t = 0.25 if health < 25.0 else 0.6
			Fx.particles(get_parent(), global_position + global_transform.basis.z * 2.0 + Vector3(0, 1.1, 0), Vector3.UP, "smoke", 2 if health > 25.0 else 4)
	# --- tyre screech when sliding sideways or braking hard at speed
	var slip := absf(v.dot(global_transform.basis.x))
	var screech := clampf((slip - 3.0) / 5.0, 0.0, 1.0)
	if brake > 30.0 and speed_kmh > 35.0:
		screech = maxf(screech, 0.7)
	screech_snd.volume_db = lerpf(screech_snd.volume_db, lerpf(-60.0, -4.0, screech), 1.0 - exp(-dt * 10.0))
	# --- engine: pitch follows speed, louder under throttle
	var eng_load := absf(engine_force) / MAX_FORCE if driving else 0.0
	engine_snd.pitch_scale = 0.6 + clampf(speed_kmh / 80.0, 0.0, 1.5) + eng_load * 0.25
	engine_snd.volume_db = (-9.0 + eng_load * 5.0) if driving else -26.0
	if not driving:
		return
	if Controls.just("interact"):
		Sfx.play_3d("horn", global_position, 2.0)
		if main and main.peds:
			main.peds.panic(global_position, 10.0)
	if Controls.just("siren") and (not main or main.input_guard <= 0.0):
		siren_on = not siren_on
	var mv := Controls.move_vector()
	var throttle := mv.y
	var steer_in := -mv.x
	# steering gets tighter at speed
	var steer_lim := lerpf(0.6, 0.12, clampf(speed_kmh / 90.0, 0.0, 1.0))
	steering = move_toward(steering, steer_in * steer_lim, dt * 2.4)
	brake = 0.0
	if throttle > 0.05:
		if fwd_speed < -1.0:
			brake = MAX_BRAKE * throttle
			engine_force = 0.0
		else:
			engine_force = MAX_FORCE * throttle * clampf(1.0 - fwd_speed / TOP_SPEED, 0.0, 1.0) * (0.55 if health < 25.0 else 1.0)
	elif throttle < -0.05:
		if fwd_speed > 1.0:
			brake = MAX_BRAKE * -throttle
			engine_force = 0.0
		else:
			engine_force = MAX_FORCE * 0.6 * throttle * clampf(1.0 + fwd_speed / 9.0, 0.0, 1.0)
	else:
		engine_force = 0.0
		brake = 2.5
	if Controls.held("jump"):
		brake = MAX_BRAKE * 0.6
		for w in get_children():
			if w is VehicleWheel3D and not w.use_as_steering:
				w.wheel_friction_slip = 1.1
	else:
		for w in get_children():
			if w is VehicleWheel3D:
				w.wheel_friction_slip = 2.6
	# anti-roll stabiliser: keeps the heavy SUV planted in fast corners
	var up := global_transform.basis.y
	if up.dot(Vector3.UP) > 0.3:
		var corr := up.cross(Vector3.UP)
		apply_torque(corr * mass * 14.0 - angular_velocity.project(fwd) * mass * 1.5)
	# auto-right when flipped
	if global_transform.basis.y.dot(Vector3.UP) < 0.4:
		flip_t += dt
		if flip_t > 2.0:
			var yaw := atan2(fwd.x, fwd.z)
			global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 1.2, 0))
			linear_velocity = Vector3.ZERO; angular_velocity = Vector3.ZERO
			flip_t = 0.0
	else:
		flip_t = 0.0

func _process(dt: float) -> void:
	if not driving:
		return
	var look := Controls.consume_look()
	if look.length() > 0.0001:
		look_t = 1.6
		cam_yaw -= look.x
		cam_pitch = clampf(cam_pitch - look.y, -0.9, 0.25)
	else:
		look_t -= dt
		if look_t <= 0.0:
			cam_yaw = lerp_angle(cam_yaw, 0.0, 1.0 - exp(-dt * 2.5))
			cam_pitch = lerpf(cam_pitch, -0.22, 1.0 - exp(-dt * 2.0))
	var t := _cam_target()
	cam.global_transform = cam.global_transform.interpolate_with(t, 1.0 - exp(-dt * 9.0))
	cam.fov = lerpf(cam.fov, 68.0 + clampf(speed_kmh / 110.0, 0.0, 1.0) * 14.0, 1.0 - exp(-dt * 3.0))

func _crash(dv: float) -> void:
	var power := clampf(dv / 14.0, 0.15, 1.0)
	Sfx.play_3d("crash" if power > 0.45 else "crash_small", global_position, lerpf(-4.0, 8.0, power), randf_range(0.9, 1.1))
	var p := global_position + Vector3(0, 0.8, 0) + prev_vel.normalized() * 2.3
	Fx.particles(get_parent(), p, -prev_vel.normalized() + Vector3.UP * 0.5, "spark", int(10 + power * 30))
	if power > 0.4:
		Fx.particles(get_parent(), p, Vector3.UP, "dust", 6)
	health = maxf(health - dv * 1.4, 0.0)
	if main and driving:
		main.shake = maxf(main.shake, power * 0.9)
		if health < 25.0 and health + dv * 1.4 >= 25.0:
			main.hud.radio("الصقر ١", "السيارة انضربت كثير… المحرك بيطلع دخان!", 3.0)

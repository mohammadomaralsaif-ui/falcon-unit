extends RefCounted
## Short-lived visual effects: tracers, muzzle flashes, impact sparks, explosions.

static var _tracer_mat: StandardMaterial3D
static var _spark_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
static var _blood_mat: StandardMaterial3D

static func _init_mats() -> void:
	if _tracer_mat:
		return
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1, 0.85, 0.5)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(1, 0.8, 0.4)
	_tracer_mat.emission_energy_multiplier = 4.0
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.albedo_color = Color(1, 0.75, 0.3)
	_spark_mat.emission_enabled = true
	_spark_mat.emission = Color(1, 0.7, 0.3)
	_spark_mat.emission_energy_multiplier = 3.0
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.albedo_color = Color(0.5, 0.48, 0.45, 0.35)
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.vertex_color_use_as_albedo = true
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64; gt.height = 64
	_smoke_mat.albedo_texture = gt
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.albedo_color = Color(0.4, 0.02, 0.02)
	_blood_mat.roughness = 0.4

static func tracer(root: Node, a: Vector3, b: Vector3, col := Color(1, 0.85, 0.5)) -> void:
	_init_mats()
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, minf(len, 6.0))
	mi.mesh = bm
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var dir := (b - a).normalized()
	var start := a + dir * minf(len, 6.0) * 0.5
	mi.look_at_from_position(start, start + dir, Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", b - dir * minf(len, 6.0) * 0.5, minf(len / 300.0, 0.2))
	tw.tween_callback(mi.queue_free)

static func flash(root: Node, pos: Vector3, energy := 3.0, col := Color(1, 0.75, 0.4), dur := 0.06, rng := 8.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)

static func particles(root: Node, pos: Vector3, normal: Vector3, kind := "spark", amount := 12) -> void:
	_init_mats()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.explosiveness = 0.95
	var m := BoxMesh.new()
	match kind:
		"spark":
			m.size = Vector3(0.03, 0.03, 0.03)
			p.mesh = m; p.material_override = _spark_mat
			p.lifetime = 0.35; p.initial_velocity_min = 3; p.initial_velocity_max = 8; p.gravity = Vector3(0, -9.8, 0)
		"blood":
			m.size = Vector3(0.05, 0.05, 0.05)
			p.mesh = m; p.material_override = _blood_mat
			p.lifetime = 0.6; p.initial_velocity_min = 1.5; p.initial_velocity_max = 4; p.gravity = Vector3(0, -9.8, 0)
		"dust":
			var q := QuadMesh.new(); q.size = Vector2(0.3, 0.3)
			p.mesh = q; p.material_override = _smoke_mat
			p.lifetime = 0.9; p.initial_velocity_min = 0.3; p.initial_velocity_max = 1.2; p.gravity = Vector3(0, 0.3, 0)
			p.scale_amount_min = 1.0; p.scale_amount_max = 2.5
		"smoke":
			var q := QuadMesh.new(); q.size = Vector2(1.5, 1.5)
			p.mesh = q; p.material_override = _smoke_mat
			p.lifetime = 2.5; p.initial_velocity_min = 0.5; p.initial_velocity_max = 2.5; p.gravity = Vector3(0, 0.6, 0)
			p.scale_amount_min = 1.0; p.scale_amount_max = 3.0
	p.direction = normal if normal.length() > 0.1 else Vector3.UP
	p.spread = 50.0
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := root.get_tree().create_timer(p.lifetime + 0.2)
	t.timeout.connect(p.queue_free)

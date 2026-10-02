extends RefCounted
## Short-lived visual effects: tracers, muzzle flashes, impact sparks, explosions.

static var _tracer_mat: StandardMaterial3D
static var _spark_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
static var _blood_mat: StandardMaterial3D
static var _meshes := {}

## Shared meshes so effects don't allocate new geometry every shot.
static func _mesh(key: String) -> Mesh:
	if not _meshes.has(key):
		match key:
			"tracer":
				var b := BoxMesh.new(); b.size = Vector3(0.025, 0.025, 1.0); _meshes[key] = b
			"spark":
				var b := BoxMesh.new(); b.size = Vector3(0.03, 0.03, 0.03); _meshes[key] = b
			"blood":
				var q := QuadMesh.new(); q.size = Vector2(0.05, 0.05); _meshes[key] = q
			"blood_mist":
				var q := QuadMesh.new(); q.size = Vector2(0.34, 0.34); _meshes[key] = q
			"dust":
				var q := QuadMesh.new(); q.size = Vector2(0.3, 0.3); _meshes[key] = q
			"smoke":
				var q := QuadMesh.new(); q.size = Vector2(1.5, 1.5); _meshes[key] = q
			"flash_long":
				var q := QuadMesh.new(); q.size = Vector2(0.16, 0.42); _meshes[key] = q
			"flash_front":
				var q := QuadMesh.new(); q.size = Vector2(0.2, 0.2); _meshes[key] = q
			"hole":
				var q := QuadMesh.new(); q.size = Vector2(0.09, 0.09); _meshes[key] = q
	return _meshes[key]

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
	# soft round dark-red sprites that always face the camera (droplets and the fine spray)
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blood_mat.albedo_color = Color(0.3, 0.012, 0.015, 0.95)
	_blood_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_blood_mat.vertex_color_use_as_albedo = true
	_blood_mat.albedo_texture = gt

static func tracer(root: Node, a: Vector3, b: Vector3, col := Color(1, 0.85, 0.5)) -> void:
	_init_mats()
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("tracer")
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var dir := (b - a).normalized()
	var start := a + dir * minf(len, 6.0) * 0.5
	mi.look_at_from_position(start, start + dir, Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT)
	mi.scale = Vector3(1, 1, minf(len, 6.0))
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
	match kind:
		"spark":
			p.mesh = _mesh("spark"); p.material_override = _spark_mat
			p.lifetime = 0.35; p.initial_velocity_min = 3; p.initial_velocity_max = 8; p.gravity = Vector3(0, -9.8, 0)
		"blood":
			# droplets: small, fast, pulled down, gone in half a second
			p.mesh = _mesh("blood"); p.material_override = _blood_mat
			p.lifetime = 0.5; p.initial_velocity_min = 1.2; p.initial_velocity_max = 4.2; p.gravity = Vector3(0, -9.8, 0)
			p.scale_amount_min = 0.5; p.scale_amount_max = 1.3
			p.color_ramp = _fade()
		"blood_mist":
			# the fine red puff at the wound
			p.mesh = _mesh("blood_mist"); p.material_override = _blood_mat
			p.lifetime = 0.3; p.initial_velocity_min = 0.3; p.initial_velocity_max = 1.1; p.gravity = Vector3(0, -0.6, 0)
			p.scale_amount_min = 0.6; p.scale_amount_max = 1.5
			p.color = Color(1, 1, 1, 0.5)
			p.color_ramp = _fade()
		"dust":
			p.mesh = _mesh("dust"); p.material_override = _smoke_mat
			p.lifetime = 0.9; p.initial_velocity_min = 0.3; p.initial_velocity_max = 1.2; p.gravity = Vector3(0, 0.3, 0)
			p.scale_amount_min = 1.0; p.scale_amount_max = 2.5
		"smoke":
			p.mesh = _mesh("smoke"); p.material_override = _smoke_mat
			p.lifetime = 2.5; p.initial_velocity_min = 0.5; p.initial_velocity_max = 2.5; p.gravity = Vector3(0, 0.6, 0)
			p.scale_amount_min = 1.0; p.scale_amount_max = 3.0
	p.direction = normal if normal.length() > 0.1 else Vector3.UP
	p.spread = 50.0 if kind != "blood" else 32.0
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := root.get_tree().create_timer(p.lifetime + 0.2)
	t.timeout.connect(p.queue_free)

static var _fade_grad: Gradient
static func _fade() -> Gradient:
	if not _fade_grad:
		_fade_grad = Gradient.new()
		_fade_grad.set_color(0, Color(1, 1, 1, 1))
		_fade_grad.set_color(1, Color(1, 1, 1, 0))
		_fade_grad.add_point(0.6, Color(1, 1, 1, 0.9))
	return _fade_grad

static var _flash_mat: StandardMaterial3D
static var _hole_mat: StandardMaterial3D
static var _holes: Array = []

## Star-shaped muzzle flash at the barrel tip, lives for two frames.
static func muzzle(root: Node, tip: Node3D) -> void:
	if not _flash_mat:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 0.95, 0.7, 1)); g.set_color(1, Color(1, 0.5, 0.1, 0))
		gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5); gt.width = 64; gt.height = 64
		_flash_mat.albedo_texture = gt
	var n := Node3D.new()
	tip.add_child(n)
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh("flash_long")
		mi.material_override = _flash_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation = Vector3(PI / 2, 0, k * PI / 2.0 + randf() * 0.6)
		mi.position.z = -0.12
		n.add_child(mi)
	var front := MeshInstance3D.new()
	front.mesh = _mesh("flash_front"); front.material_override = _flash_mat
	front.rotation.z = randf() * TAU
	n.add_child(front)
	var t := root.get_tree().create_timer(0.045)
	t.timeout.connect(n.queue_free)

## Small dark bullet hole stuck to a wall (keeps the most recent 60).
static func bullet_hole(root: Node, pos: Vector3, normal: Vector3) -> void:
	if not _hole_mat:
		_hole_mat = StandardMaterial3D.new()
		_hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.03, 0.03, 0.03, 1)); g.set_color(1, Color(0.2, 0.18, 0.16, 0))
		g.add_point(0.35, Color(0.05, 0.05, 0.05, 0.95))
		gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5); gt.width = 32; gt.height = 32
		_hole_mat.albedo_texture = gt
		_hole_mat.roughness = 0.9
	if normal.length() < 0.5:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("hole")
	mi.material_override = _hole_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.01)
	_holes.append(mi)
	if _holes.size() > 60:
		var old = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()

static var _splat_mat: StandardMaterial3D
static var _splats: Array = []

static func _blood_material() -> StandardMaterial3D:
	if _splat_mat:
		return _splat_mat
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new(); r.seed = 77
	# main blob + droplets, soft edges
	var blobs := [[64.0, 64.0, 34.0]]
	for i in 14:
		var a := r.randf() * TAU
		var d := r.randf_range(26.0, 58.0)
		blobs.append([64.0 + cos(a) * d, 64.0 + sin(a) * d, r.randf_range(1.2, 4.5)])
	for y in 128:
		for x in 128:
			var v := 0.0
			for b in blobs:
				var dd: float = Vector2(x - b[0], y - b[1]).length() / b[2]
				v = maxf(v, clampf(1.6 - dd * 1.2, 0.0, 1.0))
			if v > 0.0:
				var shade := r.randf_range(0.85, 1.0)
				img.set_pixel(x, y, Color(0.32 * shade, 0.015, 0.02, minf(v * 1.4, 0.95)))
	img.generate_mipmaps()
	_splat_mat = StandardMaterial3D.new()
	_splat_mat.albedo_texture = ImageTexture.create_from_image(img)
	_splat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# matte enough that the sky doesn't mirror in it (it used to flash white-pink outdoors)
	_splat_mat.roughness = 0.8
	_splat_mat.metallic_specular = 0.15
	return _splat_mat

static func _splat_mesh() -> Mesh:
	if not _meshes.has("splat"):
		var q := QuadMesh.new(); q.size = Vector2(1, 1)
		_meshes["splat"] = q
	return _meshes["splat"]

## A blood decal stuck to a surface. Keeps the most recent 40.
static func blood_splat(root: Node, pos: Vector3, normal: Vector3, size := 0.6) -> MeshInstance3D:
	if normal.length() < 0.5:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = _splat_mesh()
	mi.material_override = _blood_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	var b := Basis.looking_at(-normal, up).rotated(normal.normalized(), randf() * TAU)
	mi.global_transform = Transform3D(b, pos + normal * 0.012)
	mi.scale = Vector3(size, size, 1)
	_splats.append(mi)
	if _splats.size() > 40:
		var old = _splats.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return mi

static var _cloud_mat: StandardMaterial3D

## Smoke grenade cloud: a handful of big soft sprites that swell, hang and thin out.
static func smoke_cloud(root: Node3D, pos: Vector3, radius: float, dur: float) -> void:
	_init_mats()
	if not _cloud_mat:
		_cloud_mat = StandardMaterial3D.new()
		_cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cloud_mat.albedo_color = Color(0.74, 0.74, 0.72, 0.62)
		_cloud_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_cloud_mat.albedo_texture = _smoke_mat.albedo_texture
		_cloud_mat.disable_receive_shadows = true
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = pos
	var n := 7
	for i in n:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new(); q.size = Vector2(radius * 1.5, radius * 1.3)
		mi.mesh = q
		mi.material_override = _cloud_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * i / n
		var off := Vector3(cos(a), 0, sin(a)) * radius * (0.45 if i > 0 else 0.0) + Vector3(0, randf_range(-0.2, 0.9), 0)
		mi.position = Vector3.ZERO
		mi.scale = Vector3.ONE * 0.1
		holder.add_child(mi)
		var tw := mi.create_tween()
		tw.tween_property(mi, "position", off, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(mi, "scale", Vector3.ONE, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(mi, "position", off + Vector3(0, 0.5, 0), dur - 3.6)
		tw.tween_property(mi, "scale", Vector3.ONE * 1.6, 2.0)
		tw.parallel().tween_property(mi, "transparency", 1.0, 2.0)
	root.get_tree().create_timer(dur + 0.2).timeout.connect(holder.queue_free)

## Bullet hits a person: spray + splatter on the wall behind and the floor below.
static func blood_hit(root: Node3D, pos: Vector3, dir: Vector3, normal: Vector3) -> void:
	# a short spray out of the exit side, a puff at the wound
	particles(root, pos, (dir + Vector3.UP * 0.25).normalized(), "blood", 12)
	particles(root, pos, (normal + dir * 0.3).normalized(), "blood_mist", 4)
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + dir * 0.4, pos + dir * 3.2, 1)
	var hit := space.intersect_ray(q)
	if hit:
		blood_splat(root, hit.position, hit.normal, randf_range(0.45, 0.9))
	var qd := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, -2.6, 0) + dir * 0.6, 1)
	var hd := space.intersect_ray(qd)
	if hd:
		blood_splat(root, hd.position, hd.normal, randf_range(0.3, 0.55))

## Slowly spreading pool under a body.
static func blood_pool(root: Node3D, pos: Vector3) -> void:
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.8, 0), pos + Vector3(0, -1.5, 0), 1)
	var hit := space.intersect_ray(q)
	if not hit:
		return
	var mi := blood_splat(root, hit.position, Vector3.UP, 0.15)
	if mi:
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(1.6, 1.6, 1), 6.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

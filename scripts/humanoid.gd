extends RefCounted
const CustomModels = preload("res://scripts/custom_models.gd")
## Loads the rigged soldier / civilian models, sets up looping animations, tints and weapons.

static var _soldier: PackedScene
static var _civ: PackedScene
static var _tints := {}

static func soldier(tint := Color(1, 1, 1)) -> Node3D:
	if not _soldier:
		_soldier = load("res://assets/models/soldier.glb")
	var m: Node3D = _soldier.instantiate()
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	if ap:
		for n in ap.get_animation_list():
			var a := ap.get_animation(n)
			if n != "TPose":
				a.loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")
	if tint != Color(1, 1, 1):
		_tint(m, tint)
	_shadows(m)
	return m

static func civilian() -> Node3D:
	if not _civ:
		_civ = load("res://assets/models/civilian.glb")
	var m: Node3D = _civ.instantiate()
	_shadows(m)
	return m

static func _shadows(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_shadows(c)

static func _tint(n: Node, col: Color) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.mesh:
			for i in c.mesh.get_surface_count():
				var base: Material = c.get_active_material(i)
				if base is BaseMaterial3D:
					var key := str(base.get_instance_id()) + col.to_html()
					if not _tints.has(key):
						var dup: BaseMaterial3D = base.duplicate()
						dup.albedo_color = col
						_tints[key] = dup
					c.set_surface_override_material(i, _tints[key])
		_tint(c, col)

static func anim(m: Node) -> AnimationPlayer:
	return m.find_child("AnimationPlayer", true, false)

static func skeleton(m: Node) -> Skeleton3D:
	return m.find_child("Skeleton3D", true, false) as Skeleton3D

static func bone_named(sk: Skeleton3D, part: String) -> int:
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.ends_with(part) and not n.ends_with("Fore" + part) and not n.ends_with("Up" + part):
			return i
	return -1

## Sidearm (Glock): origin at the grip, barrel along -Z.
static func pistol() -> Node3D:
	var real := CustomModels.weapon("pistol", 0.19, 0.035)
	if real:
		var t := Marker3D.new(); t.name = "Muzzle"; t.position = Vector3(0, 0.025, -0.16)
		real.add_child(t)
		return real
	var g := Node3D.new()
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.06, 0.06, 0.07); m.roughness = 0.5
	for b in [[Vector3(0.03, 0.035, 0.19), Vector3(0, 0.02, -0.06)], [Vector3(0.028, 0.1, 0.045), Vector3(0, -0.04, 0.0)]]:
		var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = b[0]; bm.material = m
		mi.mesh = bm; mi.position = b[1]; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(mi)
	var t2 := Marker3D.new(); t2.name = "Muzzle"; t2.position = Vector3(0, 0.025, -0.16)
	g.add_child(t2)
	return g

## Bolt-action sniper rifle: the long rifle body with a big scope on top. Origin at the grip.
static func sniper() -> Node3D:
	var g := Node3D.new()
	var real := CustomModels.weapon("sniper", 1.2, 0.36)
	if not real:
		real = CustomModels.weapon("rifle_swat", 1.2, 0.36)
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.05, 0.05, 0.06); m.metallic = 0.7; m.roughness = 0.35
	if real:
		g.add_child(real)
	else:
		var body := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.05, 0.09, 1.1); bm.material = m
		body.mesh = bm; body.position = Vector3(0, 0.02, -0.2); g.add_child(body)
	var sc := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.034; cm.bottom_radius = 0.034; cm.height = 0.36; cm.material = m
	sc.mesh = cm; sc.rotation.x = PI / 2; sc.position = Vector3(0, 0.125, -0.1)
	g.add_child(sc)
	for z in [-0.3, 0.06]:
		var lens := MeshInstance3D.new()
		var lm := CylinderMesh.new(); lm.top_radius = 0.037; lm.bottom_radius = 0.037; lm.height = 0.06; lm.material = m
		lens.mesh = lm; lens.rotation.x = PI / 2; lens.position = Vector3(0, 0.125, z)
		g.add_child(lens)
	for mi in g.find_children("*", "GeometryInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var t := Marker3D.new(); t.name = "Muzzle"; t.position = Vector3(0, 0.03, -0.84)
	g.add_child(t)
	return g

static func rifle(kind := "m4") -> Node3D:
	## Built facing -Z, origin at the pistol grip. Geometry is built once per kind and shared.
	# real weapon models dropped into assets/weapons/ win
	var real := CustomModels.weapon("rifle_swat" if kind == "m4" else "rifle_robber", 0.98, 0.30)
	if real:
		var tip0 := Marker3D.new(); tip0.name = "Muzzle"; tip0.position = Vector3(0, 0.03, -0.69)
		real.add_child(tip0)
		return real
	if _gun_cache.has(kind):
		var g2 := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = _gun_cache[kind]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g2.add_child(mi)
		var tip2 := Marker3D.new(); tip2.name = "Muzzle"; tip2.position = Vector3(0, 0.045, -0.7)
		g2.add_child(tip2)
		return g2
	var g := Node3D.new()
	var metal := StandardMaterial3D.new(); metal.albedo_color = Color(0.07, 0.07, 0.08); metal.metallic = 0.8; metal.roughness = 0.35
	var poly := StandardMaterial3D.new(); poly.roughness = 0.65
	poly.albedo_color = Color(0.1, 0.1, 0.11) if kind == "m4" else Color(0.38, 0.2, 0.08)
	var parts := []
	if kind == "m4":
		parts = [
			[Vector3(0.05, 0.07, 0.26), Vector3(0, 0.045, -0.06), metal],      # upper receiver
			[Vector3(0.046, 0.05, 0.2), Vector3(0, 0.0, -0.03), metal],        # lower receiver
			[Vector3(0.06, 0.06, 0.3), Vector3(0, 0.045, -0.34), poly],        # handguard
			[Vector3(0.012, 0.012, 0.012), Vector3(0, 0.08, -0.34), metal],    # rail bumps
			[Vector3(0.018, 0.018, 0.16), Vector3(0, 0.045, -0.56), metal],    # barrel
			[Vector3(0.028, 0.028, 0.05), Vector3(0, 0.045, -0.655), metal],   # muzzle device
			[Vector3(0.035, 0.1, 0.045), Vector3(0, -0.06, 0.05), poly],       # grip
			[Vector3(0.032, 0.14, 0.06), Vector3(0, -0.08, -0.1), metal],      # magazine
			[Vector3(0.045, 0.07, 0.17), Vector3(0, 0.02, 0.2), poly],         # stock
			[Vector3(0.05, 0.09, 0.03), Vector3(0, 0.0, 0.29), poly],          # butt pad
			[Vector3(0.012, 0.03, 0.14), Vector3(0, 0.035, 0.08), metal],      # buffer tube
			[Vector3(0.04, 0.045, 0.1), Vector3(0, 0.105, -0.08), metal],      # red-dot body
			[Vector3(0.035, 0.035, 0.01), Vector3(0, 0.11, -0.135), metal],
			[Vector3(0.02, 0.04, 0.02), Vector3(0, 0.09, -0.45), metal],       # front sight
		]
	else:
		parts = [
			[Vector3(0.05, 0.075, 0.3), Vector3(0, 0.03, -0.06), metal],
			[Vector3(0.055, 0.055, 0.22), Vector3(0, 0.035, -0.32), poly],     # wooden handguard
			[Vector3(0.018, 0.018, 0.22), Vector3(0, 0.05, -0.52), metal],
			[Vector3(0.012, 0.012, 0.18), Vector3(0, 0.08, -0.4), metal],      # gas tube
			[Vector3(0.02, 0.05, 0.02), Vector3(0, 0.075, -0.62), metal],
			[Vector3(0.035, 0.1, 0.045), Vector3(0, -0.06, 0.05), metal],
			[Vector3(0.05, 0.08, 0.26), Vector3(0, 0.0, 0.22), poly],          # wooden stock
		]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = pt[0]
		mi.mesh = bm; mi.position = pt[1]; mi.material_override = pt[2]
		g.add_child(mi)
	if kind == "ak":
		# curved magazine: three tilted segments
		for i in 3:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(0.034, 0.075, 0.06)
			mi.mesh = bm; mi.material_override = metal
			mi.position = Vector3(0, -0.035 - i * 0.065, -0.11 - i * i * 0.018)
			mi.rotation.x = -0.25 * i
			g.add_child(mi)
	_gun_cache[kind] = _merge(g)
	var tip := Marker3D.new(); tip.name = "Muzzle"; tip.position = Vector3(0, 0.045, -0.7)
	g.add_child(tip)
	return g

static var _gun_cache := {}

## Collapse all box parts of a weapon into one mesh (one surface per material).
static func _merge(g: Node3D) -> ArrayMesh:
	var groups := {}
	for c in g.get_children():
		if c is MeshInstance3D:
			var m: Material = c.material_override
			if not groups.has(m):
				var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[m] = st
			groups[m].append_from(c.mesh, 0, c.transform)
			g.remove_child(c)
			c.free()
	var am := ArrayMesh.new()
	for m in groups:
		groups[m].commit(am)
		am.surface_set_material(am.get_surface_count() - 1, m)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)
	return am

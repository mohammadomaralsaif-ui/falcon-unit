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

## Tactical pump-action shotgun (M870 style): steel receiver with a top rail and ghost-ring sight,
## barrel over a magazine tube, ribbed polymer pump, pistol-grip stock, shell carrier on the side.
## Origin at the grip, barrel toward -Z. Built once and shared.
static func shotgun() -> Node3D:
	var g := Node3D.new()
	if not _gun_cache.has("shotgun"):
		# police pump-action: parkerised steel, black synthetic furniture, shells on the side
		var steel := StandardMaterial3D.new(); steel.albedo_color = Color(0.2, 0.21, 0.23); steel.metallic = 0.55; steel.roughness = 0.42
		var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.11, 0.115, 0.125); dark.metallic = 0.5; dark.roughness = 0.5
		var poly := StandardMaterial3D.new(); poly.albedo_color = Color(0.075, 0.075, 0.08); poly.roughness = 0.68
		var rubber := StandardMaterial3D.new(); rubber.albedo_color = Color(0.025, 0.025, 0.025); rubber.roughness = 0.95
		var shell := StandardMaterial3D.new(); shell.albedo_color = Color(0.68, 0.08, 0.05); shell.roughness = 0.5
		var brass := StandardMaterial3D.new(); brass.albedo_color = Color(0.8, 0.62, 0.25); brass.metallic = 0.8; brass.roughness = 0.35
		var dot := StandardMaterial3D.new(); dot.albedo_color = Color(1.0, 0.45, 0.1); dot.emission_enabled = true; dot.emission = Color(1.0, 0.4, 0.05); dot.emission_energy_multiplier = 0.6
		var box := func(size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> void:
			var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size
			mi.mesh = bm; mi.position = pos; mi.rotation = rot; mi.material_override = m
			g.add_child(mi)
		var tube := func(radius: float, length: float, pos: Vector3, m: Material, axis := "z", sides := 12) -> void:
			var mi := MeshInstance3D.new(); var cm := CylinderMesh.new()
			cm.top_radius = radius; cm.bottom_radius = radius; cm.height = length; cm.radial_segments = sides; cm.rings = 1
			mi.mesh = cm; mi.position = pos; mi.material_override = m
			if axis == "z":
				mi.rotation.x = PI / 2
			g.add_child(mi)
		# a side profile (z = along the gun, y = up) cut out of a plate `w` thick, edges chamfered
		var plate := func(pts: Array, w: float, m: Material) -> void:
			var poly2 := PackedVector2Array()
			for q in pts:
				poly2.append(q)
			var tris := Geometry2D.triangulate_polygon(poly2)
			var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n := poly2.size()
			var hw := w * 0.5
			for sx in [-1.0, 1.0]:
				for k in range(0, tris.size(), 3):
					var ids := [tris[k], tris[k + 1], tris[k + 2]]
					if sx < 0.0:
						ids.reverse()
					for id in ids:
						st.set_uv(poly2[id] * 4.0)
						st.add_vertex(Vector3(sx * hw, poly2[id].y, poly2[id].x))
			for k in n:
				var p0 := poly2[k]
				var p1 := poly2[(k + 1) % n]
				var a := Vector3(-hw, p0.y, p0.x)
				var b := Vector3(hw, p0.y, p0.x)
				var c := Vector3(hw, p1.y, p1.x)
				var d := Vector3(-hw, p1.y, p1.x)
				for v in [a, c, b, a, d, c]:
					st.set_uv(Vector2(v.x, v.y + v.z) * 4.0)
					st.add_vertex(v)
			st.generate_normals()
			st.generate_tangents()
			st.index()            # the merge below mixes this with indexed primitives
			var am := st.commit()
			var mi := MeshInstance3D.new(); mi.mesh = am; mi.material_override = m
			g.add_child(mi)
		# receiver: flat-sided steel block, sloped at the back into the stock wrist
		plate.call([Vector2(-0.19, 0.004), Vector2(0.075, 0.004), Vector2(0.075, 0.05), Vector2(0.045, 0.074), Vector2(-0.19, 0.074)], 0.042, steel)
		box.call(Vector3(0.004, 0.022, 0.075), Vector3(0.0215, 0.05, -0.085), dark)           # ejection port
		box.call(Vector3(0.046, 0.012, 0.012), Vector3(0, 0.02, 0.03), dark)                  # cross-bolt safety
		# trigger guard (a loop) + trigger
		box.call(Vector3(0.016, 0.005, 0.085), Vector3(0, -0.026, 0.02), dark)
		box.call(Vector3(0.016, 0.03, 0.005), Vector3(0, -0.011, -0.022), dark)
		box.call(Vector3(0.016, 0.03, 0.005), Vector3(0, -0.011, 0.062), dark, Vector3(0.35, 0, 0))
		box.call(Vector3(0.006, 0.022, 0.005), Vector3(0, -0.01, 0.022), steel, Vector3(-0.3, 0, 0))
		# barrel over the magazine tube, joined by the barrel ring
		tube.call(0.0118, 0.5, Vector3(0, 0.058, -0.44), steel)
		tube.call(0.0132, 0.012, Vector3(0, 0.058, -0.684), dark)                             # muzzle crown
		tube.call(0.0128, 0.42, Vector3(0, 0.027, -0.4), steel)
		tube.call(0.0152, 0.028, Vector3(0, 0.027, -0.622), dark)                             # magazine cap
		box.call(Vector3(0.03, 0.05, 0.016), Vector3(0, 0.043, -0.596), dark)
		# sights: ghost ring at the back of the receiver, blade with a bright dot up front
		box.call(Vector3(0.024, 0.006, 0.03), Vector3(0, 0.077, 0.02), dark)
		box.call(Vector3(0.004, 0.02, 0.012), Vector3(-0.011, 0.088, 0.03), dark)
		box.call(Vector3(0.004, 0.02, 0.012), Vector3(0.011, 0.088, 0.03), dark)
		box.call(Vector3(0.026, 0.004, 0.012), Vector3(0, 0.098, 0.03), dark)
		box.call(Vector3(0.012, 0.008, 0.03), Vector3(0, 0.072, -0.665), dark)
		box.call(Vector3(0.005, 0.016, 0.014), Vector3(0, 0.082, -0.668), dark)
		box.call(Vector3(0.006, 0.006, 0.003), Vector3(0, 0.086, -0.6595), dot)
		# pump forend: a round sleeve on the tube with grip rings, and the action bars back to the receiver
		tube.call(0.026, 0.2, Vector3(0, 0.03, -0.37), poly, "z", 14)
		for k in 7:
			tube.call(0.0285, 0.01, Vector3(0, 0.03, -0.45 + k * 0.0265), poly, "z", 14)
		box.call(Vector3(0.036, 0.004, 0.09), Vector3(0, 0.03, -0.235), dark)
		# one-piece stock: wrist, grip curve, comb, butt
		plate.call([Vector2(0.07, 0.008), Vector2(0.07, 0.054), Vector2(0.115, 0.05), Vector2(0.2, 0.052), Vector2(0.395, 0.04),
			Vector2(0.395, -0.085), Vector2(0.29, -0.06), Vector2(0.2, -0.04), Vector2(0.155, -0.055), Vector2(0.12, -0.05), Vector2(0.1, -0.012)], 0.04, poly)
		box.call(Vector3(0.042, 0.13, 0.02), Vector3(0, -0.0225, 0.405), rubber)              # recoil pad
		tube.call(0.006, 0.05, Vector3(0, -0.066, 0.33), dark, "x")                           # sling swivel
		tube.call(0.006, 0.04, Vector3(0, 0.008, -0.6), dark, "x")
		# six spare shells in a carrier on the left of the receiver, brass down
		box.call(Vector3(0.008, 0.034, 0.145), Vector3(-0.025, 0.04, -0.06), poly)
		for k in 6:
			tube.call(0.0098, 0.046, Vector3(-0.038, 0.047, -0.118 + k * 0.0235), shell, "y", 10)
			tube.call(0.0102, 0.014, Vector3(-0.038, 0.017, -0.118 + k * 0.0235), brass, "y", 10)
		_gun_cache["shotgun"] = _merge(g)
	else:
		var mi2 := MeshInstance3D.new()
		mi2.mesh = _gun_cache["shotgun"]
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(mi2)
	var t := Marker3D.new(); t.name = "Muzzle"; t.position = Vector3(0, 0.058, -0.7)
	g.add_child(t)
	return g

## Ballistic shield carried on the left arm: dark slab with a viewing slit and a "شرطة" plate.
static func shield() -> Node3D:
	var g := Node3D.new()
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.05, 0.06, 0.08); m.roughness = 0.55; m.metallic = 0.3
	var glass := StandardMaterial3D.new(); glass.albedo_color = Color(0.25, 0.4, 0.5, 0.45); glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.roughness = 0.1
	var plate := StandardMaterial3D.new(); plate.albedo_color = Color(0.9, 0.9, 0.92)
	var parts := [
		[Vector3(0.6, 0.62, 0.035), Vector3(0, -0.2, 0), m],
		[Vector3(0.6, 0.12, 0.035), Vector3(0, 0.42, 0), m],
		[Vector3(0.13, 0.25, 0.035), Vector3(-0.235, 0.235, 0), m],
		[Vector3(0.13, 0.25, 0.035), Vector3(0.235, 0.235, 0), m],
		[Vector3(0.34, 0.25, 0.02), Vector3(0, 0.235, 0), glass],
		[Vector3(0.36, 0.09, 0.01), Vector3(0, -0.12, -0.022), plate],
	]
	for pt in parts:
		var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = pt[0]; bm.material = pt[2]
		mi.mesh = bm; mi.position = pt[1]; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(mi)
	var h := Node3D.new(); h.name = "Handle"; h.position = Vector3(0.05, 0.0, 0.07)
	g.add_child(h)
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
	var cm := CylinderMesh.new(); cm.top_radius = 0.034; cm.bottom_radius = 0.034; cm.height = 0.36; cm.radial_segments = 10; cm.rings = 1; cm.material = m
	sc.mesh = cm; sc.rotation.x = PI / 2; sc.position = Vector3(0, 0.125, -0.1)
	g.add_child(sc)
	for z in [-0.3, 0.06]:
		var lens := MeshInstance3D.new()
		var lm := CylinderMesh.new(); lm.top_radius = 0.037; lm.bottom_radius = 0.037; lm.height = 0.06; lm.radial_segments = 10; lm.rings = 1; lm.material = m
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

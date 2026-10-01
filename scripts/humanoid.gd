extends RefCounted
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

static func rifle(kind := "m4") -> Node3D:
	## Built facing -Z, origin at the pistol grip.
	var g := Node3D.new()
	var metal := StandardMaterial3D.new(); metal.albedo_color = Color(0.09, 0.09, 0.1); metal.metallic = 0.75; metal.roughness = 0.38
	var poly := StandardMaterial3D.new(); poly.albedo_color = Color(0.12, 0.12, 0.13) if kind == "m4" else Color(0.36, 0.2, 0.09); poly.roughness = 0.6
	var parts := [
		[Vector3(0.058, 0.075, 0.32), Vector3(0, 0.04, -0.06), metal],
		[Vector3(0.05, 0.05, 0.2), Vector3(0, -0.01, -0.02), metal],
		[Vector3(0.065, 0.065, 0.3), Vector3(0, 0.035, -0.36), poly],
		[Vector3(0.02, 0.02, 0.2), Vector3(0, 0.04, -0.6), metal],
		[Vector3(0.045, 0.09, 0.22), Vector3(0, 0.0, 0.2), poly],
		[Vector3(0.035, 0.1, 0.04), Vector3(0, -0.07, 0.04), poly],
		[Vector3(0.04, 0.16, 0.07), Vector3(0, -0.1, -0.12), metal],
		[Vector3(0.035, 0.045, 0.08), Vector3(0, 0.1, -0.08), metal],
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = pt[0]
		mi.mesh = bm; mi.position = pt[1]; mi.material_override = pt[2]
		g.add_child(mi)
	var tip := Marker3D.new(); tip.name = "Muzzle"; tip.position = Vector3(0, 0.04, -0.72)
	g.add_child(tip)
	return g

extends RefCounted
## Drop-in real models.
##   assets/cars/<kind>*.glb|.gltf|.fbx       kind = sedan, taxi, police, swat, ambulance, cashvan
##   assets/characters/<role>*.glb|.gltf|.fbx role = swat, robber, hostage, civilian, officer
## Several files per kind/role are allowed (e.g. sedan_elantra.glb, sedan_corolla.glb) and picked at random.
## Optional assets/cars/setup.json:  {"taxi_elantra.glb": {"rotate": 90}}  (degrees around Y, to make the car face +Z)
## Characters must be Mixamo-rigged (bones named mixamorig...); they reuse the game's walk/run animations.

const EXTS := ["glb", "gltf", "fbx"]
static var _lists := {}
static var _scenes := {}
static var _setup := {}
static var _setup_loaded := false

static func _list(dir: String) -> Array:
	if _lists.has(dir):
		return _lists[dir]
	var out := []
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			# exported games only contain "<file>.import"; strip it to get the source name
			var name := f.trim_suffix(".import").trim_suffix(".remap")
			if name.get_extension().to_lower() in EXTS and not out.has(name):
				out.append(name)
	out.sort()
	_lists[dir] = out
	return out

static func files_for(dir: String, prefix: String) -> Array:
	return _list(dir).filter(func(f: String): return f.to_lower().begins_with(prefix))

static func pick(dir: String, prefix: String, seed_val: int) -> String:
	var fs := files_for(dir, prefix)
	if fs.is_empty():
		return ""
	return dir.path_join(fs[absi(seed_val) % fs.size()])

static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]

static func _rotation_for(file: String) -> float:
	if not _setup_loaded:
		_setup_loaded = true
		var p := "res://assets/cars/setup.json"
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if j is Dictionary:
				_setup = j
	var e = _setup.get(file.get_file(), {})
	return deg_to_rad(float(e.get("rotate", 0.0))) if e is Dictionary else 0.0

static func _opt(file: String, key: String) -> bool:
	_rotation_for(file)
	var e = _setup.get(file.get_file(), {})
	return bool(e.get(key, false)) if e is Dictionary else false

static func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	for c in n.get_children():
		if c is Node3D:
			if not c.visible:
				continue
			var cx: Transform3D = xf * c.transform
			if c is MeshInstance3D and c.mesh and not c.skin:
				var bb: AABB = cx * c.mesh.get_aabb()
				acc[0] = bb if acc[0] == null else (acc[0] as AABB).merge(bb)
			_aabb(c, cx, acc)

## A real car model scaled to `length` metres, wheels on y = 0, facing +Z. null if none provided.
static func car(kind: String, length: float, seed_val: int) -> Node3D:
	var path := pick("res://assets/cars", kind, seed_val)
	if path == "":
		return null
	var ps := scene(path)
	if not ps:
		return null
	var inst: Node3D = ps.instantiate()
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	# lights and cameras baked into the model file (glTF point lights have unlimited range) must go
	for extra in inst.find_children("*", "Light3D", true, false) + inst.find_children("*", "Camera3D", true, false):
		extra.get_parent().remove_child(extra)
		extra.free()
	# Sketchfab exports often carry a big shadow plane and rigged door helpers: hide them
	var keep_skin := _opt(path, "keep_skinned")
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name).to_lower()
		if (mi.skin and not keep_skin) or nm.contains("sombra") or nm.contains("shadow") or nm.begins_with("plane") or nm.contains("ground"):
			mi.visible = false
	var holder := Node3D.new()
	var spin := Node3D.new()
	spin.rotation.y = _rotation_for(path)
	holder.add_child(spin)
	spin.add_child(inst)
	var acc := [null]
	_aabb(holder, Transform3D.IDENTITY, acc)
	if acc[0] == null:
		holder.free()
		return null
	var bb: AABB = acc[0]
	# if the model is longer along X than Z it was authored sideways: turn it
	if bb.size.x > bb.size.z * 1.15:
		spin.rotation.y += PI / 2
		acc = [null]
		_aabb(holder, Transform3D.IDENTITY, acc)
		bb = acc[0]
	var s := length / maxf(bb.size.z, 0.01)
	var wrap := Node3D.new()
	holder.scale = Vector3.ONE * s
	var c := bb.get_center()
	holder.position = Vector3(-c.x * s, -bb.position.y * s, -c.z * s)
	wrap.add_child(holder)
	wrap.set_meta("custom", true)
	return wrap

static var _roles = null

## Path of a real character model for this role ("" if none provided).
## assets/characters/roles.json can list several files per role (a file may serve several roles).
static func character(role: String, seed_val: int) -> String:
	if _roles == null:
		_roles = {}
		var p := "res://assets/characters/roles.json"
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if j is Dictionary:
				_roles = j
	if _roles.has(role) and (_roles[role] as Array).size() > 0:
		var arr: Array = _roles[role]
		return "res://assets/characters".path_join(arr[absi(seed_val) % arr.size()])
	return pick("res://assets/characters", role, seed_val)

## A real weapon model, scaled to `length`, barrel along -Z, rear end at z = +rear. null if none.
## assets/weapons/setup.json: {"rifle_swat.glb": {"rotate": 90}} turns the model so the muzzle faces -Z.
static func weapon(name: String, length: float, rear: float) -> Node3D:
	var path := "res://assets/weapons/%s.glb" % name
	var ps := scene(path) if ResourceLoader.exists(path) else null
	if not ps:
		return null
	var inst: Node3D = ps.instantiate()
	var holder := Node3D.new()
	var spin := Node3D.new()
	var rot := 0.0
	var sp := "res://assets/weapons/setup.json"
	if FileAccess.file_exists(sp):
		var j = JSON.parse_string(FileAccess.get_file_as_string(sp))
		if j is Dictionary and j.has(name + ".glb"):
			rot = deg_to_rad(float(j[name + ".glb"].get("rotate", 0.0)))
	spin.rotation.y = rot
	holder.add_child(spin)
	spin.add_child(inst)
	var acc := [null]
	_aabb(holder, Transform3D.IDENTITY, acc)
	if acc[0] == null:
		holder.free()
		return null
	var bb: AABB = acc[0]
	var s := length / maxf(bb.size.z, 0.001)
	holder.scale = Vector3.ONE * s
	var c := bb.get_center()
	# rear end (max z) sits at +rear, barrel runs toward -Z
	holder.position = Vector3(-c.x * s, -c.y * s, rear - bb.end.z * s)
	var wrap := Node3D.new()
	wrap.add_child(holder)
	for mi in wrap.find_children("*", "GeometryInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return wrap

## Generic prop (tree, building…) scaled so its height is `height` (0 = keep size), base on y = 0.
static func prop(name: String, height := 0.0) -> Node3D:
	var path := "res://assets/props/%s.glb" % name
	var ps := scene(path) if ResourceLoader.exists(path) else null
	if not ps:
		return null
	var inst: Node3D = ps.instantiate()
	var holder := Node3D.new()
	holder.add_child(inst)
	var acc := [null]
	_aabb(holder, Transform3D.IDENTITY, acc)
	if acc[0] == null:
		holder.free()
		return null
	var bb: AABB = acc[0]
	var s := height / maxf(bb.size.y, 0.001) if height > 0.0 else 1.0
	holder.scale = Vector3.ONE * s
	var c := bb.get_center()
	holder.position = Vector3(-c.x * s, -bb.position.y * s, -c.z * s)
	var wrap := Node3D.new()
	wrap.add_child(holder)
	wrap.set_meta("size", bb.size * s)
	return wrap

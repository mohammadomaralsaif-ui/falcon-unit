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

static func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	for c in n.get_children():
		if c is Node3D:
			var cx: Transform3D = xf * c.transform
			if c is MeshInstance3D and c.mesh:
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

## Path of a real character model for this role ("" if none provided).
static func character(role: String, seed_val: int) -> String:
	return pick("res://assets/characters", role, seed_val)

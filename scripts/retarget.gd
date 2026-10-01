extends RefCounted
## Retargets the Mixamo soldier animations (Idle / Walk / Run) onto the Ready Player Me
## civilian skeleton, so realistic clothed people can walk and run.
## Works in "model space" (both characters facing -Z) and aligns rest bone directions,
## because the soldier rests in a T-pose while the civilian rests in an A-pose.

static var _libs := {}

static func _rot(b: Basis) -> Quaternion:
	return b.orthonormalized().get_rotation_quaternion()

static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	a = a.normalized(); b = b.normalized()
	var d := a.dot(b)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var ax := a.cross(Vector3.RIGHT)
		if ax.length() < 0.01:
			ax = a.cross(Vector3.UP)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(d))

static func _chain(root: Node, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

static var _rx: RegEx

## "mixamorig7_Hips" / "mixamorig:Hips" / "Hips" -> "Hips"
static func _bare(n: String) -> String:
	if not _rx:
		_rx = RegEx.create_from_string("^mixamorig\\d*[_:]")
	return _rx.sub(n, "")

## path: target model (any Mixamo / Ready Player Me compatible rig facing +Z).
static func library(model := "res://assets/models/civilian.glb") -> AnimationLibrary:
	if _libs.has(model):
		return _libs[model]
	var src: Node3D = load("res://assets/models/soldier.glb").instantiate()
	var tgt: Node3D = load(model).instantiate()
	var ssk: Skeleton3D = src.find_child("Skeleton3D", true, false)
	var tsk: Skeleton3D = tgt.find_child("Skeleton3D", true, false)
	var sroot: Transform3D = _chain(src, ssk)
	var troot: Transform3D = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * _chain(tgt, tsk)
	var skel_path := String(tgt.get_path_to(tsk))
	var sroot_q := _rot(sroot.basis)
	var troot_q := _rot(troot.basis)
	# model-space global rests
	var Gs := {}
	var Gt := {}
	var Ps := {}
	var Pt := {}
	for i in ssk.get_bone_count():
		var g := ssk.get_bone_global_rest(i)
		Gs[i] = sroot_q * _rot(g.basis)
		Ps[i] = sroot * g.origin
	for i in tsk.get_bone_count():
		var g := tsk.get_bone_global_rest(i)
		Gt[i] = troot_q * _rot(g.basis)
		Pt[i] = troot * g.origin
	# bone map target -> source (and bare name -> target bone)
	var tbare := {}
	for i in tsk.get_bone_count():
		tbare[_bare(tsk.get_bone_name(i))] = i
	var map := {}
	for i in tsk.get_bone_count():
		var si := ssk.find_bone("mixamorig_" + _bare(tsk.get_bone_name(i)))
		if si >= 0:
			map[i] = si
	# aligned target rests: rotate each target bone so it points like the source bone
	var Gt_al := {}
	for i in tsk.get_bone_count():
		var al := Quaternion.IDENTITY
		var p := tsk.get_bone_parent(i)
		if p >= 0 and Gt_al.has(p):
			al = Gt_al[p] * Gt[p].inverse()
		if map.has(i):
			var kids := tsk.get_bone_children(i)
			var si: int = map[i]
			var skids := ssk.get_bone_children(si)
			if kids.size() > 0 and skids.size() > 0:
				var tc: int = kids[0]
				var sc := ssk.find_bone("mixamorig_" + _bare(tsk.get_bone_name(tc)))
				if sc < 0:
					sc = skids[0]
				var dt: Vector3 = Pt[tc] - Pt[i]
				var ds: Vector3 = Ps[sc] - Ps[si]
				if dt.length() > 0.001 and ds.length() > 0.001:
					var name := _bare(tsk.get_bone_name(i))
					# keep spine / neck / head / hips upright from the target's own rest
					if not (name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"]):
						al = _arc(dt, ds)
		Gt_al[i] = al * Gt[i]
	var hip_t := -1
	for i in tsk.get_bone_count():
		if _bare(tsk.get_bone_name(i)) == "Hips":
			hip_t = i
	var hip_s := ssk.find_bone("mixamorig_Hips")
	var ratio: float = Pt[hip_t].y / maxf(Ps[hip_s].y, 0.01)
	var sap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
	var lib := AnimationLibrary.new()
	for an in ["Idle", "Walk", "Run"]:
		var a := sap.get_animation(an)
		var out := Animation.new()
		out.length = a.length
		out.loop_mode = Animation.LOOP_LINEAR
		for t in a.get_track_count():
			var path := String(a.track_get_path(t))
			var bname := path.get_slice(":", 1)
			var si := ssk.find_bone(bname)
			if si < 0:
				continue
			var ti: int = tbare.get(_bare(bname), -1)
			if ti < 0:
				continue
			var tpath := NodePath(skel_path + ":" + tsk.get_bone_name(ti))
			var typ := a.track_get_type(t)
			if typ == Animation.TYPE_ROTATION_3D:
				var sp := ssk.get_bone_parent(si)
				var tp := tsk.get_bone_parent(ti)
				var gsp: Quaternion = Gs[sp] if sp >= 0 else sroot_q
				var gtp: Quaternion = Gt_al[tp] if tp >= 0 else troot_q
				var gtp_real: Quaternion = gtp
				var nt := out.add_track(Animation.TYPE_ROTATION_3D)
				out.track_set_path(nt, tpath)
				out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
				for k in a.track_get_key_count(t):
					var qs: Quaternion = a.track_get_key_value(t, k)
					var qt: Quaternion = gtp_real.inverse() * gsp * qs * Gs[si].inverse() * Gt_al[ti]
					# convert from aligned-parent frame to the real parent frame
					if tp >= 0:
						qt = qt
					out.rotation_track_insert_key(nt, a.track_get_key_time(t, k), qt.normalized())
			elif typ == Animation.TYPE_POSITION_3D and si == hip_s:
				var nt := out.add_track(Animation.TYPE_POSITION_3D)
				out.track_set_path(nt, tpath)
				for k in a.track_get_key_count(t):
					var ps: Vector3 = a.track_get_key_value(t, k)
					var world: Vector3 = sroot * ps
					var delta: Vector3 = (world - Ps[si]) * ratio
					delta.z = 0.0  # keep animations in place
					var tw: Vector3 = Pt[ti] + delta
					out.position_track_insert_key(nt, a.track_get_key_time(t, k), troot.affine_inverse() * tw)
		lib.add_animation(an, out)
	src.free()
	tgt.free()
	_libs[model] = lib
	return lib

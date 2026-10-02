extends SkeletonModifier3D
## Procedural upper-body / leg posing on top of the walk cycle:
##  "rifle"      – two-bone IK puts both hands on the weapon
##  "hands_up"   – surrender, hands raised
##  "kneel_head" – kneeling, hands on the head (hostage)
##  "kneel_back" – kneeling, hands behind the back (cuffed suspect)
##  "none"       – plain animation

var mode := "rifle"
var grip: Node3D        # right hand target
var guard: Node3D       # left hand target
var body: Node3D        # the Person node (faces -Z, metres, Y up)
var _b := {}
var point_at := Vector3.ZERO   # world position the "point" gesture aims at
var sit := 0.0          # 0..1: seated on a chair / sofa (hips at seat height, thighs forward)
var crouch := 0.0       # 0..1: lower the hips and bend the legs (feet stay planted)
var twist := 0.0        # radians: turn the chest about the vertical (legs strafe, sights stay on target)
var K := Transform3D.IDENTITY   # "civilian space" (Y up, +Z forward, metres) -> skeleton space

func _bone(n: String) -> int:
	if not _b.has(n):
		var sk := get_skeleton()
		var i := sk.find_bone(n)
		if i < 0:
			# any Mixamo prefix: mixamorig_, mixamorig7_, …
			for k in sk.get_bone_count():
				var bn := sk.get_bone_name(k)
				if bn.begins_with("mixamorig") and (bn.ends_with("_" + n) or bn.ends_with(":" + n)) and not bn.ends_with("Fore" + n):
					i = k
					break
		_b[n] = i
	return _b[n]

func _toS(p: Vector3) -> Vector3:
	return K * p

func _toC(p: Vector3) -> Vector3:
	return K.affine_inverse() * p

func _dirS(d: Vector3) -> Vector3:
	return (K.basis * d).normalized()

func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk or (mode == "none" and sit <= 0.01 and crouch <= 0.01 and absf(twist) <= 0.01):
		return
	var inv := sk.global_transform.affine_inverse()
	if body:
		K = inv * body.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	if sit > 0.01:
		_sit(sk)
	elif crouch > 0.01 and not mode.begins_with("kneel"):
		_crouch(sk)
	if absf(twist) > 0.01:
		var up := _dirS(Vector3.UP)
		for bn in ["Spine", "Spine1", "Spine2"]:
			var bi := _bone(bn)
			if bi >= 0:
				var g := sk.get_bone_global_pose(bi)
				g.basis = Basis(up, twist / 3.0) * g.basis
				sk.set_bone_global_pose(bi, g)
	match mode:
		"rifle":
			if grip and guard and grip.is_inside_tree():
				_ik("Right", inv * grip.global_position, Vector3(-0.6, -1.0, -0.5))
				_ik("Left", inv * guard.global_position, Vector3(0.7, -1.0, 0.0))
		"hands_up":
			var h := _toC(sk.get_bone_global_pose(_bone("Head")).origin)
			_ik("Right", _toS(h + Vector3(-0.22, 0.32, 0.05)), Vector3(-1, 0, -0.3))
			_ik("Left", _toS(h + Vector3(0.22, 0.32, 0.05)), Vector3(1, 0, -0.3))
		"talk":
			# explaining with the hands: both forearms up, moving with the speech rhythm
			var h := _toC(sk.get_bone_global_pose(_bone("Head")).origin)
			var t := Time.get_ticks_msec() * 0.001
			_ik("Right", _toS(h + Vector3(-0.2 - 0.06 * sin(t * 2.1), -0.42 + 0.09 * sin(t * 3.3), 0.34 + 0.05 * sin(t * 1.7))), Vector3(-0.8, -1, -0.2))
			_ik("Left", _toS(h + Vector3(0.18 + 0.04 * sin(t * 1.6 + 1.0), -0.5 + 0.05 * sin(t * 2.7 + 2.0), 0.3)), Vector3(0.8, -1, -0.2))
		"point":
			# arm stretched toward a place in the world (the bank door, the yard…)
			var hw := sk.get_bone_global_pose(_bone("RightArm")).origin
			var tgt := inv * point_at
			var dir := (tgt - hw).normalized()
			_ik("Right", hw + dir * 0.62 + _dirS(Vector3(0, 1, 0)) * 0.05, Vector3(-0.3, -1, 0))
		"salute":
			var h := _toC(sk.get_bone_global_pose(_bone("Head")).origin)
			_ik("Right", _toS(h + Vector3(-0.14, 0.07, 0.1)), Vector3(-1, -0.2, -0.1))
		"radio", "mic":
			# handset / microphone held up near the mouth
			var h := _toC(sk.get_bone_global_pose(_bone("Head")).origin)
			_ik("Right", _toS(h + Vector3(-0.07, -0.13, 0.17)), Vector3(-0.7, -1, 0))
		"camera":
			var h := _toC(sk.get_bone_global_pose(_bone("Head")).origin)
			_ik("Right", _toS(h + Vector3(-0.12, -0.12, 0.3)), Vector3(-0.8, -0.8, 0))
			_ik("Left", _toS(h + Vector3(0.1, -0.2, 0.34)), Vector3(0.8, -0.8, 0))
		"kneel_head", "kneel_back":
			_kneel(sk)
			var h := _toC(sk.get_bone_global_pose(_bone("Head")).origin)
			if mode == "kneel_head":
				_ik("Right", _toS(h + Vector3(-0.1, 0.12, -0.02)), Vector3(-1, 0.2, 0.2))
				_ik("Left", _toS(h + Vector3(0.1, 0.12, -0.02)), Vector3(1, 0.2, 0.2))
			else:
				var hip := _toC(sk.get_bone_global_pose(_bone("Hips")).origin)
				_ik("Right", _toS(hip + Vector3(-0.05, 0.02, -0.2)), Vector3(-1, 0, 0.3))
				_ik("Left", _toS(hip + Vector3(0.05, 0.02, -0.2)), Vector3(1, 0, 0.3))

func _point(b: int, child: int, dir: Vector3) -> void:
	var sk := get_skeleton()
	var g := sk.get_bone_global_pose(b)
	var c := sk.get_bone_global_pose(child).origin
	var cur := (c - g.origin)
	if cur.length() < 0.0001:
		return
	var q := _arc(cur.normalized(), _dirS(dir))
	g.basis = Basis(q) * g.basis
	sk.set_bone_global_pose(b, g)

func _kneel(sk: Skeleton3D) -> void:
	for s in ["Left", "Right"]:
		var x := 0.1 if s == "Left" else -0.1
		_point(_bone(s + "UpLeg"), _bone(s + "Leg"), Vector3(x * 0.4, -1, 0.12))
		_point(_bone(s + "Leg"), _bone(s + "Foot"), Vector3(0, -0.12, -1))
		_point(_bone(s + "Foot"), _bone(s + "ToeBase"), Vector3(0, -0.2, -1))
	var hips := sk.get_bone_global_pose(_bone("Hips"))
	var hc := _toC(hips.origin)
	hc.y = 0.55
	hips.origin = _toS(hc)
	sk.set_bone_global_pose(_bone("Hips"), hips)

## Seated: the pelvis drops to `sit_h` above the floor, the feet stay planted on the floor in front
## (two-bone leg IK, so nothing sinks through it), the back leans in, hands rest on the knees.
var sit_h := 0.6        # pelvis height above the floor: 0.6 for a chair, ~0.45 for a low lounge sofa

func _sit(sk: Skeleton3D) -> void:
	var hi := _bone("Hips")
	if hi < 0:
		return
	var feet := {}
	for s in ["Left", "Right"]:
		var f := _bone(s + "Foot")
		if f >= 0:
			feet[s] = _toC(sk.get_bone_global_pose(f).origin)
	var hips := sk.get_bone_global_pose(hi)
	var hc := _toC(hips.origin)
	hc.y = lerpf(hc.y, sit_h, sit)
	hc.z -= 0.1 * sit
	hips.origin = _toS(hc)
	sk.set_bone_global_pose(hi, hips)
	var sp := _bone("Spine")
	if sp >= 0:
		var g := sk.get_bone_global_pose(sp)
		g.basis = Basis(_dirS(Vector3(1, 0, 0)), 0.2 * sit) * g.basis
		sk.set_bone_global_pose(sp, g)
	for s in feet:
		var x := 0.13 if s == "Left" else -0.13
		var stand: Vector3 = feet[s]
		var seated := Vector3(x, maxf(stand.y, 0.07), hc.z + 0.56)
		_leg_ik(s, _toS(stand.lerp(seated, sit)), _dirS(Vector3(x * 0.5, 0.8, 1.0)))
	if mode == "none" and sit > 0.6:
		for s in ["Left", "Right"]:
			var kb := _bone(s + "Leg")
			if kb < 0:
				continue
			var knee := _toC(sk.get_bone_global_pose(kb).origin)
			var sx := 1.0 if s == "Left" else -1.0
			_ik(s, _toS(knee + Vector3(sx * 0.02, 0.08, -0.04)), Vector3(sx, -0.4, -0.3))

func _crouch(sk: Skeleton3D) -> void:
	var hi := _bone("Hips")
	if hi < 0:
		return
	var feet := {}
	for s in ["Left", "Right"]:
		var f := _bone(s + "Foot")
		if f >= 0:
			feet[s] = sk.get_bone_global_pose(f).origin
	var hips := sk.get_bone_global_pose(hi)
	var hc := _toC(hips.origin)
	hc.y -= 0.42 * crouch
	hc.z -= 0.08 * crouch
	hips.origin = _toS(hc)
	sk.set_bone_global_pose(hi, hips)
	# lean the chest forward a little, like a real low-ready stance
	var sp := _bone("Spine")
	if sp >= 0:
		var g := sk.get_bone_global_pose(sp)
		g.basis = Basis(_dirS(Vector3(1, 0, 0)), 0.3 * crouch) * g.basis
		sk.set_bone_global_pose(sp, g)
	for s in feet:
		var x := 0.15 if s == "Left" else -0.15
		_leg_ik(s, feet[s], _dirS(Vector3(x, 0.0, 1.0)))

## Two-bone IK for a leg: thigh + shin reach the foot target, knee bends toward `pole` (skeleton space).
func _leg_ik(side: String, target: Vector3, pole: Vector3) -> void:
	var sk := get_skeleton()
	var ua := _bone(side + "UpLeg")
	var fa := _bone(side + "Leg")
	var ha := _bone(side + "Foot")
	if ua < 0 or fa < 0 or ha < 0:
		return
	var foot_basis := sk.get_bone_global_pose(ha).basis
	var gu := sk.get_bone_global_pose(ua)
	var gf := sk.get_bone_global_pose(fa)
	var gh := sk.get_bone_global_pose(ha)
	var S := gu.origin
	var a := S.distance_to(gf.origin)
	var b := gf.origin.distance_to(gh.origin)
	var to := target - S
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.005)
	var dir := to.normalized()
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var perp := pole - dir * pole.dot(dir)
	if perp.length() < 0.001:
		return
	perp = perp.normalized()
	var E := S + dir * x + perp * h
	var T := S + dir * d
	gu.basis = Basis(_arc((gf.origin - S).normalized(), (E - S).normalized())) * gu.basis
	sk.set_bone_global_pose(ua, gu)
	gf = sk.get_bone_global_pose(fa)
	gh = sk.get_bone_global_pose(ha)
	gf.basis = Basis(_arc((gh.origin - gf.origin).normalized(), (T - gf.origin).normalized())) * gf.basis
	sk.set_bone_global_pose(fa, gf)
	# keep the foot flat as it was in the animation
	gh = sk.get_bone_global_pose(ha)
	gh.basis = foot_basis
	sk.set_bone_global_pose(ha, gh)

static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var d := clampf(a.dot(b), -1.0, 1.0)
	if d > 0.9999:
		return Quaternion.IDENTITY
	var ax := a.cross(b)
	if ax.length() < 0.0001:
		ax = Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT
	return Quaternion(ax.normalized(), acos(d))

## Two-bone IK in skeleton space. pole: rough elbow direction (skeleton space, +Z = forward).
func _ik(side: String, target: Vector3, pole: Vector3) -> void:
	var sk := get_skeleton()
	var ua := _bone(side + "Arm")
	var fa := _bone(side + "ForeArm")
	var ha := _bone(side + "Hand")
	if ua < 0 or fa < 0 or ha < 0:
		return
	var gu := sk.get_bone_global_pose(ua)
	var gf := sk.get_bone_global_pose(fa)
	var gh := sk.get_bone_global_pose(ha)
	var S := gu.origin
	var a := S.distance_to(gf.origin)
	var b := gf.origin.distance_to(gh.origin)
	var to := target - S
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.005)
	var dir := to.normalized()
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var pn := _dirS(pole)
	var perp := (pn - dir * pn.dot(dir))
	if perp.length() < 0.001:
		perp = Vector3.DOWN
	perp = perp.normalized()
	var E := S + dir * x + perp * h
	var T := S + dir * d
	# upper arm
	var q1 := _arc((gf.origin - S).normalized(), (E - S).normalized())
	gu.basis = Basis(q1) * gu.basis
	sk.set_bone_global_pose(ua, gu)
	# forearm (re-read after parent change)
	gf = sk.get_bone_global_pose(fa)
	gh = sk.get_bone_global_pose(ha)
	var q2 := _arc((gh.origin - gf.origin).normalized(), (T - gf.origin).normalized())
	gf.basis = Basis(q2) * gf.basis
	sk.set_bone_global_pose(fa, gf)

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
var _b := {}

func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone(n)
	return _b[n]

func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk or mode == "none":
		return
	var inv := sk.global_transform.affine_inverse()
	match mode:
		"rifle":
			if grip and guard and grip.is_inside_tree():
				_ik("Right", inv * grip.global_position, Vector3(-0.6, -1.0, -0.5))
				_ik("Left", inv * guard.global_position, Vector3(0.7, -1.0, 0.0))
		"hands_up":
			var h := sk.get_bone_global_pose(_bone("Head")).origin
			_ik("Right", h + Vector3(-0.22, 0.32, 0.05), Vector3(-1, 0, -0.3))
			_ik("Left", h + Vector3(0.22, 0.32, 0.05), Vector3(1, 0, -0.3))
		"kneel_head", "kneel_back":
			_kneel(sk)
			var h := sk.get_bone_global_pose(_bone("Head")).origin
			if mode == "kneel_head":
				_ik("Right", h + Vector3(-0.1, 0.12, -0.02), Vector3(-1, 0.2, 0.2))
				_ik("Left", h + Vector3(0.1, 0.12, -0.02), Vector3(1, 0.2, 0.2))
			else:
				var hip := sk.get_bone_global_pose(_bone("Hips")).origin
				_ik("Right", hip + Vector3(-0.05, 0.02, -0.2), Vector3(-1, 0, 0.3))
				_ik("Left", hip + Vector3(0.05, 0.02, -0.2), Vector3(1, 0, 0.3))

func _point(b: int, child: int, dir: Vector3) -> void:
	var sk := get_skeleton()
	var g := sk.get_bone_global_pose(b)
	var c := sk.get_bone_global_pose(child).origin
	var cur := (c - g.origin)
	if cur.length() < 0.0001:
		return
	var q := _arc(cur.normalized(), dir.normalized())
	g.basis = Basis(q) * g.basis
	sk.set_bone_global_pose(b, g)

func _kneel(sk: Skeleton3D) -> void:
	for s in ["Left", "Right"]:
		var x := 0.1 if s == "Left" else -0.1
		_point(_bone(s + "UpLeg"), _bone(s + "Leg"), Vector3(x * 0.4, -1, 0.12))
		_point(_bone(s + "Leg"), _bone(s + "Foot"), Vector3(0, -0.12, -1))
		_point(_bone(s + "Foot"), _bone(s + "ToeBase"), Vector3(0, -0.2, -1))
	var hips := sk.get_bone_global_pose(_bone("Hips"))
	hips.origin.y = 0.55
	sk.set_bone_global_pose(_bone("Hips"), hips)

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
	var pn := pole.normalized()
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

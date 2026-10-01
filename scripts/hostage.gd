extends StaticBody3D
## Bank hostage: kneeling civilian with hands behind the head. Press E nearby to free them.

const Humanoid = preload("res://scripts/humanoid.gd")

var main: Node
var dead := false
var rescued := false
var model: Node3D

func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.3
	cs.shape = cap; cs.position = Vector3(0, 0.65, 0)
	add_child(cs)
	model = Humanoid.civilian()
	add_child(model)
	_pose()

func _pose() -> void:
	var sk := Humanoid.skeleton(model)
	if not sk:
		return
	# kneel: lower the whole body and fold the legs; hands on head
	_rot_global(sk, "LeftUpLeg", Vector3(1, 0, 0), -1.5)
	_rot_global(sk, "RightUpLeg", Vector3(1, 0, 0), -1.5)
	_rot_global(sk, "LeftLeg", Vector3(1, 0, 0), 1.5)
	_rot_global(sk, "RightLeg", Vector3(1, 0, 0), 1.5)
	model.position.y = -0.45
	_arm_up(sk, "Left")
	_arm_up(sk, "Right")

func _bone(sk: Skeleton3D, n: String) -> int:
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		if bn == n or bn.ends_with(":" + n) or bn.ends_with("_" + n):
			return i
	return -1

## Rotate a bone in skeleton space (axis given in skeleton/global space) about its rest pose.
func _rot_global(sk: Skeleton3D, n: String, axis: Vector3, ang: float) -> void:
	var b := _bone(sk, n)
	if b < 0:
		return
	var p := sk.get_bone_parent(b)
	var parent_g := sk.get_bone_global_pose(p).basis if p >= 0 else Basis()
	var g := sk.get_bone_global_pose(b).basis
	var ng := Basis(axis.normalized(), ang) * g
	sk.set_bone_pose_rotation(b, (parent_g.inverse() * ng).get_rotation_quaternion())

func _arm_up(sk: Skeleton3D, side: String) -> void:
	var arm := _bone(sk, side + "Arm")
	var fore := _bone(sk, side + "ForeArm")
	if arm < 0 or fore < 0:
		return
	var a_pos := sk.get_bone_global_pose(arm).origin
	var f_pos := sk.get_bone_global_pose(fore).origin
	var out := (f_pos - a_pos)
	var sgn := 1.0 if out.x > 0 else -1.0
	# upper arm: raise slightly and swing back so the elbow points out to the side
	_rot_global(sk, side + "Arm", Vector3(0, 0, 1), sgn * 0.5)
	# forearm folds up toward the head
	_rot_global(sk, side + "ForeArm", Vector3(0, 1, 0), sgn * 2.4)

func take_hit(_dmg: float, _head := false, from: Node3D = null) -> bool:
	if dead or rescued:
		return false
	dead = true
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", -PI / 2, 0.5)
	if main:
		main.on_hostage_dead(self, from)
	return true

func rescue() -> void:
	if dead or rescued:
		return
	rescued = true
	collision_layer = 0
	var tw := create_tween()
	tw.tween_property(model, "position:y", 0.0, 0.4)
	tw.tween_interval(1.0)
	tw.tween_property(model, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	tw.tween_callback(func(): visible = false)

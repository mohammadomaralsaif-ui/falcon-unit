extends StaticBody3D
## Bank hostage: kneels with hands on head. Press E to free them, then they follow the
## player's exact path (breadcrumb trail) out of the building to the ambulance.

const Person = preload("res://scripts/person.gd")
const Fx = preload("res://scripts/fx.gd")

var main: Node
var dead := false
var freed := false     # following the player
var rescued := false   # out of the building, safe
var model: Node3D
var trail_idx := 0
var gone := false
var escort: Node3D = null   # teammate walking this hostage out (null = follow the player)

func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.3
	cs.shape = cap; cs.position = Vector3(0, 0.65, 0)
	add_child(cs)
	model = Person.new("hostage")
	add_child(model)
	model.set_mode("kneel_head")

func take_hit(_dmg: float, _head := false, from: Node3D = null) -> bool:
	if dead or rescued:
		return false
	dead = true
	freed = false
	model.set_mode("none")
	model.anim.pause()
	model.collapse()
	if main:
		main.on_hostage_dead(self, from)
		get_tree().create_timer(1.7).timeout.connect(func(): Fx.blood_pool(main, model.fallen_center()))
	return true

func free_hostage(trail_size: int) -> void:
	if dead or freed or rescued:
		return
	freed = true
	model.set_mode("none")
	model.play("Idle")
	trail_idx = maxi(trail_size - 1, 0)

func _physics_process(dt: float) -> void:
	if dead or gone or not main:
		return
	var goal := Vector3.INF
	var spd := 0.0
	if rescued:
		goal = main.city.cordon_point + Vector3(13, 0, 4)
		spd = 3.0
	elif freed:
		if escort and (not is_instance_valid(escort) or escort.dead):
			escort = null
		var leader: Node3D = escort if escort else main.player
		var pl: Vector3 = leader.global_position
		var dl := global_position.distance_to(pl)
		if dl > 1.9:
			if main.nav_ready:
				goal = main.nav_step(global_position, pl)
			else:
				var trail: Array = main.trail
				if trail.size() > 0:
					trail_idx = mini(trail_idx, trail.size() - 1)
					goal = trail[trail_idx]
					if Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 0.9 and trail_idx < trail.size() - 1:
						trail_idx += 1
						goal = trail[trail_idx]
			spd = 4.6 if dl > 5.0 else 2.2
		# out of the bank?
		var dz: float = main.city.door_pos.z
		if global_position.z > dz + 3.5 or (global_position.z > dz + 1.2 and pl.z > dz + 3.0):
			rescued = true
			freed = false
			main.on_hostage_saved(self)
	if goal == Vector3.INF:
		model.play("Idle")
		return
	var d := goal - global_position
	d.y = 0
	if d.length() < 0.6:
		model.play("Idle")
		if rescued:
			gone = true
			var tw := create_tween()
			tw.tween_interval(1.5)
			tw.tween_callback(_vanish)
		return
	var step := d.normalized() * minf(spd * dt, d.length())
	global_position += step
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-dt * 10.0))
	model.play("Run" if spd > 3.5 else "Walk", spd / (5.5 if spd > 3.5 else 1.6))

func _vanish() -> void:
	visible = false
	collision_layer = 0

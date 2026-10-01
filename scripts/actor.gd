extends CharacterBody3D
## AI soldier used for both gunmen (side = "enemy") and SWAT teammates (side = "team").

const Person = preload("res://scripts/person.gd")
const Fx = preload("res://scripts/fx.gd")

var main: Node
var side := "enemy"
var display_name := ""
var model: Node3D
var gun: Node3D
var muzzle: Marker3D
var hp := 100.0
var dead := false
var surrendered := false
var cuffed := false
var state := "idle"
var target: Node3D = null
var react := 0.0
var fire_cd := 0.0
var burst := 0
var stun := 0.0
var think := 0.0
var last_seen := Vector3.ZERO
var hunter := false
var home_yaw := 0.0
var follow_offset := Vector3.ZERO
var cur_anim := ""
var accuracy := 0.42
var damage := 10.0

func setup(_main: Node, _side: String, pos: Vector3, yaw: float, name_ := "") -> void:
	main = _main
	side = _side
	display_name = name_
	position = pos
	rotation.y = yaw
	home_yaw = yaw
	hunter = randf() < 0.45

func _ready() -> void:
	collision_layer = 2 if side == "enemy" else 16
	collision_mask = 1 | 4 | 8 | (16 if side == "enemy" else 2)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.8
	cs.shape = cap; cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	model = Person.new("swat" if side == "team" else "robber")
	add_child(model)
	gun = model.gun
	muzzle = model.muzzle
	if side == "team":
		var tag := Label3D.new()
		tag.text = "▼ " + display_name
		tag.font = load("res://assets/fonts/Tajawal-Bold.ttf")
		tag.font_size = 30; tag.pixel_size = 0.0011; tag.fixed_size = true; tag.outline_size = 8
		tag.modulate = Color(0.45, 0.7, 1.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = Vector3(0, 2.25, 0)
		add_child(tag)

func _physics_process(dt: float) -> void:
	if dead:
		return
	fire_cd -= dt
	stun -= dt
	think -= dt
	if not is_on_floor():
		velocity.y -= 9.8 * dt
	else:
		velocity.y = 0.0
	var move := Vector3.ZERO
	if surrendered:
		velocity.x = 0; velocity.z = 0
		move_and_slide()
		return
	if stun > 0.0:
		rotation.y += sin(Time.get_ticks_msec() * 0.01) * dt * 2.0
		_play("Idle")
		move_and_slide()
		return
	if side == "enemy":
		move = _enemy_ai(dt)
	else:
		move = _team_ai(dt)
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	_play("Run" if hs > 3.5 else ("Walk" if hs > 0.3 else "Idle"))
	var aim_pitch := 0.0
	if target and is_instance_valid(target):
		var tp := target.global_position + Vector3(0, 1.3, 0)
		var d := tp - (global_position + Vector3(0, 1.3, 0))
		aim_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	model.set_aim(lerpf(model.aim_pitch, aim_pitch if target else -0.35, 1.0 - exp(-dt * 8.0)))

func _play(n: String) -> void:
	var hs := Vector2(velocity.x, velocity.z).length()
	model.play(n, clampf(hs / (5.5 if n == "Run" else 1.6), 0.7, 1.5) if n != "Idle" else 1.0)

func _eye() -> Vector3:
	return global_position + Vector3(0, 1.6, 0)

func can_see(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_eye(), p, 1 | 8)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _face(p: Vector3, dt: float, rate := 6.0) -> float:
	var want := atan2(-(p.x - global_position.x), -(p.z - global_position.z))
	var d := wrapf(want - rotation.y, -PI, PI)
	rotation.y += clampf(d, -rate * dt, rate * dt)
	return abs(d)

func _enemy_ai(dt: float) -> Vector3:
	if think <= 0.0:
		think = randf_range(0.15, 0.3)
		var best: Node3D = null
		var bd := 48.0
		for t in main.enemy_targets():
			var tp: Vector3 = t.global_position + Vector3(0, 1.4, 0)
			var d := global_position.distance_to(tp)
			if d > bd:
				continue
			if state == "idle":
				var to := (tp - global_position).normalized()
				var fwd := -global_transform.basis.z
				if fwd.dot(to) < 0.2 and d > 5.0:
					continue
			if can_see(tp):
				best = t; bd = d
		if best:
			if target != best:
				react = main.diff_react * randf_range(0.7, 1.3)
			if state == "idle":
				alert(best.global_position)
			target = best
			last_seen = best.global_position
		else:
			target = null
	if target and is_instance_valid(target):
		var ang := _face(target.global_position, dt, 5.0)
		react -= dt
		if react <= 0.0 and fire_cd <= 0.0 and ang < 0.45:
			_shoot_at(target)
			burst += 1
			if burst >= 3:
				burst = 0
				fire_cd = randf_range(0.7, 1.4)
			else:
				fire_cd = 0.12
		return Vector3.ZERO
	if state == "alert" and hunter:
		var d := last_seen - global_position
		d.y = 0
		if d.length() > 2.0:
			_face(last_seen, dt, 6.0)
			return d.normalized() * 3.2
	elif state == "idle":
		rotation.y = home_yaw + sin(Time.get_ticks_msec() * 0.0004 + position.x) * 0.7
	return Vector3.ZERO

func _team_ai(dt: float) -> Vector3:
	var pl: Node3D = main.player
	if think <= 0.0:
		think = randf_range(0.2, 0.35)
		target = null
		var bd := 42.0
		for e in main.enemies:
			if e.dead or e.surrendered:
				continue
			var d := global_position.distance_to(e.global_position)
			if d < bd and can_see(e.global_position + Vector3(0, 1.3, 0)):
				bd = d; target = e
	var move := Vector3.ZERO
	var goal: Vector3 = pl.global_position + pl.global_transform.basis * follow_offset
	var dg := goal - global_position
	dg.y = 0
	if dg.length() > 1.0:
		var spd := 6.5 if dg.length() > 7.0 else 4.0
		move = dg.normalized() * spd
	if target and is_instance_valid(target):
		var ang := _face(target.global_position, dt, 7.0)
		if fire_cd <= 0.0 and ang < 0.3:
			fire_cd = randf_range(0.25, 0.5)
			_shoot_at(target)
	elif move.length() > 0.3:
		_face(global_position + move, dt, 8.0)
	else:
		_face(global_position - pl.global_transform.basis.z, dt, 3.0)
	return move

func _shoot_at(t: Node3D) -> void:
	var from := muzzle.global_position
	var tp := t.global_position + Vector3(0, 1.35, 0)
	var dist := from.distance_to(tp)
	var acc: float = accuracy * clampf(1.15 - dist / 45.0, 0.3, 1.1)
	if side == "team":
		acc = 0.35 * clampf(1.2 - dist / 45.0, 0.35, 1.0)
		if t.get("stun") and t.stun > 0.0:
			acc = 0.75
	var end := tp
	# the bullet only lands if nothing solid (walls, cars) is in the way right now
	var los := PhysicsRayQueryParameters3D.create(from, tp, 1 | 8)
	los.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(los).is_empty():
		acc = 0.0
	if randf() < acc and t.has_method("take_hit"):
		var killed: bool = t.take_hit(damage if side == "enemy" else randf_range(22, 34), false, self)
		if side == "team" and killed:
			main.on_team_kill(self)
	else:
		end = tp + Vector3(randf_range(-1.2, 1.2), randf_range(-0.6, 0.9), randf_range(-1.2, 1.2))
		var q := PhysicsRayQueryParameters3D.create(from, from + (end - from).normalized() * (dist + 30.0), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			end = hit.position
			Fx.particles(main, hit.position, hit.normal, "spark", 5)
			Fx.bullet_hole(main, hit.position, hit.normal)
	Fx.tracer(main, from, end, Color(1, 0.6, 0.3) if side == "enemy" else Color(0.6, 0.8, 1))
	Fx.muzzle(main, muzzle)
	Sfx.play_at("far", from, main.listener_pos(), 2.0)
	main.on_gunfire(from)

func alert(where: Vector3) -> void:
	if dead or surrendered:
		return
	if state == "idle":
		state = "alert"
		react = main.diff_react * randf_range(0.8, 1.4)
		for o in main.enemies:
			if o != self and not o.dead and o.state == "idle" and o.global_position.distance_to(global_position) < 11.0:
				o.state = "alert"
				o.last_seen = where
				o.react = main.diff_react * randf_range(1.0, 1.6)
	last_seen = where

func take_hit(dmg: float, head := false, from: Node3D = null) -> bool:
	if dead:
		return false
	if side == "enemy" and (surrendered or cuffed) and from == main.player:
		main.on_violation()
	hp -= dmg
	if from:
		alert(from.global_position)
	if hp <= 0.0:
		die(head, from)
		return true
	return false

func surrender() -> void:
	surrendered = true
	target = null
	model.set_mode("hands_up")

func die(head := false, from: Node3D = null) -> void:
	dead = true
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	model.anim.pause()
	model.set_mode("none")
	gun.visible = false
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", -PI / 2 * (1 if randf() < 0.6 else -1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(model, "position:y", 0.15, 0.5)
	if main:
		main.on_actor_dead(self, head, from)

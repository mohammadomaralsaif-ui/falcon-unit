extends Node3D
const Fx = preload("res://scripts/fx.gd")
## Civilian traffic: cars drive on the right-hand lane of the road grid, turn at junctions,
## brake for anything in front of them (including the player).

var city: Node
var cars: Array = []
var blocked := {}  # "i,j>i2,j2" road segments closed by the police cordon

const LANE := 2.3
const SPEED := 10.0

class Car:
	var body: AnimatableBody3D
	var from: Vector2i
	var to: Vector2i
	var t := 0.0
	var speed := 0.0
	var max_speed := 10.0
	var stuck := 0.0
	var want := 10.0
	var tick := 0
	var snd: AudioStreamPlayer3D
	var honk_cd := 0.0
	var hit_t := 0.0

func setup(_city: Node, count: int) -> void:
	city = _city
	# close the street in front of the bank
	var bb: Vector2i = city.bank_block
	_block(Vector2i(bb.x, bb.y + 1), Vector2i(bb.x + 1, bb.y + 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var tries := 0
	while cars.size() < count and tries < count * 10:
		tries += 1
		var a := Vector2i(rng.randi_range(0, city.N), rng.randi_range(0, city.N))
		var nb := _neighbors(a, Vector2i(-99, -99))
		if nb.is_empty():
			continue
		var b: Vector2i = nb[rng.randi() % nb.size()]
		var c := Car.new()
		c.from = a; c.to = b; c.t = rng.randf_range(0.15, 0.8)
		c.max_speed = rng.randf_range(8.0, 12.5)
		c.speed = c.max_speed
		var pos := _lane_pos(c)
		if pos.distance_to(city.spawn_point.origin) < 30.0:
			continue
		c.body = AnimatableBody3D.new()
		c.body.collision_layer = 8
		c.body.collision_mask = 0
		c.body.sync_to_physics = false
		var mi := MeshInstance3D.new()
		mi.mesh = city.random_car_mesh()
		c.body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new(); bs.size = Vector3(1.8, 1.4, 4.4)
		cs.shape = bs; cs.position = Vector3(0, 0.75, 0)
		c.body.add_child(cs)
		add_child(c.body)
		c.snd = AudioStreamPlayer3D.new()
		c.snd.stream = Sfx.streams["engine"]
		c.snd.unit_size = 4.0
		c.snd.max_distance = 45.0
		c.snd.volume_db = -14.0
		c.snd.pitch_scale = rng.randf_range(0.85, 1.15)
		c.body.add_child(c.snd)
		c.snd.play()
		_place(c)
		cars.append(c)

var main: Node

## The player's car rammed this civilian car.
func on_hit(body: Node, rel_speed: float) -> void:
	for c: Car in cars:
		if c.body == body:
			c.hit_t = clampf(rel_speed * 0.6, 3.0, 9.0)
			c.speed = 0.0
			c.stuck = 0.0
			Fx.particles(main, c.body.global_position + Vector3(0, 0.9, 0), Vector3.UP, "dust", 5)
			return

func _far_from_player(p: Vector3, d: float) -> bool:
	if not main:
		return true
	var ref: Vector3 = main.vehicle.global_position if main.in_vehicle else main.player.global_position
	return p.distance_to(ref) > d

func _key(a: Vector2i, b: Vector2i) -> String:
	return "%d,%d>%d,%d" % [a.x, a.y, b.x, b.y]

func _block(a: Vector2i, b: Vector2i) -> void:
	blocked[_key(a, b)] = true
	blocked[_key(b, a)] = true

func _node_pos(n: Vector2i) -> Vector3:
	return Vector3(city.road_center(n.x), 0, city.road_center(n.y))

func _neighbors(n: Vector2i, prev: Vector2i) -> Array:
	var out := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var m: Vector2i = n + d
		if m.x < 0 or m.y < 0 or m.x > city.N or m.y > city.N:
			continue
		if m == prev or blocked.has(_key(n, m)):
			continue
		out.append(m)
	if out.is_empty() and prev.x > -50 and not blocked.has(_key(n, prev)):
		out.append(prev)
	return out

func _lane_pos(c: Car) -> Vector3:
	var a := _node_pos(c.from)
	var b := _node_pos(c.to)
	var d := (b - a).normalized()
	var right := Vector3(-d.z, 0, d.x)
	return a.lerp(b, c.t) + right * LANE

func _place(c: Car) -> void:
	var a := _node_pos(c.from)
	var b := _node_pos(c.to)
	var d := (b - a).normalized()
	var p := _lane_pos(c)
	var yaw := atan2(d.x, d.z)
	c.body.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)

func _physics_process(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	for c: Car in cars:
		var a := _node_pos(c.from)
		var b := _node_pos(c.to)
		var seg := a.distance_to(b)
		var d := (b - a) / seg
		# look ahead for obstacles
		# obstacle check every 3rd physics tick (staggered per car)
		c.tick += 1
		if c.tick % 3 == 0:
			var p: Vector3 = c.body.global_position + Vector3(0, 0.8, 0)
			var q := PhysicsRayQueryParameters3D.create(p + d * 2.4, p + d * 13.0, 1 | 4 | 8 | 16)
			q.exclude = [c.body.get_rid()]
			var hit := space.intersect_ray(q)
			c.want = c.max_speed
			if hit:
				var dist: float = (hit.position - p).length()
				c.want = clampf((dist - 4.5) * 1.4, 0.0, c.max_speed)
		var want: float = c.want
		if c.hit_t > 0.0:
			# just got rammed: the driver stops, hazards on, leans on the horn
			c.hit_t -= dt
			want = 0.0
			if c.honk_cd <= 0.0:
				c.honk_cd = randf_range(1.2, 2.5)
				Sfx.play_3d("horn", c.body.global_position, 0.0, randf_range(0.85, 1.1))
		# slow for turns near the junction
		var remain := (1.0 - c.t) * seg
		if remain < 9.0:
			want = minf(want, 6.0)
		c.speed = move_toward(c.speed, want, dt * (30.0 if c.hit_t > 0.0 else (9.0 if want < c.speed else 3.0)))
		c.body.set_meta("traffic_speed", c.speed)
		if c.speed < 0.3:
			c.stuck += dt
		else:
			c.stuck = 0.0
		if c.tick % 6 == 0:
			c.snd.pitch_scale = 0.7 + c.speed / 22.0
		# drivers lean on the horn when something blocks them for a while
		c.honk_cd -= dt
		if c.stuck > 2.5 and c.honk_cd <= 0.0 and not _far_from_player(c.body.global_position, 40.0):
			c.honk_cd = randf_range(3.0, 6.0)
			Sfx.play_3d("horn", c.body.global_position, -2.0, randf_range(0.85, 1.1))
		if c.stuck > 12.0 and _far_from_player(c.body.global_position, 60.0):
			# respawn on a random street far from the player instead of sliding through things
			c.stuck = 0.0
			for tries in 20:
				var a2 := Vector2i(randi_range(0, city.N), randi_range(0, city.N))
				var nb2 := _neighbors(a2, Vector2i(-99, -99))
				if nb2.is_empty():
					continue
				c.from = a2
				c.to = nb2[randi() % nb2.size()]
				c.t = randf_range(0.2, 0.8)
				if _far_from_player(_lane_pos(c), 80.0):
					break
			c.speed = 0.0
			_place(c)
			continue
		c.t += c.speed * dt / seg
		if c.t >= 1.0:
			var nb := _neighbors(c.to, c.from)
			var nxt: Vector2i = nb[randi() % nb.size()] if nb.size() else c.from
			c.from = c.to
			c.to = nxt
			c.t = 0.0
		var target := _lane_pos(c)
		var nd := (_node_pos(c.to) - _node_pos(c.from)).normalized()
		var yaw := atan2(nd.x, nd.z)
		var cur: Transform3D = c.body.global_transform
		var cy := cur.basis.get_euler().y
		var ny := lerp_angle(cy, yaw, 1.0 - exp(-dt * 5.0))
		# smooth corner: blend position too
		var np := cur.origin.lerp(target, 1.0 - exp(-dt * 6.0)) if cur.origin.distance_to(target) > 0.5 else target
		c.body.global_transform = Transform3D(Basis(Vector3.UP, ny), np)

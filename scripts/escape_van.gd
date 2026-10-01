extends AnimatableBody3D
## The gang leader's getaway: an armoured cash van speeding through the street grid.
## Ram it with the SWAT car or shoot it until it breaks down.

const CarMesh = preload("res://scripts/car_mesh.gd")
const Fx = preload("res://scripts/fx.gd")

var main: Node
var city: Node
var from: Vector2i
var to: Vector2i
var t := 0.5
var speed := 0.0
var max_speed := 17.0
var hp := 100.0
var disabled := false
var smoke_t := 0.0
var siren_cd := 0.0

func setup(_main: Node, a: Vector2i, b: Vector2i) -> void:
	main = _main
	city = main.city
	from = a; to = b

func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	sync_to_physics = false
	var body := CarMesh.compact(CarMesh.build("cashvan"))
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(2.0, 2.3, 5.3)
	cs.shape = bs; cs.position = Vector3(0, 1.25, 0)
	add_child(cs)
	_place(1.0)

func _node(n: Vector2i) -> Vector3:
	return Vector3(city.road_center(n.x), 0, city.road_center(n.y))

func _lane() -> Vector3:
	var a := _node(from); var b := _node(to)
	var d := (b - a).normalized()
	return a.lerp(b, t) + Vector3(-d.z, 0, d.x) * 2.3

func _place(blend: float) -> void:
	var d := (_node(to) - _node(from)).normalized()
	var yaw := atan2(d.x, d.z)
	var cur := global_transform if is_inside_tree() else transform
	var ny := lerp_angle(cur.basis.get_euler().y, yaw, blend)
	var np := cur.origin.lerp(_lane(), blend)
	global_transform = Transform3D(Basis(Vector3.UP, ny), np)

func take_hit(dmg: float, _head := false, _from: Node3D = null) -> bool:
	if disabled:
		return false
	damage(dmg * 0.25)
	return false

func damage(d: float) -> void:
	if disabled:
		return
	hp -= d
	if main:
		main.hud.hit_marker(false)
	if hp <= 0.0:
		hp = 0.0
		disabled = true
		if main:
			main.on_van_disabled(self)

func _physics_process(dt: float) -> void:
	if not city:
		return
	if disabled:
		speed = move_toward(speed, 0.0, dt * 14.0)
		smoke_t -= dt
		if smoke_t <= 0.0:
			smoke_t = 0.35
			Fx.particles(main, global_position + global_transform.basis.z * 2.4 + Vector3(0, 1.2, 0), Vector3.UP, "smoke", 3)
	var a := _node(from); var b := _node(to)
	var seg := a.distance_to(b)
	var d := (b - a) / seg
	var want := max_speed * (0.55 + 0.45 * hp / 100.0)
	if disabled:
		want = 0.0
	# obstacle ahead (traffic) -> brake, then swerve by honking through
	var p := global_position + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(p + d * 3.0, p + d * 14.0, 8)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and not disabled:
		want = minf(want, clampf((hit.position.distance_to(p) - 5.0) * 1.2, 2.0, want))
	if (1.0 - t) * seg < 10.0:
		want = minf(want, 10.0)
	speed = move_toward(speed, want, dt * (12.0 if want < speed else 5.0))
	t += speed * dt / seg
	if t >= 1.0:
		var opts := []
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var m: Vector2i = to + dd
			if m == from or m.x < 0 or m.y < 0 or m.x > city.N or m.y > city.N:
				continue
			if main.traffic.blocked.has(main.traffic._key(to, m)):
				continue
			opts.append(m)
		if opts.is_empty():
			opts.append(from)
		var pick: Vector2i = opts[randi() % opts.size()]
		if randf() < 0.65:
			var pp: Vector3 = main.vehicle.global_position
			var best := -1.0
			for o in opts:
				var dist := _node(o).distance_to(pp)
				if dist > best:
					best = dist; pick = o
		from = to
		to = pick
		t = 0.0
	_place(1.0 - exp(-dt * 6.0))

extends Node3D
## People walking around the blocks on the sidewalks. They panic and run from gunfire,
## step out of the way of speeding cars and are recycled around the player.

const Person = preload("res://scripts/person.gd")

var main: Node
var city: Node
var peds: Array = []
const COUNT := 16

class Ped:
	var node: Node3D
	var block: Vector2i
	var u := 0.0          # position along the block perimeter (0..perimeter)
	var dir := 1.0
	var speed := 1.3
	var flee := 0.0
	var dodge := 0.0      # extra inward offset when a car comes

func setup(_main: Node) -> void:
	main = _main
	city = main.city
	for i in COUNT:
		var p := Ped.new()
		p.node = Person.new("civilian", 1000 + i)
		add_child(p.node)
		_respawn(p, true)
		peds.append(p)

func _blocked(b: Vector2i) -> bool:
	var bb: Vector2i = city.bank_block
	return absi(b.x - bb.x) <= 1 and b.y <= bb.y + 1

func _respawn(p: Ped, anywhere := false) -> void:
	var ref: Vector3 = main.player.global_position if not main.in_vehicle else main.vehicle.global_position
	for tries in 30:
		var b := Vector2i(randi_range(0, city.N - 1), randi_range(0, city.N - 1))
		if _blocked(b):
			continue
		var c := Vector3(b.x * city.P + city.R + city.B * 0.5, 0, b.y * city.P + city.R + city.B * 0.5)
		var d := c.distance_to(ref)
		if (anywhere and d < 130.0) or (d > 60.0 and d < 160.0):
			p.block = b
			break
	p.u = randf() * _perim()
	p.dir = 1.0 if randf() < 0.5 else -1.0
	p.speed = randf_range(1.1, 1.6)
	p.flee = 0.0
	_apply(p, 0.016)

func _perim() -> float:
	return (city.B + 0.8) * 4.0

func _pos(b: Vector2i, u: float, inset: float) -> Array:
	var side: float = city.B + 0.8
	var x0: float = b.x * city.P + city.R - 0.4 + inset
	var z0: float = b.y * city.P + city.R - 0.4 + inset
	var s: float = side - inset * 2.0
	u = fposmod(u, side * 4.0) / (side * 4.0) * (s * 4.0)
	if u < s:
		return [Vector3(x0 + u, 0.16, z0), Vector3(1, 0, 0)]
	u -= s
	if u < s:
		return [Vector3(x0 + s, 0.16, z0 + u), Vector3(0, 0, 1)]
	u -= s
	if u < s:
		return [Vector3(x0 + s - u, 0.16, z0 + s), Vector3(-1, 0, 0)]
	u -= s
	return [Vector3(x0, 0.16, z0 + s - u), Vector3(0, 0, -1)]

func _apply(p: Ped, dt: float) -> void:
	var r := _pos(p.block, p.u, p.dodge)
	var fwd: Vector3 = r[1] * p.dir
	p.node.global_position = r[0]
	var want := atan2(-fwd.x, -fwd.z)
	p.node.rotation.y = lerp_angle(p.node.rotation.y, want, 1.0 - exp(-dt * 8.0))

func panic(at: Vector3, radius := 38.0) -> void:
	for p in peds:
		var d: float = p.node.global_position.distance_to(at)
		if d < radius:
			p.flee = randf_range(7.0, 11.0)
			# run away from the source along the perimeter
			var r := _pos(p.block, p.u, p.dodge)
			var away: Vector3 = (p.node.global_position - at)
			p.dir = 1.0 if (r[1] as Vector3).dot(away) >= 0.0 else -1.0

func _physics_process(dt: float) -> void:
	if not main or not main.player:
		return
	var ref: Vector3 = main.vehicle.global_position if main.in_vehicle else main.player.global_position
	var car: VehicleBody3D = main.vehicle
	var car_speed: float = car.linear_velocity.length()
	for p in peds:
		var dref: float = p.node.global_position.distance_to(ref)
		if dref > 190.0:
			_respawn(p)
			continue
		# far-away walkers: stop skinning/animation work, hide beyond the fog
		p.node.anim.active = dref < 75.0
		p.node.visible = dref < 150.0
		# dodge an approaching car
		var to_car: Vector3 = car.global_position - p.node.global_position
		var want_dodge := 0.0
		if car_speed > 4.0 and to_car.length() < 9.0 and car.linear_velocity.dot(-to_car) > 0.0:
			want_dodge = 1.6
		p.dodge = move_toward(p.dodge, want_dodge, dt * 3.0)
		var spd: float = p.speed
		if p.flee > 0.0:
			p.flee -= dt
			spd = 4.6
		p.u += spd * dt * p.dir
		_apply(p, dt)
		if spd > 3.0:
			p.node.play("Run", spd / 5.5)
		else:
			p.node.play("Walk", spd / 1.5)

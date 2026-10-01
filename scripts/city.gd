extends Node3D
## Procedural Amman-style city: limestone buildings, shop signs, sidewalks, lane markings,
## street lamps, trees, parked cars, hills covered in houses, and the target bank compound.

const CarMesh = preload("res://scripts/car_mesh.gd")

const N := 5            # blocks per side
const R := 14.0         # road corridor width (incl. sidewalks)
const B := 46.0         # block size
const P := R + B        # period
const SIDEWALK := 2.2
const FLOOR_H := 3.3
const CELL := 3.2       # bank interior grid cell

const BANK_MAP := [
	"##############",
	"#H...#...E.H.#",
	"#.E..#.......#",
	"#....##.###..#",
	"#.........E..#",
	"###.####.C...#",
	"#H..#..E.....#",
	"#...#....#####",
	"#.C.....E...H#",
	"#....##......#",
	"#.E..#..C..E.#",
	"######D#######",
]

const SHOPS := ["صيدلية الشفاء", "مخبز الأمل", "بقالة النور", "حلويات", "فلافل وحمص", "مطعم شاورما", "اتصالات", "مكتبة القدس", "قهوة", "صالون", "ملابس", "عطارة"]

var rng := RandomNumberGenerator.new()
var size_total := 0.0
var bank_block := Vector2i(2, 0)
var bank_origin := Vector3.ZERO
var door_pos := Vector3.ZERO
var door_body: StaticBody3D
var enemy_spawns: Array[Vector3] = []
var hostage_spawns: Array[Vector3] = []
var spawn_point := Transform3D.IDENTITY
var cordon_point := Vector3.ZERO
var flashers: Array = []
var baked := {}
var font: Font
var _mats := {}

func build(seed_val := 7) -> void:
	rng.seed = seed_val
	font = load("res://assets/fonts/Tajawal-Bold.ttf")
	size_total = N * P + R
	_ground()
	_roads()
	for bi in N:
		for bj in N:
			if Vector2i(bi, bj) == bank_block:
				_bank_block(bi, bj)
			else:
				_block(bi, bj)
	var sx := road_center(1)
	var sz := road_center(N) - 10.0
	spawn_point = Transform3D(Basis(Vector3.UP, PI), Vector3(sx + 2.2, 0.8, sz))
	_hills()
	_parked_cars()

func road_center(k: int) -> float:
	return k * P + R * 0.5

# ---------------------------------------------------------------- materials / textures
func _img_tex(w: int, h: int, draw: Callable, srgb := true) -> ImageTexture:
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	draw.call(img)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _speckle(img: Image, n: int, cols: Array, sz := 2) -> void:
	var w := img.get_width(); var h := img.get_height()
	for i in n:
		var c: Color = cols[i % cols.size()]
		img.fill_rect(Rect2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1), rng.randi_range(1, sz), rng.randi_range(1, sz)), c)

func _noise_normal(freq := 0.05, strength := 3.0) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	nt.width = 256; nt.height = 256; nt.seamless = true; nt.as_normal_map = true; nt.bump_strength = strength
	var fn := FastNoiseLite.new(); fn.frequency = freq; fn.fractal_octaves = 4
	nt.noise = fn
	return nt

func mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"asphalt":
			m.albedo_texture = _img_tex(256, 256, func(img):
				img.fill(Color(0.17, 0.18, 0.19))
				_speckle(img, 9000, [Color(0.1, 0.1, 0.11), Color(0.26, 0.27, 0.28), Color(0.21, 0.22, 0.23)], 2)
				for i in 6:
					var x := rng.randi_range(0, 230); var y := rng.randi_range(0, 230)
					img.fill_rect(Rect2i(x, y, rng.randi_range(10, 30), rng.randi_range(6, 16)), Color(0.13, 0.13, 0.14)))
			m.normal_enabled = true; m.normal_texture = _noise_normal(0.08, 2.0)
			m.roughness = 0.88
			m.uv1_scale = Vector3(1.0 / 6.0, 1.0 / 6.0, 1)
			m.uv1_world_triplanar = true; m.uv1_triplanar = true
		"sidewalk":
			m.albedo_texture = _img_tex(128, 128, func(img):
				img.fill(Color(0.62, 0.6, 0.56))
				_speckle(img, 2500, [Color(0.5, 0.49, 0.46), Color(0.7, 0.68, 0.64)], 2)
				for k in 3:
					img.fill_rect(Rect2i(0, k * 64, 128, 2), Color(0.42, 0.41, 0.38))
					img.fill_rect(Rect2i(k * 64, 0, 2, 128), Color(0.42, 0.41, 0.38)))
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.roughness = 0.9
		"stone":
			m.albedo_texture = _facade_tex(false)
			m.normal_enabled = true; m.normal_texture = _noise_normal(0.12, 1.5)
			m.roughness = 0.85
		"shop":
			m.albedo_texture = _facade_tex(true)
			m.roughness = 0.7; m.metallic = 0.2
		"roof":
			m.albedo_color = Color(0.58, 0.55, 0.5); m.roughness = 0.95
		"plaster":
			m.albedo_texture = _img_tex(128, 128, func(img):
				img.fill(Color(0.78, 0.75, 0.69))
				_speckle(img, 2500, [Color(0.7, 0.67, 0.6), Color(0.84, 0.82, 0.77)], 3)
				img.fill_rect(Rect2i(0, 116, 128, 12), Color(0.36, 0.34, 0.31)))
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(0.3, 0.3, 0.3)
			m.roughness = 0.9
		"tile":
			m.albedo_texture = _img_tex(128, 128, func(img):
				img.fill(Color(0.66, 0.64, 0.6))
				_speckle(img, 3000, [Color(0.5, 0.48, 0.45), Color(0.78, 0.75, 0.7), Color(0.4, 0.38, 0.35)], 2)
				img.fill_rect(Rect2i(0, 0, 128, 2), Color(0.3, 0.29, 0.27)); img.fill_rect(Rect2i(0, 0, 2, 128), Color(0.3, 0.29, 0.27)))
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.roughness = 0.35
		"white":
			m.albedo_color = Color(0.92, 0.9, 0.85); m.roughness = 0.7
		"line":
			m.albedo_color = Color(0.92, 0.9, 0.82); m.roughness = 0.7
		"yellowline":
			m.albedo_color = Color(0.95, 0.75, 0.15); m.roughness = 0.7
		"pole":
			m.albedo_color = Color(0.22, 0.23, 0.25); m.metallic = 0.6; m.roughness = 0.4
		"lamp":
			m.albedo_color = Color(1, 0.95, 0.8); m.emission_enabled = true; m.emission = Color(1, 0.85, 0.6); m.emission_energy_multiplier = 1.5
		"trunk":
			m.albedo_color = Color(0.3, 0.23, 0.17); m.roughness = 0.95
		"leaf":
			m.albedo_color = Color(0.27, 0.38, 0.18); m.roughness = 0.9
		"tankblack":
			m.albedo_color = Color(0.08, 0.08, 0.08); m.roughness = 0.5
		"tankwhite":
			m.albedo_color = Color(0.85, 0.85, 0.82); m.roughness = 0.5
		"solar":
			m.albedo_color = Color(0.08, 0.12, 0.2); m.metallic = 0.7; m.roughness = 0.15
		"metal":
			m.albedo_color = Color(0.6, 0.62, 0.64); m.metallic = 0.8; m.roughness = 0.35
		"ac":
			m.albedo_color = Color(0.85, 0.85, 0.83); m.roughness = 0.5
		"door":
			m.albedo_color = Color(0.22, 0.24, 0.27); m.metallic = 0.7; m.roughness = 0.45
		"houses":
			m.vertex_color_use_as_albedo = true; m.roughness = 0.9
		"hill":
			m.albedo_color = Color(0.62, 0.55, 0.43); m.roughness = 1.0
			m.normal_enabled = true; m.normal_texture = _noise_normal(0.04, 4.0)
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(0.05, 0.05, 0.05)
		"tape":
			m.albedo_color = Color(0.95, 0.76, 0.18); m.roughness = 0.5; m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			if key.begins_with("sign"):
				var cols := [Color(0.1, 0.4, 0.25), Color(0.5, 0.25, 0.08), Color(0.08, 0.25, 0.5), Color(0.55, 0.12, 0.18), Color(0.15, 0.15, 0.18)]
				m.albedo_color = cols[int(key.substr(4)) % cols.size()]
				m.roughness = 0.5
	_mats[key] = m
	return m

func _facade_tex(shop: bool) -> ImageTexture:
	return _img_tex(256, 256, func(img: Image):
		var stone := Color(0.84, 0.78, 0.66)
		img.fill(stone)
		_speckle(img, 5000, [Color(0.76, 0.7, 0.58), Color(0.9, 0.85, 0.74), Color(0.72, 0.66, 0.55)], 3)
		for y in range(0, 256, 21):
			img.fill_rect(Rect2i(0, y, 256, 1), Color(0.66, 0.6, 0.5))
			var off := 0 if (y / 21) % 2 == 0 else 32
			for x in range(off, 256, 64):
				img.fill_rect(Rect2i(x, y, 1, 21), Color(0.66, 0.6, 0.5))
		if shop:
			img.fill_rect(Rect2i(12, 60, 232, 196), Color(0.36, 0.38, 0.4))
			for y in range(64, 256, 7):
				img.fill_rect(Rect2i(12, y, 232, 2), Color(0.25, 0.26, 0.28))
			img.fill_rect(Rect2i(8, 50, 240, 12), Color(0.2, 0.21, 0.23))
		else:
			img.fill_rect(Rect2i(40, 50, 176, 150), Color(0.6, 0.55, 0.45))
			img.fill_rect(Rect2i(48, 58, 160, 136), Color(0.08, 0.1, 0.12))
			img.fill_rect(Rect2i(126, 58, 4, 136), Color(0.55, 0.52, 0.47))
			img.fill_rect(Rect2i(48, 58, 70, 50), Color(0.22, 0.28, 0.33))
			if rng.randf() < 0.5:
				img.fill_rect(Rect2i(48, 58, 160, rng.randi_range(30, 100)), Color(0.88, 0.86, 0.8))
			img.fill_rect(Rect2i(34, 196, 188, 10), Color(0.9, 0.86, 0.76)))

# ---------------------------------------------------------------- mesh helpers
func _mi(mesh: Mesh, m: Material, pos := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _static_box(size: Vector3, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = rot_y
	add_child(sb)
	return sb

func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = size
	return b

func _multimesh(mesh: Mesh, m: Material, xforms: Array, colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)
	return mmi

func _label(text: String, pos: Vector3, rot_y: float, size := 64, col := Color.WHITE, px := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text; l.font = font; l.font_size = size; l.pixel_size = px
	l.modulate = col; l.outline_size = 8; l.outline_modulate = Color(0, 0, 0, 0.6)
	l.position = pos; l.rotation.y = rot_y
	l.double_sided = false
	add_child(l)
	return l

# ---------------------------------------------------------------- ground & roads
func _ground() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size_total + 40, size_total + 40)
	_mi(pm, mat("asphalt"), Vector3(size_total * 0.5, 0, size_total * 0.5), false)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	sb.add_child(cs)
	add_child(sb)

func _roads() -> void:
	var dashes := []
	var zebra := []
	var dash := _box_mesh(Vector3(0.15, 0.02, 2.4))
	for k in N + 1:
		var c := road_center(k)
		for bk in N:
			var a := bk * P + R
			var b := a + B
			var z := a + 2.0
			while z < b - 2.0:
				dashes.append(Transform3D(Basis(), Vector3(c, 0.01, z)))
				dashes.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(z, 0.01, c)))
				z += 6.0
	for i in N + 1:
		for j in N + 1:
			var cx := road_center(i); var cz := road_center(j)
			for s in [-1, 1]:
				for t in range(-4, 5):
					zebra.append(Transform3D(Basis(), Vector3(cx + t * 1.1, 0.012, cz + s * (R * 0.5 + 1.5))))
					zebra.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(cx + s * (R * 0.5 + 1.5), 0.012, cz + t * 1.1)))
	_multimesh(dash, mat("line"), dashes)
	_multimesh(_box_mesh(Vector3(0.55, 0.02, 2.6)), mat("line"), zebra)

# ---------------------------------------------------------------- city blocks
func _block(bi: int, bj: int) -> void:
	var x0 := bi * P + R
	var z0 := bj * P + R
	var cx := x0 + B * 0.5
	var cz := z0 + B * 0.5
	# raised sidewalk slab
	_mi(_box_mesh(Vector3(B + SIDEWALK * 2, 0.16, B + SIDEWALK * 2)), mat("sidewalk"), Vector3(cx, 0.08, cz), false)
	_static_box(Vector3(B + SIDEWALK * 2, 0.16, B + SIDEWALK * 2), Vector3(cx, 0.08, cz))
	var lot := (B - 1.0) / 2.0
	var park := rng.randf() < 0.12
	for lx in 2:
		for lz in 2:
			var bx := x0 + 0.5 + lx * lot + lot * 0.5
			var bz := z0 + 0.5 + lz * lot + lot * 0.5
			if park and lx == 0 and lz == 0:
				_trees_in_lot(bx, bz, lot)
				continue
			if rng.randf() < 0.05:
				_mosque(bx, bz, lot)
				continue
			var floors := rng.randi_range(3, 8)
			var w := lot - rng.randf_range(0.6, 2.0)
			var d := lot - rng.randf_range(0.6, 2.0)
			_building(Vector3(bx, 0.16, bz), w, d, floors, lx, lz)
	# street furniture along the block edge
	for side in 4:
		for t in range(0, 4):
			var along := x0 + 5.0 + t * 12.0
			var pos: Vector3
			var ry := 0.0
			match side:
				0: pos = Vector3(along, 0.16, z0 - SIDEWALK + 0.5); ry = 0.0
				1: pos = Vector3(along, 0.16, z0 + B + SIDEWALK - 0.5); ry = PI
				2: pos = Vector3(x0 - SIDEWALK + 0.5, 0.16, z0 + 5.0 + t * 12.0); ry = -PI / 2
				3: pos = Vector3(x0 + B + SIDEWALK - 0.5, 0.16, z0 + 5.0 + t * 12.0); ry = PI / 2
			if t % 2 == 0:
				_lamp(pos, ry)
			elif rng.randf() < 0.6:
				_tree(pos + Vector3(0, 0, 0))

func _building(base: Vector3, w: float, d: float, floors: int, lx: int, lz: int) -> void:
	var h := floors * FLOOR_H
	# ground floor shops
	var st_shop := SurfaceTool.new(); st_shop.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_up := SurfaceTool.new(); st_up.begin(Mesh.PRIMITIVE_TRIANGLES)
	_walls(st_shop, base, w, d, 0.0, FLOOR_H, 4.0, FLOOR_H)
	_walls(st_up, base, w, d, FLOOR_H, h, 3.4, FLOOR_H)
	var mi_shop := _mi(st_shop.commit(), mat("shop"))
	var mi_up := _mi(st_up.commit(), mat("stone"))
	_mi(_box_mesh(Vector3(w + 0.3, 0.35, d + 0.3)), mat("roof"), base + Vector3(0, h + 0.17, 0))
	_static_box(Vector3(w, h, d), base + Vector3(0, h * 0.5, 0))
	# balconies on the street-facing sides
	var faces := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	var bal := []
	var rail := []
	var acs := []
	for f in faces:
		var half: float = (d if f.z != 0 else w) * 0.5
		var span: float = (w if f.z != 0 else d)
		var ry := atan2(f.x, f.z)
		var basis := Basis(Vector3.UP, ry)
		var right := basis.x
		for fl in range(1, floors):
			var y := base.y + fl * FLOOR_H
			var bays := int(span / 3.4)
			for b in bays:
				var off := -span * 0.5 + 1.7 + b * 3.4
				var p: Vector3 = base + f * (half + 0.55) + right * off
				p.y = y
				if (b + fl) % 3 == 0:
					bal.append(Transform3D(basis, p))
					rail.append(Transform3D(basis, p + Vector3(0, 0.55, 0) + f * 0.55))
				elif rng.randf() < 0.18:
					acs.append(Transform3D(basis, base + f * (half + 0.2) + right * (off + 1.2) + Vector3(0, y - base.y + 1.6, 0)))
		# shop signs
		if rng.randf() < 0.7:
			var sp: Vector3 = base + f * (half + 0.08) + Vector3(0, FLOOR_H - 0.45, 0)
			var sign_w: float = min(span * 0.8, 9.0)
			var board := _mi(_box_mesh(Vector3(sign_w, 0.75, 0.12)), mat("sign%d" % (rng.randi() % 5)), sp, false)
			board.rotation.y = ry
			_label(SHOPS[rng.randi() % SHOPS.size()], sp + f * 0.08, ry, 72, Color(1, 1, 1), 0.009)
	if bal.size():
		_multimesh(_box_mesh(Vector3(2.8, 0.15, 1.1)), mat("white"), bal)
		_multimesh(_box_mesh(Vector3(2.8, 1.0, 0.06)), mat("metal"), rail)
	if acs.size():
		_multimesh(_box_mesh(Vector3(0.85, 0.55, 0.35)), mat("ac"), acs)
	# roof clutter: water tanks + solar heaters (very Amman)
	for i in rng.randi_range(2, 6):
		var p := base + Vector3(rng.randf_range(-w * 0.35, w * 0.35), h + 0.35, rng.randf_range(-d * 0.35, d * 0.35))
		var cm := CylinderMesh.new(); cm.top_radius = 0.55; cm.bottom_radius = 0.55; cm.height = 1.2
		_mi(cm, mat("tankblack" if rng.randf() < 0.6 else "tankwhite"), p + Vector3(0, 0.6, 0))
	if rng.randf() < 0.7:
		var p := base + Vector3(rng.randf_range(-w * 0.3, w * 0.3), h + 0.35, rng.randf_range(-d * 0.3, d * 0.3))
		var panel := _mi(_box_mesh(Vector3(2.0, 0.06, 1.1)), mat("solar"), p + Vector3(0, 0.7, 0))
		panel.rotation.x = -0.6
		var tank := CylinderMesh.new(); tank.top_radius = 0.25; tank.bottom_radius = 0.25; tank.height = 1.8
		var tm := _mi(tank, mat("metal"), p + Vector3(0, 1.3, -0.5))
		tm.rotation.z = PI / 2

func _walls(st: SurfaceTool, base: Vector3, w: float, d: float, y0: float, y1: float, tile_w: float, tile_h: float) -> void:
	var hw := w * 0.5; var hd := d * 0.5
	var corners := [Vector3(-hw, 0, hd), Vector3(hw, 0, hd), Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd)]
	for i in 4:
		var a: Vector3 = base + corners[i]
		var b: Vector3 = base + corners[(i + 1) % 4]
		var len := a.distance_to(b)
		var n := (b - a).cross(Vector3.UP).normalized()
		var u1 := len / tile_w
		var v0 := 0.0; var v1 := (y1 - y0) / tile_h
		var p0 := a + Vector3(0, y0, 0); var p1 := b + Vector3(0, y0, 0)
		var p2 := b + Vector3(0, y1, 0); var p3 := a + Vector3(0, y1, 0)
		var verts := [[p0, Vector2(0, v1)], [p2, Vector2(u1, v0)], [p1, Vector2(u1, v1)], [p0, Vector2(0, v1)], [p3, Vector2(0, v0)], [p2, Vector2(u1, v0)]]
		for vv in verts:
			st.set_normal(n)
			st.set_uv(vv[1])
			st.add_vertex(vv[0])

func _lamp(pos: Vector3, ry: float) -> void:
	var cm := CylinderMesh.new(); cm.top_radius = 0.06; cm.bottom_radius = 0.1; cm.height = 6.0
	_mi(cm, mat("pole"), pos + Vector3(0, 3.0, 0))
	var arm := _mi(_box_mesh(Vector3(0.08, 0.08, 1.6)), mat("pole"), pos + Vector3(0, 5.9, 0))
	arm.rotation.y = ry
	arm.position += Basis(Vector3.UP, ry) * Vector3(0, 0, -0.75)
	var head := _mi(_box_mesh(Vector3(0.35, 0.12, 0.6)), mat("lamp"), pos + Vector3(0, 5.85, 0), false)
	head.position += Basis(Vector3.UP, ry) * Vector3(0, 0, -1.5)

func _tree(pos: Vector3) -> void:
	var cm := CylinderMesh.new(); cm.top_radius = 0.1; cm.bottom_radius = 0.17; cm.height = 3.0
	_mi(cm, mat("trunk"), pos + Vector3(0, 1.5, 0))
	for i in 3:
		var sm := SphereMesh.new(); var r := rng.randf_range(1.0, 1.5)
		sm.radius = r; sm.height = r * 1.6; sm.radial_segments = 10; sm.rings = 6
		_mi(sm, mat("leaf"), pos + Vector3(rng.randf_range(-0.6, 0.6), 3.3 + rng.randf_range(0, 0.6), rng.randf_range(-0.6, 0.6)))

func _trees_in_lot(cx: float, cz: float, lot: float) -> void:
	for i in 6:
		_tree(Vector3(cx + rng.randf_range(-lot * 0.4, lot * 0.4), 0.16, cz + rng.randf_range(-lot * 0.4, lot * 0.4)))

func _mosque(cx: float, cz: float, lot: float) -> void:
	var w := lot - 3.0
	_mi(_box_mesh(Vector3(w, 7.0, w)), mat("tankwhite"), Vector3(cx, 3.66, cz))
	_static_box(Vector3(w, 7.0, w), Vector3(cx, 3.66, cz))
	var dome := SphereMesh.new(); dome.radius = w * 0.3; dome.height = w * 0.6; dome.is_hemisphere = true
	var dm := StandardMaterial3D.new(); dm.albedo_color = Color(0.25, 0.45, 0.42); dm.metallic = 0.4; dm.roughness = 0.35
	_mi(dome, dm, Vector3(cx, 7.16, cz))
	var mn := CylinderMesh.new(); mn.top_radius = 0.9; mn.bottom_radius = 1.1; mn.height = 26.0
	_mi(mn, mat("tankwhite"), Vector3(cx + w * 0.42, 13.16, cz + w * 0.42))
	var cap := CylinderMesh.new(); cap.top_radius = 0.0; cap.bottom_radius = 1.0; cap.height = 3.0
	_mi(cap, dm, Vector3(cx + w * 0.42, 27.6, cz + w * 0.42))
	_static_box(Vector3(2.2, 26, 2.2), Vector3(cx + w * 0.42, 13.16, cz + w * 0.42))

# ---------------------------------------------------------------- hills with houses (Amman skyline)
func _hills() -> void:
	var fn := FastNoiseLite.new(); fn.frequency = 0.006; fn.seed = 3
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ext := 520.0
	var c := size_total * 0.5
	var res := 64
	var step := ext * 2.0 / res
	var hfun := func(x: float, z: float) -> float:
		var dx: float = max(0.0, abs(x - c) - c - 20.0)
		var dz: float = max(0.0, abs(z - c) - c - 20.0)
		var dist: float = sqrt(dx * dx + dz * dz)
		if dist <= 0.0:
			return -0.5
		return min(dist * 0.35, 110.0) * (0.75 + 0.5 * (fn.get_noise_2d(x, z) * 0.5 + 0.5)) - 0.5
	for i in res:
		for j in res:
			var x0 := c - ext + i * step; var z0 := c - ext + j * step
			var q := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			for k in 4:
				q[k].y = hfun.call(q[k].x, q[k].z)
			if q[0].y < 0 and q[1].y < 0 and q[2].y < 0 and q[3].y < 0:
				continue
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[idx])
	st.generate_normals()
	_mi(st.commit(), mat("hill"), Vector3.ZERO, false)
	var xf := []; var cols := []
	var house := _box_mesh(Vector3(1, 1, 1))
	for i in 3500:
		var x := c + rng.randf_range(-ext * 0.95, ext * 0.95)
		var z := c + rng.randf_range(-ext * 0.95, ext * 0.95)
		var y: float = hfun.call(x, z)
		if y < 2.0:
			continue
		var s := Vector3(rng.randf_range(6, 14), rng.randf_range(4, 12), rng.randf_range(6, 14))
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)).scaled(s), Vector3(x, y + s.y * 0.5 - 1.0, z)))
		var t := rng.randf()
		cols.append(Color(0.86, 0.82, 0.72).lerp(Color(0.97, 0.95, 0.9), t).darkened(rng.randf_range(0.0, 0.15)))
	var mmi := _multimesh(house, mat("houses"), xf, cols)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------------------------------------------------------------- parked cars
func bake(node: Node3D) -> ArrayMesh:
	var groups := {}
	var stack := [[node, Transform3D.IDENTITY]]
	while stack.size():
		var it: Array = stack.pop_back()
		var n: Node3D = it[0]
		var xf: Transform3D = it[1]
		for ch in n.get_children():
			if ch is Node3D:
				var cxf: Transform3D = xf * ch.transform
				if ch is MeshInstance3D and ch.mesh:
					var m: Material = ch.material_override
					if not groups.has(m):
						var s := SurfaceTool.new(); s.begin(Mesh.PRIMITIVE_TRIANGLES)
						groups[m] = s
					for si in ch.mesh.get_surface_count():
						groups[m].append_from(ch.mesh, si, cxf)
				stack.append([ch, cxf])
	var am := ArrayMesh.new()
	for m in groups:
		groups[m].commit(am)
		am.surface_set_material(am.get_surface_count() - 1, m)
	node.free()
	return am

func baked_car(kind: String, color: Color) -> ArrayMesh:
	var key := kind + color.to_html()
	if not baked.has(key):
		baked[key] = bake(CarMesh.build(kind, color))
	return baked[key]

const CAR_COLORS := [Color(0.92, 0.92, 0.92), Color(0.6, 0.62, 0.65), Color(0.12, 0.13, 0.15), Color(0.45, 0.08, 0.08), Color(0.15, 0.25, 0.42), Color(0.75, 0.72, 0.65)]

func random_car_mesh() -> ArrayMesh:
	if rng.randf() < 0.35:
		return baked_car("taxi", Color.YELLOW)
	return baked_car("sedan", CAR_COLORS[rng.randi() % CAR_COLORS.size()])

func _parked_cars() -> void:
	for i in 26:
		var k := rng.randi_range(0, N)
		var bk := rng.randi_range(0, N - 1)
		var along := bk * P + R + rng.randf_range(6, B - 6)
		var c := road_center(k)
		var vertical := rng.randf() < 0.5
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var pos := Vector3(c + side * 5.6, 0, along) if vertical else Vector3(along, 0, c + side * 5.6)
		if pos.distance_to(spawn_point.origin) < 15 or pos.distance_to(cordon_point) < 25:
			continue
		var ry := 0.0 if vertical else PI / 2
		if side < 0:
			ry += PI
		var mi := _mi(random_car_mesh(), null, pos)
		mi.rotation.y = ry
		_static_box(Vector3(1.8, 1.4, 4.5), pos + Vector3(0, 0.7, 0), ry)

# ---------------------------------------------------------------- bank compound (mission target)
func _bank_block(bi: int, bj: int) -> void:
	var x0 := bi * P + R
	var z0 := bj * P + R
	_mi(_box_mesh(Vector3(B + SIDEWALK * 2, 0.16, B + SIDEWALK * 2)), mat("sidewalk"), Vector3(x0 + B * 0.5, 0.08, z0 + B * 0.5), false)
	_static_box(Vector3(B + SIDEWALK * 2, 0.16, B + SIDEWALK * 2), Vector3(x0 + B * 0.5, 0.08, z0 + B * 0.5))
	var rows := BANK_MAP.size()
	var cols: int = BANK_MAP[0].length()
	var ox := x0 + (B - cols * CELL) * 0.5
	var oz := z0 + B - rows * CELL - 0.5
	bank_origin = Vector3(ox, 0.16, oz)
	var wall_st := SurfaceTool.new(); wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wh := 4.2
	var wall_mesh := _box_mesh(Vector3(CELL, wh, CELL))
	for r in rows:
		var line: String = BANK_MAP[r]
		for c in cols:
			var ch := line[c]
			var p := Vector3(ox + c * CELL + CELL * 0.5, 0.16, oz + r * CELL + CELL * 0.5)
			match ch:
				"#":
					wall_st.append_from(wall_mesh, 0, Transform3D(Basis(), p + Vector3(0, wh * 0.5, 0)))
					_static_box(Vector3(CELL, wh, CELL), p + Vector3(0, wh * 0.5, 0))
				"E":
					enemy_spawns.append(p)
				"H":
					hostage_spawns.append(p)
				"C":
					var crate := _mi(_box_mesh(Vector3(2.2, 1.3, 2.2)), mat("door"), p + Vector3(0, 0.65, 0))
					crate.material_override = _crate_mat()
					_static_box(Vector3(2.2, 1.3, 2.2), p + Vector3(0, 0.65, 0))
				"D":
					door_pos = p
					door_body = StaticBody3D.new()
					var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(CELL, 3.2, 0.3); cs.shape = bs
					door_body.add_child(cs)
					for s in [-1, 1]:
						var leaf := MeshInstance3D.new(); leaf.mesh = _box_mesh(Vector3(CELL * 0.5 - 0.05, 3.1, 0.12)); leaf.material_override = mat("door")
						leaf.position = Vector3(s * CELL * 0.25, 1.55, 0)
						door_body.add_child(leaf)
					door_body.position = p
					add_child(door_body)
					var lintel := _mi(_box_mesh(Vector3(CELL, wh - 3.2, CELL)), mat("plaster"), p + Vector3(0, 3.2 + (wh - 3.2) * 0.5, 0))
					lintel.material_override = mat("plaster")
	var walls := _mi(wall_st.commit(), mat("plaster"))
	# floor + roof
	var fl := _mi(_box_mesh(Vector3(cols * CELL, 0.05, rows * CELL)), mat("tile"), bank_origin + Vector3(cols * CELL * 0.5, 0.03, rows * CELL * 0.5), false)
	var roof := _mi(_box_mesh(Vector3(cols * CELL + 0.6, 0.4, rows * CELL + 0.6)), mat("roof"), bank_origin + Vector3(cols * CELL * 0.5, wh + 0.2, rows * CELL * 0.5))
	# facade sign
	var sign_pos := door_pos + Vector3(0, wh + 1.2, CELL * 0.5 + 0.2)
	var board := _mi(_box_mesh(Vector3(10, 1.6, 0.25)), mat("bankboard"), sign_pos, false)
	var bm := StandardMaterial3D.new(); bm.albedo_color = Color(0.06, 0.16, 0.29); board.material_override = bm
	_label("مصرف الشرق", sign_pos + Vector3(0, 0, 0.14), 0.0, 120, Color(0.96, 0.9, 0.72), 0.01)
	# interior lights
	for i in 3:
		var ol := OmniLight3D.new()
		ol.light_color = Color(1, 0.88, 0.7); ol.light_energy = 2.0; ol.omni_range = 16.0
		ol.position = bank_origin + Vector3(cols * CELL * (0.2 + i * 0.3), 3.6, rows * CELL * 0.5)
		add_child(ol)
	cordon_point = door_pos + Vector3(0, 0, 14.0)

func _crate_mat() -> StandardMaterial3D:
	if _mats.has("crate"):
		return _mats["crate"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _img_tex(128, 128, func(img):
		img.fill(Color(0.33, 0.37, 0.22))
		_speckle(img, 1500, [Color(0.25, 0.29, 0.16), Color(0.42, 0.47, 0.3)], 2)
		img.fill_rect(Rect2i(0, 0, 128, 8), Color(0.18, 0.2, 0.12)); img.fill_rect(Rect2i(0, 120, 128, 8), Color(0.18, 0.2, 0.12))
		img.fill_rect(Rect2i(0, 0, 8, 128), Color(0.18, 0.2, 0.12)); img.fill_rect(Rect2i(120, 0, 8, 128), Color(0.18, 0.2, 0.12)))
	m.roughness = 0.85
	_mats["crate"] = m
	return m

func build_cordon() -> void:
	var cp := cordon_point
	for spec in [["police", Vector3(-7, 0, 0), PI / 2], ["police", Vector3(7, 0, 0), -PI / 2], ["ambulance", Vector3(13, 0, 1), -PI / 2]]:
		var car := CarMesh.build(spec[0])
		car.position = cp + spec[1]
		car.rotation.y = spec[2]
		add_child(car)
		flashers.append(car.get_meta("flashers"))
		_static_box(Vector3(2.0, 1.6, 5.0), car.position + Vector3(0, 0.8, 0), spec[2])
	var tape := _mi(_box_mesh(Vector3(22, 0.08, 0.01)), mat("tape"), cp + Vector3(0, 1.0, 4.5), false)
	_label("شرطة · ممنوع الاقتراب   شرطة · ممنوع الاقتراب", cp + Vector3(0, 1.0, 4.52), 0.0, 32, Color(0.05, 0.05, 0.05), 0.006).outline_size = 0
	for x in [-11.0, 11.0]:
		var cm := CylinderMesh.new(); cm.top_radius = 0.04; cm.bottom_radius = 0.05; cm.height = 1.1
		_mi(cm, mat("tape"), cp + Vector3(x, 0.55, 4.5))

func open_door() -> void:
	if door_body:
		for ch in door_body.get_children():
			if ch is CollisionShape3D:
				ch.disabled = true
		var tw := create_tween().set_parallel(true)
		var i := 0
		for ch in door_body.get_children():
			if ch is MeshInstance3D:
				var s := -1.0 if i == 0 else 1.0
				i += 1
				tw.tween_property(ch, "position", ch.position + Vector3(s * 1.5, -1.45, -4.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(ch, "rotation", Vector3(-PI / 2, s * 0.8, 0), 0.6)

# ---------------------------------------------------------------- draw-call reduction
## Merge every static MeshInstance3D / small MultiMesh under the city into a few big meshes
## (one per material per 120 m chunk). Cuts ~2700 draw calls down to a few hundred for phones.
func merge_static() -> void:
	const CHUNK := 120.0
	var groups := {}
	var mats := {}
	var victims: Array = []
	var stack := [[self as Node3D, Transform3D.IDENTITY]]
	while stack.size():
		var it: Array = stack.pop_back()
		var n: Node3D = it[0]
		var xf: Transform3D = it[1]
		for ch in n.get_children():
			if not (ch is Node3D) or ch == door_body or ch.has_meta("no_merge"):
				continue
			var cxf: Transform3D = xf * ch.transform
			if ch is MeshInstance3D and ch.mesh and ch.visible:
				var c := cxf.origin
				var ck := Vector2i(floori(c.x / CHUNK), floori(c.z / CHUNK))
				for si in ch.mesh.get_surface_count():
					var m: Material = ch.material_override if ch.material_override else ch.mesh.surface_get_material(si)
					var fmt := _fmt(ch.mesh, si)
					var key := "%d_%d_%d_%d_%d" % [ck.x, ck.y, m.get_instance_id() if m else 0, fmt, ch.cast_shadow]
					if not groups.has(key):
						var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
						groups[key] = st
						mats[key] = [m, ch.cast_shadow]
					groups[key].append_from(ch.mesh, si, cxf)
				victims.append(ch)
			elif ch is MultiMeshInstance3D and ch.multimesh and not ch.multimesh.use_colors and ch.multimesh.instance_count < 400:
				var mm: MultiMesh = ch.multimesh
				for i in mm.instance_count:
					var ixf: Transform3D = cxf * mm.get_instance_transform(i)
					var c := ixf.origin
					var ck := Vector2i(floori(c.x / CHUNK), floori(c.z / CHUNK))
					for si in mm.mesh.get_surface_count():
						var m: Material = ch.material_override if ch.material_override else mm.mesh.surface_get_material(si)
						var fmt := _fmt(mm.mesh, si)
						var key := "%d_%d_%d_%d_%d" % [ck.x, ck.y, m.get_instance_id() if m else 0, fmt, ch.cast_shadow]
						if not groups.has(key):
							var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
							groups[key] = st
							mats[key] = [m, ch.cast_shadow]
						groups[key].append_from(mm.mesh, si, ixf)
				victims.append(ch)
			elif ch is Label3D:
				ch.visibility_range_end = 140.0
			stack.append([ch, cxf])
	# one MeshInstance per chunk+shadow mode, with one surface per material
	var per_chunk := {}
	for key in groups:
		var parts: PackedStringArray = key.split("_")
		var ck: String = parts[0] + "_" + parts[1] + "_" + parts[4]
		if not per_chunk.has(ck):
			per_chunk[ck] = [ArrayMesh.new(), int(parts[4])]
		var am: ArrayMesh = per_chunk[ck][0]
		if am.get_surface_count() >= 250:
			continue
		groups[key].commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[key][0])
	for v in victims:
		v.get_parent().remove_child(v)
		v.queue_free()
	for ck in per_chunk:
		var mi := MeshInstance3D.new()
		mi.mesh = per_chunk[ck][0]
		mi.cast_shadow = per_chunk[ck][1]
		add_child(mi)

var _fmt_cache := {}
func _fmt(mesh: Mesh, si: int) -> int:
	var k := "%d_%d" % [mesh.get_instance_id(), si]
	if _fmt_cache.has(k):
		return _fmt_cache[k]
	var a := mesh.surface_get_arrays(si)
	var f := 0
	if a[Mesh.ARRAY_COLOR] != null: f |= 1
	if a[Mesh.ARRAY_TEX_UV] != null: f |= 2
	if a[Mesh.ARRAY_INDEX] != null: f |= 4
	if a[Mesh.ARRAY_TANGENT] != null: f |= 8
	_fmt_cache[k] = f
	return f

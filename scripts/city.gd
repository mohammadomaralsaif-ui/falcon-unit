extends Node3D
## Procedural Amman-style city: limestone buildings, shop signs, sidewalks, lane markings,
## street lamps, trees, parked cars, hills covered in houses, and the target bank compound.

const CarMesh = preload("res://scripts/car_mesh.gd")
const Settings = preload("res://scripts/settings.gd")
const CustomModels = preload("res://scripts/custom_models.gd")

const N := 5            # blocks per side
const R := 14.0         # road corridor width (incl. sidewalks)
const B := 46.0         # block size
const P := R + B        # period
const SIDEWALK := 2.2
const FLOOR_H := 3.3
const CELL := 3.2       # bank interior grid cell

const BANK_MAP := [
	"##############",
	"#H.K.#..KE.H.#",
	"#.E..#.......#",
	"#..P.##.###..#",
	"#.........E..#",
	"###.####.C..P#",
	"#H..#.KE.....#",
	"#...#....#####",
	"#.C..O..E...H#",
	"#K...##.TTTT.#",
	"#.E..#..C..E.#",
	"######D#######",
]

const SHOPS := ["صيدلية الشفاء", "مخبز الأمل", "بقالة النور", "حلويات", "فلافل وحمص", "مطعم شاورما", "اتصالات", "مكتبة القدس", "قهوة", "صالون", "ملابس", "عطارة"]

var rng := RandomNumberGenerator.new()
var size_total := 0.0
var bank_block := Vector2i(2, 0)   # the mission building's block (name kept from mission 1)
var mission := {}
var imap: Array = []
var style := "bank"
var evidence_spawns: Array[Vector3] = []
var bomb_pos := Vector3.INF
var cover_points: Array[Vector3] = []
var bank_origin := Vector3.ZERO
var door_pos := Vector3.ZERO
var door_body: StaticBody3D
var enemy_spawns: Array[Vector3] = []
var hostage_spawns: Array[Vector3] = []
var spawn_point := Transform3D.IDENTITY
var sniper_nests: Array = []      # [roof position, yaw] on the tall buildings facing the target (sniper missions)
var cordon_point := Vector3.ZERO
var flashers: Array = []
var baked := {}
var font: Font
var _mats := {}

func build(seed_val := 7, m: Dictionary = {}) -> void:
	Settings.load_all()
	rng.seed = seed_val
	mission = m
	if m.has("block"):
		bank_block = m.block
		imap = m.map
		style = m.style
	else:
		imap = BANK_MAP
	font = load("res://assets/fonts/Tajawal-Bold.ttf")
	size_total = N * P + R
	var _t := Time.get_ticks_msec()
	_ground()
	_roads()
	if OS.has_environment("FALCON_PROFILE"): print("  city ground+roads ", Time.get_ticks_msec() - _t); _t = Time.get_ticks_msec()
	for bi in N:
		for bj in N:
			if Vector2i(bi, bj) == bank_block:
				_bank_block(bi, bj)
			else:
				_block(bi, bj)
	if OS.has_environment("FALCON_PROFILE"): print("  city blocks ", Time.get_ticks_msec() - _t); _t = Time.get_ticks_msec()
	var sx := road_center(1)
	var sz := road_center(N) - 10.0
	spawn_point = Transform3D(Basis(Vector3.UP, PI), Vector3(sx + 2.2, 0.8, sz))
	_hills()
	if OS.has_environment("FALCON_PROFILE"): print("  city hills ", Time.get_ticks_msec() - _t); _t = Time.get_ticks_msec()
	_parked_cars()
	if OS.has_environment("FALCON_PROFILE"): print("  city parked ", Time.get_ticks_msec() - _t); _t = Time.get_ticks_msec()
	build_hq()
	_build_trees()
	if OS.has_environment("FALCON_PROFILE"): print("  city hq+trees ", Time.get_ticks_msec() - _t); _t = Time.get_ticks_msec()

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
			# near-white stone wall with rows of windows (tinted per house by its instance colour);
			# bottom quarter of the image is the plain roof
			m.albedo_texture = _img_tex(256, 256, func(img: Image):
				img.fill(Color(0.97, 0.96, 0.94))
				_speckle(img, 2600, [Color(0.9, 0.89, 0.86), Color(1, 1, 1), Color(0.86, 0.84, 0.8)], 3)
				for fy in [64, 128]:
					img.fill_rect(Rect2i(0, fy - 2, 256, 3), Color(0.8, 0.78, 0.74))
				for row in 3:
					for col in 4:
						var wx := 14 + col * 62
						var wy := 12 + row * 64
						img.fill_rect(Rect2i(wx - 3, wy - 3, 38, 40), Color(0.78, 0.76, 0.72))
						img.fill_rect(Rect2i(wx, wy, 32, 34), Color(0.2, 0.26, 0.33))
						img.fill_rect(Rect2i(wx + 15, wy, 2, 34), Color(0.7, 0.7, 0.7))
						if (row * 4 + col) % 5 == 2:
							img.fill_rect(Rect2i(wx, wy + 14, 32, 20), Color(0.5, 0.56, 0.5))      # shutter half down
				img.fill_rect(Rect2i(0, 190, 256, 6), Color(0.7, 0.68, 0.63))
				img.fill_rect(Rect2i(0, 196, 256, 60), Color(0.8, 0.78, 0.73)))
		"retaining":
			# coursed limestone blocks, no windows
			m.albedo_texture = _img_tex(128, 128, func(img: Image):
				img.fill(Color(0.8, 0.74, 0.62))
				_speckle(img, 2600, [Color(0.72, 0.66, 0.55), Color(0.86, 0.81, 0.7), Color(0.76, 0.7, 0.58)], 3)
				for cy in range(0, 128, 16):
					img.fill_rect(Rect2i(0, cy, 128, 1), Color(0.58, 0.53, 0.44))
					for cx in range((cy / 16 % 2) * 16, 128, 32):
						img.fill_rect(Rect2i(cx, cy, 1, 16), Color(0.6, 0.55, 0.46)))
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(0.18, 0.18, 0.18)
			m.roughness = 0.9
		"hill":
			m.albedo_texture = _img_tex(128, 128, func(img: Image):
				img.fill(Color(0.6, 0.55, 0.44))
				_speckle(img, 2200, [Color(0.52, 0.47, 0.37), Color(0.68, 0.63, 0.5), Color(0.45, 0.47, 0.33), Color(0.57, 0.52, 0.42)], 5))
			m.roughness = 1.0
			m.normal_enabled = true; m.normal_texture = _noise_normal(0.04, 4.0)
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(0.05, 0.05, 0.05)
		"sofa":
			m.albedo_color = Color(0.32, 0.22, 0.17); m.roughness = 0.95
		"granite":
			m.albedo_texture = _img_tex(128, 128, func(img):
				img.fill(Color(0.36, 0.36, 0.38))
				_speckle(img, 4000, [Color(0.26, 0.26, 0.28), Color(0.48, 0.47, 0.46), Color(0.58, 0.56, 0.54)], 1)
				img.fill_rect(Rect2i(0, 0, 128, 1), Color(0.08, 0.08, 0.08)); img.fill_rect(Rect2i(0, 0, 1, 128), Color(0.08, 0.08, 0.08)))
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(0.4, 0.4, 0.4)
			m.roughness = 0.22; m.metallic = 0.1
		"interior":
			m.albedo_texture = _img_tex(64, 256, func(img):
				img.fill(Color(0.86, 0.82, 0.74))
				_speckle(img, 600, [Color(0.82, 0.78, 0.7), Color(0.9, 0.87, 0.8)], 2)
				img.fill_rect(Rect2i(0, 200, 64, 56), Color(0.36, 0.22, 0.13))
				_speckle(img, 300, [Color(0.3, 0.18, 0.1), Color(0.42, 0.27, 0.16)], 1)
				img.fill_rect(Rect2i(0, 198, 64, 4), Color(0.25, 0.15, 0.08))
				img.fill_rect(Rect2i(0, 0, 64, 6), Color(0.95, 0.94, 0.9)))
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(1.0 / 4.2, 1.0 / 4.2, 1.0 / 4.2)
			m.roughness = 0.8
		"marble":
			m.albedo_texture = _img_tex(256, 256, func(img):
				img.fill(Color(0.88, 0.85, 0.79))
				_speckle(img, 3000, [Color(0.83, 0.8, 0.74), Color(0.92, 0.9, 0.86)], 3)
				for v in 7:
					var y := rng.randf_range(0, 256); var slope := rng.randf_range(-0.6, 0.6)
					for x in 256:
						var yy := int(y + x * slope + sin(x * 0.07 + v) * 6.0) % 256
						if yy < 0: yy += 256
						img.set_pixel(x, yy, Color(0.62, 0.58, 0.52))
				for k in 2:
					img.fill_rect(Rect2i(0, k * 128, 256, 2), Color(0.55, 0.52, 0.47))
					img.fill_rect(Rect2i(k * 128, 0, 2, 256), Color(0.55, 0.52, 0.47)))
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(0.33, 0.33, 0.33)
			m.roughness = 0.18
		"wood":
			m.albedo_texture = _img_tex(64, 64, func(img):
				img.fill(Color(0.4, 0.25, 0.14))
				for y in 64:
					if rng.randf() < 0.35:
						img.fill_rect(Rect2i(0, y, 64, 1), Color(0.33, 0.2, 0.11)))
			m.uv1_triplanar = true; m.uv1_scale = Vector3(1.5, 1.5, 1.5)
			m.roughness = 0.45
		"glass":
			m.albedo_color = Color(0.55, 0.7, 0.75, 0.25); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05; m.metallic = 0.3
		"darkglass":
			m.albedo_color = Color(0.06, 0.09, 0.12); m.roughness = 0.04; m.metallic = 0.6
		"screen":
			m.albedo_color = Color(0.05, 0.08, 0.12); m.emission_enabled = true; m.emission = Color(0.3, 0.55, 0.9); m.emission_energy_multiplier = 0.8
		"ceilinglight":
			m.albedo_color = Color(1, 1, 1); m.emission_enabled = true; m.emission = Color(1, 0.96, 0.88); m.emission_energy_multiplier = 3.0
		"black":
			m.albedo_color = Color(0.05, 0.05, 0.06); m.roughness = 0.5
		"pot":
			m.albedo_color = Color(0.55, 0.3, 0.18); m.roughness = 0.8
		"bin":
			m.albedo_color = Color(0.13, 0.33, 0.2); m.roughness = 0.6; m.metallic = 0.3
		"tlred":
			m.albedo_color = Color(0.4, 0, 0); m.emission_enabled = true; m.emission = Color(1, 0.1, 0.05); m.emission_energy_multiplier = 3.0
		"tlgreen":
			m.albedo_color = Color(0, 0.3, 0.1); m.emission_enabled = true; m.emission = Color(0.1, 1, 0.4); m.emission_energy_multiplier = 3.0
		"dish":
			m.albedo_color = Color(0.85, 0.85, 0.83); m.roughness = 0.4; m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"litwindow":
			m.albedo_color = Color(0.55, 0.45, 0.28); m.emission_enabled = true; m.emission = Color(1.0, 0.78, 0.42); m.emission_energy_multiplier = 0.75
		"cone":
			m.albedo_color = Color(0.95, 0.4, 0.05); m.roughness = 0.6
		"tape":
			m.albedo_color = Color(0.95, 0.76, 0.18); m.roughness = 0.5; m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"curb":
			m.albedo_texture = _img_tex(64, 16, func(img):
				img.fill(Color(0.9, 0.75, 0.15))
				img.fill_rect(Rect2i(0, 0, 32, 16), Color(0.08, 0.08, 0.08)))
			m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3(1.0, 1.0, 1.0)
			m.roughness = 0.75
		"manhole":
			m.albedo_color = Color(0.12, 0.12, 0.12); m.metallic = 0.6; m.roughness = 0.5
		"rebar":
			m.albedo_color = Color(0.35, 0.2, 0.12); m.metallic = 0.5; m.roughness = 0.7
		_:
			if key.begins_with("stone") and key.length() > 5:
				var v := int(key.substr(5))
				var t := _facade_v2(v)
				m.albedo_texture = t[0]
				m.normal_enabled = true; m.normal_texture = t[1]; m.normal_scale = 1.0
				m.roughness = 0.85
			elif key.begins_with("shop") and key.length() > 4:
				var v := int(key.substr(4))
				var t := _shop_v2(v)
				m.albedo_texture = t[0]
				m.normal_enabled = true; m.normal_texture = t[1]
				m.roughness = 0.6
				if v % 3 == 1:
					m.emission_enabled = true; m.emission_texture = t[2]; m.emission = Color(1, 1, 1); m.emission_energy_multiplier = 0.3
			elif key.begins_with("awning"):
				var cols := [Color(0.65, 0.1, 0.1), Color(0.1, 0.35, 0.2), Color(0.12, 0.25, 0.5), Color(0.8, 0.55, 0.1)]
				m.albedo_color = cols[int(key.substr(6)) % cols.size()]
				m.roughness = 0.8
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if key.begins_with("sign"):
				var cols := [Color(0.1, 0.4, 0.25), Color(0.5, 0.25, 0.08), Color(0.08, 0.25, 0.5), Color(0.55, 0.12, 0.18), Color(0.15, 0.15, 0.18)]
				m.albedo_color = cols[int(key.substr(4)) % cols.size()]
				m.roughness = 0.5
	_mats[key] = m
	return m

const STONES := [Color(0.9, 0.87, 0.8), Color(0.84, 0.77, 0.64), Color(0.79, 0.68, 0.52), Color(0.83, 0.82, 0.79), Color(0.86, 0.8, 0.7)]

## Cut-stone facade bay (3.4 m x 3.3 m) with a window, plus a matching normal map.
func _facade_v2(v: int) -> Array:
	var W := 512; var H := 512
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var hgt := Image.create(W, H, false, Image.FORMAT_RGB8)
	var base: Color = STONES[v % STONES.size()]
	img.fill(base); hgt.fill(Color(0.7, 0.7, 0.7))
	var r := RandomNumberGenerator.new(); r.seed = 900 + v
	# stone courses with staggered blocks of varying shade
	var y := 0
	var row := 0
	while y < H:
		var ch := r.randi_range(36, 48)
		var x := -r.randi_range(0, 80)
		while x < W:
			var bw := r.randi_range(70, 150)
			var shade := r.randf_range(-0.06, 0.05)
			var col := Color(base.r + shade, base.g + shade, base.b + shade * 1.2)
			img.fill_rect(Rect2i(maxi(x, 0), y, mini(bw, W - maxi(x, 0)), ch), col)
			# chisel texture
			for k in 60:
				var px := r.randi_range(maxi(x, 0), maxi(mini(x + bw, W - 1), 0)); var py := r.randi_range(y, mini(y + ch, H - 1))
				var d := r.randf_range(-0.08, 0.06)
				img.set_pixel(px, py, Color(col.r + d, col.g + d, col.b + d))
				hgt.set_pixel(px, py, Color(0.62 + d, 0.62 + d, 0.62 + d))
			# joint
			if x > 0:
				img.fill_rect(Rect2i(x, y, 2, ch), base.darkened(0.3))
				hgt.fill_rect(Rect2i(x, y, 2, ch), Color(0.35, 0.35, 0.35))
			x += bw
		img.fill_rect(Rect2i(0, y, W, 2), base.darkened(0.3))
		hgt.fill_rect(Rect2i(0, y, W, 2), Color(0.35, 0.35, 0.35))
		y += ch
		row += 1
	# window with stone surround
	var style := v % 3
	var wx := 136; var wy := 110; var ww := 240; var wh := 250
	var sur := base.lightened(0.12)
	img.fill_rect(Rect2i(wx - 22, wy - 22, ww + 44, wh + 44), sur)
	hgt.fill_rect(Rect2i(wx - 22, wy - 22, ww + 44, wh + 44), Color(0.85, 0.85, 0.85))
	img.fill_rect(Rect2i(wx - 34, wy + wh + 10, ww + 68, 18), sur.lightened(0.05))   # sill
	hgt.fill_rect(Rect2i(wx - 34, wy + wh + 10, ww + 68, 18), Color(1, 1, 1))
	# glass with sky reflection gradient
	for gy in wh:
		var t := float(gy) / wh
		var gc := Color(0.32, 0.42, 0.5).lerp(Color(0.08, 0.1, 0.12), t)
		img.fill_rect(Rect2i(wx, wy + gy, ww, 1), gc)
	hgt.fill_rect(Rect2i(wx, wy, ww, wh), Color(0.1, 0.1, 0.1))
	if style == 1:
		# arched top
		for ax in ww + 44:
			var dx := (ax - (ww + 44) * 0.5) / ((ww + 44) * 0.5)
			var top := int(40 * (1.0 - sqrt(maxf(1.0 - dx * dx, 0.0))))
			img.fill_rect(Rect2i(wx - 22 + ax, wy - 22, 1, top), base)
	# aluminium frame + mullion
	var fr := Color(0.85, 0.86, 0.86) if style != 2 else Color(0.25, 0.22, 0.2)
	for rr in [Rect2i(wx, wy, ww, 8), Rect2i(wx, wy + wh - 8, ww, 8), Rect2i(wx, wy, 8, wh), Rect2i(wx + ww - 8, wy, 8, wh), Rect2i(wx + ww / 2 - 4, wy, 8, wh)]:
		img.fill_rect(rr, fr)
		hgt.fill_rect(rr, Color(0.4, 0.4, 0.4))
	# blinds / curtains
	var blind := r.randi_range(0, 2)
	if blind == 1:
		var bh := r.randi_range(60, 200)
		for by in range(0, bh, 6):
			img.fill_rect(Rect2i(wx + 8, wy + 8 + by, ww - 16, 4), Color(0.88, 0.86, 0.8))
	elif blind == 2:
		img.fill_rect(Rect2i(wx + 10, wy + 10, 70, wh - 20), Color(0.75, 0.62, 0.45))
		img.fill_rect(Rect2i(wx + ww - 80, wy + 10, 70, wh - 20), Color(0.75, 0.62, 0.45))
	if style == 2:
		# wrought iron security grille
		for gx in range(wx + 20, wx + ww, 28):
			img.fill_rect(Rect2i(gx, wy - 4, 4, wh + 8), Color(0.1, 0.1, 0.1))
			hgt.fill_rect(Rect2i(gx, wy - 4, 4, wh + 8), Color(1, 1, 1))
		for gy2 in [wy + 60, wy + wh - 60]:
			img.fill_rect(Rect2i(wx, gy2, ww, 4), Color(0.1, 0.1, 0.1))
	# weathering streaks under the sill
	for k in 8:
		var sx := r.randi_range(wx - 20, wx + ww + 20)
		var sl := r.randi_range(30, 110)
		img.fill_rect(Rect2i(sx, wy + wh + 28, 3, sl), base.darkened(0.12))
	img.generate_mipmaps()
	hgt.bump_map_to_normal_map(6.0)
	hgt.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(hgt)]

## Ground-floor shop bay: 0 = closed roller shutter, 1 = open lit shop, 2 = glass shopfront.
func _shop_v2(v: int) -> Array:
	var W := 512; var H := 512
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var hgt := Image.create(W, H, false, Image.FORMAT_RGB8)
	var emi := Image.create(W, H, false, Image.FORMAT_RGB8)
	var base: Color = STONES[(v / 3) % STONES.size()]
	img.fill(base); hgt.fill(Color(0.7, 0.7, 0.7)); emi.fill(Color.BLACK)
	var r := RandomNumberGenerator.new(); r.seed = 500 + v
	var ox := 34; var oy := 70; var ow := 444; var oh := 442
	img.fill_rect(Rect2i(ox - 10, oy - 10, ow + 20, oh + 10), Color(0.2, 0.21, 0.23))
	match v % 3:
		0:
			for yy in range(oy, H, 9):
				img.fill_rect(Rect2i(ox, yy, ow, 6), Color(0.52, 0.54, 0.56))
				img.fill_rect(Rect2i(ox, yy + 6, ow, 3), Color(0.36, 0.38, 0.4))
				hgt.fill_rect(Rect2i(ox, yy + 6, ow, 3), Color(0.3, 0.3, 0.3))
			# graffiti-free padlock box
			img.fill_rect(Rect2i(ox + ow / 2 - 14, H - 40, 28, 20), Color(0.2, 0.2, 0.2))
		1:
			# lit interior: a few shelves with goods in soft colours (reads as a shop, not as noise)
			img.fill_rect(Rect2i(ox, oy, ow, oh), Color(0.5, 0.47, 0.42))
			for sy in range(oy + 110, H - 30, 110):
				img.fill_rect(Rect2i(ox + 14, sy, ow - 28, 10), Color(0.36, 0.26, 0.17))
				var gx := ox + 22
				while gx < ox + ow - 60:
					var gw := r.randi_range(26, 54)
					var gh := r.randi_range(40, 78)
					img.fill_rect(Rect2i(gx, sy - gh, gw, gh), Color.from_hsv(r.randf(), r.randf_range(0.15, 0.4), r.randf_range(0.55, 0.8)))
					gx += gw + r.randi_range(8, 20)
			emi.fill_rect(Rect2i(ox, oy, ow, oh), Color(0.35, 0.33, 0.28))
			img.fill_rect(Rect2i(ox + ow / 2 - 50, oy + 120, 100, oh - 120), Color(0.15, 0.18, 0.2))
			emi.fill_rect(Rect2i(ox + ow / 2 - 50, oy + 120, 100, oh - 120), Color.BLACK)
		2:
			for gy in oh:
				var t := float(gy) / oh
				img.fill_rect(Rect2i(ox, oy + gy, ow, 1), Color(0.3, 0.38, 0.44).lerp(Color(0.1, 0.12, 0.14), t))
			img.fill_rect(Rect2i(ox + 60, oy + 200, 120, 150), Color(0.6, 0.2, 0.25))
			img.fill_rect(Rect2i(ox + 260, oy + 180, 100, 170), Color(0.25, 0.3, 0.55))
	# frame
	for rr in [Rect2i(ox, oy, ow, 8), Rect2i(ox, oy, 8, oh), Rect2i(ox + ow - 8, oy, 8, oh)]:
		img.fill_rect(rr, Color(0.7, 0.71, 0.72))
	hgt.fill_rect(Rect2i(ox, oy, ow, oh), Color(0.25, 0.25, 0.25))
	img.generate_mipmaps(); emi.generate_mipmaps()
	hgt.bump_map_to_normal_map(5.0)
	hgt.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(hgt), ImageTexture.create_from_image(emi)]

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
	l.visibility_range_end = 75.0 if size < 100 else 140.0
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
	_curbs(cx, cz)
	if rng.randf() < 0.6:
		var mh := CylinderMesh.new(); mh.top_radius = 0.35; mh.bottom_radius = 0.35; mh.height = 0.02; mh.radial_segments = 16
		_mi(mh, mat("manhole"), Vector3(cx + rng.randf_range(-20, 20), 0.01, z0 - SIDEWALK - rng.randf_range(2.0, 6.0)), false)
	var lot := (B - 1.0) / 2.0
	var park := rng.randf() < 0.12
	var overlook := style == "yard" and Vector2i(bi, bj) == bank_block + Vector2i(0, 1)
	for lx in 2:
		for lz in 2:
			var bx := x0 + 0.5 + lx * lot + lot * 0.5
			var bz := z0 + 0.5 + lz * lot + lot * 0.5
			if overlook and lz == 0:
				# sniper overwatch: a tall block across the street from the target yard
				var fw := lot - 1.0
				var fd := lot - 1.0
				var fl := 7
				_building(Vector3(bx, 0.16, bz), fw, fd, fl, lx, lz)
				var top := 0.16 + fl * FLOOR_H
				for e in [[Vector3(0, 0, fd * 0.5), Vector3(fw, 1.1, 0.3)], [Vector3(0, 0, -fd * 0.5), Vector3(fw, 1.1, 0.3)], [Vector3(fw * 0.5, 0, 0), Vector3(0.3, 1.1, fd)], [Vector3(-fw * 0.5, 0, 0), Vector3(0.3, 1.1, fd)]]:
					_static_box(e[1], Vector3(bx, top + 0.55, bz) + e[0])
				_static_box(Vector3(fw, 0.2, fd), Vector3(bx, top + 0.1, bz))
				sniper_nests.append([Vector3(bx, top + 0.25, bz - fd * 0.5 + 0.55), 0.0])
				continue
			if park and lx == 0 and lz == 0:
				_trees_in_lot(bx, bz, lot)
				continue
			if rng.randf() < 0.05 and _loft(bx, bz, lot):
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
			if t == 0 and side == 0:
				_traffic_light(Vector3(x0 - SIDEWALK + 0.4, 0.16, z0 - SIDEWALK + 0.4))
			if t == 3 and side == 1:
				_traffic_light(Vector3(x0 + B + SIDEWALK - 0.4, 0.16, z0 + B + SIDEWALK - 0.4))
			if t == 1 and rng.randf() < 0.35:
				var bp := pos + Basis(Vector3.UP, ry) * Vector3(2.5, 0, 0)
				var bin := _mi(_box_mesh(Vector3(1.6, 1.2, 1.0)), mat("bin"), bp + Vector3(0, 0.6, 0))
				bin.rotation.y = ry
				_static_box(Vector3(1.6, 1.2, 1.0), bp + Vector3(0, 0.6, 0), ry)
			if t % 2 == 0:
				_lamp(pos, ry)
			elif rng.randf() < 0.45:
				_tree(pos + Vector3(0, 0, 0))

func _building(base: Vector3, w: float, d: float, floors: int, lx: int, lz: int) -> void:
	var h := floors * FLOOR_H
	# ground floor shops
	var st_shop := SurfaceTool.new(); st_shop.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_up := SurfaceTool.new(); st_up.begin(Mesh.PRIMITIVE_TRIANGLES)
	_walls(st_shop, base, w, d, 0.0, FLOOR_H, 4.0, FLOOR_H)
	_walls(st_up, base, w, d, FLOOR_H, h, 3.4, FLOOR_H)
	var sv := rng.randi_range(0, 4)
	var shopv := sv * 3 + rng.randi_range(0, 2)
	var stone_m := mat("stone%d" % sv)
	var mi_shop := _mi(st_shop.commit(), mat("shop%d" % shopv))
	var mi_up := _mi(st_up.commit(), stone_m)
	_mi(_box_mesh(Vector3(w + 0.3, 0.35, d + 0.3)), mat("roof"), base + Vector3(0, h + 0.17, 0))
	# floor cornice bands + roof parapet
	for fl in range(1, floors + 1):
		_mi(_box_mesh(Vector3(w + 0.16, 0.14, d + 0.16)), mat("white"), base + Vector3(0, fl * FLOOR_H - 0.05, 0))
	for e in [[Vector3(0, 0, d * 0.5), Vector3(w + 0.3, 0.9, 0.22)], [Vector3(0, 0, -d * 0.5), Vector3(w + 0.3, 0.9, 0.22)], [Vector3(w * 0.5, 0, 0), Vector3(0.22, 0.9, d + 0.3)], [Vector3(-w * 0.5, 0, 0), Vector3(0.22, 0.9, d + 0.3)]]:
		_mi(_box_mesh(e[1]), mat("white"), base + e[0] + Vector3(0, h + 0.8, 0))
	# dark stone plinth at street level + white limestone corner quoins (typical Amman facades)
	_mi(_box_mesh(Vector3(w + 0.14, 0.55, d + 0.14)), mat("granite"), base + Vector3(0, 0.27, 0))
	for qx in [-1, 1]:
		for qz in [-1, 1]:
			_mi(_box_mesh(Vector3(0.42, h - FLOOR_H, 0.42)), mat("white"), base + Vector3(qx * w * 0.5, FLOOR_H + (h - FLOOR_H) * 0.5, qz * d * 0.5))
	# set-back penthouse ("روف") on taller buildings
	if floors >= 4 and rng.randf() < 0.45:
		var pw := w * 0.55
		var pd := d * 0.5
		var pp := base + Vector3(rng.randf_range(-0.15, 0.15) * w, h + 0.35, -d * 0.2)
		var ph_st := SurfaceTool.new(); ph_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_walls(ph_st, pp, pw, pd, 0.0, FLOOR_H * 0.95, 3.4, FLOOR_H)
		_mi(ph_st.commit(), stone_m)
		_mi(_box_mesh(Vector3(pw + 0.6, 0.18, pd + 0.6)), mat("white"), pp + Vector3(0, FLOOR_H * 0.95 + 0.09, 0))
	# stair room on the roof
	var srp := base + Vector3(rng.randf_range(-w * 0.25, w * 0.25), h + 0.35, rng.randf_range(-d * 0.25, d * 0.25))
	_mi(_box_mesh(Vector3(3.0, 2.6, 3.2)), stone_m, srp + Vector3(0, 1.3, 0))
	_mi(_box_mesh(Vector3(1.0, 2.0, 0.06)), mat("door"), srp + Vector3(0, 1.0, 1.62), false)
	# unfinished-floor rebar: very common on Amman roofs
	if rng.randf() < 0.35:
		var rb := CylinderMesh.new(); rb.top_radius = 0.02; rb.bottom_radius = 0.02; rb.height = 1.4; rb.radial_segments = 4
		for cx in [-1, 0, 1]:
			for cz in [-1, 1]:
				var cp := base + Vector3(cx * (w * 0.5 - 0.4), h + 1.05, cz * (d * 0.5 - 0.4))
				for k in 4:
					_mi(rb, mat("rebar"), cp + Vector3((k % 2) * 0.15, 0, (k / 2) * 0.15), false)
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
			if rng.randf() < 0.5:
				var aw := _mi(_box_mesh(Vector3(sign_w, 0.05, 1.3)), mat("awning%d" % (rng.randi() % 4)), sp + f * 0.65 + Vector3(0, -0.55, 0), true)
				aw.rotation = Vector3(0.3, ry, 0)
			_label(SHOPS[rng.randi() % SHOPS.size()], sp + f * 0.08, ry, 72, Color(1, 1, 1), 0.009)
	if bal.size():
		_multimesh(_box_mesh(Vector3(2.8, 0.15, 1.1)), mat("white"), bal)
		_multimesh(_box_mesh(Vector3(2.8, 1.0, 0.06)), mat("metal"), rail)
	if acs.size():
		_multimesh(_box_mesh(Vector3(0.85, 0.55, 0.35)), mat("ac"), acs)
	# roof clutter: water tanks + solar heaters (very Amman)
	for i in rng.randi_range(2, 6):
		var p := base + Vector3(rng.randf_range(-w * 0.35, w * 0.35), h + 0.35, rng.randf_range(-d * 0.35, d * 0.35))
		var cm := CylinderMesh.new(); cm.top_radius = 0.55; cm.bottom_radius = 0.55; cm.height = 1.2; cm.radial_segments = 8; cm.rings = 1
		_mi(cm, mat("tankblack" if rng.randf() < 0.6 else "tankwhite"), p + Vector3(0, 0.6, 0))
	for i in rng.randi_range(1, 4):
		var p := base + Vector3(rng.randf_range(-w * 0.4, w * 0.4), h + 0.35, rng.randf_range(-d * 0.4, d * 0.4))
		var dm := SphereMesh.new(); dm.radius = 0.45; dm.height = 0.22; dm.is_hemisphere = true; dm.radial_segments = 14; dm.rings = 3
		var dish := _mi(dm, mat("dish"), p + Vector3(0, 0.75, 0))
		dish.rotation = Vector3(-1.1, rng.randf() * TAU, 0)
		var pc := CylinderMesh.new(); pc.top_radius = 0.03; pc.bottom_radius = 0.03; pc.height = 0.75; pc.radial_segments = 8; pc.rings = 1
		_mi(pc, mat("pole"), p + Vector3(0, 0.37, 0))
	if rng.randf() < 0.7:
		var p := base + Vector3(rng.randf_range(-w * 0.3, w * 0.3), h + 0.35, rng.randf_range(-d * 0.3, d * 0.3))
		var panel := _mi(_box_mesh(Vector3(2.0, 0.06, 1.1)), mat("solar"), p + Vector3(0, 0.7, 0))
		panel.rotation.x = -0.6
		var tank := CylinderMesh.new(); tank.top_radius = 0.25; tank.bottom_radius = 0.25; tank.height = 1.8; tank.radial_segments = 8; tank.rings = 1
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

func _pole_body(pos: Vector3, radius: float, height: float, kind: String) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new(); cy.radius = radius; cy.height = height
	cs.shape = cy
	cs.position = Vector3(0, height * 0.5, 0)
	sb.add_child(cs)
	sb.position = pos
	sb.set_meta("prop", kind)
	add_child(sb)

func _lamp(pos: Vector3, ry: float) -> void:
	var cm := CylinderMesh.new(); cm.top_radius = 0.06; cm.bottom_radius = 0.1; cm.height = 6.0; cm.radial_segments = 8; cm.rings = 1
	_mi(cm, mat("pole"), pos + Vector3(0, 3.0, 0))
	_pole_body(pos, 0.14, 6.0, "pole")
	var arm := _mi(_box_mesh(Vector3(0.08, 0.08, 1.6)), mat("pole"), pos + Vector3(0, 5.9, 0))
	arm.rotation.y = ry
	arm.position += Basis(Vector3.UP, ry) * Vector3(0, 0, -0.75)
	var head := _mi(_box_mesh(Vector3(0.35, 0.12, 0.6)), mat("lamp"), pos + Vector3(0, 5.85, 0), false)
	head.position += Basis(Vector3.UP, ry) * Vector3(0, 0, -1.5)

func _curbs(cx: float, cz: float) -> void:
	var half := B * 0.5 + SIDEWALK
	_mi(_box_mesh(Vector3(half * 2 + 0.25, 0.2, 0.25)), mat("curb"), Vector3(cx, 0.1, cz - half), false)
	_mi(_box_mesh(Vector3(half * 2 + 0.25, 0.2, 0.25)), mat("curb"), Vector3(cx, 0.1, cz + half), false)
	_mi(_box_mesh(Vector3(0.25, 0.2, half * 2 + 0.25)), mat("curb"), Vector3(cx - half, 0.1, cz), false)
	_mi(_box_mesh(Vector3(0.25, 0.2, half * 2 + 0.25)), mat("curb"), Vector3(cx + half, 0.1, cz), false)

func _traffic_light(pos: Vector3) -> void:
	var cm := CylinderMesh.new(); cm.top_radius = 0.07; cm.bottom_radius = 0.08; cm.height = 3.2; cm.radial_segments = 8; cm.rings = 1
	_mi(cm, mat("pole"), pos + Vector3(0, 1.6, 0))
	_pole_body(pos, 0.12, 3.2, "pole")
	for k in 2:
		var ry := PI * 0.25 + k * PI
		var b := Basis(Vector3.UP, ry)
		var hp := pos + Vector3(0, 3.0, 0) + b * Vector3(0, 0, 0.18)
		var box := _mi(_box_mesh(Vector3(0.3, 0.85, 0.22)), mat("black"), hp)
		box.rotation.y = ry
		var on_red := (int(pos.x + pos.z) + k) % 2 == 0
		var lmp715 := _mi(_box_mesh(Vector3(0.16, 0.16, 0.04)), mat("tlred" if on_red else "black"), hp + Vector3(0, 0.25, 0) + b * Vector3(0, 0, 0.12), false)
		lmp715.rotation.y = ry
		var lmp818 := _mi(_box_mesh(Vector3(0.16, 0.16, 0.04)), mat("black"), hp + b * Vector3(0, 0, 0.12), false)
		lmp818.rotation.y = ry
		var lmp69 := _mi(_box_mesh(Vector3(0.16, 0.16, 0.04)), mat("black" if on_red else "tlgreen"), hp + Vector3(0, -0.25, 0) + b * Vector3(0, 0, 0.12), false)
		lmp69.rotation.y = ry

func _loft(cx: float, cz: float, lot: float) -> bool:
	var b := CustomModels.prop("building_loft_lod")   # vertex-coloured, 1 draw call (the HQ uses the full model)
	if not b:
		b = CustomModels.prop("building_loft")
	if not b:
		return false
	var sz: Vector3 = b.get_meta("size")
	var k := minf(lot * 0.92 / sz.x, lot * 0.92 / sz.z)
	b.scale = Vector3.ONE * k
	b.position = Vector3(cx, 0.16, cz)
	b.rotation.y = rng.randi_range(0, 3) * PI * 0.5
	b.set_meta("no_merge", true)
	add_child(b)
	_static_box(Vector3(sz.x * k, sz.y * k, sz.z * k), Vector3(cx, 0.16 + sz.y * k * 0.5, cz), b.rotation.y)
	return true

var tree_list: Array = []        # [position, yaw, height] of every real-model tree (drawn as MultiMeshes)

func _tree(pos: Vector3) -> void:
	if CustomModels.scene("res://assets/props/tree.glb"):
		tree_list.append([pos, rng.randf() * TAU, rng.randf_range(5.5, 7.5)])
		_pole_body(pos, 0.25, 3.0, "tree")
		return
	var cm := CylinderMesh.new(); cm.top_radius = 0.1; cm.bottom_radius = 0.17; cm.height = 3.0; cm.radial_segments = 8; cm.rings = 1
	_mi(cm, mat("trunk"), pos + Vector3(0, 1.5, 0))
	_pole_body(pos, 0.22, 3.0, "tree")
	for i in 3:
		var sm := SphereMesh.new(); var r := rng.randf_range(1.0, 1.5)
		sm.radius = r; sm.height = r * 1.6; sm.radial_segments = 10; sm.rings = 6
		_mi(sm, mat("leaf"), pos + Vector3(rng.randf_range(-0.6, 0.6), 3.3 + rng.randf_range(0, 0.6), rng.randf_range(-0.6, 0.6)))

## All trees of a block share three MultiMeshes (trunk, branches, leaves): 3 draw calls per block
## instead of 3 per tree.
func _build_trees() -> void:
	if tree_list.is_empty():
		return
	var tpl := CustomModels.prop("tree", 1.0)
	if not tpl:
		return
	var parts := []     # [mesh, transform relative to the tree root]
	var stack := [[tpl as Node3D, Transform3D.IDENTITY]]
	while stack.size():
		var it: Array = stack.pop_back()
		for ch in (it[0] as Node3D).get_children():
			if ch is Node3D:
				var cxf: Transform3D = (it[1] as Transform3D) * ch.transform
				if ch is MeshInstance3D and ch.mesh:
					parts.append([ch.mesh, cxf])
				stack.append([ch, cxf])
	var chunks := {}
	for t in tree_list:
		var p: Vector3 = t[0]
		var key := Vector2i(floori(p.x / P), floori(p.z / P))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(t)
	for key in chunks:
		var list: Array = chunks[key]
		var center := Vector3.ZERO
		for t in list:
			center += t[0]
		center /= list.size()
		for part in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = list.size()
			for i in list.size():
				var t: Array = list[i]
				var root := Transform3D(Basis(Vector3.UP, float(t[1])).scaled(Vector3.ONE * float(t[2])), (t[0] as Vector3) - center)
				mm.set_instance_transform(i, root * (part[1] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = center
			mmi.set_meta("no_merge", true)
			mmi.visibility_range_end = [110.0, 150.0, 200.0][Settings.quality]
			if Settings.quality < 2:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
	tpl.free()

func _trees_in_lot(cx: float, cz: float, lot: float) -> void:
	for i in 6:
		_tree(Vector3(cx + rng.randf_range(-lot * 0.4, lot * 0.4), 0.16, cz + rng.randf_range(-lot * 0.4, lot * 0.4)))

func _mosque(cx: float, cz: float, lot: float) -> void:
	var w := lot - 3.0
	_mi(_box_mesh(Vector3(w, 7.0, w)), mat("tankwhite"), Vector3(cx, 3.66, cz))
	_static_box(Vector3(w, 7.0, w), Vector3(cx, 3.66, cz))
	var dome := SphereMesh.new(); dome.radius = w * 0.3; dome.height = w * 0.6; dome.is_hemisphere = true; dome.radial_segments = 16; dome.rings = 6
	var dm := StandardMaterial3D.new(); dm.albedo_color = Color(0.25, 0.45, 0.42); dm.metallic = 0.4; dm.roughness = 0.35
	_mi(dome, dm, Vector3(cx, 7.16, cz))
	var mn := CylinderMesh.new(); mn.top_radius = 0.9; mn.bottom_radius = 1.1; mn.height = 26.0; mn.radial_segments = 8; mn.rings = 1
	_mi(mn, mat("tankwhite"), Vector3(cx + w * 0.42, 13.16, cz + w * 0.42))
	var cap := CylinderMesh.new(); cap.top_radius = 0.0; cap.bottom_radius = 1.0; cap.height = 3.0; cap.radial_segments = 8; cap.rings = 1
	_mi(cap, dm, Vector3(cx + w * 0.42, 27.6, cz + w * 0.42))
	_static_box(Vector3(2.2, 26, 2.2), Vector3(cx + w * 0.42, 13.16, cz + w * 0.42))

# ---------------------------------------------------------------- hills with houses (Amman skyline)
## The hillsides around the district: they now start right behind a retaining wall at the edge of the
## outer streets (no more bare strip of ground), and are covered in stone houses with windows.
func _hills() -> void:
	var fn := FastNoiseLite.new(); fn.frequency = 0.006; fn.seed = 3
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ext := 520.0
	var c := size_total * 0.5
	var edge := 2.0                                   # the slope starts this far outside the streets
	# the police HQ compound sits outside the grid on the south side: keep its pad flat
	var px0 := road_center(1) + 3.2 - 24.0
	var px1 := road_center(1) + 3.2 + 24.0
	var pz1 := size_total + 38.0
	var hfun := func(x: float, z: float) -> float:
		var dx: float = max(0.0, abs(x - c) - c - edge)
		var dz: float = max(0.0, abs(z - c) - c - edge)
		var dist: float = sqrt(dx * dx + dz * dz)
		var qx: float = max(0.0, max(px0 - x, x - px1))
		var qz: float = max(0.0, max(size_total - z, z - pz1))
		dist = min(dist, sqrt(qx * qx + qz * qz))
		if dist <= 0.0:
			return -0.5
		return min(dist * 0.35, 110.0) * (0.75 + 0.5 * (fn.get_noise_2d(x, z) * 0.5 + 0.5)) - 0.5
	# grid lines land exactly on the edges, so the slope never spills onto a street
	var lines := func(lo: float, hi: float, extra: Array) -> Array:
		var out: Array = [lo, hi]
		out.append_array(extra)
		var v := lo - 16.0
		while v > c - ext:
			out.append(v); v -= 16.0
		v = hi + 16.0
		while v < c + ext:
			out.append(v); v += 16.0
		v = lo + 16.0
		while v < hi - 8.0:
			out.append(v); v += 16.0
		out.sort()
		return out
	var xs: Array = lines.call(-edge, size_total + edge, [px0, px1])
	var zs: Array = lines.call(-edge, size_total + edge, [pz1])
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var q := [Vector3(xs[i], 0, zs[j]), Vector3(xs[i + 1], 0, zs[j]), Vector3(xs[i + 1], 0, zs[j + 1]), Vector3(xs[i], 0, zs[j + 1])]
			for k in 4:
				q[k].y = hfun.call(q[k].x, q[k].z)
			if q[0].y < 0 and q[1].y < 0 and q[2].y < 0 and q[3].y < 0:
				continue
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[idx])
	st.generate_normals()
	_mi(st.commit(), mat("hill"), Vector3.ZERO, false)
	# stone retaining wall along the outer streets (with a gap for the HQ compound)
	var wh := 3.2
	var wmat := mat("retaining")
	var segs := [
		[Vector3(c, 0, -0.6), Vector3(size_total + 2.4, wh, 1.2)],
		[Vector3(-0.6, 0, c), Vector3(1.2, wh, size_total + 2.4)],
		[Vector3(size_total + 0.6, 0, c), Vector3(1.2, wh, size_total + 2.4)],
		[Vector3((px0 - 1.2) * 0.5, 0, size_total + 0.6), Vector3(px0 + 1.2, wh, 1.2)],
		[Vector3((px1 + size_total + 1.2) * 0.5, 0, size_total + 0.6), Vector3(size_total + 1.2 - px1, wh, 1.2)],
		# the HQ compound's own yard wall
		[Vector3(px0 - 0.6, 0, (size_total + pz1) * 0.5 + 0.6), Vector3(1.2, wh, pz1 - size_total + 1.2)],
		[Vector3(px1 + 0.6, 0, (size_total + pz1) * 0.5 + 0.6), Vector3(1.2, wh, pz1 - size_total + 1.2)],
		[Vector3((px0 + px1) * 0.5, 0, pz1 + 0.6), Vector3(px1 - px0 + 2.4, wh, 1.2)],
	]
	for sg in segs:
		var p: Vector3 = sg[0]; var sz: Vector3 = sg[1]
		_mi(_box_mesh(sz), wmat, p + Vector3(0, wh * 0.5, 0), false)
		_mi(_box_mesh(Vector3(sz.x + 0.3 if sz.x > sz.z else 1.5, 0.22, 1.5 if sz.x > sz.z else sz.z + 0.3)), mat("roof"), p + Vector3(0, wh + 0.11, 0), false)
		_static_box(sz, p + Vector3(0, wh * 0.5, 0))
	# houses: one MultiMesh, each with windows and a flat roof, packed densest next to the district
	var xf := []; var cols := []
	var tones := [Color(0.84, 0.79, 0.69), Color(0.78, 0.71, 0.58), Color(0.9, 0.87, 0.8), Color(0.72, 0.65, 0.53), Color(0.82, 0.77, 0.7), Color(0.76, 0.72, 0.66)]
	for i in 6200:
		var near := i < 2600
		var span := (c + 150.0) if near else ext * 0.95
		var x := c + rng.randf_range(-span, span)
		var z := c + rng.randf_range(-span, span)
		var y: float = hfun.call(x, z)
		if y < 2.0:
			continue
		var s := Vector3(rng.randf_range(7, 14), rng.randf_range(5, 12), rng.randf_range(7, 14))
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.25, 0.25)).scaled(s), Vector3(x, y + s.y * 0.5 - 1.5, z)))
		cols.append((tones[rng.randi() % tones.size()] as Color).darkened(rng.randf_range(0.0, 0.12)))
	var mmi := _multimesh(_house_mesh(), mat("houses"), xf, cols)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Unit box for the hillside houses: the four walls show the window texture, the roof a plain patch.
func _house_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.5
	var corners := [Vector3(-h, 0, h), Vector3(h, 0, h), Vector3(h, 0, -h), Vector3(-h, 0, -h)]
	for i in 4:
		var a: Vector3 = corners[i]; var b: Vector3 = corners[(i + 1) % 4]
		var n := (b - a).cross(Vector3.UP).normalized()
		var quad := [[a + Vector3(0, -h, 0), Vector2(0, 0.75)], [b + Vector3(0, -h, 0), Vector2(1, 0.75)], [b + Vector3(0, h, 0), Vector2(1, 0)], [a + Vector3(0, h, 0), Vector2(0, 0)]]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n); st.set_uv(quad[idx][1]); st.add_vertex(quad[idx][0])
	var top := [[Vector3(-h, h, h), Vector2(0.05, 0.98)], [Vector3(h, h, h), Vector2(0.95, 0.98)], [Vector3(h, h, -h), Vector2(0.95, 0.8)], [Vector3(-h, h, -h), Vector2(0.05, 0.8)]]
	for idx in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP); st.set_uv(top[idx][1]); st.add_vertex(top[idx][0])
	return st.commit()

# ---------------------------------------------------------------- parked cars
func bake(node: Node3D, lods := true) -> ArrayMesh:
	var groups := {}
	var stack := [[node, Transform3D.IDENTITY]]
	while stack.size():
		var it: Array = stack.pop_back()
		var n: Node3D = it[0]
		var xf: Transform3D = it[1]
		for ch in n.get_children():
			if ch is Node3D:
				var cxf: Transform3D = xf * ch.transform
				if ch is MeshInstance3D and ch.mesh and ch.visible:
					for si in ch.mesh.get_surface_count():
						var m: Material = ch.material_override
						if not m:
							m = ch.get_surface_override_material(si)
						if not m:
							m = ch.mesh.surface_get_material(si)
						if not groups.has(m):
							var s := SurfaceTool.new(); s.begin(Mesh.PRIMITIVE_TRIANGLES)
							groups[m] = s
						var src: Mesh = ch.mesh
						var ssi: int = si
						groups[m].append_from(src, ssi, cxf)
				stack.append([ch, cxf])
	# ImporterMesh builds automatic LODs, so far-away cars cost a fraction of the triangles
	var im := ImporterMesh.new()
	for m in groups:
		var one := ArrayMesh.new()
		groups[m].commit(one)
		if one.get_surface_count() > 0:
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, one.surface_get_arrays(0), [], {}, m)
	if lods:
		im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

## Cars are baked ONCE per model (geometry + automatic LODs). The body colour is not baked in:
## painted vertices carry a mask in their vertex alpha and a tiny shader tints them, so twenty
## differently coloured cars share one mesh and cost nothing extra to load.
var _car_base := {}
var _paint_mats := {}
var _paint_shader: Shader

const PAINT_SHADER := """shader_type spatial;
uniform vec3 paint : source_color = vec3(0.8);
uniform float ref = 0.5;
void vertex() {
	if (COLOR.a < 0.75) {
		float sh = clamp(max(COLOR.r, max(COLOR.g, COLOR.b)) / max(ref, 0.01), 0.35, 1.4);
		COLOR.rgb = paint * sh;
	}
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.3;
	METALLIC = 0.15;
}
"""

var CAR_LOD_DIST: float:
	get: return [20.0, 26.0, 34.0][Settings.quality]

func _car_model(kind: String, variant: int) -> Array:
	var key := kind + str(variant)
	if not _car_base.has(key):
		# a hand-reduced far model (assets/cars/lod/<same file>) takes over beyond CAR_LOD_DIST;
		# the full model then never needs runtime LOD generation (slow to build, ugly on these meshes)
		var far_mesh: ArrayMesh = null
		var files: Array = CustomModels.files_for("res://assets/cars", kind)
		if files.size() > 0:
			var lp := "res://assets/cars/lod/" + String(files[variant % files.size()])
			if ResourceLoader.exists(lp):
				var fn := CustomModels.car_from(lp, float(CarMesh.SPECS["sedan"].L))
				if fn:
					far_mesh = bake(fn, false)
					fn.free()
		var node := CarMesh.build(kind, Color.WHITE, true, variant)
		var painted := node.has_meta("paint")
		var mesh := bake(node, far_mesh == null)
		node.free()
		var ref := _paint_ref(mesh) if painted else 0.0
		var far_ref := _paint_ref(far_mesh) if (painted and far_mesh) else ref
		_car_base[key] = [mesh, ref, painted, far_mesh, far_ref]
	return _car_base[key]

## Average brightness of the paint-masked vertices (the shader keeps each vertex's shade relative to it).
func _paint_ref(mesh: ArrayMesh) -> float:
	var ref := 0.0
	var cnt := 0
	for si in mesh.get_surface_count():
		var cols = mesh.surface_get_arrays(si)[Mesh.ARRAY_COLOR]
		if cols is PackedColorArray:
			for k in range(0, cols.size(), 5):
				var c: Color = cols[k]
				if c.a < 0.75:
					ref += maxf(c.r, maxf(c.g, c.b)); cnt += 1
	return ref / maxf(cnt, 1.0)

func _paint_mat(color: Color, ref: float) -> ShaderMaterial:
	var key := color.to_html() + str(snappedf(ref, 0.001))
	if not _paint_mats.has(key):
		if not _paint_shader:
			_paint_shader = Shader.new()
			_paint_shader.code = PAINT_SHADER
		var m := ShaderMaterial.new()
		m.shader = _paint_shader
		m.set_shader_parameter("paint", color)
		m.set_shader_parameter("ref", ref)
		_paint_mats[key] = m
	return _paint_mats[key]

## Give a MeshInstance3D a car body of this kind and colour. `far_end` > 0 hides it past that distance.
func dress_car(mi: MeshInstance3D, kind: String, color: Color, far_end := 0.0) -> void:
	var b: Array = _car_model(kind, CustomModels.weighted_pick("res://assets/cars", kind, rng))
	mi.mesh = b[0]
	var pm: ShaderMaterial = _paint_mat(color, b[1]) if b[2] else null
	_paint_surfaces(mi, pm)
	if b[3]:
		mi.visibility_range_end = CAR_LOD_DIST
		var far := MeshInstance3D.new()
		far.mesh = b[3]
		far.visibility_range_begin = CAR_LOD_DIST
		far.visibility_range_end = far_end
		if Settings.quality < 2:
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_paint_surfaces(far, _paint_mat(color, b[4]) if b[2] else null)
		mi.add_child(far)
	elif far_end > 0.0:
		mi.visibility_range_end = far_end

func _paint_surfaces(mi: MeshInstance3D, pm: ShaderMaterial) -> void:
	if not pm:
		return
	for si in mi.mesh.get_surface_count():
		var sm := mi.mesh.surface_get_material(si) as StandardMaterial3D
		if sm and sm.vertex_color_use_as_albedo and sm.albedo_color.v > 0.5:      # not the dark glass
			mi.set_surface_override_material(si, pm)

const CAR_COLORS := [Color(0.95, 0.95, 0.95), Color(0.76, 0.77, 0.8), Color(0.08, 0.08, 0.09), Color(0.72, 0.08, 0.08), Color(0.16, 0.36, 0.78), Color(0.86, 0.8, 0.64), Color(0.9, 0.9, 0.92), Color(0.33, 0.35, 0.38), Color(0.12, 0.42, 0.28), Color(0.7, 0.52, 0.26)]

func dress_random_car(mi: MeshInstance3D, far_end := 0.0) -> void:
	if rng.randf() < 0.18:
		dress_car(mi, "taxi", Color.YELLOW, far_end)
	else:
		dress_car(mi, "sedan", CAR_COLORS[rng.randi() % CAR_COLORS.size()], far_end)

func _parked_cars() -> void:
	var n := 16      # few parked cars: most of what you see on the street should be moving
	for i in n:
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
		var mi := MeshInstance3D.new()
		dress_random_car(mi, 140.0)
		mi.position = pos
		add_child(mi)
		mi.rotation.y = ry
		mi.set_meta("no_merge", true)
		_static_box(Vector3(1.8, 1.4, 4.5), pos + Vector3(0, 0.7, 0), ry)

# ---------------------------------------------------------------- bank compound (mission target)
func _bank_block(bi: int, bj: int) -> void:
	var x0 := bi * P + R
	var z0 := bj * P + R
	_mi(_box_mesh(Vector3(B + SIDEWALK * 2, 0.16, B + SIDEWALK * 2)), mat("sidewalk"), Vector3(x0 + B * 0.5, 0.08, z0 + B * 0.5), false)
	_static_box(Vector3(B + SIDEWALK * 2, 0.16, B + SIDEWALK * 2), Vector3(x0 + B * 0.5, 0.08, z0 + B * 0.5))
	_curbs(x0 + B * 0.5, z0 + B * 0.5)
	var rows := imap.size()
	var cols: int = imap[0].length()
	var ox := x0 + (B - cols * CELL) * 0.5
	var oz := z0 + B - rows * CELL - 0.5
	bank_origin = Vector3(ox, 0.16, oz)
	var wall_st := SurfaceTool.new(); wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var out_st := SurfaceTool.new(); out_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yard := style == "yard"
	var wh := 4.2 if not yard else 2.6
	var wall_mesh := _box_mesh(Vector3(CELL, wh, CELL))
	for r in rows:
		var line: String = imap[r]
		for c in cols:
			var ch := line[c]
			var p := Vector3(ox + c * CELL + CELL * 0.5, 0.16, oz + r * CELL + CELL * 0.5)
			match ch:
				"#":
					var outer := r == 0 or c == 0 or r == rows - 1 or c == cols - 1
					var wst: SurfaceTool = out_st if outer else wall_st
					wst.append_from(wall_mesh, 0, Transform3D(Basis(), p + Vector3(0, wh * 0.5, 0)))
					_static_box(Vector3(CELL, wh, CELL), p + Vector3(0, wh * 0.5, 0))
				"E":
					enemy_spawns.append(p)
				"H":
					hostage_spawns.append(p)
				"K":
					if style == "mall":
						_bench(p)
					else:
						_desk(p)
					cover_points.append(p)
				"S":
					_sofa(p)
					cover_points.append(p)
				"B":
					_bed(p)
				"V":
					evidence_spawns.append(p)
					_table(p)
				"X":
					bomb_pos = p
				"P":
					_plant(p)
				"O":
					_mi(_box_mesh(Vector3(0.8, wh, 0.8)), mat("marble"), p + Vector3(0, wh * 0.5, 0))
					_static_box(Vector3(0.8, wh, 0.8), p + Vector3(0, wh * 0.5, 0))
					cover_points.append(p)
				"T":
					cover_points.append(p)
					if style == "apartment":
						_table(p)
						continue
					if style == "mall":
						_kiosk(p)
						continue
					_mi(_box_mesh(Vector3(CELL, 1.1, 0.8)), mat("wood"), p + Vector3(0, 0.55, 0))
					_mi(_box_mesh(Vector3(CELL, 0.05, 0.95)), mat("granite"), p + Vector3(0, 1.12, 0))
					_mi(_box_mesh(Vector3(CELL - 0.1, 0.9, 0.03)), mat("glass"), p + Vector3(0, 1.6, 0.0), false)
					_mi(_box_mesh(Vector3(0.5, 0.32, 0.03)), mat("screen"), p + Vector3(0.6, 1.32, -0.2), false)
					_static_box(Vector3(CELL, 1.1, 0.8), p + Vector3(0, 0.55, 0))
				"U":
					_bus(p)
					cover_points.append(p + Vector3(-6.4, 0, 0))
					cover_points.append(p + Vector3(6.4, 0, 0))
				"C":
					var crate := _mi(_box_mesh(Vector3(2.2, 1.3, 2.2)), mat("door"), p + Vector3(0, 0.65, 0))
					crate.material_override = _crate_mat()
					cover_points.append(p)
					_static_box(Vector3(2.2, 1.3, 2.2), p + Vector3(0, 0.65, 0))
				"D":
					door_pos = p
					door_body = StaticBody3D.new()
					var dh := 3.2 if not yard else wh
					var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(CELL, dh, 0.3); cs.shape = bs
					cs.position = Vector3(0, dh * 0.5, 0)
					door_body.add_child(cs)
					for s in [-1, 1]:
						var leaf := MeshInstance3D.new(); leaf.mesh = _box_mesh(Vector3(CELL * 0.5 - 0.05, dh - 0.1, 0.12)); leaf.material_override = mat("door")
						leaf.position = Vector3(s * CELL * 0.25, (dh - 0.1) * 0.5, 0)
						door_body.add_child(leaf)
					door_body.position = p
					add_child(door_body)
					if yard:
						continue
					var lintel := _mi(_box_mesh(Vector3(CELL, wh - 3.2, CELL)), mat("plaster"), p + Vector3(0, 3.2 + (wh - 3.2) * 0.5, 0))
					lintel.material_override = mat("plaster")
					_static_box(Vector3(CELL, wh - 3.2, CELL), p + Vector3(0, 3.2 + (wh - 3.2) * 0.5, 0))
	# ground-floor windows on the outside of the mission building (frames, glass, security bars)
	if style in ["bank", "apartment"]:
		for r in rows:
			for c in cols:
				if imap[r][c] != "#":
					continue
				var corner := (r == 0 or r == rows - 1) and (c == 0 or c == cols - 1)
				if corner or (style == "bank" and r == rows - 1 and mission.get("bank_front", true)):
					continue
				var nrm := Vector3.ZERO
				if r == 0: nrm = Vector3(0, 0, -1)
				elif r == rows - 1: nrm = Vector3(0, 0, 1)
				elif c == 0: nrm = Vector3(-1, 0, 0)
				elif c == cols - 1: nrm = Vector3(1, 0, 0)
				if nrm == Vector3.ZERO or (c + r) % 2 == 1:
					continue
				var wp := Vector3(ox + c * CELL + CELL * 0.5, 0.16 + 2.0, oz + r * CELL + CELL * 0.5) + nrm * (CELL * 0.5 + 0.03)
				var wry := atan2(nrm.x, nrm.z)
				var fr := _mi(_box_mesh(Vector3(1.9, 1.6, 0.08)), mat("white"), wp, false)
				fr.rotation.y = wry
				var gl := _mi(_box_mesh(Vector3(1.66, 1.36, 0.1)), mat("darkglass" if mission.get("sky", "") != "night" else "litwindow"), wp + nrm * 0.02, false)
				gl.rotation.y = wry
				var sill := _mi(_box_mesh(Vector3(2.1, 0.1, 0.3)), mat("white"), wp + Vector3(0, -0.85, 0) + nrm * 0.1, false)
				sill.rotation.y = wry
				if style == "apartment" and mission.get("bars", true):
					for bk in 5:
						var bar := _mi(_box_mesh(Vector3(0.03, 1.36, 0.03)), mat("black"), wp + nrm * 0.12 + Basis(Vector3.UP, wry) * Vector3(-0.66 + bk * 0.33, 0, 0), false)
						bar.rotation.y = wry
	var in_mat: String = {"bank": "interior", "apartment": "plaster", "mall": "white", "yard": "sidewalk"}[style]
	var out_mat: String = {"bank": "granite", "apartment": "stone%d" % (bi % 5), "mall": "darkglass", "yard": "plaster"}[style]
	var floor_mat: String = {"bank": "marble", "apartment": "tile", "mall": "marble", "yard": "asphalt"}[style]
	var skin: Dictionary = mission.get("mats", {})
	in_mat = skin.get("in", in_mat)
	out_mat = skin.get("out", out_mat)
	floor_mat = skin.get("floor", floor_mat)
	var walls := _mi(wall_st.commit(), mat(in_mat))
	_mi(out_st.commit(), mat(out_mat))
	if yard:
		# open-air compound: no roof, no ceiling lights. A couple of floodlights on poles.
		_mi(_box_mesh(Vector3(cols * CELL, 0.05, rows * CELL)), mat(floor_mat), bank_origin + Vector3(cols * CELL * 0.5, 0.03, rows * CELL * 0.5), false)
		_static_box(Vector3(cols * CELL, 0.05, rows * CELL), bank_origin + Vector3(cols * CELL * 0.5, 0.03, rows * CELL * 0.5))
		for k in 2:
			var lp := bank_origin + Vector3(cols * CELL * (0.25 + k * 0.5), 0, CELL * 1.2)
			var pole := CylinderMesh.new(); pole.top_radius = 0.07; pole.bottom_radius = 0.09; pole.height = 7.0; pole.radial_segments = 8; pole.rings = 1
			_mi(pole, mat("pole"), lp + Vector3(0, 3.5, 0))
			_mi(_box_mesh(Vector3(0.7, 0.3, 0.4)), mat("lamp"), lp + Vector3(0, 7.0, 0.2), false)
		cordon_point = door_pos + Vector3(0, 0, 14.0)
		return
	# residential / office floors stacked above the mission floor
	var floors_up: int = mission.get("floors_above", 0)
	if floors_up > 0:
		var up_st := SurfaceTool.new(); up_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var fc := bank_origin + Vector3(cols * CELL * 0.5, 0, rows * CELL * 0.5)
		var top := wh + 0.4 + floors_up * FLOOR_H
		_walls(up_st, Vector3(fc.x, 0.16, fc.z), cols * CELL, rows * CELL, wh + 0.4, top, 3.4, FLOOR_H)
		_mi(up_st.commit(), mat("stone%d" % ((bi + bj) % 5)))
		_mi(_box_mesh(Vector3(cols * CELL + 0.3, 0.35, rows * CELL + 0.3)), mat("roof"), Vector3(fc.x, 0.16 + top + 0.17, fc.z))
		_static_box(Vector3(cols * CELL, top - wh, rows * CELL), Vector3(fc.x, 0.16 + wh + (top - wh) * 0.5, fc.z))
		for fl2 in range(1, floors_up + 1):
			_mi(_box_mesh(Vector3(cols * CELL + 0.16, 0.14, rows * CELL + 0.16)), mat("white"), Vector3(fc.x, 0.16 + wh + 0.4 + fl2 * FLOOR_H - 0.05, fc.z))
	# floor + roof
	var fl := _mi(_box_mesh(Vector3(cols * CELL, 0.05, rows * CELL)), mat(floor_mat), bank_origin + Vector3(cols * CELL * 0.5, 0.03, rows * CELL * 0.5), false)
	_static_box(Vector3(cols * CELL, 0.05, rows * CELL), bank_origin + Vector3(cols * CELL * 0.5, 0.03, rows * CELL * 0.5))
	var roof := _mi(_box_mesh(Vector3(cols * CELL + 0.6, 0.4, rows * CELL + 0.6)), mat("roof"), bank_origin + Vector3(cols * CELL * 0.5, wh + 0.2, rows * CELL * 0.5))
	# facade sign
	var sign_text: String = mission.get("sign", "مصرف الشرق")
	if sign_text != "":
		var sign_pos := door_pos + Vector3(0, wh - 0.3 if floors_up > 0 else wh + 1.2, CELL * 0.5 + 0.2)
		var board := _mi(_box_mesh(Vector3(12, 1.5, 0.25)), mat("bankboard"), sign_pos, false)
		var bm := StandardMaterial3D.new()
		bm.albedo_color = mission.get("sign_color", Color(0.06, 0.16, 0.29) if style == "bank" else Color(0.45, 0.08, 0.32))
		board.material_override = bm
		_label(sign_text, sign_pos + Vector3(0, 0, 0.14), 0.0, 120, Color(0.96, 0.9, 0.72), 0.01)
	# interior lights: ceiling panels + a few real lights + reflection probe (no sky reflections indoors)
	for r in range(1, rows - 1, 2):
		for c in range(1, cols - 1, 2):
			if imap[r][c] != "#":
				_mi(_box_mesh(Vector3(1.2, 0.04, 1.2)), mat("ceilinglight"), bank_origin + Vector3(c * CELL + CELL * 0.5, wh - 0.03, r * CELL + CELL * 0.5), false)
	# six soft lights in a 3 x 2 grid light the whole floor evenly (no shadows: cheap on phones)
	for i in 6:
		var ol := OmniLight3D.new()
		ol.light_color = {"bank": Color(1, 0.93, 0.82), "apartment": Color(1, 0.8, 0.58), "mall": Color(0.95, 0.97, 1.0)}[style]
		ol.light_energy = {"bank": 1.6, "apartment": 1.25, "mall": 0.95}[style]
		ol.omni_range = 17.0
		ol.omni_attenuation = 0.7
		ol.position = bank_origin + Vector3(cols * CELL * (0.18 + (i % 3) * 0.32), 3.6, rows * CELL * (0.28 if i < 3 else 0.72))
		add_child(ol)
	var rp := ReflectionProbe.new()
	rp.size = Vector3(cols * CELL, wh, rows * CELL)
	rp.position = bank_origin + Vector3(cols * CELL * 0.5, wh * 0.5, rows * CELL * 0.5)
	rp.interior = true
	rp.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	rp.ambient_color = Color(0.55, 0.5, 0.44)
	rp.ambient_color_energy = {"bank": 1.1, "apartment": 1.0, "mall": 0.7}.get(style, 1.0)
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(rp)
	cordon_point = door_pos + Vector3(0, 0, 14.0)
	if style != "bank" or not mission.get("bank_front", true):
		return
	# street facade: tinted glass bays between granite columns, steps, ATM
	var fz := oz + rows * CELL + 0.02
	for c in range(1, cols - 1):
		if c == 6:
			continue
		var x := ox + c * CELL + CELL * 0.5
		_mi(_box_mesh(Vector3(CELL - 0.5, 3.0, 0.05)), mat("darkglass"), Vector3(x, 1.9, fz), false)
		_mi(_box_mesh(Vector3(0.5, wh, 0.35)), mat("granite"), Vector3(ox + c * CELL, 0.16 + wh * 0.5, fz + 0.1))
	_mi(_box_mesh(Vector3(CELL * 2.0, 0.15, 1.2)), mat("granite"), door_pos + Vector3(0, 0.0, CELL * 0.5 + 0.6), false)
	var atm := door_pos + Vector3(CELL * 2.5, 0, CELL * 0.5 + 0.25)
	_mi(_box_mesh(Vector3(0.9, 1.7, 0.5)), mat("door"), atm + Vector3(0, 0.85, 0))
	_mi(_box_mesh(Vector3(0.5, 0.35, 0.02)), mat("screen"), atm + Vector3(0, 1.25, 0.26), false)
	_label("صراف آلي ATM", atm + Vector3(0, 1.62, 0.26), 0.0, 40, Color(1, 1, 1), 0.006)
	cordon_point = door_pos + Vector3(0, 0, 14.0)

## City bus (10.5 m) lying along X: white body with a blue band, dark windows, wheels. Solid cover.
func _bus(p: Vector3) -> void:
	var L := 10.5
	var body := StandardMaterial3D.new(); body.albedo_color = Color(0.9, 0.9, 0.88); body.roughness = 0.5
	var band := StandardMaterial3D.new(); band.albedo_color = Color(0.1, 0.3, 0.62); band.roughness = 0.5
	_mi(_box_mesh(Vector3(L, 2.35, 2.5)), body, p + Vector3(0, 1.65, 0))
	_mi(_box_mesh(Vector3(L + 0.02, 0.5, 2.52)), band, p + Vector3(0, 1.05, 0), false)
	_mi(_box_mesh(Vector3(L - 0.4, 0.12, 2.3)), mat("roof"), p + Vector3(0, 2.88, 0), false)
	for side in [-1.0, 1.0]:
		_mi(_box_mesh(Vector3(L - 1.6, 0.85, 0.04)), mat("darkglass"), p + Vector3(-0.3, 2.1, side * 1.26), false)
		for wx in [-3.4, 3.2]:
			var wm := CylinderMesh.new(); wm.top_radius = 0.48; wm.bottom_radius = 0.48; wm.height = 0.3; wm.radial_segments = 12; wm.rings = 1
			var wh := _mi(wm, mat("black"), p + Vector3(wx, 0.48, side * 1.12), false)
			wh.rotation.x = PI / 2
	_mi(_box_mesh(Vector3(0.04, 1.2, 2.2)), mat("darkglass"), p + Vector3(L * 0.5 + 0.01, 1.95, 0), false)       # windscreen
	_mi(_box_mesh(Vector3(0.04, 0.9, 2.0)), mat("darkglass"), p + Vector3(-L * 0.5 - 0.01, 2.1, 0), false)
	_mi(_box_mesh(Vector3(0.05, 1.9, 0.9)), mat("black"), p + Vector3(2.2, 1.45, 1.27), false)                   # door
	_label("النقل العام · خط ٢٦", p + Vector3(-1.0, 1.05, 1.28), 0.0, 40, Color(1, 1, 1), 0.007)
	_static_box(Vector3(L, 2.9, 2.5), p + Vector3(0, 1.45, 0))

func _desk(p: Vector3) -> void:
	_mi(_box_mesh(Vector3(1.6, 0.05, 0.8)), mat("wood"), p + Vector3(0, 0.76, 0))
	_mi(_box_mesh(Vector3(1.5, 0.7, 0.05)), mat("wood"), p + Vector3(0, 0.38, -0.35))
	for sx in [-0.75, 0.75]:
		_mi(_box_mesh(Vector3(0.05, 0.74, 0.75)), mat("wood"), p + Vector3(sx, 0.37, 0))
	_mi(_box_mesh(Vector3(0.55, 0.34, 0.03)), mat("black"), p + Vector3(0.1, 1.05, -0.2))
	_mi(_box_mesh(Vector3(0.5, 0.29, 0.01)), mat("screen"), p + Vector3(0.1, 1.05, -0.18), false)
	_mi(_box_mesh(Vector3(0.45, 0.02, 0.15)), mat("black"), p + Vector3(0.1, 0.79, 0.1), false)
	# office chair
	_mi(_box_mesh(Vector3(0.5, 0.08, 0.5)), mat("black"), p + Vector3(0, 0.5, 0.75))
	_mi(_box_mesh(Vector3(0.5, 0.55, 0.07)), mat("black"), p + Vector3(0, 0.8, 1.0))
	var cm := CylinderMesh.new(); cm.top_radius = 0.03; cm.bottom_radius = 0.03; cm.height = 0.45; cm.radial_segments = 8; cm.rings = 1
	_mi(cm, mat("metal"), p + Vector3(0, 0.25, 0.75))
	_static_box(Vector3(1.6, 0.8, 0.8), p + Vector3(0, 0.4, 0))

func _sofa(p: Vector3) -> void:
	var m := mat("sofa")
	_mi(_box_mesh(Vector3(2.0, 0.45, 0.9)), m, p + Vector3(0, 0.25, 0))
	_mi(_box_mesh(Vector3(2.0, 0.5, 0.25)), m, p + Vector3(0, 0.7, -0.33))
	for sx in [-0.95, 0.95]:
		_mi(_box_mesh(Vector3(0.2, 0.35, 0.9)), m, p + Vector3(sx, 0.6, 0))
	_static_box(Vector3(2.0, 0.9, 0.9), p + Vector3(0, 0.45, 0))

func _bed(p: Vector3) -> void:
	_mi(_box_mesh(Vector3(1.6, 0.45, 2.1)), mat("wood"), p + Vector3(0, 0.22, 0))
	_mi(_box_mesh(Vector3(1.55, 0.2, 2.0)), mat("white"), p + Vector3(0, 0.55, 0))
	_mi(_box_mesh(Vector3(1.6, 0.9, 0.08)), mat("wood"), p + Vector3(0, 0.6, -1.05))
	_static_box(Vector3(1.6, 0.65, 2.1), p + Vector3(0, 0.32, 0))

func _table(p: Vector3) -> void:
	_mi(_box_mesh(Vector3(1.4, 0.05, 0.9)), mat("wood"), p + Vector3(0, 0.76, 0))
	for sx in [-0.62, 0.62]:
		for sz in [-0.38, 0.38]:
			_mi(_box_mesh(Vector3(0.06, 0.74, 0.06)), mat("wood"), p + Vector3(sx, 0.37, sz))
	_static_box(Vector3(1.4, 0.8, 0.9), p + Vector3(0, 0.4, 0))

func _bench(p: Vector3) -> void:
	_mi(_box_mesh(Vector3(2.4, 0.08, 0.6)), mat("wood"), p + Vector3(0, 0.45, 0))
	_mi(_box_mesh(Vector3(2.2, 0.42, 0.4)), mat("metal"), p + Vector3(0, 0.21, 0))
	_static_box(Vector3(2.4, 0.5, 0.6), p + Vector3(0, 0.25, 0))

func _kiosk(p: Vector3) -> void:
	_mi(_box_mesh(Vector3(2.6, 1.0, 1.2)), mat("white"), p + Vector3(0, 0.5, 0))
	_mi(_box_mesh(Vector3(2.5, 0.6, 1.1)), mat("glass"), p + Vector3(0, 1.3, 0), false)
	_mi(_box_mesh(Vector3(2.6, 0.08, 1.25)), mat("granite"), p + Vector3(0, 1.62, 0))
	_mi(_box_mesh(Vector3(2.4, 0.3, 0.05)), mat("sign%d" % (int(p.x + p.z) % 5)), p + Vector3(0, 2.3, 0))
	_static_box(Vector3(2.6, 1.0, 1.2), p + Vector3(0, 0.5, 0))

func _plant(p: Vector3) -> void:
	var pot := CylinderMesh.new(); pot.top_radius = 0.3; pot.bottom_radius = 0.22; pot.height = 0.6; pot.radial_segments = 8; pot.rings = 1
	_mi(pot, mat("pot"), p + Vector3(0, 0.3, 0))
	for i in 3:
		var sm := SphereMesh.new(); sm.radius = 0.4; sm.height = 0.9; sm.radial_segments = 8; sm.rings = 5
		_mi(sm, mat("leaf"), p + Vector3(rng.randf_range(-0.15, 0.15), 1.0 + i * 0.25, rng.randf_range(-0.15, 0.15)))
	_static_box(Vector3(0.6, 0.6, 0.6), p + Vector3(0, 0.3, 0))

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

var crowd_spots: Array = []       # [position, yaw] for onlookers behind the police tape
var press_spots: Array = []       # [position, yaw, role] reporter / camera operator
var hq_pos := Vector3.INF         # police HQ ("غرفة العمليات") next to the start point
var hq_scale := 1.0

func build_cordon() -> void:
	var cp := cordon_point
	var zc := cp.z - 4.9            # centre line of the street in front of the target
	# --- the street is sealed on both sides: patrol car + tape + cones, crowd and press behind
	var blk_x0: float = bank_block.x * P + R
	for sd in [-1.0, 1.0]:
		# just inside each end of the street, clear of the junctions so cross traffic keeps flowing
		var bx: float = (blk_x0 + 7.2) if sd < 0 else (blk_x0 + B - 7.2)
		var car := CarMesh.build("police")
		# west side leaves the south lane open so the SWAT truck can roll in
		car.position = Vector3(bx, 0, zc - 3.0 if sd < 0 else zc)
		car.rotation.y = 0.25 * sd
		car.set_meta("no_merge", true)
		for gi in car.find_children("*", "GeometryInstance3D", true, false):
			gi.visibility_range_end = 120.0
		add_child(car)
		flashers.append(car.get_meta("flashers"))
		_static_box(Vector3(2.0, 1.6, 5.0), car.position + Vector3(0, 0.8, 0), car.rotation.y)
		var tx: float = bx + sd * 3.2
		var z_from: float = zc - 6.6
		var z_to: float = zc + (0.6 if sd < 0 else 6.6)
		_mi(_box_mesh(Vector3(0.01, 0.08, z_to - z_from)), mat("tape"), Vector3(tx, 1.0, (z_from + z_to) * 0.5), false)
		for pz in [z_from, z_to]:
			var cm := CylinderMesh.new(); cm.top_radius = 0.04; cm.bottom_radius = 0.05; cm.height = 1.1; cm.radial_segments = 8; cm.rings = 1
			_mi(cm, mat("tape"), Vector3(tx, 0.55, pz))
		if sd < 0:
			for cz in [zc + 0.7, zc + 4.4, zc + 5.2, zc + 6.0]:
				var cone := CylinderMesh.new(); cone.top_radius = 0.03; cone.bottom_radius = 0.16; cone.height = 0.5; cone.radial_segments = 8; cone.rings = 1
				_mi(cone, mat("cone"), Vector3(tx, 0.25, cz))
		# onlookers stand behind the tape, looking toward the target
		for k in 9:
			var px := 0.0
			var pz := 0.0
			# nobody stands inside somebody else
			for attempt in 24:
				px = tx + sd * rng.randf_range(0.8, 3.0)
				pz = zc + rng.randf_range(-6.2, 0.0 if sd < 0 else 6.2)
				var free := true
				for other in crowd_spots:
					if (other[0] as Vector3).distance_to(Vector3(px, 0.0, pz)) < 1.0:
						free = false
						break
				if free:
					break
			# [where, facing (yaw 0 looks down -Z), how far along the tape they may wander, tape x, side]
			crowd_spots.append([Vector3(px, 0.0, pz), atan2(sd, rng.randf_range(-0.4, 0.4)), Vector2(zc - 6.2, zc + (0.0 if sd < 0 else 6.2)), tx, sd])
	# --- press: reporter + camera on a tripod just behind the east tape, news car parked behind them
	# press pen inside the cordon on the south pavement, by the east barrier
	var ex: float = blk_x0 + B - 7.2 - 9.5
	press_spots = [[Vector3(ex + 1.6, 0.16, zc + 5.8), -PI * 0.5, "reporter"], [Vector3(ex + 4.4, 0.16, zc + 6.0), PI * 0.5, "camera"]]
	var tri := Vector3(ex + 3.9, 0.16, zc + 6.0)
	for a3 in 3:
		var leg := _mi(_box_mesh(Vector3(0.03, 1.35, 0.03)), mat("black"), tri + Vector3(cos(a3 * TAU / 3.0) * 0.22, 0.66, sin(a3 * TAU / 3.0) * 0.22))
		leg.rotation = Vector3(sin(a3 * TAU / 3.0) * 0.3, 0, -cos(a3 * TAU / 3.0) * 0.3)
	_mi(_box_mesh(Vector3(0.42, 0.24, 0.2)), mat("black"), tri + Vector3(-0.08, 1.45, 0))
	var lens := CylinderMesh.new(); lens.top_radius = 0.06; lens.bottom_radius = 0.07; lens.height = 0.16; lens.radial_segments = 8; lens.rings = 1
	var lm := _mi(lens, mat("black"), tri + Vector3(-0.36, 1.45, 0))
	lm.rotation.z = PI / 2
	var van := MeshInstance3D.new()
	dress_car(van, "sedan", Color(0.9, 0.9, 0.92))
	van.position = Vector3(ex - 4.0, 0, zc + 3.7)
	van.rotation.y = PI / 2
	van.set_meta("no_merge", true)
	add_child(van)
	_static_box(Vector3(1.9, 1.4, 4.6), van.position + Vector3(0, 0.7, 0), PI / 2)
	var dishm := SphereMesh.new(); dishm.radius = 0.5; dishm.height = 0.25; dishm.is_hemisphere = true; dishm.radial_segments = 12; dishm.rings = 3
	var dish := _mi(dishm, mat("dish"), van.position + Vector3(0, 1.75, 0))
	dish.rotation = Vector3(-0.9, 0.6, 0)
	_label("قناة الإخبارية · بث مباشر", van.position + Vector3(0, 1.0, -0.98), PI, 34, Color(0.85, 0.1, 0.1), 0.006)
	# --- command post beside the colonel: unmarked black car + folding table with the building plans
	var cmd := MeshInstance3D.new()
	dress_car(cmd, "sedan", Color(0.05, 0.05, 0.06))
	cmd.position = cp + Vector3(9.5, 0, 2.6)
	cmd.rotation.y = -PI / 2
	cmd.set_meta("no_merge", true)
	add_child(cmd)
	_static_box(Vector3(1.9, 1.4, 4.6), cmd.position + Vector3(0, 0.7, 0), PI / 2)
	_mi(_box_mesh(Vector3(1.6, 0.05, 0.8)), mat("wood"), cp + Vector3(5.2, 0.85, 3.3))
	for lx in [-0.7, 0.7]:
		_mi(_box_mesh(Vector3(0.05, 0.85, 0.7)), mat("black"), cp + Vector3(5.2 + lx, 0.42, 3.3))
	_mi(_box_mesh(Vector3(0.9, 0.01, 0.6)), mat("white"), cp + Vector3(5.2, 0.885, 3.3), false)
	_static_box(Vector3(1.6, 0.9, 0.8), cp + Vector3(5.2, 0.45, 3.3))
	_mi(_box_mesh(Vector3(26, 0.08, 0.01)), mat("tape"), cp + Vector3(0, 1.0, 5.6), false)
	_label("شرطة · ممنوع الاقتراب   شرطة · ممنوع الاقتراب", cp + Vector3(0, 1.0, 5.62), 0.0, 32, Color(0.05, 0.05, 0.05), 0.006).outline_size = 0

## Police HQ next to the start: the office building model, with a sign. The intro plays inside it.
func build_hq() -> void:
	var b := CustomModels.prop("building_loft")
	if not b:
		return
	var sz: Vector3 = b.get_meta("size")
	hq_scale = 1.0
	hq_pos = Vector3(road_center(1) + 3.2, 0.0, size_total + 3.5 + sz.z * 0.5)
	# the unit's truck waits right outside the door, nose toward the street it will take
	spawn_point = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hq_pos.x + 8.5, 0.8, size_total - 1.2))
	b.position = hq_pos
	b.set_meta("no_merge", true)
	add_child(b)
	_static_box(Vector3(sz.x, sz.y, sz.z), hq_pos + Vector3(0, sz.y * 0.5, 0))
	_mi(_box_mesh(Vector3(sz.x + 8.0, 0.12, 6.0)), mat("sidewalk"), hq_pos + Vector3(0, 0.06, -sz.z * 0.5 - 1.6), false)
	# monument sign on the forecourt, facing the street
	var sp := hq_pos + Vector3(-9.5, 1.1, -sz.z * 0.5 - 2.6)
	var board := _mi(_box_mesh(Vector3(7.0, 1.6, 0.3)), mat("bankboard"), sp, false)
	board.material_override = _hq_mat()
	board.set_meta("no_merge", true)
	_mi(_box_mesh(Vector3(7.4, 0.3, 0.6)), mat("granite"), sp + Vector3(0, -0.95, 0), false)
	_label("مديرية الأمن العام\nوحدة الصقر", sp + Vector3(0, 0, -0.17), PI, 110, Color(0.96, 0.9, 0.72), 0.005)
	_static_box(Vector3(7.0, 1.8, 0.4), sp + Vector3(0, -0.2, 0))

func _hq_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.12, 0.08)
	return m

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
				# below the top quality level only big things (walls, roofs) cast shadows: halves the shadow pass
				if Settings.quality < 2 and ch.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					var asz: Vector3 = ch.mesh.get_aabb().size * cxf.basis.get_scale()
					if maxf(asz.x, maxf(asz.y, asz.z)) < 6.0:
						ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				for si in ch.mesh.get_surface_count():
					var m: Material = ch.material_override if ch.material_override else ch.mesh.surface_get_material(si)
					if _is_plain(m):
						# flat-coloured props all share one vertex-colour material: one draw call per chunk
						# instead of one per colour (poles, tanks, rails, signs, bins…)
						var vkey := "%d_%d_%d_%d_%d" % [ck.x, ck.y, _vc_mat().get_instance_id(), 99, ch.cast_shadow]
						if not groups.has(vkey):
							var vst := SurfaceTool.new(); vst.begin(Mesh.PRIMITIVE_TRIANGLES)
							groups[vkey] = vst
							mats[vkey] = [_vc_mat(), ch.cast_shadow]
						groups[vkey].append_from(_coloured(ch.mesh, si, (m as StandardMaterial3D).albedo_color), 0, cxf)
						continue
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
				if Settings.quality < 2:
					ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				for i in mm.instance_count:
					var ixf: Transform3D = cxf * mm.get_instance_transform(i)
					var c := ixf.origin
					var ck := Vector2i(floori(c.x / CHUNK), floori(c.z / CHUNK))
					for si in mm.mesh.get_surface_count():
						var m: Material = ch.material_override if ch.material_override else mm.mesh.surface_get_material(si)
						var src: Mesh = mm.mesh
						var ssi: int = si
						var fmt := 99
						if _is_plain(m):
							var ckey := "%d_%d_%d" % [mm.mesh.get_instance_id(), si, m.get_instance_id()]
							if not _col_cache.has(ckey):
								_col_cache[ckey] = _coloured(mm.mesh, si, (m as StandardMaterial3D).albedo_color)
							src = _col_cache[ckey]
							ssi = 0
							m = _vc_mat()
						else:
							fmt = _fmt(mm.mesh, si)
						var key := "%d_%d_%d_%d_%d" % [ck.x, ck.y, m.get_instance_id() if m else 0, fmt, ch.cast_shadow]
						if not groups.has(key):
							var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
							groups[key] = st
							mats[key] = [m, ch.cast_shadow]
						groups[key].append_from(src, ssi, ixf)
				victims.append(ch)
			elif ch is Label3D:
				ch.visibility_range_end = minf(ch.visibility_range_end if ch.visibility_range_end > 0.0 else 140.0, 140.0)
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
			push_warning("merge_static: chunk %s hit the 250-surface limit, geometry dropped" % ck)
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
var _vc: StandardMaterial3D
var _plain_cache := {}
var _col_cache := {}

func _vc_mat() -> StandardMaterial3D:
	if not _vc:
		_vc = StandardMaterial3D.new()
		_vc.vertex_color_use_as_albedo = true
		_vc.vertex_color_is_srgb = true
		_vc.roughness = 0.75
	return _vc

## A plain material = just a colour: no textures, no glow, not see-through, default culling.
func _is_plain(m: Material) -> bool:
	if not (m is StandardMaterial3D):
		return false
	var id := m.get_instance_id()
	if not _plain_cache.has(id):
		var sm := m as StandardMaterial3D
		_plain_cache[id] = sm.albedo_texture == null and not sm.normal_enabled and not sm.emission_enabled \
			and sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and sm.cull_mode == BaseMaterial3D.CULL_BACK \
			and not sm.uv1_triplanar and not sm.vertex_color_use_as_albedo and sm.metallic < 0.7
	return _plain_cache[id]

## Copy of one surface with every vertex painted `col` (positions + normals + colours only).
func _coloured(mesh: Mesh, si: int, col: Color) -> ArrayMesh:
	var a := mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	cols.fill(col)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = a[Mesh.ARRAY_NORMAL]
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = a[Mesh.ARRAY_INDEX]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return am
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

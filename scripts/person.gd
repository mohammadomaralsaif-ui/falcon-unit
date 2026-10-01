extends Node3D
## A realistic clothed human (Ready Player Me body) with retargeted walk/run animations,
## outfit + gear for each role, and IK posing (rifle, surrender, kneeling).
## Faces -Z like every other actor in the game.

const Retarget = preload("res://scripts/retarget.gd")
const PoseMod = preload("res://scripts/pose_mod.gd")
const Humanoid = preload("res://scripts/humanoid.gd")
const CustomModels = preload("res://scripts/custom_models.gd")
const CarMesh = preload("res://scripts/car_mesh.gd")

var role := "swat"
var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var pose: SkeletonModifier3D
var gun: Node3D
var muzzle: Marker3D
var cur := ""
var aim_pitch := 0.0
var gun_rest := Vector3(0.17, 1.3, -0.3)

static var _civ: PackedScene
static var _woman: PackedScene
var model_path := "res://assets/models/civilian.glb"
var custom := false
static var _mats := {}

func _init(_role := "swat", seed_val := 0) -> void:
	role = _role
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else randi()
	var female := false
	if female:
		if not _woman:
			_woman = load("res://assets/models/michelle.glb")
		model = _woman.instantiate()
		model_path = "res://assets/models/michelle.glb"
		var old_ap := model.find_child("AnimationPlayer", true, false)
		if old_ap:
			old_ap.get_parent().remove_child(old_ap)
			old_ap.free()
	else:
		# a real Mixamo character dropped into assets/characters/ wins over the built-in body
		var real := CustomModels.character(role, rng.randi())
		if real != "" and CustomModels.scene(real):
			model = CustomModels.scene(real).instantiate()
			model_path = real
			custom = true
			for ap in model.find_children("*", "AnimationPlayer", true, false):
				ap.get_parent().remove_child(ap)
				ap.free()
		else:
			if not _civ:
				_civ = load("res://assets/models/civilian.glb")
			model = _civ.instantiate()
	model.rotation.y = PI
	add_child(model)
	skel = model.find_child("Skeleton3D", true, false)
	if custom:
		# normalise height: head bone at ~1.62 m whatever units the file used
		var hb := -1
		for k in skel.get_bone_count():
			var bn := skel.get_bone_name(k)
			if bn == "Head" or (bn.begins_with("mixamorig") and bn.ends_with("_Head")):
				hb = k
				break
		if hb >= 0:
			var hy: float = (Retarget._chain(model, skel) * skel.get_bone_global_rest(hb).origin).y
			if hy > 0.01:
				model.scale = Vector3.ONE * (1.62 / hy)
	anim = AnimationPlayer.new()
	anim.root_node = NodePath("..")
	model.add_child(anim)
	anim.add_animation_library("", Retarget.library(model_path))
	if not female and not custom:
		_dress(rng)
	pose = PoseMod.new()
	pose.body = self
	skel.add_child(pose)
	if role in ["swat", "robber"]:
		gun = Humanoid.rifle("m4" if role == "swat" else "ak")
		gun.position = gun_rest
		add_child(gun)
		muzzle = gun.get_node("Muzzle")
		var g1 := Node3D.new(); g1.position = Vector3(0.0, -0.03, 0.06); gun.add_child(g1)
		var g2 := Node3D.new(); g2.position = Vector3(-0.02, -0.02, -0.34); gun.add_child(g2)
		pose.grip = g1
		pose.guard = g2
		pose.mode = "rifle"
	else:
		pose.mode = "none"
	# only the skinned body casts shadows; gear, labels and the rifle don't (big draw-call saving)
	for c in _all(model):
		if c is GeometryInstance3D:
			var skinned: bool = c is MeshInstance3D and c.get_parent() == skel
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if skinned else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ready() -> void:
	play("Idle")
	anim.seek(randf() * 1.5)

func play(n: String, speed := 1.0) -> void:
	if n != cur:
		anim.play(n, 0.25)
		cur = n
	anim.speed_scale = speed

func set_mode(m: String) -> void:
	pose.mode = m
	if gun:
		gun.visible = m == "rifle"
	if m.begins_with("kneel") or m == "hands_up":
		play("Idle")

func set_aim(p: float) -> void:
	aim_pitch = p
	if gun:
		gun.rotation.x = p
		gun.position = gun_rest + Vector3(0, sin(p) * 0.12, 0)

func _all(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out

func _mesh(n: String) -> MeshInstance3D:
	return model.find_child(n, true, false) as MeshInstance3D

static var _fabric: Texture2D
static var _denim: Texture2D
static var _rbox_cache := {}

static func _noise_tex(kind: String) -> Texture2D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new(); r.seed = 5 if kind == "fabric" else 9
	for y in 128:
		for x in 128:
			var v := 0.82 + r.randf() * 0.18
			if kind == "denim":
				v *= 0.88 + 0.12 * float((x + y) % 4 < 2)
			else:
				v *= 0.94 + 0.06 * float((x % 3 == 0) or (y % 3 == 0))
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)

## Rounded-edge box (bevelled), used for vest plates and pouches.
static func rbox(size: Vector3, bev := 0.02) -> Mesh:
	var key := str(size) + str(bev)
	if not _rbox_cache.has(key):
		var hz := size.z * 0.5; var hy := size.y * 0.5
		var poly := PackedVector2Array([Vector2(-hz, -hy), Vector2(hz, -hy), Vector2(hz, hy), Vector2(-hz, hy)])
		_rbox_cache[key] = CarMesh.extrude_round(poly, size.x, bev, 0.0, 0.0, 1.0, 0.0, 10.0)
	return _rbox_cache[key]

func _tint(n: String, col: Color, rough := -1.0, fabric := "") -> void:
	var mi := _mesh(n)
	if not mi:
		return
	var base: Material = mi.mesh.surface_get_material(0)
	var key := n + col.to_html() + str(rough) + fabric
	if not _mats.has(key):
		var m: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
		m.albedo_color = col
		if fabric == "fabric":
			if not _fabric: _fabric = _noise_tex("fabric")
			m.albedo_texture = _fabric
		elif fabric == "denim":
			if not _denim: _denim = _noise_tex("denim")
			m.albedo_texture = _denim
		if rough >= 0.0:
			m.roughness = rough
		_mats[key] = m
	mi.set_surface_override_material(0, _mats[key])

func _mat(col: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var key := col.to_html() + str(rough) + str(metal)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col; m.roughness = rough; m.metallic = metal
		_mats[key] = m
	return _mats[key]

func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	return ba

func _part(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.position = pos; mi.rotation = rot; mi.scale = scl
	mi.material_override = m
	parent.add_child(mi)
	return mi

func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = s
	return b

func _dress(rng: RandomNumberGenerator) -> void:
	var font: Font = load("res://assets/fonts/Tajawal-Bold.ttf")
	match role:
		"swat", "officer":
			var navy := Color(0.12, 0.14, 0.2) if role == "swat" else Color(0.22, 0.3, 0.45)
			_tint("Wolf3D_Outfit_Top", navy, 0.9, "fabric" if role == "swat" else "")
			_tint("Wolf3D_Outfit_Bottom", Color(0.1, 0.11, 0.15) if role == "swat" else Color(0.12, 0.14, 0.2), 0.9, "fabric")
			_tint("Wolf3D_Outfit_Footwear", Color(0.06, 0.06, 0.06), 0.6)
			var head := _attach("Head")
			if role == "swat":
				# ballistic helmet
				var hcol := _mat(Color(0.1, 0.11, 0.12), 0.6)
				var hm := SphereMesh.new(); hm.radius = 0.135; hm.height = 0.17; hm.is_hemisphere = true; hm.radial_segments = 24; hm.rings = 8
				_part(head, hm, Vector3(0, 0.095, -0.01), hcol, Vector3(-0.08, 0, 0), Vector3(1.0, 1.0, 1.1))
				# side rails + NVG shroud + strap
				for sx in [-1.0, 1.0]:
					_part(head, rbox(Vector3(0.015, 0.025, 0.16), 0.006), Vector3(sx * 0.133, 0.12, -0.01), _mat(Color(0.06, 0.06, 0.06), 0.5))
					var cm := CylinderMesh.new(); cm.top_radius = 0.042; cm.bottom_radius = 0.045; cm.height = 0.035; cm.radial_segments = 16
					_part(head, cm, Vector3(sx * 0.11, 0.045, 0.0), _mat(Color(0.14, 0.14, 0.12), 0.7), Vector3(0, 0, PI / 2))
					_part(head, rbox(Vector3(0.01, 0.1, 0.02), 0.004), Vector3(sx * 0.1, 0.0, 0.035), _mat(Color(0.08, 0.08, 0.08), 0.9))
				_part(head, rbox(Vector3(0.05, 0.035, 0.03), 0.008), Vector3(0, 0.2, 0.135), _mat(Color(0.05, 0.05, 0.05), 0.4, 0.4))
				# ballistic glasses
				_part(head, rbox(Vector3(0.16, 0.04, 0.02), 0.008), Vector3(0, 0.075, 0.118), _mat(Color(0.02, 0.025, 0.03), 0.05, 0.7))
				_tint("Wolf3D_Beard", Color(0.12, 0.09, 0.07))
			else:
				# police peaked cap
				var cap := CylinderMesh.new(); cap.top_radius = 0.125; cap.bottom_radius = 0.11; cap.height = 0.08
				_part(head, cap, Vector3(0, 0.15, 0.0), _mat(Color(0.15, 0.2, 0.35), 0.7))
				_part(head, _box(Vector3(0.18, 0.015, 0.09)), Vector3(0, 0.115, 0.12), _mat(Color(0.03, 0.03, 0.03), 0.3))
				_part(head, _box(Vector3(0.05, 0.04, 0.01)), Vector3(0, 0.16, 0.115), _mat(Color(0.9, 0.75, 0.3), 0.3, 0.8))
			# plate carrier vest
			var chest := _attach("Spine2")
			var vest_col := Color(0.11, 0.12, 0.13) if role == "swat" else Color(0.18, 0.2, 0.22)
			var vm := _mat(vest_col, 0.9)
			_part(chest, rbox(Vector3(0.32, 0.31, 0.08), 0.025), Vector3(0, -0.09, 0.115), vm)    # front plate
			_part(chest, rbox(Vector3(0.32, 0.33, 0.07), 0.025), Vector3(0, -0.08, -0.095), vm)   # back plate
			for sx in [-1.0, 1.0]:
				_part(chest, rbox(Vector3(0.05, 0.2, 0.23), 0.02), Vector3(sx * 0.165, -0.14, 0.012), vm)  # cummerbund
				_part(chest, rbox(Vector3(0.065, 0.035, 0.22), 0.012), Vector3(sx * 0.11, 0.075, 0.01), vm) # shoulder straps
			if role == "swat":
				var pm := _mat(Color(0.13, 0.14, 0.14), 0.95)
				for i in 3:
					_part(chest, rbox(Vector3(0.075, 0.11, 0.045), 0.012), Vector3(-0.085 + i * 0.085, -0.17, 0.165), pm)
				_part(chest, rbox(Vector3(0.05, 0.08, 0.035), 0.01), Vector3(0.1, 0.0, 0.16), pm)   # radio pouch
				var ant := CylinderMesh.new(); ant.top_radius = 0.004; ant.bottom_radius = 0.006; ant.height = 0.22
				_part(chest, ant, Vector3(0.12, 0.13, -0.12), _mat(Color(0.05, 0.05, 0.05), 0.5))
				# pistol holster on the right thigh
				var thigh := _attach("RightUpLeg")
				_part(thigh, rbox(Vector3(0.05, 0.17, 0.11), 0.015), Vector3(-0.09, 0.2, 0.0), _mat(Color(0.07, 0.07, 0.07), 0.8))
			var back := Label3D.new()
			back.text = "الأمن العام\nPOLICE"
			back.font = font; back.font_size = 48; back.pixel_size = 0.0019
			back.modulate = Color(0.95, 0.95, 0.9) if role == "swat" else Color(1, 0.85, 0.3)
			back.outline_size = 0
			back.position = Vector3(0, -0.05, -0.13)
			back.double_sided = false
			back.rotation.y = PI
			chest.add_child(back)
			var front := Label3D.new()
			front.text = "شرطة"
			front.font = font; front.font_size = 40; front.pixel_size = 0.0022
			front.outline_size = 0
			front.position = Vector3(0, -0.02, 0.135)
			front.double_sided = false
			chest.add_child(front)
			# belt + knee pads
			var hips := _attach("Hips")
			_part(hips, _box(Vector3(0.31, 0.05, 0.21)), Vector3(0, 0.04, 0.01), _mat(Color(0.07, 0.07, 0.07), 0.8))
		"robber":
			# balaclava, dark tracksuits / jackets, jeans
			_tint("Wolf3D_Head", Color(0.04, 0.04, 0.045), 0.95)
			var beard := _mesh("Wolf3D_Beard")
			if beard: beard.visible = false
			var teeth := _mesh("Wolf3D_Teeth")
			if teeth: teeth.visible = false
			var tops := [Color(0.18, 0.2, 0.14), Color(0.25, 0.25, 0.27), Color(0.08, 0.08, 0.09), Color(0.3, 0.2, 0.12), Color(0.15, 0.17, 0.22)]
			var bottoms := [Color(0.18, 0.24, 0.38), Color(0.08, 0.08, 0.1), Color(0.25, 0.25, 0.22)]
			_tint("Wolf3D_Outfit_Top", tops[rng.randi() % tops.size()], 0.95, "fabric")
			_tint("Wolf3D_Outfit_Bottom", bottoms[rng.randi() % bottoms.size()], 0.9, "denim")
			_tint("Wolf3D_Outfit_Footwear", Color(0.15, 0.13, 0.12))
			if rng.randf() < 0.5:
				var chest := _attach("Spine2")
				_part(chest, _box(Vector3(0.33, 0.28, 0.23)), Vector3(0, -0.09, 0.015), _mat(Color(0.2, 0.22, 0.16), 0.9))
		"hostage", "civilian":
			var tops := [Color(0.95, 0.95, 0.95), Color(0.55, 0.68, 0.85), Color(0.75, 0.68, 0.55), Color(0.6, 0.15, 0.15), Color(0.3, 0.42, 0.3)]
			var bottoms := [Color(0.15, 0.15, 0.17), Color(0.3, 0.3, 0.33), Color(0.2, 0.25, 0.4)]
			var casual := role == "civilian" and rng.randf() < 0.6
			_tint("Wolf3D_Outfit_Top", tops[rng.randi() % tops.size()], 0.85, "fabric" if casual else "")
			_tint("Wolf3D_Outfit_Bottom", bottoms[rng.randi() % bottoms.size()], 0.85, "denim" if casual else "")
			if role == "hostage":
				# bank staff tie
				var chest := _attach("Spine2")
				_part(chest, _box(Vector3(0.04, 0.2, 0.01)), Vector3(0, 0.05, 0.12), _mat([Color(0.5, 0.08, 0.1), Color(0.1, 0.15, 0.35)][rng.randi() % 2], 0.6))

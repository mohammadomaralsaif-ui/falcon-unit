extends Node3D
## Mission orchestrator: world setup, story beats, phases, callbacks from actors/player.

const City = preload("res://scripts/city.gd")
const Traffic = preload("res://scripts/traffic.gd")
const Vehicle = preload("res://scripts/vehicle.gd")
const Player = preload("res://scripts/player.gd")
const Actor = preload("res://scripts/actor.gd")
const Hostage = preload("res://scripts/hostage.gd")
const Hud = preload("res://scripts/hud.gd")
const Fx = preload("res://scripts/fx.gd")
const Person = preload("res://scripts/person.gd")
const EscapeVan = preload("res://scripts/escape_van.gd")
const Pedestrians = preload("res://scripts/pedestrians.gd")
const Missions = preload("res://scripts/missions.gd")
const CustomModels = preload("res://scripts/custom_models.gd")
const Voice = preload("res://scripts/voice.gd")
const Settings = preload("res://scripts/settings.gd")

var city: Node3D
var traffic: Node3D
var vehicle: VehicleBody3D
var player: CharacterBody3D
var hud: CanvasLayer
var cine_cam: Camera3D
var enemies: Array = []
var team: Array = []
var hostages: Array = []
var phase := "brief"
var in_vehicle := true
var team_size := 3
var difficulty := 1
var diff_react := 0.6
var mission_time := 0.0
var door_open := false
var team_spawned := false
var yell_cd := 0.0
var slowmo_t := 0.0
var shake := 0.0
var cine_t := 0.0
var arrests := 0
var violations := 0
var team_lost := 0
var hostages_lost := 0
var hostages_saved := 0
var ended := false
var trail: Array = []
var deadline := 300.0
var colonel: Node3D
var van: AnimatableBody3D
var leader: Node3D
var leader_cuffed := false
var chase_t := 0.0
var ram_cd := 0.0
var intro_shots: Array = []
var intro_i := -1
var intro_t := 0.0
var talked := false
var peds: Node3D
var input_guard := 0.0
var civilians_hit := 0
var nav_region: NavigationRegion3D
var nav_ready := false
var ambience: AudioStreamPlayer
var chase_pending := false

const COLONEL := "العقيد سامر الخطيب"
const NEGOTIATOR := "المفاوِضة الرائد ليلى"
var LEADER := "أبو جاسر"
var M: Dictionary = {}
var evidence: Array = []          # [node, collected, destroyed]
var evidence_got := 0
var evidence_lost := 0
var bomb: Node3D
var bomb_t := 0.0
var bomb_defused := false
var defuse_hold := 0.0
var flashbangs := 3
var smokes := 0
var smoke_clouds: Array = []     # [centre, radius, seconds left]: gunmen can't see through these
var night := false
var executioners: Array = []
var enemy_sight := 48.0
var team_order := "follow"        # follow | hold   ([T] / "أوامر")
var cutscene_t := 0.0             # cinematic dialogue with the colonel (player frozen)
var cut_shots: Array = []
var cut_i := 0
var cut_k := 0.0
var repair_hold := 0.0
var sniper_mission := false
var crowd: Array = []             # onlookers + press behind the tape (Person nodes)
var crowd_t := 0.0
var hq_set: Array = []            # nodes of the ops-room intro (freed when the mission starts)
var drive_started := false
var gestures := {}                # dialogue line -> colonel gesture
var colonel_talk_t := 0.0
var shout_cd := 0.0
var talk_cd := 0.0
var duck_t := 0.0
var breacher: Node = null         # teammate sent to plant the charge
var team_tick := 0.0

const ENEMY_ALERT := ["الشرطة! الشرطة دخلت!", "ارجع لورا! ما حدا يقرّب!", "شباب، دخلوا علينا!", "خلّيك مكانك وإلا بطخّ!"]
const ENEMY_SURRENDER := ["لا تطخ! لا تطخ! مستسلم!", "خلص، خلص! رميت السلاح!", "إيديّ فوق… لا تطخ!"]
const HOSTAGE_THANKS := ["الله يخليك! طلّعني من هون!", "شكراً… الحمد لله إنكم جيتوا!", "كنت متأكد إنكم رح تيجوا."]
const CROWD_LINES := ["شو صاير جوّا يا حضرة الضابط؟", "الله يحميكم يا شباب.", "أخوي موظف جوّا… طمّنوني عليه!", "من ساعتين وإحنا واقفين هون.", "ديروا بالكم على حالكم."]
const PED_LINES := ["يعطيكم العافية يا شباب.", "في إشي صاير؟ ليش كل هالشرطة؟", "الله يقوّيكم.", "خير إن شاء الله؟"]
const PLAYER_REPLIES := ["كله تحت السيطرة. ارجعوا لورا لو سمحتوا.", "إن شاء الله خير. خلّيكم بعيد عن الطوق.", "الله يسلّمك."]
const REPORTER_LINES := ["حضرة الضابط! كلمة لقناة الإخبارية؟ متى الاقتحام؟", "قناة الإخبارية… في إصابات بين الرهائن؟"]
const TEAM_NAMES := ["الصقر ٢", "الصقر ٣", "الصقر ٤", "الصقر ٥"]
const TEAM_OFFSETS := [Vector3(-1.4, 0, 2.0), Vector3(1.4, 0, 2.2), Vector3(-1.6, 0, 4.2), Vector3(1.6, 0, 4.4)]

var loaded := false
var _pt := 0
var _load_layer: CanvasLayer
var _load_bar: ProgressBar
var _load_lbl: Label

func _stage(label: String, frac: float) -> void:
	if OS.has_environment("FALCON_PROFILE"):
		print("STAGE %-22s %5d ms" % [label, Time.get_ticks_msec() - _pt])
	_pt = Time.get_ticks_msec()
	if _load_bar:
		_load_bar.value = frac * 100.0
		_load_lbl.text = label
	# let the loading screen redraw between the heavy steps (two frames: one to draw, one to show)
	await get_tree().process_frame
	await get_tree().process_frame
	_pt = Time.get_ticks_msec()

func _loading_screen() -> void:
	_load_layer = CanvasLayer.new()
	_load_layer.layer = 50
	add_child(_load_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.078, 0.125)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_layer.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.custom_minimum_size = Vector2(520, 0)
	vb.add_theme_constant_override("separation", 14)
	_load_layer.add_child(vb)
	var f: Font = load("res://assets/fonts/Tajawal-Bold.ttf")
	var title := Label.new()
	title.text = "وحدة الصقر"
	title.add_theme_font_override("font", f); title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.96, 0.8, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = M.title + " · " + M.area
	sub.add_theme_font_override("font", f); sub.add_theme_font_size_override("font_size", 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	_load_bar = ProgressBar.new()
	_load_bar.custom_minimum_size = Vector2(520, 10)
	_load_bar.show_percentage = false
	vb.add_child(_load_bar)
	_load_lbl = Label.new()
	_load_lbl.add_theme_font_override("font", f); _load_lbl.add_theme_font_size_override("font_size", 18)
	_load_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_load_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_load_lbl)

func _ready() -> void:
	Controls.reset()
	Engine.time_scale = 1.0
	get_tree().paused = false
	M = Missions.get_m()
	team_size = Missions.team_size
	difficulty = Missions.difficulty
	if M.leader != "":
		LEADER = M.leader
	deadline = M.deadline
	bomb_t = M.bomb_time
	night = M.sky == "night"
	sniper_mission = M.get("type", "") == "sniper"
	if sniper_mission:
		enemy_sight = 80.0
	_loading_screen()
	_pt = Time.get_ticks_msec()
	_load_world()

## The world is built in steps with the loading screen refreshed in between, so the phone never
## looks frozen while the city is generated.
func _load_world() -> void:
	await _stage("تجهيز…", 0.02)
	_environment()
	if OS.has_environment("FALCON_PROFILE"): print("  env ", Time.get_ticks_msec() - _pt)
	city = Node3D.new()
	city.set_script(City)
	add_child(city)
	if OS.has_environment("FALCON_PROFILE"): print("  city node ", Time.get_ticks_msec() - _pt)
	city.build(7, M)
	if OS.has_environment("FALCON_PROFILE"): print("  city built ", Time.get_ticks_msec() - _pt)
	await _stage("بناء المدينة", 0.35)
	city.build_cordon()
	if night:
		city.mat("lamp").emission_energy_multiplier = 9.0
		for k in 4:
			var sl := OmniLight3D.new()
			sl.light_color = Color(1.0, 0.72, 0.4)
			sl.light_energy = 2.2
			sl.omni_range = 18.0
			sl.position = city.cordon_point + Vector3(-18.0 + k * 12.0, 5.6, -3.0 + (k % 2) * 9.0)
			add_child(sl)
	city.merge_static()
	await _stage("دمج المباني", 0.6)
	_setup_nav()
	await _stage("خريطة الحركة", 0.66)
	traffic = Node3D.new()
	traffic.set_script(Traffic)
	add_child(traffic)
	traffic.main = self
	traffic.setup(city, Settings.traffic_count())
	vehicle = VehicleBody3D.new()
	vehicle.set_script(Vehicle)
	vehicle.main = self
	add_child(vehicle)
	vehicle.global_transform = city.spawn_point
	await _stage("السيارات", 0.74)
	player = CharacterBody3D.new()
	player.set_script(Player)
	player.main = self
	add_child(player)
	player.global_position = city.spawn_point.origin + Vector3(3, 0, 0)
	player.set_active(false)
	player.shot_fired.connect(_on_player_shot)
	for hp in city.hostage_spawns:
		var h := StaticBody3D.new()
		h.set_script(Hostage)
		h.main = self
		add_child(h)
		h.global_position = hp
		h.rotation.y = randf() * TAU
		hostages.append(h)
	colonel = Person.new("officer", 77)
	add_child(colonel)
	colonel.global_position = city.cordon_point + Vector3(3.0, 0, 1.5)
	colonel.rotation.y = PI
	var tag := Label3D.new()
	tag.text = COLONEL
	tag.font = load("res://assets/fonts/Tajawal-Bold.ttf")
	tag.font_size = 30; tag.pixel_size = 0.0011; tag.fixed_size = true; tag.outline_size = 8
	tag.modulate = Color(1, 0.85, 0.4)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.15, 0)
	colonel.add_child(tag)
	await _stage("الشخصيات", 0.82)
	ambience = AudioStreamPlayer.new()
	ambience.stream = Sfx.ambience(night)
	ambience.volume_db = -17.0
	ambience.bus = "SFX"
	add_child(ambience)
	ambience.play()
	await _stage("الأصوات", 0.86)
	peds = Node3D.new()
	peds.set_script(Pedestrians)
	add_child(peds)
	peds.setup(self)
	_spawn_objectives()
	if not sniper_mission:
		_spawn_crowd()
	await _stage("الناس", 0.95)
	cine_cam = Camera3D.new()
	cine_cam.fov = 55; cine_cam.far = 1500
	add_child(cine_cam)
	cine_cam.current = true
	hud = CanvasLayer.new()
	hud.set_script(Hud)
	hud.main = self
	add_child(hud)
	hud.set_letterbox(true)
	await _stage("جاهز", 1.0)
	loaded = true
	_load_layer.queue_free()
	_load_bar = null
	world_ready.emit()
	if Missions.autostart:
		Missions.autostart = false
		_start_mission.call_deferred()
		if Missions.checkpoint:
			Missions.checkpoint = false
			_checkpoint_start.call_deferred()
	else:
		_menu_scene()
		hud.show_briefing(_start_mission)

signal world_ready

## "كمّل من نقطة الاقتحام": skip the opening, the drive and the briefing — the truck is already
## parked at the cordon and the team is out, ready to stack on the door.
func _checkpoint_start() -> void:
	await get_tree().process_frame
	_begin_drive()
	if sniper_mission:
		return
	hud.clear_radio()
	var cp: Vector3 = city.cordon_point
	var zs: float = city.road_center(city.bank_block.y + 1)
	var sx := 1.0 if cp.x > vehicle.global_position.x else -1.0
	vehicle.auto_drive = false
	vehicle.siren_on = false
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * sx), Vector3(cp.x - sx * 12.0, 0.7, zs + 1.5 * sx))
	await get_tree().create_timer(0.4).timeout
	_arrive()
	_exit_vehicle()
	_talk_colonel()
	hud.clear_radio()
	hud.set_letterbox(false)
	hud.show_banner("نقطة الاقتحام", "الفريق جاهز عند الطوق – كمّل", 2.5)

## Menu backdrop: the duty room with the team waiting. Far cheaper to draw than the whole city.
func _menu_scene() -> void:
	if city.hq_pos != Vector3.INF:
		_build_ops_room()

func _spawn_objectives() -> void:
	# evidence: laptops / ledgers / weapon cases on tables, glowing so they read in the dark
	var kinds := ["laptop", "ledger", "case"]
	for i in city.evidence_spawns.size():
		var n := Node3D.new()
		var k: String = kinds[i % kinds.size()]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		match k:
			"laptop": bm.size = Vector3(0.4, 0.04, 0.3)
			"ledger": bm.size = Vector3(0.25, 0.08, 0.35)
			_: bm.size = Vector3(0.9, 0.2, 0.35)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.1, 0.12) if k != "ledger" else Color(0.45, 0.1, 0.08)
		m.emission_enabled = true; m.emission = Color(1.0, 0.8, 0.3); m.emission_energy_multiplier = 0.35
		mi.material_override = m
		mi.position = Vector3(0, 0.82, 0)
		n.add_child(mi)
		var lbl := Label3D.new()
		lbl.text = "◆ دليل"
		lbl.font = load("res://assets/fonts/Tajawal-Bold.ttf")
		lbl.font_size = 26; lbl.pixel_size = 0.0011; lbl.fixed_size = true; lbl.outline_size = 8
		lbl.modulate = Color(1, 0.85, 0.3)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 1.5, 0)
		lbl.visibility_range_end = 14.0
		n.add_child(lbl)
		add_child(n)
		n.global_position = city.evidence_spawns[i]
		evidence.append([n, false, false])
	if city.bomb_pos != Vector3.INF:
		bomb = Node3D.new()
		var body := MeshInstance3D.new()
		var bb := BoxMesh.new(); bb.size = Vector3(0.7, 0.45, 0.5)
		body.mesh = bb
		var bmat := StandardMaterial3D.new(); bmat.albedo_color = Color(0.2, 0.22, 0.16)
		body.material_override = bmat
		body.position = Vector3(0, 0.23, 0)
		bomb.add_child(body)
		var led := MeshInstance3D.new()
		var lm := BoxMesh.new(); lm.size = Vector3(0.3, 0.1, 0.02)
		led.mesh = lm
		var lmat := StandardMaterial3D.new(); lmat.albedo_color = Color(0.2, 0, 0); lmat.emission_enabled = true; lmat.emission = Color(1, 0.05, 0.05); lmat.emission_energy_multiplier = 3.0
		led.material_override = lmat
		led.position = Vector3(0, 0.35, 0.26)
		bomb.add_child(led)
		var tl := Label3D.new()
		tl.name = "Timer"
		tl.font = load("res://assets/fonts/Tajawal-Bold.ttf")
		tl.font_size = 34; tl.pixel_size = 0.0012; tl.fixed_size = true; tl.outline_size = 8
		tl.modulate = Color(1, 0.25, 0.2)
		tl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tl.position = Vector3(0, 0.9, 0)
		tl.visibility_range_end = 22.0
		bomb.add_child(tl)
		add_child(bomb)
		bomb.global_position = city.bomb_pos

# ------------------------------------------------------------------ navigation (bank + street in front)
func _setup_nav() -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.2)
	NavigationServer3D.map_set_cell_height(map, 0.1)
	var x0: float = city.bank_block.x * city.P + city.R
	var z0: float = city.bank_block.y * city.P + city.R
	var area := AABB(Vector3(x0 - 10.0, -1.0, z0 - 10.0), Vector3(city.B + 34.0, 7.0, city.B + 42.0))
	# a plain floor collider so the baker has ground everywhere in the area
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new()
	bs.size = Vector3(area.size.x, 0.1, area.size.z); cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(area.get_center().x, -0.05, area.get_center().z)
	city.add_child(floor_body)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.2
	nm.cell_height = 0.1
	nm.agent_radius = 0.4
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.35
	nm.agent_max_slope = 40.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"navsrc"
	nm.filter_baking_aabb = area
	city.add_to_group("navsrc")
	nav_region = NavigationRegion3D.new()
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	nav_region.bake_finished.connect(func(): nav_ready = true)
	nav_region.bake_navigation_mesh(true)

## Next waypoint from `from` toward `to` along the navmesh (or `to` itself outside the baked area).
func nav_step(from: Vector3, to: Vector3) -> Vector3:
	if not nav_ready:
		return to
	var map := get_world_3d().navigation_map
	var cf := NavigationServer3D.map_get_closest_point(map, from)
	if Vector2(cf.x - from.x, cf.z - from.z).length() > 1.5:
		return to
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	for p in path:
		if Vector2(p.x - from.x, p.z - from.z).length() > 0.6:
			return p
	return to

func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	var sky_kind: String = M.get("sky", "golden")
	sm.sky_top_color = {"golden": Color(0.24, 0.42, 0.68), "night": Color(0.02, 0.03, 0.09), "morning": Color(0.3, 0.52, 0.85)}[sky_kind]
	sm.sky_horizon_color = {"golden": Color(0.93, 0.76, 0.56), "night": Color(0.12, 0.1, 0.16), "morning": Color(0.78, 0.84, 0.9)}[sky_kind]
	sm.ground_horizon_color = Color(0.75, 0.62, 0.5) if sky_kind != "night" else Color(0.08, 0.07, 0.08)
	sm.ground_bottom_color = Color(0.3, 0.26, 0.22) if sky_kind != "night" else Color(0.02, 0.02, 0.03)
	sm.sun_angle_max = 20.0
	sm.sun_curve = 0.12
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# a neutral fill colour instead of the raw sky: shaded streets stay readable (the sky alone turned
	# every shadow deep blue by day and pitch black at night)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = {"golden": Color(0.78, 0.72, 0.68), "night": Color(0.34, 0.4, 0.6), "morning": Color(0.74, 0.77, 0.84)}[sky_kind]
	env.ambient_light_energy = {"golden": 0.8, "night": 1.0, "morning": 0.85}[sky_kind]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.96
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = {"golden": Color(0.86, 0.74, 0.6), "night": Color(0.06, 0.06, 0.1), "morning": Color(0.82, 0.86, 0.9)}[sky_kind]
	env.fog_density = 0.0009          # light haze only: the far end of a street stays readable
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.03
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = {"golden": Vector3(-24, -128, 0), "night": Vector3(-55, 40, 0), "morning": Vector3(-42, 70, 0)}[sky_kind]
	sun.light_color = {"golden": Color(1.0, 0.84, 0.64), "night": Color(0.55, 0.65, 1.0), "morning": Color(1.0, 0.96, 0.88)}[sky_kind]
	sun.light_energy = {"golden": 1.35, "night": 0.5, "morning": 1.25}[sky_kind]
	sun.shadow_opacity = 0.82
	if sky_kind == "night":
		env.glow_intensity = 0.9
		env.glow_hdr_threshold = 0.9
		env.tonemap_exposure = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.04
	add_child(sun)
	_env = env
	_sun = sun
	Settings.apply(get_viewport(), env, sun)
	Voice.enabled = Settings.voice

var _env: Environment
var _sun: DirectionalLight3D

func apply_quality() -> void:
	Settings.apply(get_viewport(), _env, _sun)

# ------------------------------------------------------------------ mission flow
func _start_mission() -> void:
	diff_react = [0.95, 0.6, 0.38][difficulty]
	# loadout picked in the briefing
	if not sniper_mission:
		player.give_primary(Settings.primary)
		match Settings.gear:
			"smoke":
				flashbangs = 0
				smokes = 3
			"shield":
				flashbangs = 1
				player.give_shield()
	Missions.team_size = team_size
	Missions.difficulty = difficulty
	var n_enemies: int = M.enemies[difficulty]
	var spawns: Array = city.enemy_spawns.duplicate()
	spawns.shuffle()
	for i in mini(n_enemies, spawns.size()):
		var e := CharacterBody3D.new()
		e.set_script(Actor)
		e.setup(self, "enemy", spawns[i] + Vector3(randf_range(-0.6, 0.6), 0.1, randf_range(-0.6, 0.6)), randf() * TAU)
		e.accuracy = [0.28, 0.4, 0.55][difficulty] * float(M.accuracy)
		e.damage = [6.0, 9.0, 13.0][difficulty]
		if sniper_mission:
			e.hunter = false
		add_child(e)
		enemies.append(e)
	# one gunman per mission guards the hostages and will execute one if the assault drags on
	if M.executioner and hostages.size() > 0 and enemies.size() > 0:
		var h0 = hostages.pick_random()
		var best = enemies[0]
		for e in enemies:
			if e.global_position.distance_to(h0.global_position) < best.global_position.distance_to(h0.global_position):
				best = e
		best.executioner_of = h0
		best.hunter = false
		executioners.append(best)
	hud.close_briefing()
	_start_intro()

# ---- cinematic intro: three shots, like a news report cutting to the team
func _start_intro() -> void:
	phase = "intro"
	var c: Vector3 = city.door_pos
	var mid: float = city.size_total * 0.5
	var vp: Vector3 = vehicle.global_position
	intro_shots = [
		[Vector3(mid - 90, 95, city.size_total + 50), Vector3(mid + 20, 75, city.size_total + 10), c, 6.0],
		# from the far kerb, in the open street (the old spot was inside the building opposite)
		[c + Vector3(-14, 1.9, 13.2), c + Vector3(8, 2.6, 12.4), c + Vector3(0, 2.4, 0), 6.5],
		[vp + Vector3(-7, 1.4, -9), vp + Vector3(5, 2.2, -8), vp + Vector3(0, 1.0, 0), 6.0],
	]
	if sniper_mission and city.sniper_nests.size() > 0:
		var np: Vector3 = city.sniper_nests[0][0]
		intro_shots[2] = [np + Vector3(-4, 1.5, 4), np + Vector3(1, 1.2, 2.5), c + Vector3(0, 0, -12), 6.0]
	# opening shot: the operations room at HQ — the call comes in, the team gets up
	if city.hq_pos != Vector3.INF:
		_build_ops_room()
		var hp: Vector3 = city.hq_pos
		intro_shots.push_front([hp + Vector3(4.7, 2.2, -3.5), hp + Vector3(4.0, 2.0, -2.8), hp + Vector3(1.6, 1.5, -0.6), 8.0])
	else:
		intro_shots.push_front(intro_shots[0])
	intro_i = -1
	_next_shot()

var ops_team: Array = []      # the unit, seated on the sofa until the call comes
var ops_officer: Node3D

## The duty room inside HQ (the office model): the team sits on the sofa, the duty officer stands
## by the wall display. Used as the menu backdrop and for the opening scene.
func _build_ops_room() -> void:
	if not hq_set.is_empty():
		return
	var hp: Vector3 = city.hq_pos
	var fl := 0.73        # the office model's real floor (slab + rug) — measured, not the street level
	var screen := MeshInstance3D.new()
	var qm := BoxMesh.new(); qm.size = Vector3(0.08, 1.7, 3.0)
	screen.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.02, 0.05, 0.1)
	sm.emission_enabled = true; sm.emission = Color(0.12, 0.4, 0.75); sm.emission_energy_multiplier = 1.1
	screen.material_override = sm
	add_child(screen)
	screen.global_position = hp + Vector3(5.0, fl + 1.55, -0.6)
	hq_set.append(screen)
	var stand := MeshInstance3D.new()
	var stm := BoxMesh.new(); stm.size = Vector3(0.12, 0.7, 0.5)
	stand.mesh = stm
	var dmat := StandardMaterial3D.new(); dmat.albedo_color = Color(0.08, 0.08, 0.09)
	stand.material_override = dmat
	add_child(stand)
	stand.global_position = hp + Vector3(5.0, fl + 0.35, -0.6)
	hq_set.append(stand)
	var lbl := Label3D.new()
	lbl.text = "غرفة العمليات\n%s · %s" % [M.title, M.area]
	lbl.font = load("res://assets/fonts/Tajawal-Bold.ttf")
	lbl.font_size = 64; lbl.pixel_size = 0.0038; lbl.outline_size = 0
	lbl.modulate = Color(0.8, 0.94, 1.0)
	add_child(lbl)
	lbl.global_position = screen.global_position + Vector3(-0.06, 0, 0)
	lbl.rotation.y = -PI / 2
	hq_set.append(lbl)
	for lp in [Vector3(3.0, fl + 2.7, 1.2), Vector3(1.5, fl + 2.7, -2.2)]:
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.96, 0.9); fill.light_energy = 1.5; fill.omni_range = 9.0
		add_child(fill)
		fill.global_position = hp + lp
		hq_set.append(fill)
	ops_officer = Person.new("officer", 300)
	add_child(ops_officer)
	ops_officer.global_position = hp + Vector3(4.3, fl, 1.2)
	ops_officer.rotation.y = PI / 2
	hq_set.append(ops_officer)
	ops_team.clear()
	# sofa seats: [position, facing]
	var seats := [[Vector3(1.2, fl, -1.15), -PI / 2], [Vector3(1.2, fl, -0.45), -PI / 2], [Vector3(2.15, fl, -1.75), PI], [Vector3(1.2, fl, 0.14), -PI / 2], [Vector3(1.9, fl, 0.62), 0.0]]
	for i in mini(seats.size(), 1 + team_size):
		var p := Person.new("swat", 1 if i == 0 else 300 + i)
		add_child(p)
		p.global_position = hp + (seats[i][0] as Vector3)
		p.rotation.y = float(seats[i][1])
		p.set_mode("none")
		p.pose.sit_h = 0.45        # low lounge sofa
		p.set_sit(1.0)
		hq_set.append(p)
		ops_team.append(p)

## The call comes in: the officer takes it, the team gets up and grabs their rifles.
func _ops_scramble() -> void:
	if ops_officer and is_instance_valid(ops_officer):
		ops_officer.set_mode("radio")
	await get_tree().create_timer(2.6).timeout
	if phase != "intro" or intro_i != 0:
		return
	if ops_officer and is_instance_valid(ops_officer):
		ops_officer.pose.point_at = city.hq_pos + Vector3(5.0, 2.25, -0.6)
		ops_officer.set_mode("point")
	for i in ops_team.size():
		var p: Node3D = ops_team[i]
		if not is_instance_valid(p):
			continue
		var tw := create_tween()
		tw.tween_interval(i * 0.25)
		tw.tween_method(p.set_sit, 1.0, 0.0, 0.7)
		# a step forward, away from the seat (model forward is -Z)
		tw.parallel().tween_property(p, "global_position", p.global_position - p.global_transform.basis.z * 0.35, 0.7)
		tw.tween_callback(func():
			p.set_mode("rifle")
			p.set_aim(-0.6))        # rifles at low ready, not pointed at each other

func _clear_ops_room() -> void:
	for n in hq_set:
		if is_instance_valid(n):
			n.queue_free()
	hq_set.clear()

func _next_shot() -> void:
	intro_i += 1
	intro_t = 0.0
	hud.clear_radio()
	match intro_i:
		0:
			if city.hq_pos != Vector3.INF:
				Sfx.play("ring", 2.0)
				_ops_scramble()
				hud.show_banner("غرفة العمليات", "مديرية الأمن العام · وحدة الصقر", 4.0)
				hud.radio("غرفة العمليات", "نداء عاجل لوحدة الصقر: %s. تحرّكوا فوراً!" % M.news, 6.5)
			else:
				intro_t = 99.0
		1:
			hud.show_banner("عاجل", M.news, 5.5)
			hud.radio("نشرة الأخبار", M.news_line, 5.8)
		2:
			hud.radio(NEGOTIATOR if M.id != "raid" else "فريق المراقبة", M.negotiator_line, 6.3)
		3:
			hud.radio(COLONEL, M.commander_line, 5.8)
		_:
			_begin_drive()

func _begin_drive() -> void:
	if sniper_mission:
		_begin_sniper()
		return
	phase = "drive"
	intro_i = 99
	_clear_ops_room()
	hud.set_letterbox(false)
	hud.set_prompt("")
	_capture_mouse(true)
	hud.clear_radio()
	hud.show_banner(M.title, "%s · %s" % [M.area, M.clock], 3.5)
	if city.hq_pos == Vector3.INF:
		in_vehicle = true
		vehicle.set_driving(true)
		_on_drive_start()
		return
	# out of the HQ door on foot: run to the truck parked across the street
	in_vehicle = false
	vehicle.set_driving(false)
	var hp: Vector3 = city.hq_pos
	var out := Vector3(hp.x + 1.5, 0.2, city.size_total + 1.9)
	player.global_position = out
	var tv: Vector3 = vehicle.global_position - out
	player.yaw = atan2(-tv.x, -tv.z)
	player.rotation.y = player.yaw
	cine_cam.far = 1500.0
	player.pitch = -0.08
	player.set_active(true)
	_place_team(out, Basis(Vector3.UP, PI * 0.5))
	hud.radio("الصقر ١", "يلّا يا شباب عالسيارة! تحرّكوا!", 2.5)
	if team_size > 0:
		hud.radio("الصقر ٢", "العدّة جاهزة وعبوة الاقتحام معنا. وراك!", 3.0)
	hud.set_waypoint(vehicle.global_position + Vector3(0, 2.2, 0))
	hud.set_objectives(["◆ اركب سيارة الوحدة [F]"])

## Called when the truck first rolls: route, radio chatter, and the teammate driver if chosen.
func _on_drive_start() -> void:
	drive_started = true
	hud.clear_radio()
	hud.radio("غرفة العمليات", "إلى الصقر ١: الطريق إلى %s مفتوح، الدوريات سكّرت الشوارع الفرعية." % M.area, 4.5)
	hud.set_waypoint(city.cordon_point + Vector3(0, 1, 0))
	hud.set_objectives(["◆ قُد السيارة إلى الطوق الأمني – %s" % M.title, "◇ [H] صفارة · [E] زامور · [F] نزول/ركوب"])
	if team_size > 0:
		if Settings.driver == 1:
			_start_auto_drive()
		for l in M.get("banter", []):
			if TEAM_NAMES.find(l[0]) < team_size or l[0] == "الصقر ١":
				hud.radio(l[0], l[1], 4.0)
	else:
		hud.radio("غرفة العمليات", "الوحدة المساندة عالقة بالأزمة. إنت لحالك يا الصقر ١.", 4.0)

## "واحد من الفريق بسوق": the truck drives itself to the cordon while the team talks on the way.
func _start_auto_drive() -> void:
	var cp: Vector3 = city.cordon_point
	var sp: Vector3 = vehicle.global_position
	var zs: float = city.road_center(city.bank_block.y + 1)
	var east := cp.x > sp.x
	# siren on: the truck runs nearer the middle of the road, past the cars that pulled over
	var lane := 1.5 if east else -1.5
	var sx := 1.0 if east else -1.0
	var lane_x: float = city.road_center(1) + 1.5
	sp = Vector3(city.road_center(1) + 2.2, 0, sp.z)
	# swing a little wide before the corner, then settle into the lane
	vehicle.route = [Vector3(lane_x + 3.2, 0, city.size_total - 4.5), Vector3(lane_x, 0, city.size_total - 12.0), Vector3(sp.x - sx * 2.0, 0, zs + 6.0), Vector3(sp.x + sx * 6.0, 0, zs - 1.5), Vector3(sp.x + sx * 15.0, 0, zs + lane), Vector3(cp.x - sx * 12.0, 0, zs + lane)]
	vehicle.route_i = 0
	vehicle.auto_drive = true
	hud.set_objectives(["◆ الصقر ٢ بيسوق للموقع – %s" % M.title, "◇ اضغط [فرامل/قفز] أو حرّك العصا لتاخذ القيادة"])
	hud.radio("الصقر ٢", "خلّيها عليّ يا سيدي، أنا بسوق. ركّز إنت بالخطة.", 3.5)

func on_take_wheel() -> void:
	hud.radio("الصقر ١", "وقّف، أنا بكمّل السواقة.", 2.0)
	hud.set_objectives(["◆ قُد السيارة إلى الطوق الأمني – %s" % M.title, "◇ [H] صفارة · [E] زامور · [F] نزول/ركوب"])

# ---- sniper mission: start on the rooftop across from the target, scoped rifle in hand
func _begin_sniper() -> void:
	phase = "sniper"
	intro_i = 99
	hud.set_letterbox(false)
	hud.set_prompt("")
	in_vehicle = false
	vehicle.set_driving(false)
	var nest: Array = city.sniper_nests[0] if city.sniper_nests.size() > 0 else [city.door_pos + Vector3(0, 0, 20), 0.0]
	player.global_position = nest[0]
	player.yaw = float(nest[1])
	player.rotation.y = player.yaw
	player.pitch = -0.28
	player.set_active(true)
	player.give_sniper()
	_capture_mouse(true)
	hud.clear_radio()
	hud.show_banner(M.title, "%s · %s" % [M.area, M.clock], 3.5)
	hud.radio(COLONEL, "الصقر ١، إنت بالموقع. عندك %d أهداف بالساحة." % enemies.size(), 4.0)
	for line in M.brief:
		hud.radio(COLONEL, line, 5.0)
	hud.radio("الفريق الأرضي", "جاهزين عند البوابة. بنستنى إشارتك.", 3.0)
	hud.set_waypoint(city.bank_origin + Vector3(city.imap[0].length() * city.CELL * 0.5, 1.0, city.imap.size() * city.CELL * 0.5))
	sniper_text()

func sniper_text() -> void:
	var alive := 0
	for e in enemies:
		if not e.dead:
			alive += 1
	var lines := ["◆ حيّد المسلحين بالساحة: باقي %d" % alive, "◆ احمِ الرهائن (%d / %d أحياء)" % [hostages.size() - hostages_lost, hostages.size()], "◇ [زر يمين / تصويب] منظار · [C] انحناء · [X] مسدس", "✖ لا تصيب الرهائن"]
	hud.set_objectives(lines)

func _arrive() -> void:
	phase = "arrive"
	hud.clear_radio()
	hud.radio(COLONEL, "الصقر ١، شايفك. صفّ عندك وتعال لعندي، أنا عند طاولة القيادة.", 4.0)
	hud.set_waypoint(colonel.global_position + Vector3(0, 2.2, 0))
	hud.set_objectives(["◆ انزل من السيارة [F]", "◆ تحدّث مع %s [E]" % COLONEL])

func _talk_colonel() -> void:
	if talked:
		return
	talked = true
	phase = "staging"
	hud.clear_radio()
	gestures.clear()
	var vals := {"n": str(enemies.size()), "h": str(hostages.size()), "e": str(evidence.size()), "leader": LEADER}
	var names := {"C": COLONEL, "P": "الصقر ١", "N": NEGOTIATOR, "T": "الصقر ٢"}
	if M.has("dialogue"):
		# a real back-and-forth: the colonel briefs, the team leader answers
		for d in M.dialogue:
			var text: String = (d[1] as String).format(vals)
			var who: String = names[d[0]]
			hud.radio(who, text, maxf(2.2, text.length() * 0.075))
			if d[2] != "":
				gestures[text] = d[2]
	else:
		hud.radio(COLONEL, "الوضع: %d مسلّحين على الأقل." % enemies.size(), 4.5)
		for line in M.brief:
			hud.radio(COLONEL, line, 5.0)
	if smokes > 0:
		hud.radio(COLONEL, "ومعك %d قنابل دخان [G]. الدخان بيعميهم عنك." % smokes, 3.0)
	elif player.shield:
		hud.radio(COLONEL, "ومعك الدرع الواقي. خلّيه دايماً بينك وبينهم.", 3.0)
	else:
		hud.radio(COLONEL, "ومعك %d قنابل صوتية [G]. استعملها." % flashbangs, 3.0)
	hud.set_waypoint(city.door_pos + Vector3(0, 1.6, 1.6))
	hud.set_objectives(["◆ تقدّم إلى الباب الرئيسي – الفريق رح يصطف معك على الجنبين", "◆ ازرع عبوة الاقتحام [E] — أو [T] ليزرعها واحد من الفريق ويقتحموا", "◇ [V] كاميرا تحت الباب قبل ما تفجّره · [C] انحناء"])
	_start_dialogue_cam()

func _update_colonel(dt: float) -> void:
	if not colonel:
		return
	if colonel_talk_t > 0.0 and cutscene_t <= 0.0:
		colonel_talk_t -= dt
		if colonel_talk_t <= 0.0:
			colonel.set_mode("none")
	# before the briefing he watches you come in and turns to face you
	if phase == "arrive" and not talked:
		var to: Vector3 = player.global_position - colonel.global_position
		if in_vehicle:
			to = vehicle.global_position - colonel.global_position
		if to.length() < 22.0:
			colonel.rotation.y = lerp_angle(colonel.rotation.y, atan2(to.x, to.z), 1.0 - exp(-dt * 4.0))
			if to.length() < 9.0 and not in_vehicle and colonel.pose.mode != "salute":
				colonel.set_mode("salute")

## Onlookers and the TV crew behind the tape: animated only when you are close, hidden when far.
func _spawn_crowd() -> void:
	var spots: Array = city.crowd_spots.duplicate()
	spots.shuffle()
	for i in mini(Settings.crowd_count(), spots.size()):
		var p := Person.new("civilian", 2000 + i)
		add_child(p)
		p.global_position = spots[i][0] + Vector3(0, 0.16 if false else 0.0, 0)
		p.rotation.y = float(spots[i][1])
		crowd.append(p)
	for ps in city.press_spots:
		var role: String = "hostage" if ps[2] == "reporter" else "civilian"
		var p := Person.new(role, 2100 + crowd.size())
		add_child(p)
		p.global_position = ps[0]
		p.rotation.y = float(ps[1])
		p.set_mode("mic" if ps[2] == "reporter" else "camera")
		crowd.append(p)

func _update_crowd(dt: float) -> void:
	crowd_t -= dt
	if crowd_t > 0.0:
		return
	crowd_t = 0.25
	duck_t -= 0.25
	shout_cd -= 0.25
	talk_cd -= 0.25
	var ref: Vector3 = listener_pos()
	for p in crowd:
		var d: float = p.global_position.distance_to(ref)
		p.visible = d < 95.0
		p.anim.speed_scale = 1.0 if d < 30.0 else 0.0
		p.set_crouch(move_toward(p.crouch, 1.0 if duck_t > 0.0 else 0.0, 0.35))

## The HUD calls this whenever a radio / dialogue line starts: cut the camera to whoever speaks
## and let the colonel act it out (salute, explain with his hands, point at the door, radio in hand).
func on_radio_line(who: String, text: String) -> void:
	if who == COLONEL:
		var g: String = gestures.get(text, "talk" if cutscene_t > 0.0 else "radio")
		colonel.pose.point_at = city.door_pos + Vector3(0, 1.5, 0)
		colonel.set_mode(g)
		colonel_talk_t = maxf(2.0, text.length() * 0.08)
	elif cutscene_t > 0.0:
		colonel.set_mode("none")
	if cutscene_t > 0.0:
		cut_i = 0 if who == COLONEL else (1 if who == "الصقر ١" else 2)
		cut_k = 0.0

## Cinematic dialogue: shot / reverse-shot between the colonel and the team leader, letterboxed.
func _start_dialogue_cam() -> void:
	cutscene_t = 1.0      # stays > 0 until the last line has been said
	var cp: Vector3 = colonel.global_position
	var pp: Vector3 = player.global_position
	var d := (cp - pp); d.y = 0
	d = d.normalized()
	var side := Vector3(-d.z, 0, d.x)
	# both face each other
	player.yaw = atan2(-d.x, -d.z)
	player.rotation.y = player.yaw
	colonel.rotation.y = atan2(d.x, d.z)
	var head_c := cp + Vector3(0, 1.62, 0)
	var head_p := pp + Vector3(0, 1.62, 0)
	cut_shots = [
		[pp - d * 1.1 + side * 0.55 + Vector3(0, 1.75, 0), pp - d * 0.8 + side * 0.45 + Vector3(0, 1.72, 0), head_c],      # over the player's shoulder
		[cp + d * 1.1 - side * 0.5 + Vector3(0, 1.72, 0), cp + d * 0.85 - side * 0.42 + Vector3(0, 1.7, 0), head_p],       # reverse: over the colonel
		[(pp + cp) * 0.5 + side * 3.2 + Vector3(0, 1.5, 0), (pp + cp) * 0.5 + side * 2.6 + Vector3(0, 1.6, 0), (head_c + head_p) * 0.5],  # two-shot
	]
	cut_i = 0
	cut_k = 0.0
	hud.set_letterbox(true)
	cine_cam.current = true

func _update_dialogue_cam(dt: float) -> void:
	cut_k = minf(cut_k + dt / 5.0, 1.0)
	if hud.radio_queue.is_empty() and hud.radio_t <= 0.0:
		cutscene_t = 0.0
	var sh: Array = cut_shots[cut_i]
	var k := cut_k * cut_k * (3.0 - 2.0 * cut_k)
	cine_cam.global_position = (sh[0] as Vector3).lerp(sh[1], k)
	cine_cam.look_at(sh[2])
	cine_cam.fov = 42.0
	hud.set_prompt("اضغط للتخطّي")
	if cutscene_t <= 0.0:
		_end_dialogue_cam()

func _end_dialogue_cam() -> void:
	cutscene_t = 0.0
	colonel.set_mode("none")
	var to_bank: Vector3 = city.door_pos - colonel.global_position
	colonel.rotation.y = atan2(to_bank.x, to_bank.z)
	hud.set_letterbox(false)
	hud.set_prompt("")
	cine_cam.fov = 55.0
	player.cam.current = true
	input_guard = 0.4
	Controls.block_fire()

func _plant_charge(who := "الصقر ١") -> void:
	if phase != "staging":
		return
	phase = "breach"
	hud.set_prompt("")
	hud.clear_radio()
	hud.radio(who, "العبوة مزروعة! ابتعدوا عن الباب!", 2.5)
	for i in 3:
		hud.show_countdown(str(3 - i))
		Sfx.play("beep", 0.0, 1.0 + i * 0.15)
		await get_tree().create_timer(1.0).timeout
	hud.show_countdown("")
	_breach()

func _breach() -> void:
	door_open = true
	var dp: Vector3 = city.door_pos + Vector3(0, 1.4, 0)
	city.open_door()
	# the doorway is open now: rebuild the walkable area so people can path through it
	get_tree().create_timer(0.2).timeout.connect(func(): nav_region.bake_navigation_mesh(true))
	Sfx.play("boom", 4.0)
	Fx.flash(self, dp, 30.0, Color(1, 0.7, 0.4), 0.5, 30.0)
	Fx.particles(self, dp, Vector3(0, 0.3, 1), "smoke", 26)
	Fx.particles(self, dp, Vector3(0, 0, -1), "smoke", 18)
	Fx.particles(self, dp, Vector3(0, 0.4, 1), "spark", 40)
	shake = 1.0
	slowmo_t = 1.4
	Engine.time_scale = 0.3
	var pd := player.global_position.distance_to(dp)
	if pd < 3.5:
		player.take_hit(35.0 * (1.0 - pd / 3.5) + 10.0, false, null)
	for e in enemies:
		var d: float = e.global_position.distance_to(dp)
		if d < 13.0:
			e.stun = 3.5 * (1.0 - d / 16.0)
		e.alert(dp)
	phase = "assault"
	hud.clear_radio()
	mission_assault_text()
	hud.radio(COLONEL, "اقتحام! اقتحام! اقتحام!", 2.0)
	hud.radio("الصقر ١", "أمن عام! الكل على الأرض!", 2.5)

func mission_assault_text() -> void:
	if phase != "assault":
		return
	var alive := 0
	for e in enemies:
		if not e.dead and not e.cuffed:
			alive += 1
	var lines := ["◆ المسلحون المتبقّون: %d" % alive]
	if bomb and not bomb_defused:
		lines.append("◆ فكّ العبوة الناسفة [E مطوّل]  %02d:%02d" % [int(bomb_t) / 60, int(bomb_t) % 60])
	if hostages.size() > 0:
		lines.append("◆ حرّر الرهائن [E] وأخرجهم لبرّا (%d / %d)" % [hostages_saved, hostages.size()])
	if evidence.size() > 0:
		lines.append("◆ اجمع الأدلة [E] (%d / %d)" % [evidence_got, evidence.size() - evidence_lost])
	lines.append("◇ [Q] استسلام · [G] %s · [X] تبديل السلاح" % (grenade_label() if grenade_label() != "" else "ما في قنابل"))
	if evidence_lost > 0:
		lines.append("✖ أدلة اتلفت: %d" % evidence_lost)
	if hostages_lost > 0:
		lines.append("✖ رهائن فقدناهم: %d" % hostages_lost)
	hud.set_objectives(lines)
	var best = null
	var bd := 1e9
	for h in hostages:
		if not h.freed and not h.rescued and not h.dead:
			var d: float = h.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d; best = h
	var escorting := hostages.any(func(h): return h.freed and not h.dead and h.escort == null)
	var ev_left = null
	var evd := 1e9
	for ev in evidence:
		if not ev[1] and not ev[2]:
			var d: float = (ev[0] as Node3D).global_position.distance_to(player.global_position)
			if d < evd:
				evd = d; ev_left = ev[0]
	if bomb and not bomb_defused:
		hud.set_waypoint(bomb.global_position + Vector3(0, 1.2, 0))
	elif escorting:
		hud.set_waypoint(city.door_pos + Vector3(0, 0.6, 11.0))
	elif best:
		hud.set_waypoint(best.global_position + Vector3(0, 1.4, 0))
	elif ev_left:
		hud.set_waypoint((ev_left as Node3D).global_position + Vector3(0, 1.4, 0))
	else:
		# nobody left to free: point at the nearest suspect who surrendered but isn't cuffed yet
		var sus = null
		var sd := 1e9
		for e in enemies:
			if e.surrendered and not e.cuffed and not e.dead:
				var d: float = e.global_position.distance_to(player.global_position)
				if d < sd:
					sd = d; sus = e
		hud.set_waypoint(sus.global_position + Vector3(0, 2.2, 0) if sus else null)

# ---- twist: the leader escapes in the cash van
func _start_chase() -> void:
	if phase != "assault":
		return
	phase = "chase"
	chase_t = 0.0
	var bb: Vector2i = city.bank_block
	van = AnimatableBody3D.new()
	van.set_script(EscapeVan)
	van.setup(self, Vector2i(bb.x, bb.y), Vector2i(bb.x + 1, bb.y))
	van.t = 0.35
	add_child(van)
	hud.clear_radio()
	hud.show_banner("هروب!", "%s هرب من الباب الخلفي بفان نقل الأموال" % LEADER, 3.5)
	hud.radio("القنّاص", "الصقر ١! فان المصرف طالع من الشارع الخلفي بسرعة! %s جوّاته!" % LEADER, 4.0)
	hud.radio(COLONEL, "لا تخلّيه يفلت! ارجع للسيارة والحقه. اصدمه أو اضرب المحرك.", 4.5)
	hud.set_objectives(["◆ الحق فان %s وأوقفه" % LEADER, "◇ اصدمه بالسيارة أو أطلق النار عليه"])

func on_van_disabled(_v) -> void:
	phase = "arrest"
	Sfx.play("boom", -4.0, 1.4)
	shake = 0.6
	hud.clear_radio()
	hud.show_banner("الفان توقّف!", "اعتقل %s" % LEADER, 3.0)
	leader = Person.new("robber", 4242)
	add_child(leader)
	var b: Basis = van.global_transform.basis
	leader.global_position = van.global_position + b.x * 2.2
	leader.global_position.y = 0.0
	var f: Vector3 = b.x
	leader.rotation.y = atan2(-f.x, -f.z)
	leader.set_mode("hands_up")
	var tag := Label3D.new()
	tag.text = LEADER
	tag.font = load("res://assets/fonts/Tajawal-Bold.ttf")
	tag.font_size = 30; tag.pixel_size = 0.0011; tag.fixed_size = true; tag.outline_size = 8
	tag.modulate = Color(1, 0.4, 0.3)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.15, 0)
	leader.add_child(tag)
	hud.radio(LEADER, "خلص! خلص! لا تطخ… أنا مستسلم!", 3.0)
	hud.set_objectives(["◆ انزل واعتقل %s [E]" % LEADER])

func _arrest_leader() -> void:
	leader_cuffed = true
	arrests += 1
	leader.set_mode("kneel_back")
	Sfx.play("cuff")
	hud.clear_radio()
	hud.radio("الصقر ١", "%s مكبّل. الأموال بالفان." % LEADER, 3.0)
	hud.radio(COLONEL, "عمل بطولي يا الصقر ١. عمّان مدينة لكم الليلة.", 4.0)
	_end(true, "")

# ------------------------------------------------------------------ per-frame
func _process(dt: float) -> void:
	if not loaded:
		return
	var real_dt := dt / maxf(Engine.time_scale, 0.05)
	if slowmo_t > 0.0:
		slowmo_t -= real_dt
	elif Engine.time_scale < 1.0:
		Engine.time_scale = minf(1.0, Engine.time_scale + real_dt * 1.8)
	var ph := fmod(Time.get_ticks_msec() * 0.0032, 1.0)
	for i in city.flashers.size():
		var fl: Dictionary = city.flashers[i]
		if fl.has("red"):
			var on := fmod(ph + i * 0.37, 1.0) < 0.5
			fl.red.emission_energy_multiplier = 6.0 if on else 0.3
			fl.blue.emission_energy_multiplier = 0.3 if on else 6.0
	if phase == "brief":
		cine_t += dt
		if city.hq_pos != Vector3.INF:
			# slow drift inside the duty room; the short far plane keeps the city out of the picture
			var hp: Vector3 = city.hq_pos
			cine_cam.far = 60.0
			cine_cam.fov = 50.0
			cine_cam.global_position = hp + Vector3(4.9 + sin(cine_t * 0.12) * 0.5, 2.2, -3.4 + cos(cine_t * 0.1) * 0.4)
			cine_cam.look_at(hp + Vector3(1.6, 1.5, -0.6))
			cine_cam.h_offset = 1.15      # keeps the team in the left half, clear of the menu panel
		else:
			var c: Vector3 = city.door_pos
			var a := cine_t * 0.08 + 0.6
			cine_cam.global_position = c + Vector3(sin(a) * 30.0 - 10.0, 26.0 + sin(cine_t * 0.2) * 3.0, 38.0 + cos(a) * 8.0)
			cine_cam.look_at(c + Vector3(0, 4, 0))
		return
	if phase == "intro":
		intro_t += dt
		var sh: Array = intro_shots[intro_i]
		var k := clampf(intro_t / sh[3], 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		cine_cam.current = true
		cine_cam.h_offset = 0.0
		cine_cam.far = 60.0 if (intro_i == 0 and city.hq_pos != Vector3.INF) else 1500.0
		cine_cam.fov = 50.0 if intro_i == 0 else 55.0
		cine_cam.global_position = (sh[0] as Vector3).lerp(sh[1], k)
		cine_cam.look_at(sh[2])
		hud.set_prompt("اضغط للتخطّي")
		if intro_t >= sh[3]:
			_next_shot()
		return
	if phase == "result":
		return
	if cutscene_t > 0.0:
		_update_dialogue_cam(dt)
	_update_colonel(dt)
	_update_crowd(dt)
	mission_time += dt
	if shake > 0.0:
		shake = maxf(shake - dt * 1.5, 0.0)
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.h_offset = randf_range(-1, 1) * shake * 0.25
			cam.v_offset = randf_range(-1, 1) * shake * 0.25
	yell_cd -= dt
	ram_cd -= dt
	input_guard -= real_dt
	# hostage-taker deadline before the breach
	if phase in ["drive", "arrive", "staging", "sniper"]:
		deadline -= dt
		if M.deadline > 0.0 and deadline <= 0.0:
			_deadline_hit()
	# bomb clock runs from the moment the team rolls out
	if bomb and not bomb_defused and phase in ["drive", "arrive", "staging", "breach", "assault"]:
		bomb_t -= dt
		var tl: Label3D = bomb.get_node("Timer")
		tl.text = "%02d:%02d" % [int(maxf(bomb_t, 0.0)) / 60, int(maxf(bomb_t, 0.0)) % 60]
		if int(bomb_t * 2.0) != int((bomb_t + dt) * 2.0) and player.global_position.distance_to(bomb.global_position) < 25.0:
			Sfx.play_3d("beep", bomb.global_position, -6.0, 1.3)
		if bomb_t <= 0.0:
			_bomb_explodes()
	if Controls.just("flash") and not in_vehicle and player.alive and phase in ["staging", "breach", "assault"] and input_guard <= 0.0 and doorcam_t <= 0.0:
		_throw_flashbang("smoke" if (smokes > 0 and flashbangs <= 0) else "flash")
	for sc in smoke_clouds:
		sc[2] -= dt
	if smoke_clouds.size() > 0 and smoke_clouds[0][2] <= 0.0:
		smoke_clouds.pop_front()
	if doorcam_t > 0.0:
		_update_doorcam(dt)
	elif Controls.just("gadget") and _doorcam_ready():
		_start_doorcam()
	if mark_t > 0.0 and phase == "assault":
		mark_t -= dt          # the picture goes stale once the shooting starts and people move
		if mark_t <= 30.0:
			marked.clear()
			mark_t = 0.0
	# breadcrumb trail for hostages following the player
	if not in_vehicle and player.alive:
		var pp := player.global_position
		if trail.is_empty() or (trail[-1] as Vector3).distance_to(pp) > 0.8:
			trail.append(pp)
			if trail.size() > 500:
				trail.pop_front()
				for h in hostages:
					h.trail_idx = maxi(h.trail_idx - 1, 0)
	# vehicle enter / exit
	if Controls.just("vehicle") and input_guard <= 0.0:
		if in_vehicle:
			if vehicle.speed_kmh > 15.0:
				hud.show_banner("", "خفّف السرعة حتى تنزل", 1.2)
			else:
				_exit_vehicle()
		elif player.alive and player.global_position.distance_to(vehicle.global_position) < 4.5:
			_enter_vehicle()
	if phase == "drive":
		var ref: Vector3 = vehicle.global_position if in_vehicle else player.global_position
		if ref.distance_to(city.cordon_point) < 26.0:
			_arrive()
	if phase == "chase" and van:
		chase_t += dt
		hud.set_waypoint(van.global_position + Vector3(0, 3.0, 0))
		hud.set_objectives(["◆ الحق فان %s وأوقفه" % LEADER, "◇ اصدمه بالسيارة أو أطلق النار عليه", "حالة الفان: %d%%" % int(van.hp)])
		if in_vehicle and ram_cd <= 0.0 and (van in vehicle.get_colliding_bodies() or vehicle.global_position.distance_to(van.global_position) < 3.0):
			var vv: Vector3 = van.global_transform.basis.z * van.speed
			var rel: float = (vehicle.linear_velocity - vv).length()
			if rel > 3.0:
				ram_cd = 0.6
				van.damage(rel * 2.2)
				vehicle.linear_velocity *= 0.75
				shake = 0.7
				Sfx.play("boom", -8.0, 1.8)
				Fx.particles(self, (vehicle.global_position + van.global_position) * 0.5 + Vector3(0, 0.8, 0), Vector3.UP, "spark", 20)
		if chase_t > 240.0 and not ended:
			_end(false, "%s هرب بالأموال. المطاردة طالت كثير." % LEADER)
	elif phase == "arrest" and leader:
		hud.set_waypoint(leader.global_position + Vector3(0, 2.2, 0))
	if cutscene_t <= 0.0:
		_interactions()
	_team_work(dt)
	if Controls.just("orders") and not in_vehicle and player.alive and input_guard <= 0.0 and cutscene_t <= 0.0:
		_give_order()
	if phase == "assault" and Controls.just("yell") and not in_vehicle and input_guard <= 0.0:
		_yell()

func timer_text() -> String:
	if bomb and not bomb_defused and phase in ["drive", "arrive", "staging", "breach", "assault"]:
		var tb := maxf(bomb_t, 0.0)
		return "العبوة  %02d:%02d" % [int(tb) / 60, int(tb) % 60]
	if phase in ["drive", "arrive", "staging", "sniper"] and M.deadline > 0.0:
		var t := maxf(deadline, 0.0)
		var lbl: String = "مهلة الخاطفين" if M.deadline_kind == "execute" else "إتلاف الأدلة بعد"
		return "%s  %02d:%02d" % [lbl, int(t) / 60, int(t) % 60]
	if phase == "chase":
		var t := maxf(240.0 - chase_t, 0.0)
		return "المطاردة  %02d:%02d" % [int(t) / 60, int(t) % 60]
	return "%02d:%02d" % [int(mission_time) / 60, int(mission_time) % 60]

func timer_urgent() -> bool:
	if bomb and not bomb_defused and bomb_t < 60.0:
		return true
	return (phase in ["drive", "arrive", "staging", "sniper"] and M.deadline > 0.0 and deadline < 60.0) or (phase == "chase" and chase_t > 180.0)

func _deadline_hit() -> void:
	if M.deadline_kind == "evidence":
		deadline = 120.0
		for ev in evidence:
			if not ev[1] and not ev[2]:
				ev[2] = true
				evidence_lost += 1
				(ev[0] as Node3D).visible = false
				Fx.particles(self, (ev[0] as Node3D).global_position + Vector3(0, 1, 0), Vector3.UP, "smoke", 8)
				hud.clear_radio()
				hud.radio("فريق المراقبة", "في دخان طالع من الشباك… عم يحرقوا الأدلة! خسرنا دليل.", 4.5)
				hud.radio(COLONEL, "الصقر ١، أسرع قبل ما يتلفوا الباقي!", 2.5)
				return
		return
	_execute_hostage()

func _execute_hostage() -> void:
	var alive := hostages.filter(func(h): return not h.dead)
	deadline = 180.0
	if alive.is_empty():
		return
	alive.pick_random().take_hit(999.0, false, null)
	Sfx.play("far", -6.0, 0.8)
	hud.clear_radio()
	hud.radio(NEGOTIATOR, "سمعنا طلقة جوّا… خسرنا رهينة. %s بقول إنّه رح يعيدها بعد ثلاث دقايق!" % LEADER, 5.0)
	hud.radio(COLONEL, "الصقر ١، أسرع!", 2.5)

func _interactions() -> void:
	if in_vehicle or not player.alive:
		hud.set_prompt("")
		return
	if doorcam_t > 0.0:
		hud.set_prompt("اسحب لتحرّك الكاميرا   ·   [V] إغلاق   ·   %d ث" % int(ceil(doorcam_t)))
		return
	var pp := player.global_position
	var text := ""
	var action := Callable()
	if phase == "arrive" and pp.distance_to(colonel.global_position) < 3.0:
		text = "[E] تحدّث مع %s" % COLONEL
		action = _talk_colonel
	elif phase == "staging":
		if pp.distance_to(city.door_pos + Vector3(0, 0, 1.6)) < 2.6:
			text = "[E] ازرع عبوة الاقتحام   ·   [V] كاميرا تحت الباب"
			action = _plant_charge
	elif phase == "assault" and bomb and not bomb_defused and pp.distance_to(bomb.global_position) < 2.2:
		if Controls.held("interact"):
			defuse_hold += get_process_delta_time()
			text = "جارٍ فكّ العبوة… %d%%" % int(defuse_hold / 4.0 * 100.0)
			if defuse_hold >= 4.0:
				_defuse_bomb()
				text = ""
		else:
			defuse_hold = 0.0
			text = "[E] اضغط مطوّل لفكّ العبوة"
	elif phase == "assault" and _near_evidence(pp) != null:
		var ev = _near_evidence(pp)
		text = "[E] حرّز الدليل"
		action = func(): _collect(ev)
	elif phase == "assault":
		var best = null
		var bd := 2.4
		for e in enemies:
			if e.surrendered and not e.cuffed and not e.dead:
				var d: float = pp.distance_to(e.global_position)
				if d < bd:
					bd = d; best = e
		if best:
			text = "[E] تكبيل المشتبه"
			action = func(): _cuff(best)
		else:
			for h in hostages:
				if not h.freed and not h.rescued and not h.dead:
					var d: float = pp.distance_to(h.global_position)
					if d < bd:
						bd = d; best = h
			if best:
				text = "[E] فكّ وثاق الرهينة"
				action = func(): _free(best)
	elif phase == "arrest" and leader and not leader_cuffed and pp.distance_to(leader.global_position) < 2.6:
		text = "[E] اعتقال %s" % LEADER
		action = _arrest_leader
	if text == "" and talk_cd <= 0.0 and phase in ["drive", "arrive", "staging"]:
		var civ = _near_civilian(pp)
		if civ != null:
			text = "[E] تحدّث"
			action = func(): _talk_civilian(civ[0], civ[1])
	if text == "" and vehicle.broken and pp.distance_to(vehicle.global_position) < 4.5:
		if Controls.held("interact"):
			repair_hold += get_process_delta_time()
			text = "تصليح ميداني… %d%%" % int(repair_hold / 6.0 * 100.0)
			if repair_hold >= 6.0:
				repair_hold = 0.0
				vehicle.repair()
				Sfx.play("reload", -2.0, 0.7)
				hud.show_banner("", "السيارة اشتغلت… بس انتبه عليها", 2.0)
		else:
			repair_hold = 0.0
			text = "[E] اضغط مطوّل لتصليح السيارة"
	elif text == "" and pp.distance_to(vehicle.global_position) < 4.5:
		text = "[F] ركوب السيارة"
	hud.set_prompt(text)
	if action.is_valid() and Controls.just("interact"):
		action.call()

func _near_evidence(pp: Vector3):
	for ev in evidence:
		if not ev[1] and not ev[2] and (ev[0] as Node3D).global_position.distance_to(pp) < 2.0:
			return ev
	return null

func _collect(ev) -> void:
	ev[1] = true
	evidence_got += 1
	(ev[0] as Node3D).visible = false
	Sfx.play("cuff", -2.0, 1.3)
	hud.radio("الصقر ١", ["الدليل معي! حاسوب فيه كشوفات الشحنات.", "حرّزت الدفتر، فيه أسماء وأرقام.", "صندوق أسلحة مهرّبة، تم التحريز."][(evidence_got - 1) % 3], 3.0)
	mission_assault_text()
	_check_win()

func _defuse_bomb() -> void:
	bomb_defused = true
	defuse_hold = 0.0
	Sfx.play("cuff", 0.0, 0.7)
	(bomb.get_node("Timer") as Label3D).text = "تم التعطيل"
	(bomb.get_node("Timer") as Label3D).modulate = Color(0.4, 1, 0.5)
	hud.show_banner("تم تعطيل العبوة", "%02d:%02d قبل الانفجار" % [int(bomb_t) / 60, int(bomb_t) % 60], 3.0)
	hud.radio(COLONEL, "العبوة معطّلة! ممتاز يا الصقر ١. كمّلوا التنظيف.", 3.5)
	mission_assault_text()
	_check_win()

func _bomb_explodes() -> void:
	bomb_t = 0.0
	var bp: Vector3 = bomb.global_position + Vector3(0, 1, 0)
	Sfx.play("boom", 8.0, 0.7)
	Fx.flash(self, bp, 60.0, Color(1, 0.6, 0.3), 1.0, 60.0)
	for k in 3:
		Fx.particles(self, bp, Vector3.UP, "smoke", 30)
	Fx.particles(self, bp, Vector3.UP, "spark", 60)
	shake = 1.5
	if player.global_position.distance_to(bp) < 25.0:
		player.take_hit(999.0, false, null)
	_end(false, "انفجرت العبوة قبل ما تتعطّل.")

## G / flash button: throw a stun grenade where the camera points (bounces off walls, max 14 m).
## True if a smoke cloud lies between the two points.
func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	for sc in smoke_clouds:
		var c: Vector3 = sc[0]
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (a + ab * t).distance_to(c) < float(sc[1]) * 0.85:
			return true
	return false

func grenade_label() -> String:
	if flashbangs > 0:
		return "فلاش %d" % flashbangs
	if smokes > 0:
		return "دخان %d" % smokes
	return ""

func _throw_flashbang(kind := "flash") -> void:
	if kind == "smoke":
		smokes -= 1
	elif flashbangs <= 0:
		hud.show_banner("", "خلصت القنابل", 1.2)
		return
	else:
		flashbangs -= 1
	var cam: Camera3D = player.cam
	var from := player.global_position + Vector3(0, 1.5, 0)
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 14.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var land: Vector3 = (hit.position + hit.normal * 0.4) if hit else from + dir * 14.0
	var dq := PhysicsRayQueryParameters3D.create(land, land + Vector3(0, -6, 0), 1)
	var dh := get_world_3d().direct_space_state.intersect_ray(dq)
	if dh:
		land = dh.position + Vector3(0, 0.1, 0)
	var g := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.035; cm.bottom_radius = 0.035; cm.height = 0.12
	g.mesh = cm
	add_child(g)
	g.global_position = from + dir * 0.5
	var mid := (g.global_position + land) * 0.5 + Vector3(0, 1.2, 0)
	var tw := create_tween()
	var start := from + dir * 0.5
	tw.tween_method(func(t: float): g.global_position = start.bezier_interpolate(mid, mid, land, t), 0.0, 1.0, 0.6)
	Sfx.play("click", -4.0, 0.8)
	player.model.throw_anim()
	hud.radio("الصقر ١", "قنبلة صوتية!" if kind == "flash" else "دخان!", 1.5)
	mission_assault_text()
	if kind == "smoke":
		get_tree().create_timer(1.0).timeout.connect(func(): _smoke_pop(g))
	else:
		get_tree().create_timer(1.3).timeout.connect(func(): _flashbang_bang(g))

## Smoke grenade: a thick cloud for a quarter of a minute. Gunmen lose sight of whatever is behind it.
func _smoke_pop(g: Node3D) -> void:
	var p := g.global_position + Vector3(0, 1.1, 0)
	g.queue_free()
	Sfx.play_3d("sputter", p, 2.0, 0.6)
	Fx.smoke_cloud(self, p, 4.6, 15.0)
	smoke_clouds.append([p, 4.6, 15.0])

func _flashbang_bang(g: Node3D) -> void:
	var p := g.global_position + Vector3(0, 0.5, 0)
	g.queue_free()
	Sfx.play_3d("boom", p, 4.0, 1.9)
	Fx.flash(self, p, 40.0, Color(1, 1, 1), 0.35, 18.0)
	Fx.particles(self, p, Vector3.UP, "smoke", 10)
	var space := get_world_3d().direct_space_state
	for e in enemies:
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(p)
		if d < 9.0:
			var q := PhysicsRayQueryParameters3D.create(p, e.global_position + Vector3(0, 1.5, 0), 1)
			if space.intersect_ray(q).is_empty():
				e.stun = maxf(e.stun, 5.0 * (1.0 - d / 12.0))
				e.alert(p)
	# blind the player too if they're close and looking at it
	var pd := player.global_position.distance_to(p)
	if pd < 10.0:
		var look: Vector3 = -player.cam.global_basis.z
		var facing: float = look.dot((p - player.cam.global_position).normalized())
		hud.white_flash(clampf((1.0 - pd / 10.0) * (0.4 + maxf(facing, 0.0)), 0.0, 1.0))

func on_executioner(e) -> void:
	hud.radio("الصقر ٢" if team.size() > 0 else COLONEL, "في مسلّح واقف فوق رهينة! حيّدوه بسرعة!", 3.0)

func _cuff(e) -> void:
	e.cuffed = true
	arrests += 1
	Sfx.play("cuff")
	e.model.set_mode("kneel_back")
	hud.feed("+ اعتقال", Color(0.5, 0.85, 1.0))
	hud.radio("الصقر ١", "المشتبه مكبّل!", 2.0)
	mission_assault_text()
	_check_win()

func _free(h) -> void:
	h.free_hostage(trail.size())
	hud.feed("+ رهينة محرّرة", Color(0.55, 1.0, 0.6))
	Sfx.play("cuff", -4.0, 0.8)
	hud.radio("رهينة", HOSTAGE_THANKS.pick_random(), 2.5)
	# hand the hostage to the nearest free teammate, who walks them out while you keep clearing
	var best = null
	var bd := 30.0
	for t in team:
		if t.dead or not t.visible or t.escort_h:
			continue
		var d: float = t.global_position.distance_to(h.global_position)
		if d < bd:
			bd = d; best = t
	if best:
		best.escort_h = h
		h.escort = best
		hud.radio(best.display_name, ["أنا ماسك الرهينة، بطلّعها لبرّا. غطّوني!", "استلمتها! طالع فيها عالإسعاف.", "معي الرهينة، كمّلوا التنظيف!"].pick_random(), 3.0)
	else:
		hud.radio("الصقر ١", ["امشي ورايا وما تبعدي عنّي، رح نطلع سوا.", "إنت بأمان هلأ. ضلّك ورايا لبرّا.", "قوم معي… خلّيك لازق فيّ لحد الباب."].pick_random(), 3.0)
	mission_assault_text()

func on_hostage_saved(_h) -> void:
	hostages_saved += 1
	hud.radio("المسعف", "استلمنا الرهينة، بخير والحمد لله.", 2.5)
	mission_assault_text()
	_check_win()

func _yell() -> void:
	if yell_cd > 0.0:
		return
	yell_cd = 2.2
	hud.radio("الصقر ١", ["أمن عام! ارمِ سلاحك وانبطح!", "ارمِ السلاح! إيديك فوق راسك!", "انتهى الموضوع! ارمِ سلاحك!"].pick_random(), 2.0)
	var eye := player.global_position + Vector3(0, 1.6, 0)
	for e in enemies:
		if e.dead or e.surrendered:
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d > 16.0 or not e.can_see(eye):
			continue
		var chance: float = 0.18 + (1.0 - e.hp / 100.0) * 0.45
		if e.stun > 0.0:
			chance += 0.45
		var others := 0
		for o in enemies:
			if o != e and not o.dead and not o.surrendered and o.global_position.distance_to(e.global_position) < 8.0:
				others += 1
		chance -= others * 0.08
		chance += team.filter(func(t): return not t.dead and t.visible and t.global_position.distance_to(e.global_position) < 14.0).size() * 0.08
		if randf() < chance:
			e.surrender()
			hud.show_banner("استسلم!", "اقترب منه واضغط E للتكبيل", 1.8)
		else:
			e.alert(player.global_position)
	mission_assault_text()

func _exit_vehicle() -> void:
	in_vehicle = false
	vehicle.set_driving(false)
	_reset_shake()
	trail.clear()
	var b := vehicle.global_transform.basis
	var vp := vehicle.global_position
	var y := maxf(vp.y, 0.0) + 0.2
	var flat := func(v: Vector3) -> Vector3: return Vector3(v.x, y, v.z)
	var out: Vector3 = _free_spot([flat.call(vp + b.x * 1.9), flat.call(vp - b.x * 1.9), flat.call(vp - b.z * 3.6), flat.call(vp + b.z * 3.6), flat.call(vp + b.x * 3.0)], [vehicle.get_rid()])
	player.global_position = out
	var f := b.z; f.y = 0
	player.yaw = atan2(f.x, f.z) + PI
	player.rotation.y = player.yaw
	player.set_active(true)
	_place_team(out, b)

func _place_team(out: Vector3, b: Basis) -> void:
	var used: Array = [out]
	if team_size > 0:
		if not team_spawned:
			team_spawned = true
			for i in team_size:
				var t := CharacterBody3D.new()
				t.set_script(Actor)
				t.setup(self, "team", Vector3.ZERO, player.yaw, TEAM_NAMES[i])
				t.follow_offset = TEAM_OFFSETS[i]
				t.team_index = i
				t.accuracy = 0.4
				add_child(t)
				team.append(t)
		for i in team.size():
			var t = team[i]
			if t.dead:
				continue
			t.visible = true
			t.process_mode = Node.PROCESS_MODE_INHERIT
			t.collision_layer = 16
			var cands := []
			for k in 6:
				cands.append(out + b.z * (-1.6 - k * 1.1) + b.x * (0.0 if k % 2 == 0 else -0.9))
				cands.append(out + b.z * (1.6 + k * 1.1))
			cands.append(out + Vector3(0, 0, 0))
			# physics hasn't seen the teammates placed this frame yet: keep them apart by hand
			var free_c := cands.filter(func(c): return not used.any(func(u): return (u as Vector3).distance_to(c) < 1.0))
			t.global_position = _free_spot(free_c if free_c.size() > 0 else cands, [vehicle.get_rid(), player.get_rid()])
			used.append(t.global_position)
			t.rotation.y = player.yaw

# ---- fibre-optic camera under the door: see who is inside before you breach
var doorcam_t := 0.0
var doorcam_yaw := 0.0
var doorcam_pitch := 0.15
var marked: Array = []          # gunmen / hostages seen through the camera (shown on the map and through the wall)
var mark_t := 0.0

func _doorcam_ready() -> bool:
	return phase == "staging" and not in_vehicle and player.alive and cutscene_t <= 0.0 and input_guard <= 0.0 \
		and not door_open and player.global_position.distance_to(city.door_pos + Vector3(0, 0, 1.6)) < 3.0

func _start_doorcam() -> void:
	doorcam_t = 10.0
	doorcam_yaw = 0.0
	doorcam_pitch = 0.15
	input_guard = 0.3
	Controls.aim_toggle = false
	cine_cam.current = true
	cine_cam.h_offset = 0.0
	cine_cam.fov = 92.0
	cine_cam.near = 0.03
	cine_cam.far = 70.0
	Sfx.play("click", -6.0, 1.4)
	hud.radio("الصقر ١", "الكاميرا تحت الباب… ولا نَفَس.", 2.0)

func _update_doorcam(dt: float) -> void:
	doorcam_t -= dt
	var look := Controls.consume_look()
	doorcam_yaw = clampf(doorcam_yaw - look.x, -1.35, 1.35)
	doorcam_pitch = clampf(doorcam_pitch - look.y, -0.1, 0.6)
	var eye: Vector3 = city.door_pos + Vector3(0, 0.14, -0.5)
	cine_cam.global_position = eye
	cine_cam.rotation = Vector3(doorcam_pitch, doorcam_yaw, 0)
	# whoever the lens can actually see gets marked
	var space := get_world_3d().direct_space_state
	var seen: Array = []
	seen.append_array(enemies)
	seen.append_array(hostages)
	for a in seen:
		if a.dead or marked.has(a):
			continue
		var tp: Vector3 = a.global_position + Vector3(0, 1.0, 0)
		if not cine_cam.is_position_in_frustum(tp):
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, tp, 1)
		if space.intersect_ray(q).is_empty():
			marked.append(a)
			Sfx.play("beep", -12.0, 1.6)
	if doorcam_t <= 0.0 or (input_guard <= 0.0 and (Controls.just("gadget") or Controls.just("jump"))):
		_end_doorcam()

func _end_doorcam() -> void:
	doorcam_t = 0.0
	input_guard = 0.3
	cine_cam.near = 0.05
	cine_cam.far = 1500.0
	cine_cam.fov = 55.0
	player.cam.current = true
	mark_t = 45.0
	var ne := marked.filter(func(a): return a.get("side") == "enemy").size()
	var nh := marked.size() - ne
	if marked.is_empty():
		hud.radio("الصقر ١", "ما شفت حدا من هالزاوية. ندخل بحذر.", 2.5)
	else:
		hud.show_banner("", "الكاميرا: مسلّحين %d  ·  رهائن %d" % [ne, nh], 3.5)
		hud.radio("الصقر ١", "شفت اللي جوّا. حفظت أماكنهم.", 2.5)

## [T] team orders. Before the breach: send a teammate to blow the door. During the assault:
## follow me -> hold here -> push in and clear on your own.
func _give_order() -> void:
	var alive_team := team.filter(func(t): return not t.dead and t.visible)
	if alive_team.is_empty():
		hud.radio("الصقر ١", "ما في حدا معي… أنا لحالي.", 2.0)
		return
	if phase == "staging" and cutscene_t <= 0.0:
		if breacher == null:
			breacher = alive_team[0]
			breacher.task_goal = city.door_pos + Vector3(0, 0, 1.5)
			team_order = "assault"
			hud.radio("الصقر ١", "%s، افتح الباب! الباقي جاهزين للدخول." % breacher.display_name, 2.5)
			hud.radio(breacher.display_name, "علم! رايح أزرع العبوة.", 2.0)
			hud.show_banner("", "أمر للفريق: نفّذوا الاقتحام", 1.8)
		return
	var nxt := {"follow": "hold", "hold": "assault", "assault": "follow"}
	team_order = nxt[team_order]
	if team_order == "assault" and phase != "assault":
		team_order = "follow"
	match team_order:
		"hold":
			for t in alive_team:
				t.hold_pos = t.global_position
			hud.radio("الصقر ١", ["اثبتوا مكانكم وغطّوا!", "خليكم هون، أمّنوا المكان!"].pick_random(), 2.0)
			hud.radio(alive_team[0].display_name, ["تمام، ثابتين ومغطّينك.", "علم، ماسكين المكان."].pick_random(), 2.0)
			hud.show_banner("", "أمر للفريق: اثبتوا مكانكم", 1.5)
		"assault":
			hud.radio("الصقر ١", ["تقدّموا ونظّفوا الغرف!", "ادخلوا! غرفة غرفة!"].pick_random(), 2.0)
			hud.radio(alive_team[0].display_name, ["داخلين! غطّونا!", "متقدّمين، الغرفة الجاي إلنا."].pick_random(), 2.0)
			hud.show_banner("", "أمر للفريق: تقدّموا ونظّفوا", 1.5)
		_:
			hud.radio("الصقر ١", ["اتبعوني! تحرّك!", "معي يا شباب، يلّا!"].pick_random(), 2.0)
			hud.radio(alive_team[0].display_name, ["وراك!", "متحرّكين معك."].pick_random(), 1.6)
			hud.show_banner("", "أمر للفريق: اتبعوني", 1.5)

## Teammates sent in on their own cuff suspects and free hostages they reach, and the breacher blows the door.
func _team_work(dt: float) -> void:
	if breacher != null:
		if breacher.dead or phase != "staging":
			breacher.task_goal = Vector3.INF
			breacher = null
		elif breacher.global_position.distance_to(city.door_pos + Vector3(0, 0, 1.5)) < 1.6:
			var who: String = breacher.display_name
			breacher.task_goal = Vector3.INF
			breacher = null
			_plant_charge(who)
	team_tick -= dt
	if team_tick > 0.0 or phase != "assault" or team_order != "assault":
		return
	team_tick = 0.6
	for t in team:
		if t.dead or not t.visible or t.escort_h:
			continue
		for e in enemies:
			if e.surrendered and not e.cuffed and not e.dead and t.global_position.distance_to(e.global_position) < 2.4:
				e.cuffed = true
				arrests += 1
				Sfx.play_3d("cuff", e.global_position)
				e.model.set_mode("kneel_back")
				hud.radio(t.display_name, "المشتبه مكبّل!", 1.8)
				mission_assault_text()
				_check_win()
				return
		for h in hostages:
			if not h.dead and not h.freed and not h.rescued and t.global_position.distance_to(h.global_position) < 2.4:
				h.free_hostage(trail.size())
				t.escort_h = h
				h.escort = t
				hud.radio(t.display_name, "لقيت رهينة! بطلّعها لبرّا.", 2.2)
				mission_assault_text()
				return

func on_vehicle_broken() -> void:
	hud.show_banner("السيارة تعطّلت!", "انزل [F] واضغط [E] مطوّل جنبها لتصليحها", 3.5)
	hud.radio("الصقر ١", "المحرك وقف! السيارة طفت!", 2.5)

func _free_spot(cands: Array, exclude: Array) -> Vector3:
	var space := get_world_3d().direct_space_state
	var sh := CapsuleShape3D.new(); sh.radius = 0.38; sh.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1 | 2 | 8 | 16
	q.exclude = exclude
	for c in cands:
		q.transform = Transform3D(Basis(), c + Vector3(0, 0.95, 0))
		if space.intersect_shape(q, 1).is_empty():
			return c
	return (cands[0] as Vector3) + Vector3(0, 2.6, 0)

func _reset_shake() -> void:
	shake = 0.0
	for c in [player.cam, vehicle.cam, cine_cam]:
		if c:
			c.h_offset = 0.0
			c.v_offset = 0.0

func _enter_vehicle() -> void:
	in_vehicle = true
	if phase == "drive" and not drive_started:
		_on_drive_start.call_deferred()
	_reset_shake()
	trail.clear()
	player.set_active(false)
	vehicle.set_driving(true)
	for t in team:
		if t.dead:
			continue
		t.visible = false
		t.process_mode = Node.PROCESS_MODE_DISABLED
		t.collision_layer = 0

func _check_win() -> void:
	if ended:
		return
	if phase == "sniper":
		for e in enemies:
			if not e.dead:
				return
		for h in hostages:
			if not h.dead:
				h.rescued = true
				hostages_saved += 1
		hud.clear_radio()
		hud.radio("الفريق الأرضي", "الساحة نظيفة! داخلين… الرهائن معنا وبخير.", 3.5)
		hud.radio(COLONEL, "عمل قنّاص محترف يا الصقر ١. ولا طلقة ضايعة.", 3.5)
		_end(true, "")
		return
	if phase != "assault":
		return
	for e in enemies:
		if not e.dead and not e.cuffed:
			return
	for h in hostages:
		if not h.rescued and not h.dead:
			return
	for ev in evidence:
		if not ev[1] and not ev[2]:
			return
	if bomb and not bomb_defused:
		return
	if M.finale != "van":
		hud.radio(COLONEL, "الموقع آمن. عمل ممتاز يا الصقر ١، رجعوا الكل سالمين.", 4.0)
		_end(true, "")
		return
	if chase_pending:
		return
	chase_pending = true
	hud.radio(COLONEL, "المصرف آمن. عمل ممتاز… لحظة، شو صاير ورا المبنى؟", 3.5)
	await get_tree().create_timer(3.0).timeout
	if ended or not player.alive:
		return
	_start_chase()

func _end(win: bool, reason: String) -> void:
	if ended:
		return
	ended = true
	await get_tree().create_timer(1.6 if win else 2.2, true, false, true).timeout
	phase = "result"
	Engine.time_scale = 1.0
	_capture_mouse(false)
	var st: Dictionary = player.stats
	var acc: float = (100.0 * st.hits / st.shots) if st.shots > 0 else 0.0
	var kills := 0
	for e in enemies:
		if e.dead:
			kills += 1
	var lines := [
		"الوقت: %02d:%02d" % [int(mission_time) / 60, int(mission_time) % 60],
		M.title,
		"اعتقالات: %d    ·    تحييد: %d" % [arrests, kills],
		"دقة الإصابة: %d%%    ·    طلقات في الرأس: %d" % [int(acc), st.heads],
		"خسائر الفريق: %d    ·    مخالفات: %d    ·    مدنيون مصابون: %d" % [team_lost, violations, civilians_hit],
	]
	if hostages.size() > 0:
		lines.insert(2, "الرهائن المحررون: %d / %d" % [hostages_saved, hostages.size()])
	if evidence.size() > 0:
		lines.insert(2, "الأدلة المحرّزة: %d / %d" % [evidence_got, evidence.size()])
	if bomb:
		lines.insert(2, "العبوة: %s" % ("معطّلة ✔" if bomb_defused else "انفجرت ✖"))
	if M.finale == "van":
		lines.insert(2, ("%s: معتقل ✔" % LEADER) if leader_cuffed else ("%s: هارب ✖" % LEADER))
	if reason != "":
		lines.push_front(reason)
	var rating := ""
	if win:
		var score: float = 55.0 + arrests * 5.0 + acc * 0.15 + hostages_saved * 6.0 - hostages_lost * 15.0 - violations * 15.0 - team_lost * 8.0 - maxf(mission_time - 420.0, 0.0) * 0.05
		score += evidence_got * 6.0 - evidence_lost * 10.0 + (10.0 if bomb_defused else 0.0)
		rating = "ممتاز ★★★" if score >= 90 else ("جيد جداً ★★" if score >= 70 else "مقبول ★")
		Missions.complete(Missions.current, rating)
	hud.show_result(win, "المهمة ناجحة" if win else "فشلت المهمة", lines, rating)

# ------------------------------------------------------------------ callbacks used by actors / player
func enemy_targets() -> Array:
	var out := []
	if player.active and player.alive:
		out.append(player)
	for t in team:
		if not t.dead and t.visible:
			out.append(t)
	return out

func listener_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO

## Gunmen shout when they spot the police or give up (rate-limited so they don't talk over each other).
func enemy_shout(e, kind: String) -> void:
	if phase != "assault" or sniper_mission:
		return
	if kind == "alert" and (shout_cd > 0.0 or e.global_position.distance_to(player.global_position) > 30.0):
		return
	shout_cd = 7.0
	hud.radio("مسلّح", (ENEMY_ALERT if kind == "alert" else ENEMY_SURRENDER).pick_random(), 2.2)

## Talk to a bystander / the TV reporter: they turn to you, say their piece, you answer.
func _talk_civilian(p: Node3D, kind: String) -> void:
	talk_cd = 6.0
	var to: Vector3 = player.global_position - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	var prev: String = p.pose.mode
	if peds:
		for pd in peds.peds:
			if pd.node == p:
				pd.talk = 5.0
	p.set_mode("talk")
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(p) and p.pose.mode == "talk":
			p.set_mode(prev))
	if kind == "reporter":
		hud.radio("المراسلة", REPORTER_LINES.pick_random(), 3.5)
		hud.radio("الصقر ١", "ما في تصريح هلأ. ارجعوا ورا الشريط.", 2.5)
	else:
		hud.radio("مواطن", (CROWD_LINES if kind == "crowd" else PED_LINES).pick_random(), 3.0)
		hud.radio("الصقر ١", PLAYER_REPLIES.pick_random(), 2.5)

## Nearest person you can talk to: [node, kind] or null.
func _near_civilian(pp: Vector3):
	var best = null
	var bd := 2.8
	for i in crowd.size():
		var p: Node3D = crowd[i]
		var d := pp.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = [p, "reporter" if p.pose.mode in ["mic", "camera"] else "crowd"]
	if peds:
		for pd in peds.peds:
			if pd.down > 0.0 or pd.flee > 0.0:
				continue
			var d2 := pp.distance_to(pd.node.global_position)
			if d2 < bd:
				bd = d2
				best = [pd.node, "ped"]
	return best

func on_gunfire(from: Vector3) -> void:
	# the crowd behind the tape ducks when shots ring out
	if duck_t <= 0.0 and crowd.size() > 0 and from.distance_to(city.cordon_point) < 90.0:
		hud.radio("مواطن", "يا ساتر! طخّ! انزلوا عالأرض!", 2.0)
	duck_t = 5.0
	if peds:
		peds.panic(from)
	for e in enemies:
		if not e.dead and not e.surrendered and e.global_position.distance_to(from) < 22.0:
			e.alert(from)

func _on_player_shot(pos: Vector3) -> void:
	on_gunfire(pos)

func on_civilian_hit() -> void:
	violations += 1
	civilians_hit += 1
	hud.radio(COLONEL, "الصقر ١! دهست مدني! انتبه على الطريق!", 3.0)

func on_violation() -> void:
	violations += 1
	hud.radio("قائد العمليات", "الصقر ١! المشتبه كان مستسلماً! التزم بقواعد الاشتباك!", 3.0)

func on_actor_dead(a, head: bool, from) -> void:
	if a.side == "team":
		team_lost += 1
		hud.radio("الصقر ١", "سقط %s! رجل مصاب!" % a.display_name, 3.0)
		if a.escort_h and is_instance_valid(a.escort_h):
			a.escort_h.escort = null
			hud.radio("الصقر ١", "الرهينة لحالها! تعالي ورايا!", 2.5)
			a.escort_h = null
		return
	if from == player:
		player.stats.kills += 1
		if head:
			player.stats.heads += 1
		hud.feed("إصابة بالراس · تحييد" if head else "تحييد")
	if phase == "assault":
		mission_assault_text()
	if phase == "sniper":
		# the others see their friend drop and go for the hostages / look for the shooter
		for o in enemies:
			if o != a and not o.dead and o.global_position.distance_to(a.global_position) < 16.0 and o.can_see(a.global_position + Vector3(0, 0.8, 0)):
				o.alert(a.global_position)
		sniper_text()
		hud.radio("الفريق الأرضي", ["إصابة مؤكدة.", "الهدف سقط.", "تم التحييد، كمّل.", "ضربة نظيفة."].pick_random(), 1.8)
	_check_win()

func on_team_kill(_a) -> void:
	hud.radio(_a.display_name, ["تم تحييد مسلّح!", "مسلّح سقط!", "الهدف محيّد!"].pick_random(), 2.0)

func on_player_hit(killed: bool, _head: bool) -> void:
	hud.hit_marker(killed)
	Sfx.play("hit", -6.0)

func on_player_damaged(from) -> void:
	hud.damage_flash(from if from is Node3D else null)

func on_player_dead() -> void:
	hud.radio("قائد العمليات", "الصقر ١ لا يستجيب! الصقر ١!", 3.0)
	_end(false, "سقطت أثناء الاقتحام.")

func on_hostage_dead(_h, from) -> void:
	hostages_lost += 1
	mission_assault_text()
	if phase == "sniper":
		sniper_text()
		if hostages_lost >= hostages.size() and from != player:
			_end(false, "أعدموا كل الرهائن.")
			return
	if from == player:
		_end(false, "قُتلت رهينة بنيرانك.")
	else:
		_check_win()

# ------------------------------------------------------------------ mouse
func _capture_mouse(on: bool) -> void:
	if Controls.is_touch:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if not loaded:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if phase not in ["brief", "result"] and hud and not get_tree().paused:
			hud.toggle_pause()

func _unhandled_input(e: InputEvent) -> void:
	if not loaded:
		return
	if cutscene_t > 0.0 and ((e is InputEventKey and e.pressed and not e.echo) or (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed)):
		get_viewport().set_input_as_handled()
		hud.clear_radio()
		_end_dialogue_cam()
		return
	if phase == "intro" and intro_t > 0.5 and intro_i < 3:
		if (e is InputEventKey and e.pressed) or (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			get_viewport().set_input_as_handled()
			input_guard = 0.4
			Controls.block_fire()
			_begin_drive()
			return
	if e.is_action_pressed("pause") and phase not in ["brief", "result", "intro"]:
		hud.toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if Controls.is_touch:
		return
	if e is InputEventMouseButton and e.pressed and phase not in ["brief", "result", "intro"] and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		_capture_mouse(true)
		Controls.block_fire()
		get_viewport().set_input_as_handled()

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
var night := false
var executioners: Array = []

const TEAM_NAMES := ["الصقر ٢", "الصقر ٣", "الصقر ٤", "الصقر ٥"]
const TEAM_OFFSETS := [Vector3(-1.4, 0, 2.0), Vector3(1.4, 0, 2.2), Vector3(-1.6, 0, 4.2), Vector3(1.6, 0, 4.4)]

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
	_environment()
	city = Node3D.new()
	city.set_script(City)
	add_child(city)
	city.build(7, M)
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
	_setup_nav()
	traffic = Node3D.new()
	traffic.set_script(Traffic)
	add_child(traffic)
	traffic.main = self
	traffic.setup(city, 14 if CustomModels.files_for("res://assets/cars", "sedan").size() > 0 else 22)
	vehicle = VehicleBody3D.new()
	vehicle.set_script(Vehicle)
	vehicle.main = self
	add_child(vehicle)
	vehicle.global_transform = city.spawn_point
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
	ambience = AudioStreamPlayer.new()
	ambience.stream = Sfx.streams["ambience"]
	ambience.volume_db = -14.0
	add_child(ambience)
	ambience.play()
	peds = Node3D.new()
	peds.set_script(Pedestrians)
	add_child(peds)
	peds.setup(self)
	_spawn_objectives()
	cine_cam = Camera3D.new()
	cine_cam.fov = 55; cine_cam.far = 1500
	add_child(cine_cam)
	cine_cam.current = true
	hud = CanvasLayer.new()
	hud.set_script(Hud)
	hud.main = self
	add_child(hud)
	hud.set_letterbox(true)
	if Missions.autostart:
		Missions.autostart = false
		_start_mission.call_deferred()
	else:
		hud.show_briefing(_start_mission)

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
	sm.sky_top_color = {"golden": Color(0.24, 0.42, 0.68), "night": Color(0.01, 0.015, 0.05), "morning": Color(0.3, 0.52, 0.85)}[sky_kind]
	sm.sky_horizon_color = {"golden": Color(0.93, 0.76, 0.56), "night": Color(0.12, 0.1, 0.16), "morning": Color(0.78, 0.84, 0.9)}[sky_kind]
	sm.ground_horizon_color = Color(0.75, 0.62, 0.5) if sky_kind != "night" else Color(0.08, 0.07, 0.08)
	sm.ground_bottom_color = Color(0.3, 0.26, 0.22) if sky_kind != "night" else Color(0.02, 0.02, 0.03)
	sm.sun_angle_max = 20.0
	sm.sun_curve = 0.12
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = {"golden": 0.7, "night": 0.45, "morning": 0.8}[sky_kind]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = {"golden": Color(0.86, 0.74, 0.6), "night": Color(0.06, 0.06, 0.1), "morning": Color(0.82, 0.86, 0.9)}[sky_kind]
	env.fog_density = 0.0028
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = {"golden": Vector3(-24, -128, 0), "night": Vector3(-55, 40, 0), "morning": Vector3(-42, 70, 0)}[sky_kind]
	sun.light_color = {"golden": Color(1.0, 0.84, 0.64), "night": Color(0.55, 0.65, 1.0), "morning": Color(1.0, 0.96, 0.88)}[sky_kind]
	sun.light_energy = {"golden": 1.5, "night": 0.22, "morning": 1.35}[sky_kind]
	if sky_kind == "night":
		env.glow_intensity = 0.9
		env.glow_hdr_threshold = 0.9
		env.tonemap_exposure = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.04
	add_child(sun)

# ------------------------------------------------------------------ mission flow
func _start_mission() -> void:
	diff_react = [0.95, 0.6, 0.38][difficulty]
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
		[c + Vector3(-16, 2.2, 26), c + Vector3(9, 3.2, 21), c + Vector3(0, 2.2, 0), 6.5],
		[vp + Vector3(-7, 1.4, -9), vp + Vector3(5, 2.2, -8), vp + Vector3(0, 1.0, 0), 6.0],
	]
	intro_i = -1
	_next_shot()

func _next_shot() -> void:
	intro_i += 1
	intro_t = 0.0
	hud.clear_radio()
	match intro_i:
		0:
			hud.show_banner("عاجل", M.news, 5.5)
			hud.radio("نشرة الأخبار", M.news_line, 5.8)
		1:
			hud.radio(NEGOTIATOR if M.id != "raid" else "فريق المراقبة", M.negotiator_line, 6.3)
		2:
			hud.radio(COLONEL, M.commander_line, 5.8)
		_:
			_begin_drive()

func _begin_drive() -> void:
	phase = "drive"
	intro_i = 99
	hud.set_letterbox(false)
	hud.set_prompt("")
	vehicle.set_driving(true)
	_capture_mouse(true)
	hud.clear_radio()
	hud.radio("غرفة العمليات", "إلى الصقر ١: الطريق إلى %s مفتوح، الدوريات سكّرت الشوارع الفرعية." % M.area, 4.5)
	hud.radio("الصقر ٢", "الفريق جاهز بالخلف يا سيدي. عبوة الاقتحام معنا." if team_size > 0 else "الوحدة المساندة عالقة بالأزمة. أنت لوحدك يا الصقر ١.", 4.0)
	hud.show_banner(M.title, "%s · %s" % [M.area, M.clock], 3.5)
	hud.set_waypoint(city.cordon_point + Vector3(0, 1, 0))
	hud.set_objectives(["◆ قُد السيارة إلى الطوق الأمني – %s" % M.title, "◇ [H] صفارة · [E] زمّور · [F] نزول/ركوب"])

func _arrive() -> void:
	phase = "arrive"
	hud.clear_radio()
	hud.radio(COLONEL, "الصقر ١، أنا عند الطوق. انزل وتعال لعندي.", 4.0)
	hud.set_waypoint(colonel.global_position + Vector3(0, 2.2, 0))
	hud.set_objectives(["◆ انزل من السيارة [F]", "◆ تحدّث مع %s [E]" % COLONEL])

func _talk_colonel() -> void:
	if talked:
		return
	talked = true
	phase = "staging"
	hud.clear_radio()
	var n := enemies.size()
	var situation := "الوضع: %d مسلّحين على الأقل" % n
	if hostages.size() > 0:
		situation += "، و%d رهائن جوّا" % hostages.size()
	if evidence.size() > 0:
		situation += "، و%d أدلة لازم نحصّلها" % evidence.size()
	hud.radio(COLONEL, situation + ".", 4.5)
	for line in M.brief:
		hud.radio(COLONEL, line, 5.0)
	hud.radio(COLONEL, "معك %d قنابل صوتية [G] — ارمِها بالغرف قبل ما تدخل." % flashbangs, 4.0)
	if M.finale == "van":
		hud.radio(NEGOTIATOR, "انتبه… %s ذكي. ما بستبعد يكون عامل طريق هروب." % LEADER, 4.0)
	hud.set_waypoint(city.door_pos + Vector3(0, 1.6, 1.6))
	hud.set_objectives(["◆ تقدّم إلى الباب الرئيسي", "◆ ازرع عبوة الاقتحام [E]"])

func _plant_charge() -> void:
	phase = "breach"
	hud.set_prompt("")
	hud.clear_radio()
	hud.radio("الصقر ١", "العبوة مزروعة! ابتعدوا عن الباب!", 2.5)
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
	lines.append("◇ [Q] استسلام · [G] قنبلة صوتية (%d)" % flashbangs)
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
		cine_cam.global_position = (sh[0] as Vector3).lerp(sh[1], k)
		cine_cam.look_at(sh[2])
		hud.set_prompt("اضغط للتخطّي")
		if intro_t >= sh[3]:
			_next_shot()
		return
	if phase == "result":
		return
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
	if phase in ["drive", "arrive", "staging"]:
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
	if Controls.just("flash") and not in_vehicle and player.alive and phase in ["staging", "breach", "assault"] and input_guard <= 0.0:
		_throw_flashbang()
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
	_interactions()
	if phase == "assault" and Controls.just("yell") and not in_vehicle and input_guard <= 0.0:
		_yell()

func timer_text() -> String:
	if bomb and not bomb_defused and phase in ["drive", "arrive", "staging", "breach", "assault"]:
		var tb := maxf(bomb_t, 0.0)
		return "العبوة  %02d:%02d" % [int(tb) / 60, int(tb) % 60]
	if phase in ["drive", "arrive", "staging"] and M.deadline > 0.0:
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
	return (phase in ["drive", "arrive", "staging"] and M.deadline > 0.0 and deadline < 60.0) or (phase == "chase" and chase_t > 180.0)

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
	var pp := player.global_position
	var text := ""
	var action := Callable()
	if phase == "arrive" and pp.distance_to(colonel.global_position) < 3.0:
		text = "[E] تحدّث مع %s" % COLONEL
		action = _talk_colonel
	elif phase == "staging":
		if pp.distance_to(city.door_pos + Vector3(0, 0, 1.6)) < 2.6:
			text = "[E] ازرع عبوة الاقتحام"
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
	if text == "" and pp.distance_to(vehicle.global_position) < 4.5:
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
func _throw_flashbang() -> void:
	if flashbangs <= 0:
		hud.show_banner("", "خلصت القنابل الصوتية", 1.2)
		return
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
	hud.radio("الصقر ١", "قنبلة صوتية!", 1.5)
	mission_assault_text()
	get_tree().create_timer(1.3).timeout.connect(func(): _flashbang_bang(g))

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
	hud.radio("الصقر ١", "المشتبه مكبّل!", 2.0)
	mission_assault_text()
	_check_win()

func _free(h) -> void:
	h.free_hostage(trail.size())
	Sfx.play("cuff", -4.0, 0.8)
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
	if team_size > 0:
		if not team_spawned:
			team_spawned = true
			for i in team_size:
				var t := CharacterBody3D.new()
				t.set_script(Actor)
				t.setup(self, "team", Vector3.ZERO, player.yaw, TEAM_NAMES[i])
				t.follow_offset = TEAM_OFFSETS[i]
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
			t.global_position = _free_spot(cands, [vehicle.get_rid(), player.get_rid()])
			t.rotation.y = player.yaw

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
	if ended or phase != "assault":
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

func on_gunfire(from: Vector3) -> void:
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
	if phase == "assault":
		mission_assault_text()
	_check_win()

func on_team_kill(_a) -> void:
	hud.radio(_a.display_name, ["تم تحييد مسلّح!", "مسلّح سقط!", "الهدف محيّد!"].pick_random(), 2.0)

func on_player_hit(killed: bool, _head: bool) -> void:
	hud.hit_marker(killed)
	Sfx.play("hit", -6.0)

func on_player_damaged(_from) -> void:
	hud.damage_flash()

func on_player_dead() -> void:
	hud.radio("قائد العمليات", "الصقر ١ لا يستجيب! الصقر ١!", 3.0)
	_end(false, "سقطت أثناء الاقتحام.")

func on_hostage_dead(_h, from) -> void:
	hostages_lost += 1
	mission_assault_text()
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
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if phase not in ["brief", "result"] and hud and not get_tree().paused:
			hud.toggle_pause()

func _unhandled_input(e: InputEvent) -> void:
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

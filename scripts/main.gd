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

const TEAM_NAMES := ["الصقر ٢", "الصقر ٣", "الصقر ٤", "الصقر ٥"]
const TEAM_OFFSETS := [Vector3(-1.4, 0, 2.0), Vector3(1.4, 0, 2.2), Vector3(-1.6, 0, 4.2), Vector3(1.6, 0, 4.4)]

func _ready() -> void:
	_environment()
	city = Node3D.new()
	city.set_script(City)
	add_child(city)
	city.build(7)
	city.build_cordon()
	city.merge_static()
	traffic = Node3D.new()
	traffic.set_script(Traffic)
	add_child(traffic)
	traffic.setup(city, 22)
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
	cine_cam = Camera3D.new()
	cine_cam.fov = 55; cine_cam.far = 1500
	add_child(cine_cam)
	cine_cam.current = true
	hud = CanvasLayer.new()
	hud.set_script(Hud)
	hud.main = self
	add_child(hud)
	hud.set_letterbox(true)
	hud.show_briefing(_start_mission)

func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.24, 0.42, 0.68)
	sm.sky_horizon_color = Color(0.93, 0.76, 0.56)
	sm.ground_horizon_color = Color(0.75, 0.62, 0.5)
	sm.ground_bottom_color = Color(0.3, 0.26, 0.22)
	sm.sun_angle_max = 20.0
	sm.sun_curve = 0.12
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.74, 0.6)
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
	sun.rotation_degrees = Vector3(-24, -128, 0)
	sun.light_color = Color(1.0, 0.84, 0.64)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.04
	add_child(sun)

# ------------------------------------------------------------------ mission flow
func _start_mission() -> void:
	diff_react = [0.95, 0.6, 0.38][difficulty]
	var n_enemies: int = [6, 8, 9][difficulty]
	var spawns: Array = city.enemy_spawns.duplicate()
	spawns.shuffle()
	for i in minf(n_enemies, spawns.size()):
		var e := CharacterBody3D.new()
		e.set_script(Actor)
		e.setup(self, "enemy", spawns[i] + Vector3(randf_range(-0.6, 0.6), 0.1, randf_range(-0.6, 0.6)), randf() * TAU)
		e.accuracy = [0.28, 0.4, 0.55][difficulty]
		e.damage = [6.0, 9.0, 13.0][difficulty]
		add_child(e)
		enemies.append(e)
	phase = "drive"
	hud.close_briefing()
	hud.set_letterbox(false)
	vehicle.set_driving(true)
	_capture_mouse(true)
	hud.radio("غرفة العمليات", "إلى جميع الوحدات: بلاغ عبر ٩١١ عن إطلاق نار داخل «مصرف الشرق» – جبل عمّان، شارع الرينبو.", 5.0)
	hud.radio("قائد العمليات", "الصقر ١، هنا القيادة. المفاوضات فشلت والمسلحون يهددون الرهائن. توجّه فوراً إلى الطوق الأمني.", 5.5)
	hud.radio("الصقر ٢", "الفريق جاهز بالخلف يا سيدي. المعدّات وعبوة الاقتحام معنا." if team_size > 0 else "الوحدة المساندة عالقة بالأزمة. أنت لوحدك يا الصقر ١.", 4.0)
	hud.show_banner("وحدة الصقر", "مصرف الشرق · جبل عمّان · ٥:٤٢ م", 3.5)
	hud.set_waypoint(city.cordon_point + Vector3(0, 1, 0))
	hud.set_objectives(["◆ قُد السيارة إلى الطوق الأمني أمام المصرف", "◇ [H] تشغيل/إيقاف الصفارة · [F] نزول"])

func _arrive() -> void:
	phase = "staging"
	hud.clear_radio()
	hud.radio("قائد العمليات", "وصلتم. اترجّلوا وتقدّموا إلى الباب الرئيسي. ازرع عبوة الاقتحام عند إشارتك.", 5.0)
	hud.radio("القنّاص", "أرصد حركة خلف الزجاج… لا يوجد خط رمي آمن. القرار لكم.", 4.0)
	hud.set_waypoint(city.door_pos + Vector3(0, 1.6, 1.6))
	hud.set_objectives(["◆ ترجّل [F] وتقدّم إلى باب المصرف", "◆ ازرع عبوة الاقتحام [E]"])

func _plant_charge() -> void:
	phase = "breach"
	hud.set_prompt("")
	hud.radio("الصقر ١", "العبوة مزروعة! ابتعدوا عن الباب!", 2.5)
	Sfx.play("beep")
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
	hud.radio("قائد العمليات", "اقتحام! اقتحام! اقتحام!", 2.0)
	hud.radio("الصقر ١", "أمن عام! الكل على الأرض!", 2.5)

func mission_assault_text() -> void:
	var alive := 0
	var cuffed := 0
	for e in enemies:
		if e.cuffed:
			cuffed += 1
		elif not e.dead:
			alive += 1
	var hs := 0
	for h in hostages:
		if h.rescued:
			hs += 1
	var lines := [
		"◆ المسلحون المتبقّون: %d" % alive,
		"◆ حرّر الرهائن [E] (%d / %d)" % [hs, hostages.size()],
		"◇ [Q] أمر بالاستسلام · [E] تكبيل المستسلم",
	]
	hud.set_objectives(lines)
	# waypoint to nearest hostage still waiting
	var best = null
	var bd := 1e9
	for h in hostages:
		if not h.rescued and not h.dead:
			var d: float = h.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d; best = h
	hud.set_waypoint(best.global_position + Vector3(0, 1.4, 0) if best else null)

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
	# vehicle enter / exit
	if Controls.just("vehicle"):
		if in_vehicle:
			_exit_vehicle()
		elif player.alive and player.global_position.distance_to(vehicle.global_position) < 4.5:
			_enter_vehicle()
	if phase == "drive":
		var ref: Vector3 = vehicle.global_position if in_vehicle else player.global_position
		if ref.distance_to(city.cordon_point) < 24.0:
			_arrive()
	_interactions()
	if phase == "assault" and Controls.just("yell") and not in_vehicle:
		_yell()

func _interactions() -> void:
	if in_vehicle or not player.alive:
		hud.set_prompt("")
		return
	var pp := player.global_position
	var text := ""
	var action := Callable()
	if phase == "staging" or phase == "drive":
		if pp.distance_to(city.door_pos + Vector3(0, 0, 1.6)) < 2.6:
			text = "[E] ازرع عبوة الاقتحام"
			action = _plant_charge
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
				if not h.rescued and not h.dead:
					var d: float = pp.distance_to(h.global_position)
					if d < bd:
						bd = d; best = h
			if best:
				text = "[E] فكّ وثاق الرهينة"
				action = func(): _rescue(best)
	if text == "" and pp.distance_to(vehicle.global_position) < 4.5:
		text = "[F] ركوب السيارة"
	hud.set_prompt(text)
	if action.is_valid() and Controls.just("interact"):
		action.call()

func _cuff(e) -> void:
	e.cuffed = true
	arrests += 1
	Sfx.play("cuff")
	var tw := create_tween()
	tw.tween_property(e.model, "position:y", -0.55, 0.4)
	hud.radio("الصقر ١", "المشتبه مكبّل!", 2.0)
	mission_assault_text()
	_check_win()

func _rescue(h) -> void:
	h.rescue()
	hostages_saved += 1
	Sfx.play("cuff", -4.0, 0.8)
	hud.radio("الصقر ١", ["أنتِ بأمان الآن، اخرجي من الباب بسرعة!", "تم تحرير رهينة، أرسلوا الإسعاف!", "انزل وامشِ خلفي… أنت بأمان."].pick_random(), 3.0)
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
	var b := vehicle.global_transform.basis
	var out := vehicle.global_position + b.x * 1.9
	out.y = maxf(vehicle.global_position.y, 0.2)
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
			t.global_position = vehicle.global_position - b.x * 1.9 + b.z * (-1.5 - i * 1.2)
			t.global_position.y = out.y
			t.rotation.y = player.yaw

func _enter_vehicle() -> void:
	in_vehicle = true
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
	_end(true, "")

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
		"الرهائن المحررون: %d / %d" % [hostages_saved, hostages.size()],
		"اعتقالات: %d    ·    تحييد: %d" % [arrests, kills],
		"دقة الإصابة: %d%%    ·    طلقات في الرأس: %d" % [int(acc), st.heads],
		"خسائر الفريق: %d    ·    مخالفات: %d" % [team_lost, violations],
	]
	if reason != "":
		lines.push_front(reason)
	var rating := ""
	if win:
		var score: float = 60.0 + arrests * 6.0 + acc * 0.15 - violations * 15.0 - team_lost * 8.0 - maxf(mission_time - 240.0, 0.0) * 0.05
		rating = "ممتاز ★★★" if score >= 90 else ("جيد جداً ★★" if score >= 70 else "مقبول ★")
		hud.radio("قائد العمليات", "عمل ممتاز يا الصقر ١. الموقع آمن، الإسعاف يتسلّم الرهائن.", 5.0)
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
	for e in enemies:
		if not e.dead and not e.surrendered and e.global_position.distance_to(from) < 22.0:
			e.alert(from)

func _on_player_shot(pos: Vector3) -> void:
	on_gunfire(pos)

func on_violation() -> void:
	violations += 1
	hud.radio("قائد العمليات", "الصقر ١! المشتبه كان مستسلماً! التزم بقواعد الاشتباك!", 3.0)

func on_actor_dead(a, head: bool, from) -> void:
	if a.side == "team":
		team_lost += 1
		hud.radio("الصقر ١", "سقط %s! رجل مصاب!" % a.display_name, 3.0)
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

func _unhandled_input(e: InputEvent) -> void:
	if Controls.is_touch:
		return
	if e.is_action_pressed("pause"):
		_capture_mouse(false)
	elif e is InputEventMouseButton and e.pressed and phase not in ["brief", "result"] and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)

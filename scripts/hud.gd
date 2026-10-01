extends CanvasLayer
## All 2D UI: briefing, mission HUD, radio subtitles, waypoint, minimap, results, touch controls.

var main: Node
var font: Font
var root: Control
var objectives: Label
var timer_lbl: Label
var radio_box: PanelContainer
var radio_who: Label
var radio_txt: Label
var banner: Label
var banner_sub: Label
var prompt: Label
var crosshair: Control
var hitmark: Control
var hit_t := 0.0
var hit_kill := false
var vignette: TextureRect
var vig_a := 0.0
var hp_bar: ProgressBar
var ammo_lbl: Label
var speed_lbl: Label
var waypoint: Control
var wp_lbl: Label
var wp_target = null
var minimap: Control
var briefing: Control
var result: Control
var touch_root: Node2D
var touch_buttons := {}
var radio_queue: Array = []
var radio_t := 0.0
var banner_t := 0.0
var countdown_lbl: Label
var letterbox: Array = []
var _timer_red := false
var pause_menu: Control

# touch state
var joy_finger := -1
var joy_origin := Vector2.ZERO
var look_finger := -1
var look_last := Vector2.ZERO
var joy_ring: Control

const GOLD := Color(0.96, 0.8, 0.35)
const BLUE := Color(0.45, 0.72, 1.0)

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = load("res://assets/fonts/Tajawal-Bold.ttf")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_hud()
	if Controls.is_touch:
		_build_touch()

# ------------------------------------------------------------------ helpers
func _label(text: String, size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _panel_style(col := Color(0.03, 0.05, 0.08, 0.72), border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	if border.a > 0:
		sb.border_color = border
		sb.border_width_right = 4
	return sb

func _button(text: String, cb: Callable, size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	var n := _panel_style(Color(0.08, 0.12, 0.18, 0.9)); n.border_color = Color(1, 1, 1, 0.15); n.set_border_width_all(1)
	var h := _panel_style(Color(0.15, 0.22, 0.32, 0.95)); h.border_color = GOLD; h.set_border_width_all(2)
	var p := _panel_style(GOLD.darkened(0.3))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", h)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b

# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	# damage vignette
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0, 0, 0)); g.set_color(1, Color(0.55, 0, 0, 0.85))
	g.add_point(0.55, Color(0.6, 0, 0, 0))
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.05, 1.05); gt.width = 256; gt.height = 256
	vignette = TextureRect.new(); vignette.texture = gt
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0
	root.add_child(vignette)
	# cinematic letterbox bars
	for top in [true, false]:
		var bar := ColorRect.new(); bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size.y = 0
		bar.size.y = 0
		root.add_child(bar)
		letterbox.append(bar)
	# objectives (top right, Arabic is RTL)
	var op := PanelContainer.new()
	op.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.05, 0.08, 0.6), GOLD))
	op.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	op.position = Vector2(-20, 18)
	op.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	op.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(op)
	objectives = _label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	op.add_child(objectives)
	timer_lbl = _label("", 22, Color(1, 1, 1, 0.85))
	timer_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_lbl.position = Vector2(-160, 14); timer_lbl.size = Vector2(320, 30)
	root.add_child(timer_lbl)
	# minimap (top left)
	minimap = Control.new()
	minimap.position = Vector2(20, 18)
	minimap.size = Vector2(190, 190)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)
	# radio subtitles
	radio_box = PanelContainer.new()
	radio_box.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.04, 0.07, 0.78), BLUE))
	radio_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	radio_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	radio_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	radio_box.position.y = -150
	radio_box.custom_minimum_size = Vector2(640, 0)
	radio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radio_box.visible = false
	root.add_child(radio_box)
	var vb := VBoxContainer.new(); vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radio_box.add_child(vb)
	radio_who = _label("", 20, BLUE, HORIZONTAL_ALIGNMENT_RIGHT)
	radio_txt = _label("", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	radio_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	radio_txt.custom_minimum_size.x = 600
	vb.add_child(radio_who); vb.add_child(radio_txt)
	# banner
	banner = _label("", 64, GOLD)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position.y = -170
	banner.modulate.a = 0
	root.add_child(banner)
	banner_sub = _label("", 26, Color.WHITE)
	banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	banner_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_sub.position.y = -95
	banner_sub.modulate.a = 0
	root.add_child(banner_sub)
	countdown_lbl = _label("", 120, Color(1, 0.35, 0.25))
	countdown_lbl.set_anchors_preset(Control.PRESET_CENTER)
	countdown_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	countdown_lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(countdown_lbl)
	# interaction prompt
	prompt = _label("", 28, Color.WHITE)
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.position.y = 70
	root.add_child(prompt)
	# crosshair + hitmarker
	crosshair = Control.new(); crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.draw.connect(func():
		var a := 0.85
		var gap: float = 6.0 + (1.0 - (main.player.aim if main and main.player else 0.0)) * 6.0
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			crosshair.draw_line(d * gap, d * (gap + 9), Color(0, 0, 0, 0.6), 4)
			crosshair.draw_line(d * gap, d * (gap + 9), Color(1, 1, 1, a), 2)
		crosshair.draw_circle(Vector2.ZERO, 1.6, Color(1, 1, 1, a)))
	root.add_child(crosshair)
	hitmark = Control.new(); hitmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmark.set_anchors_preset(Control.PRESET_CENTER)
	hitmark.draw.connect(func():
		var c := Color(1, 0.25, 0.2) if hit_kill else Color.WHITE
		c.a = clampf(hit_t * 4.0, 0, 1)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			hitmark.draw_line(d * 7, d * 15, c, 3))
	root.add_child(hitmark)
	# health + ammo (bottom)
	var bl := VBoxContainer.new(); bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(24, -80)
	root.add_child(bl)
	bl.add_child(_label("الصحة", 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT))
	hp_bar = ProgressBar.new(); hp_bar.custom_minimum_size = Vector2(260, 14); hp_bar.show_percentage = false
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.5); bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new(); fg.bg_color = Color(0.85, 0.9, 0.95); fg.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("background", bg); hp_bar.add_theme_stylebox_override("fill", fg)
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.add_child(hp_bar)
	ammo_lbl = _label("", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	ammo_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_lbl.position = Vector2(-30, -30)
	root.add_child(ammo_lbl)
	speed_lbl = _label("", 54, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	speed_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	speed_lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	speed_lbl.position = Vector2(-30, -30)
	root.add_child(speed_lbl)
	# waypoint
	waypoint = Control.new(); waypoint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	waypoint.draw.connect(func():
		var pts := PackedVector2Array([Vector2(0, -14), Vector2(11, 0), Vector2(0, 14), Vector2(-11, 0)])
		waypoint.draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
		var inner := PackedVector2Array([Vector2(0, -10), Vector2(8, 0), Vector2(0, 10), Vector2(-8, 0)])
		waypoint.draw_colored_polygon(inner, GOLD))
	root.add_child(waypoint)
	wp_lbl = _label("", 18, GOLD)
	wp_lbl.position = Vector2(-40, 16); wp_lbl.size = Vector2(80, 24)
	waypoint.add_child(wp_lbl)

# ------------------------------------------------------------------ public API
const TOUCH_HINTS := {"[E]": "(زر تفاعل)", "[F]": "(زر سيارة)", "[H]": "(زر صفارة)", "[Q]": "(زر استسلم!)", "[R]": "(زر تعبئة)"}

## On phones, replace keyboard key hints with the on-screen button names.
func _touchify(t: String) -> String:
	if not Controls.is_touch:
		return t
	for k in TOUCH_HINTS:
		t = t.replace(k, TOUCH_HINTS[k])
	return t.replace("اضغط E", "اضغط زر التفاعل")

func set_objectives(lines: Array) -> void:
	objectives.text = _touchify("\n".join(lines))

func radio(who: String, text: String, dur := 4.0) -> void:
	radio_queue.append([who, text, dur])

func clear_radio() -> void:
	radio_queue.clear()
	radio_t = 0.0

func show_banner(text: String, sub := "", dur := 3.0) -> void:
	banner.text = text
	banner_sub.text = _touchify(sub)
	banner_t = dur
	var tw := create_tween()
	banner.scale = Vector2(1.15, 1.15)
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(banner_sub, "modulate:a", 1.0, 0.4)

func set_prompt(text: String) -> void:
	prompt.text = _touchify(text)

func hit_marker(kill: bool) -> void:
	hit_t = 0.3
	hit_kill = kill

func damage_flash() -> void:
	vig_a = minf(vig_a + 0.45, 1.0)

func set_waypoint(p) -> void:
	wp_target = p

func set_letterbox(on: bool) -> void:
	var h := 70.0 if on else 0.0
	for i in letterbox.size():
		var bar: ColorRect = letterbox[i]
		var tw := create_tween()
		tw.tween_property(bar, "custom_minimum_size:y", h, 0.6)
		if i == 1:
			tw.parallel().tween_property(bar, "position:y", root.size.y - h, 0.6)

func show_countdown(t: String) -> void:
	countdown_lbl.text = t
	countdown_lbl.scale = Vector2(1.4, 1.4)
	countdown_lbl.pivot_offset = countdown_lbl.size * 0.5
	var tw := create_tween()
	tw.tween_property(countdown_lbl, "scale", Vector2.ONE, 0.3)

# ------------------------------------------------------------------ per-frame
func _process(dt: float) -> void:
	var udt: float = dt / maxf(Engine.time_scale, 0.05)
	# radio
	if radio_t > 0.0:
		radio_t -= udt
		if radio_t <= 0.0:
			radio_box.visible = false
	elif radio_queue.size() > 0:
		var m: Array = radio_queue.pop_front()
		radio_who.text = "◉  " + m[0]
		radio_txt.text = m[1]
		radio_t = m[2]
		radio_box.visible = true
		Sfx.play("beep", -10.0)
	# banner
	if banner_t > 0.0:
		banner_t -= udt
		banner.scale = banner.scale.lerp(Vector2.ONE, 1.0 - exp(-udt * 8.0))
		banner.pivot_offset = banner.size * 0.5
		if banner_t <= 0.0:
			var tw := create_tween()
			tw.tween_property(banner, "modulate:a", 0.0, 0.6)
			tw.parallel().tween_property(banner_sub, "modulate:a", 0.0, 0.6)
	countdown_lbl.pivot_offset = countdown_lbl.size * 0.5
	hit_t = maxf(hit_t - udt, 0.0)
	hitmark.queue_redraw()
	vig_a = maxf(vig_a - udt * 0.6, 0.0)
	if not main:
		return
	var pl = main.player
	var low: float = 1.0 - pl.hp / 100.0 if pl else 0.0
	vignette.modulate.a = maxf(vig_a, low * 0.7 if low > 0.4 else 0.0)
	var in_car: bool = main.in_vehicle
	var playing: bool = not (main.phase in ["brief", "result", "intro"])
	crosshair.visible = playing and not in_car and pl.alive
	crosshair.queue_redraw()
	hp_bar.get_parent().visible = playing and not in_car
	hp_bar.value = pl.hp
	ammo_lbl.visible = playing and not in_car
	ammo_lbl.text = ("إعادة تعبئة…" if pl.reload_t > 0.0 else "%d  ⁄  %d" % [pl.ammo, pl.reserve])
	speed_lbl.visible = playing and in_car
	if in_car:
		speed_lbl.text = "%d كم/س" % int(main.vehicle.speed_kmh)
	objectives.get_parent().visible = playing
	minimap.visible = playing
	timer_lbl.visible = playing
	timer_lbl.text = main.timer_text()
	var urgent_now: bool = main.timer_urgent() and fmod(Time.get_ticks_msec() * 0.002, 1.0) < 0.6
	if urgent_now != _timer_red:
		_timer_red = urgent_now
		timer_lbl.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if urgent_now else Color(1, 1, 1, 0.9))
	minimap.queue_redraw()
	# waypoint projection
	var cam := get_viewport().get_camera_3d()
	if wp_target != null and cam and playing:
		var p: Vector3 = wp_target
		var vs := root.size
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		if behind:
			sp = vs - sp
			sp.y = vs.y - 40
		sp.x = clampf(sp.x, 40, vs.x - 40)
		sp.y = clampf(sp.y, 60, vs.y - 60)
		waypoint.position = sp
		waypoint.visible = true
		var ref: Vector3 = main.vehicle.global_position if in_car else pl.global_position
		wp_lbl.text = "%d م" % int(ref.distance_to(p))
		waypoint.queue_redraw()
	else:
		waypoint.visible = false
	if touch_root:
		var show_touch := playing and not get_tree().paused
		if touch_root.visible and not show_touch:
			# controls are going away: forget any finger that was on the stick / look area
			joy_finger = -1
			look_finger = -1
			Controls.reset()
		touch_root.visible = show_touch
		_layout_touch()
		var near_car: bool = in_car or (pl.global_position.distance_to(main.vehicle.global_position) < 4.5)
		for k in touch_buttons:
			var b: TouchScreenButton = touch_buttons[k]
			match k:
				"siren":
					b.visible = in_car
				"fire", "aim", "reload":
					b.visible = not in_car
				"yell":
					b.visible = not in_car and main.phase == "assault"
				"interact":
					b.visible = not in_car and prompt.text != "" and not prompt.text.contains("سيارة")
				"vehicle":
					b.visible = near_car
				"jump":
					b.visible = true
					b.get_child(0).text = "فرامل" if in_car else "قفز"
				"pause":
					b.visible = true

func _draw_minimap() -> void:
	if not main or not main.city:
		return
	var c = main.city
	var sz := minimap.size
	var center := sz * 0.5
	var ref: Node3D = main.vehicle if main.in_vehicle else main.player
	var pos := ref.global_position
	var scale := 0.55  # px per meter
	minimap.draw_circle(center, sz.x * 0.5, Color(0.04, 0.06, 0.09, 0.7))
	var cam := get_viewport().get_camera_3d()
	var cam_yaw := 0.0
	if cam:
		var f := -cam.global_transform.basis.z
		cam_yaw = atan2(f.x, -f.z)
	var to_map := func(w: Vector3) -> Vector2:
		var d := Vector2(w.x - pos.x, w.z - pos.z) * scale
		return center + d.rotated(-cam_yaw)
	var R2 := sz.x * 0.5 - 4
	for k in c.N + 1:
		var rc: float = c.road_center(k)
		var a: Vector2 = to_map.call(Vector3(rc, 0, -20)); var b: Vector2 = to_map.call(Vector3(rc, 0, c.size_total + 20))
		_clip_line(a, b, center, R2, Color(0.55, 0.58, 0.62, 0.8), 6)
		a = to_map.call(Vector3(-20, 0, rc)); b = to_map.call(Vector3(c.size_total + 20, 0, rc))
		_clip_line(a, b, center, R2, Color(0.55, 0.58, 0.62, 0.8), 6)
	# objective
	if wp_target != null:
		var o: Vector2 = to_map.call(wp_target)
		if o.distance_to(center) > R2 - 6:
			o = center + (o - center).normalized() * (R2 - 6)
		minimap.draw_circle(o, 6, GOLD)
	# enemies spotted
	for e in main.enemies:
		if e.surrendered and not e.cuffed and not e.dead:
			var spos: Vector2 = to_map.call(e.global_position)
			if spos.distance_to(center) < R2:
				minimap.draw_circle(spos, 4.5, Color(1, 0.85, 0.2))
			continue
		if not e.dead and not e.surrendered and e.state == "alert" and main.door_open:
			var ep: Vector2 = to_map.call(e.global_position)
			if ep.distance_to(center) < R2:
				minimap.draw_circle(ep, 3.5, Color(1, 0.3, 0.25))
	for tm in main.team:
		if not tm.dead and tm.visible:
			var tp: Vector2 = to_map.call(tm.global_position)
			if tp.distance_to(center) < R2:
				minimap.draw_circle(tp, 3.5, BLUE)
	# player arrow (always pointing up = camera direction)
	var fwd := -ref.global_transform.basis.z if not main.in_vehicle else ref.global_transform.basis.z
	var ang := atan2(fwd.x, -fwd.z) - cam_yaw
	var arrow := PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(0, 3), Vector2(-6, 7)])
	for i in arrow.size():
		arrow[i] = center + arrow[i].rotated(ang)
	minimap.draw_colored_polygon(arrow, Color.WHITE)
	minimap.draw_arc(center, sz.x * 0.5, 0, TAU, 48, Color(1, 1, 1, 0.25), 2)

func _clip_line(a: Vector2, b: Vector2, c: Vector2, r: float, col: Color, w: float) -> void:
	# clip segment to circle
	var d := b - a
	var f := a - c
	var A := d.dot(d); var Bq := 2 * f.dot(d); var C := f.dot(f) - r * r
	var disc := Bq * Bq - 4 * A * C
	if disc <= 0:
		return
	var s := sqrt(disc)
	var t0: float = clampf((-Bq - s) / (2 * A), 0.0, 1.0)
	var t1: float = clampf((-Bq + s) / (2 * A), 0.0, 1.0)
	if t1 <= t0:
		return
	minimap.draw_line(a + d * t0, a + d * t1, col, w)

# ------------------------------------------------------------------ briefing / results
func show_briefing(on_start: Callable) -> void:
	briefing = Control.new()
	briefing.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(briefing)
	var shade := ColorRect.new(); shade.color = Color(0.0, 0.02, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	briefing.add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.04, 0.07, 0.86), GOLD))
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position.x = -40
	panel.custom_minimum_size = Vector2(560, 0)
	briefing.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(_label("وحدة الصقر", 54, GOLD, HORIZONTAL_ALIGNMENT_RIGHT))
	vb.add_child(_label("الأمن العام · العمليات الخاصة · عمّان", 20, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_RIGHT))
	var story := _label("الساعة ٥:٤٢ مساءً. مسلّحون اقتحموا «مصرف الشرق» في جبل عمّان واحتجزوا موظفين كرهائن. فشلت المفاوضات، وقائد العمليات أعطى الإذن بالاقتحام.\n\nمهمتك: قُد سيارة الوحدة إلى الطوق الأمني، فجّر الباب، حرّر الرهائن واعتقل المسلحين أحياء إن أمكن.", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size.x = 520
	vb.add_child(story)
	vb.add_child(HSeparator.new())
	vb.add_child(_label("عدد أفراد الفريق معك", 22, BLUE, HORIZONTAL_ALIGNMENT_RIGHT))
	var team_row := HBoxContainer.new(); team_row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(team_row)
	var team_btns := []
	for n in [4, 3, 2, 1, 0]:
		var b := _button(str(n), func():
			main.team_size = n
			for tb in team_btns:
				tb.modulate = Color(1, 1, 1, 0.55)
			team_btns[4 - n].modulate = Color.WHITE, 28)
		b.custom_minimum_size = Vector2(70, 56)
		b.modulate = Color.WHITE if n == main.team_size else Color(1, 1, 1, 0.55)
		team_row.add_child(b)
		team_btns.append(b)
	vb.add_child(_label("الصعوبة", 22, BLUE, HORIZONTAL_ALIGNMENT_RIGHT))
	var diff_row := HBoxContainer.new(); diff_row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(diff_row)
	var diff_btns := []
	var diffs := [["واقعي", 2], ["متوسط", 1], ["سهل", 0]]
	for i in diffs.size():
		var dname: String = diffs[i][0]
		var dv: int = diffs[i][1]
		var b := _button(dname, func():
			main.difficulty = dv
			for db in diff_btns:
				db.modulate = Color(1, 1, 1, 0.55)
			diff_btns[i].modulate = Color.WHITE, 24)
		b.custom_minimum_size = Vector2(110, 52)
		b.modulate = Color.WHITE if dv == main.difficulty else Color(1, 1, 1, 0.55)
		diff_row.add_child(b)
		diff_btns.append(b)
	vb.add_child(HSeparator.new())
	var start := _button("ابدأ المهمة  ◀", func():
		briefing.queue_free()
		briefing = null
		on_start.call(), 34)
	start.custom_minimum_size = Vector2(0, 70)
	vb.add_child(start)
	var hint := "تحكم: WASD حركة · الفأرة نظر/إطلاق · F ركوب/نزول · E تفاعل · Q أمر استسلام · R تعبئة · H صفارة" if not Controls.is_touch else "عصا يسار للحركة · اسحب يمين للنظر"
	var hl := _label(hint, 16, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.custom_minimum_size.x = 520
	vb.add_child(hl)

func toggle_pause() -> void:
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null
		get_tree().paused = false
		if not Controls.is_touch and main.phase not in ["brief", "result"]:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Controls.block_fire()
		return
	get_tree().paused = true
	Controls.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu = Control.new()
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(pause_menu)
	var shade := ColorRect.new(); shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.04, 0.07, 0.92), GOLD))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(440, 0)
	pause_menu.add_child(panel)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(_label("إيقاف مؤقت", 44, GOLD))
	var cont := _button("متابعة", toggle_pause, 30); cont.custom_minimum_size.y = 60
	vb.add_child(cont)
	var again := _button("إعادة المهمة", func():
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().reload_current_scene(), 30)
	again.custom_minimum_size.y = 60
	vb.add_child(again)
	var quit := _button("خروج من اللعبة", func(): get_tree().quit(), 26)
	quit.custom_minimum_size.y = 54
	vb.add_child(quit)

func close_briefing() -> void:
	if briefing:
		briefing.queue_free()
		briefing = null

func show_result(win: bool, title: String, lines: Array, rating: String) -> void:
	result = Control.new()
	result.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(result)
	var shade := ColorRect.new(); shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.04, 0.07, 0.9), GOLD if win else Color(0.9, 0.25, 0.2)))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 0)
	result.add_child(panel)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(_label(title, 50, GOLD if win else Color(1, 0.4, 0.3)))
	if rating != "":
		vb.add_child(_label("التقييم: " + rating, 34, Color.WHITE))
	vb.add_child(HSeparator.new())
	for l in lines:
		vb.add_child(_label(l, 24, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_RIGHT))
	vb.add_child(HSeparator.new())
	var again := _button("إعادة المهمة", func():
		Engine.time_scale = 1.0
		get_tree().reload_current_scene(), 32)
	again.custom_minimum_size = Vector2(0, 64)
	vb.add_child(again)

# ------------------------------------------------------------------ touch controls
func _circle_tex(r: int, fill: Color, ring: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			if d < r - 4:
				img.set_pixel(x, y, fill)
			elif d < r:
				img.set_pixel(x, y, ring)
	return ImageTexture.create_from_image(img)

func _build_touch() -> void:
	touch_root = Node2D.new()
	add_child(touch_root)
	var specs := {
		"fire": ["نار", 70], "aim": ["تصويب", 46], "reload": ["تعبئة", 38], "jump": ["قفز", 40],
		"interact": ["تفاعل", 44], "vehicle": ["سيارة", 40], "yell": ["استسلم!", 42], "siren": ["صفارة", 38],
		"pause": ["II", 26],
	}
	for k in specs:
		var r: int = specs[k][1]
		var b := TouchScreenButton.new()
		b.texture_normal = _circle_tex(r, Color(0.05, 0.08, 0.12, 0.45), Color(1, 1, 1, 0.5))
		b.texture_pressed = _circle_tex(r, Color(0.96, 0.8, 0.35, 0.45), Color(1, 1, 1, 0.8))
		var sh := CircleShape2D.new(); sh.radius = r
		b.shape = sh
		b.shape_centered = true
		b.action = k
		b.passby_press = k == "fire"
		var l := _label(specs[k][0], 18 if r < 50 else 24)
		l.size = Vector2(r * 2, r * 2)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)
		touch_root.add_child(b)
		touch_buttons[k] = b
	joy_ring = Control.new()
	joy_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_ring.draw.connect(func():
		if joy_finger < 0:
			return
		joy_ring.draw_circle(joy_origin, 80, Color(0, 0, 0, 0.25))
		joy_ring.draw_arc(joy_origin, 80, 0, TAU, 40, Color(1, 1, 1, 0.4), 3)
		joy_ring.draw_circle(joy_origin + Controls.touch_move * Vector2(1, -1) * 80, 32, Color(1, 1, 1, 0.5)))
	joy_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(joy_ring)

func _layout_touch() -> void:
	var vs := root.size
	var place := {
		"fire": Vector2(vs.x - 120, vs.y - 150), "aim": Vector2(vs.x - 250, vs.y - 110),
		"reload": Vector2(vs.x - 110, vs.y - 300), "jump": Vector2(vs.x - 240, vs.y - 240),
		"interact": Vector2(vs.x - 380, vs.y - 110), "vehicle": Vector2(vs.x - 380, vs.y - 230),
		"yell": Vector2(vs.x - 250, vs.y - 370), "siren": Vector2(vs.x - 120, vs.y - 150),
		"pause": Vector2(vs.x * 0.5 + 200, 34),
	}
	for k in touch_buttons:
		var b: TouchScreenButton = touch_buttons[k]
		var r: float = (b.shape as CircleShape2D).radius
		b.position = place[k] - Vector2(r, r)
	joy_ring.queue_redraw()

func _on_button(p: Vector2) -> bool:
	for k in touch_buttons:
		var b: TouchScreenButton = touch_buttons[k]
		if not b.visible:
			continue
		var r: float = (b.shape as CircleShape2D).radius
		if p.distance_to(b.position + Vector2(r, r)) < r + 6:
			return true
	return false

func _on_fire(p: Vector2) -> bool:
	var b: TouchScreenButton = touch_buttons["fire"]
	if not b.visible:
		return false
	return b.visible and p.distance_to(b.position + Vector2(70, 70)) < 76

func _unhandled_input(e: InputEvent) -> void:
	if pause_menu and e.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()

func _input(e: InputEvent) -> void:
	if not Controls.is_touch or not touch_root or not touch_root.visible:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if e.position.x < root.size.x * 0.4 and joy_finger < 0 and not _on_button(e.position):
				joy_finger = e.index
				joy_origin = e.position
				Controls.touch_move = Vector2.ZERO
			elif e.position.x >= root.size.x * 0.4 and look_finger < 0 and (not _on_button(e.position) or _on_fire(e.position)):
				look_finger = e.index
				look_last = e.position
		else:
			if e.index == joy_finger:
				joy_finger = -1
				Controls.touch_move = Vector2.ZERO
			elif e.index == look_finger:
				look_finger = -1
	elif e is InputEventScreenDrag:
		if e.index == joy_finger:
			var d: Vector2 = (e.position - joy_origin) / 80.0
			d = d.limit_length(1.0)
			Controls.touch_move = Vector2(d.x, -d.y)
		elif e.index == look_finger:
			Controls.touch_look += e.position - look_last
			look_last = e.position

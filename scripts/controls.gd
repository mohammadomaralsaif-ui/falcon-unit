extends Node
## Unified input: keyboard/mouse on desktop + virtual joystick/buttons on touch screens.

var touch_move := Vector2.ZERO
var touch_look := Vector2.ZERO
var mouse_look := Vector2.ZERO
var is_touch := false
var _touch_pressed := {}
var _touch_just := {}

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"vehicle": [KEY_F],
	"reload": [KEY_R],
	"yell": [KEY_Q],
	"siren": [KEY_H],
	"crouch": [KEY_C],
	"pause": [KEY_ESCAPE],
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_touch = DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
	for a in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in ACTIONS[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		if is_touch:
			continue  # touches are emulated as mouse clicks; fire/aim come from on-screen buttons
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)

func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_look += e.relative

func move_vector() -> Vector2:
	var v := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
	v += touch_move
	return v.limit_length(1.0)

func consume_look() -> Vector2:
	var l := mouse_look * 0.0022 + touch_look * 0.005
	mouse_look = Vector2.ZERO
	touch_look = Vector2.ZERO
	return l

func set_touch(action: String, down: bool) -> void:
	if down and not _touch_pressed.get(action, false):
		_touch_just[action] = Time.get_ticks_msec()
	_touch_pressed[action] = down

func held(action: String) -> bool:
	if action == "sprint" and is_touch and touch_move.y > 0.9:
		return true
	return Input.is_action_pressed(action) or _touch_pressed.get(action, false)

func just(action: String) -> bool:
	if Input.is_action_just_pressed(action):
		return true
	var t: int = _touch_just.get(action, -1)
	if t >= 0 and Time.get_ticks_msec() - t < 200:
		_touch_just[action] = -1
		return true
	return false

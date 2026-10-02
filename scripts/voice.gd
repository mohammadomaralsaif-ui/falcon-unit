extends RefCounted
## Spoken dialogue. Every line in the game is pre-recorded (tools/build_voices.py) with its own
## voice per character — the colonel, the team leader, each teammate, the negotiator, gunmen,
## bystanders… — and stored as assets/voice/<md5 of "speaker|text">.ogg.
## Radio traffic is played through a "Radio" bus (band-limited + a little grit); people standing
## next to you are played clean. Lines without a recording fall back to the phone's own
## text-to-speech (different device voice / pitch per character), or to subtitles only.

static var enabled := true
static var _voice := ""
static var _checked := false
static var _queue: Array = []

const SPEAKERS := {
	"colonel": {"pitch": 0.78, "rate": 0.95},
	"negotiator": {"pitch": 1.25, "rate": 1.0},
	"player": {"pitch": 0.92, "rate": 1.08},
	"team": {"pitch": 1.02, "rate": 1.12},
	"ops": {"pitch": 0.9, "rate": 1.05},
	"news": {"pitch": 1.1, "rate": 1.0},
	"enemy": {"pitch": 0.7, "rate": 1.15},
	"medic": {"pitch": 1.15, "rate": 1.05},
}

static var _player: AudioStreamPlayer
static var _buses := false

## Call once with a node that lives in the scene tree (the HUD).
static func setup(host: Node) -> void:
	if not _buses:
		_buses = true
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, "Radio")
		AudioServer.set_bus_send(i, "Master")
		var hp := AudioEffectHighPassFilter.new(); hp.cutoff_hz = 420.0
		var lp := AudioEffectLowPassFilter.new(); lp.cutoff_hz = 3300.0
		var ds := AudioEffectDistortion.new(); ds.mode = AudioEffectDistortion.MODE_OVERDRIVE; ds.drive = 0.22; ds.post_gain = -2.0
		AudioServer.add_bus_effect(i, hp); AudioServer.add_bus_effect(i, lp); AudioServer.add_bus_effect(i, ds)
		AudioServer.set_bus_volume_db(i, 4.0)
		AudioServer.add_bus(i + 1)
		AudioServer.set_bus_name(i + 1, "Voice")
		AudioServer.set_bus_send(i + 1, "Master")
		AudioServer.set_bus_volume_db(i + 1, 5.0)
	_player = AudioStreamPlayer.new()
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_player)

static func clip_path(who: String, text: String) -> String:
	return "res://assets/voice/%s.ogg" % (who + "|" + text).md5_text()

## Speak a line. Returns its length in seconds (0 when there is no recording and no device voice).
static func say(who: String, text: String, in_person := false) -> float:
	if not enabled:
		return 0.0
	var path := clip_path(who, text)
	if _player and is_instance_valid(_player) and ResourceLoader.exists(path):
		var st: AudioStream = load(path)
		_player.stream = st
		_player.bus = "Voice" if in_person else "Radio"
		_player.play()
		return st.get_length()
	if available():
		var sp: Dictionary = SPEAKERS[kind_of(who)]
		var v := _voice
		if _voices.size() > 1:
			v = _voices[absi(who.hash()) % _voices.size()]      # a different device voice per character
		DisplayServer.tts_speak(clean(text), v, 100, float(sp.pitch), float(sp.rate), 0, false)
		return estimate(text, who)
	return 0.0

static var _voices: PackedStringArray = []

static func available() -> bool:
	if not _checked:
		_checked = true
		if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
			return false
		var vs := DisplayServer.tts_get_voices_for_language("ar")
		_voices = vs
		if vs.size() > 0:
			_voice = vs[0]
	return enabled and _voice != ""

static func kind_of(who: String) -> String:
	if who.contains("العقيد") or who.contains("قائد"):
		return "colonel"
	if who.contains("المفاو") or who.contains("ليلى"):
		return "negotiator"
	if who == "الصقر ١":
		return "player"
	if who.begins_with("الصقر") or who.contains("القنّاص") or who.contains("فريق"):
		return "team"
	if who.contains("نشرة") or who.contains("أخبار"):
		return "news"
	if who.contains("مسعف"):
		return "medic"
	if who.contains("عمليات"):
		return "ops"
	return "enemy"

static func clean(text: String) -> String:
	var t := text
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	t = re.sub(t, "", true)
	for pair in [["الصقر ١", "الصقر واحد"], ["الصقر ٢", "الصقر اثنين"], ["الصقر ٣", "الصقر ثلاثة"], ["الصقر ٤", "الصقر أربعة"], ["الصقر ٥", "الصقر خمسة"], ["«", ""], ["»", ""], ["…", "، "], ["◆", ""], ["◇", ""], ["—", "، "]]:
		t = t.replace(pair[0], pair[1])
	return t.strip_edges()

## Seconds the line will roughly take to say (Arabic TTS ≈ 13 characters a second).
static func estimate(text: String, who := "") -> float:
	var r: float = SPEAKERS[kind_of(who)].rate if who != "" else 1.0
	return clean(text).length() / (13.0 * r) + 0.5

static func stop() -> void:
	if _player and is_instance_valid(_player):
		_player.stop()
	if _voice != "":
		DisplayServer.tts_stop()

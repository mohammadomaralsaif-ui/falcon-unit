extends RefCounted
## Spoken dialogue: radio lines, orders and shouts are read out by the phone's text-to-speech
## engine (Android: Google TTS "العربية"). Each speaker gets their own pitch / pace so the
## colonel, the negotiator and the team sound like different people.
## If the phone has no Arabic voice installed the game silently falls back to subtitles only.

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

static func available() -> bool:
	if not _checked:
		_checked = true
		if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
			return false
		var vs := DisplayServer.tts_get_voices_for_language("ar")
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

static func say(who: String, text: String, interrupt := false) -> void:
	if not available():
		return
	var sp: Dictionary = SPEAKERS[kind_of(who)]
	DisplayServer.tts_speak(clean(text), _voice, 100, float(sp.pitch), float(sp.rate), 0, interrupt)

static func stop() -> void:
	if _voice != "":
		DisplayServer.tts_stop()

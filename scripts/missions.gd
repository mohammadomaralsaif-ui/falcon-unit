extends RefCounted
## Campaign: every mission is data. Interiors are 14x12 grids (3.2 m cells, door 'D' on the street side).
##  # wall   E gunman   H hostage   V evidence   X bomb   C crate   K desk/bench   P plant   O pillar
##  T counter (bank teller / table / shop kiosk, by style)   S sofa   B bed
##  U bus (yard maps: an 10.5 m city bus lying along the row, centred on this cell)
## Optional per-mission look: "mats" {in, out, floor}, "bars" (window bars), "bank_front" (glass bays + ATM).
## What is SAID in each mission — the campaign "رمل أسود" — lives in assets/story.json (Arabic line +
## the English line that is spoken), keyed by mission id: intro scene, drive talk, briefing at the
## cordon, story beats during the assault, the scene after it, and for the last chapter the choice.

static var current := 0   # index of the mission being played (survives scene reloads)
static var autostart := false
static var checkpoint := false     # retry straight from the cordon (skip the opening and the drive)
static var team_size := 3
static var difficulty := 1

const LIST := [
	{
		"id": "bank",
		"title": "مصرف الشرق",
		"subtitle": "سطو مسلّح واحتجاز رهائن",
		"area": "جبل عمّان",
		"clock": "٥:٤٢ م",
		"sky": "golden",
		"block": Vector2i(2, 0),
		"style": "bank",
		"sign": "مصرف الشرق",
		"floors_above": 2,
		"enemies": [5, 6, 7],
		"accuracy": 1.0,
		"executioner": true,
		"deadline": 300.0,
		"deadline_kind": "execute",
		"bomb_time": 0.0,
		"finale": "van",
		"leader": "أبو جاسر",
		"news": "مسلّحون يحتجزون رهائن داخل «مصرف الشرق» – جبل عمّان",
		"map": [
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
		],
	},
	{
		"id": "raid",
		"title": "مداهمة جبل الحسين",
		"subtitle": "مستودع أسلحة لعصابة تهريب",
		"area": "جبل الحسين",
		"clock": "١١:٢٠ م",
		"sky": "night",
		"block": Vector2i(3, 2),
		"style": "apartment",
		"sign": "",
		"floors_above": 4,
		"enemies": [7, 8, 9],
		"accuracy": 1.15,
		"executioner": false,
		"deadline": 240.0,
		"deadline_kind": "evidence",
		"bomb_time": 0.0,
		"finale": "van",
		"leader": "الخال",
		"news": "معلومات استخبارية: مستودع أسلحة مهرّبة في طابق أرضي بجبل الحسين",
		"map": [
			"##############",
			"#E..#V..#..E.#",
			"#.S.#...#.B..#",
			"#...##.###...#",
			"#.E......E...#",
			"##.####..##.##",
			"#V.#..T.E.#..#",
			"#..#.....C#.V#",
			"#..##.#####..#",
			"#E.....E.....#",
			"#..C....S..E.#",
			"######D#######",
		],
	},
	{
		"id": "mall",
		"title": "مول الياسمين",
		"subtitle": "قنبلة ورهائن في مركز تجاري",
		"area": "عبدون",
		"clock": "٩:٠٥ ص",
		"sky": "morning",
		"block": Vector2i(4, 1),
		"style": "mall",
		"sign": "مول الياسمين",
		"floors_above": 1,
		"enemies": [7, 8, 9],
		"accuracy": 1.3,
		"executioner": true,
		"deadline": 0.0,
		"deadline_kind": "",
		"bomb_time": 270.0,
		"finale": "",
		"leader": "",
		"news": "إخلاء مول الياسمين في عبدون بعد بلاغ عن عبوة ناسفة",
		"map": [
			"##############",
			"#H..T..O..T.E#",
			"#..E.........#",
			"#O...KK..O...#",
			"#.......E..H.#",
			"#.T..O..X..T.#",
			"#..E.....E...#",
			"#O...T..O..E.#",
			"#..H.......P.#",
			"#.E..O..T..E.#",
			"#P...........#",
			"######D#######",
		],
	},
	{
		"id": "sniper",
		"type": "sniper",
		"title": "عين الصقر",
		"subtitle": "مهمة قنص – غطاء من فوق السطوح",
		"area": "ماركا",
		"clock": "٦:١٥ م",
		"sky": "golden",
		"block": Vector2i(2, 1),
		"style": "yard",
		"sign": "",
		"floors_above": 0,
		"enemies": [5, 6, 7],
		"accuracy": 0.8,
		"executioner": true,
		"deadline": 240.0,
		"deadline_kind": "execute",
		"bomb_time": 0.0,
		"finale": "",
		"leader": "",
		"news": "مسلّحون يحتجزون عمّالاً داخل ساحة مستودعات في ماركا",
		"map": [
			"##############",
			"#E....C....E.#",
			"#..H.....H...#",
			"#....##..E...#",
			"#.E..##...C..#",
			"#........P...#",
			"#..C...E.....#",
			"#.....H...##.#",
			"#.E.......##.#",
			"#....C....E..#",
			"#..P.........#",
			"######D#######",
		],
	},
	{
		"id": "hotel",
		"title": "فندق الواحة",
		"subtitle": "نزلاء محتجزين في غرف الفندق",
		"area": "الشميساني",
		"clock": "٩:٤٠ م",
		"sky": "night",
		"block": Vector2i(3, 1),
		"style": "apartment",
		"mats": {"in": "interior", "floor": "marble"},
		"bars": false,
		"sign": "فندق الواحة",
		"sign_color": Color(0.35, 0.22, 0.06),
		"floors_above": 6,
		"enemies": [7, 8, 9],
		"accuracy": 1.15,
		"executioner": true,
		"deadline": 300.0,
		"deadline_kind": "execute",
		"bomb_time": 0.0,
		"finale": "",
		"leader": "الذيب",
		"news": "مسلّحون يسيطرون على «فندق الواحة» في الشميساني ويحتجزون نزلاء",
		"map": [
			"##############",
			"#B.H#B.E#H.B.#",
			"#..E#...#.E..#",
			"##.####.###.##",
			"#....E.......#",
			"##.###.##.##.#",
			"#B.E#S.#H.#BE#",
			"#..H#..#..#..#",
			"##.##.###.##.#",
			"#P..E...S..KP#",
			"#K...E...E..K#",
			"######D#######",
		],
	},
	{
		"id": "bus",
		"title": "الباص المخطوف",
		"subtitle": "ركّاب محتجزين في مجمّع الباصات",
		"area": "طبربور",
		"clock": "٧:١٥ ص",
		"sky": "morning",
		"block": Vector2i(3, 3),
		"style": "yard",
		"sign": "",
		"floors_above": 0,
		"enemies": [5, 6, 7],
		"accuracy": 1.0,
		"executioner": true,
		"deadline": 270.0,
		"deadline_kind": "execute",
		"bomb_time": 0.0,
		"finale": "",
		"leader": "",
		"news": "خطف حافلة ركّاب داخل مجمّع الشمال في طبربور",
		"map": [
			"##############",
			"#E....C....E.#",
			"#............#",
			"#..H..U...H..#",
			"#.........E..#",
			"#.E...H..C..E#",
			"#C...........#",
			"#....E..H....#",
			"#..C.....C...#",
			"#.....E......#",
			"#.P........P.#",
			"######D#######",
		],
	},
	{
		"id": "embassy",
		"title": "ليلة السفارة",
		"subtitle": "اقتحام مسلّح لمبنى دبلوماسي",
		"area": "دير غبار",
		"clock": "٢:١٠ ص",
		"sky": "night",
		"block": Vector2i(4, 0),
		"style": "bank",
		"mats": {"out": "plaster"},
		"bank_front": false,
		"sign": "مبنى السفارة",
		"sign_color": Color(0.07, 0.2, 0.12),
		"floors_above": 2,
		"enemies": [8, 9, 10],
		"accuracy": 1.3,
		"executioner": true,
		"deadline": 300.0,
		"deadline_kind": "execute",
		"bomb_time": 0.0,
		"finale": "van",
		"leader": "الرائد نضال",
		"news": "مسلّحون يقتحمون مبنى سفارة في دير غبار ويحتجزون موظفين",
		"map": [
			"##############",
			"#H.E.#V..#.EH#",
			"#....#.E.#...#",
			"#.K..##.##.K.#",
			"#....E...E...#",
			"##.###.O.###.#",
			"#E.#H.....#EV#",
			"#..#..TT..#..#",
			"#.##..E...##.#",
			"#..E..O...E..#",
			"#P...C..C...P#",
			"######D#######",
		],
	},
]

static func get_m() -> Dictionary:
	return LIST[clampi(current, 0, LIST.size() - 1)]

# ---- the story
static var _story = null

static func story() -> Dictionary:
	if _story == null:
		_story = {}
		var p := "res://assets/story.json"
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if j is Dictionary:
				_story = j
	return _story

static func story_of(id: String) -> Dictionary:
	return story().get("missions", {}).get(id, {})

## Speaker code in the script ("C", "P", "2", "L"…) -> the name shown and voiced.
static func who(code: String, leader := "") -> String:
	var c: String = str(story().get("cast", {}).get(code, code))
	return leader if c == "@leader" else c

## Callsign -> the person behind it ("الصقر ٢" -> "رعد · الصقر ٢").
static func show_name(name: String) -> String:
	return str(story().get("show", {}).get(name, name))

## Someone who has no business being on the unit's channel.
static func hacked(name: String) -> bool:
	return name in story().get("hacked", [])

## "الفصل الأول · الصندوق ١١٤"
static func chapter_label(index: int) -> String:
	var st := story_of(LIST[index].id)
	if st.is_empty():
		return LIST[index].title
	return "%s · %s" % [st.chapter, st.name]

# ---- progress (unlocked missions), stored on the device
const SAVE := "user://progress.cfg"

static func unlocked() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		var u := int(cf.get_value("progress", "unlocked", 1))
		# missions added in an update: completing the one before still opens them
		for i in LIST.size():
			if str(cf.get_value("ratings", LIST[i].id, "")) != "":
				u = maxi(u, i + 2)
		return clampi(u, 1, LIST.size())
	return 1

static func complete(index: int, rating: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	var u := maxi(unlocked(), mini(index + 2, LIST.size()))
	cf.set_value("progress", "unlocked", u)
	cf.set_value("ratings", LIST[index].id, rating)
	cf.save(SAVE)

static func rating_of(index: int) -> String:
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		return str(cf.get_value("ratings", LIST[index].id, ""))
	return ""

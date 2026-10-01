extends RefCounted
## Campaign: every mission is data. Interiors are 14x12 grids (3.2 m cells, door 'D' on the street side).
##  # wall   E gunman   H hostage   V evidence   X bomb   C crate   K desk/bench   P plant   O pillar
##  T counter (bank teller / table / shop kiosk, by style)   S sofa   B bed

static var current := 0   # index of the mission being played (survives scene reloads)
static var autostart := false
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
		"news_line": "…ولا تزال قوات الأمن العام تطوّق محيط المصرف منذ ساعتين وسط حالة من الترقّب.",
		"negotiator_line": "«أبو جاسر» رفض كل العروض. معه أربع رهائن من موظفي البنك… وهدّد يقتل وحدة كل خمس دقايق.",
		"commander_line": "الصقر ١، القرار انأخذ. عندك خمس دقايق توصل وتقتحم. الرهائن أولاً… بالتوفيق يا شباب.",
		"brief": ["الباب الرئيسي مقفول بسلاسل، رح تفجّره بعبوة. الانفجار رح يدوّخ اللي ورا الباب لثواني.", "بدّي إيّاهم أحياء إذا بتقدر — اصرخ عليهم يستسلموا. والرهائن طلّعهم من الباب."],
		"story": "الساعة ٥:٤٢ مساءً. مسلّحون اقتحموا «مصرف الشرق» في جبل عمّان واحتجزوا موظفين كرهائن. فشلت المفاوضات، وقائد العمليات أعطى الإذن بالاقتحام.",
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
		"news_line": "…مصادر أمنية: العصابة نفسها وراء تهريب أسلحة عبر الحدود الشمالية.",
		"negotiator_line": "المراقبة بتأكد: «الخال» وجماعته جوّا، ومعهم أسلحة أوتوماتيكية. حاسّين إنهم مراقَبين وبدّهم يتلفوا الأدلة.",
		"commander_line": "الصقر ١، بدّي الأدلة سليمة: الحواسيب ودفاتر الشحنات. عندك أربع دقايق قبل ما يحرقوا كل إشي.",
		"brief": ["الشقة فيها غرف كثيرة وممرات ضيقة. نظّفوا غرفة غرفة واستخدموا القنابل الصوتية.", "اجمعوا الأدلة الثلاثة [E] واعتقلوا اللي بيستسلم."],
		"story": "منتصف الليل في جبل الحسين. عصابة «الخال» مخزّنة أسلحة مهرّبة بطابق أرضي لبناية سكنية. المداهمة لازم تكون سريعة قبل ما يتلفوا الأدلة.",
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
		"news_line": "…مسلّحون يتحصّنون داخل المول مع عدد من الموظفين بعد إخلاء معظم الزوّار.",
		"negotiator_line": "المسلحين ما بدهم يفاوضوا. زارعين عبوة بنص المول ومؤقّتها شغّال.",
		"commander_line": "الصقر ١، المؤقت أقل من خمس دقايق. فكّ العبوة أول إشي، وبعدين الرهائن.",
		"brief": ["العبوة بنص الصالة. اضغط [E] مطوّل جنبها لتفكّها.", "المسلحين محترفين وتصويبهم أدق. لا تتقدّم لحالك."],
		"story": "الصبح في عبدون. بلاغ عن عبوة ناسفة في «مول الياسمين» ومسلحين متحصّنين جوّا مع موظفين. الوقت ضيّق جداً.",
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
]

static func get_m() -> Dictionary:
	return LIST[clampi(current, 0, LIST.size() - 1)]

# ---- progress (unlocked missions), stored on the device
const SAVE := "user://progress.cfg"

static func unlocked() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		return clampi(int(cf.get_value("progress", "unlocked", 1)), 1, LIST.size())
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

extends RefCounted
## Player options kept on the device: graphics quality, who drives, spoken dialogue.

const SAVE := "user://progress.cfg"
static var _loaded := false
static var quality := 1        # 0 خفيف · 1 متوسط · 2 عالي
static var driver := 0         # 0 = the player drives · 1 = a teammate drives (auto-drive to the scene)
static var voice := true

const QUALITY_NAMES := ["خفيفة", "متوسطة", "عالية"]

static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var mobile := OS.has_feature("mobile")
	quality = 1 if mobile else 2
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		quality = clampi(int(cf.get_value("settings", "quality", quality)), 0, 2)
		driver = clampi(int(cf.get_value("settings", "driver", 0)), 0, 1)
		voice = bool(cf.get_value("settings", "voice", true))
	if OS.has_environment("FALCON_QUALITY"):
		quality = clampi(int(OS.get_environment("FALCON_QUALITY")), 0, 2)

static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	cf.set_value("settings", "quality", quality)
	cf.set_value("settings", "driver", driver)
	cf.set_value("settings", "voice", voice)
	cf.save(SAVE)

static func traffic_count() -> int:
	load_all()
	return [14, 20, 26][quality]

static func ped_count() -> int:
	load_all()
	return [8, 13, 22][quality]

static func crowd_count() -> int:
	load_all()
	return [5, 8, 14][quality]

## Renderer side of the quality level (resolution scale, shadows, glow).
static func apply(vp: Viewport, env: Environment, sun: DirectionalLight3D) -> void:
	load_all()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = [0.6, 0.8, 1.0][quality]
	vp.msaa_3d = Viewport.MSAA_DISABLED
	if env:
		env.glow_enabled = quality > 0
		env.fog_enabled = true
	if sun:
		sun.shadow_enabled = quality > 0
		sun.directional_shadow_max_distance = [0.0, 45.0, 70.0][quality]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if quality < 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

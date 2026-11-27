extends RefCounted
## Player options kept on the device: graphics quality, who drives, spoken dialogue.

const SAVE := "user://progress.cfg"
static var _loaded := false
static var quality := 1        # 0 خفيف · 1 متوسط · 2 عالي · 3 فائق (strong phones: full resolution, 4x anti-aliasing, long sharp shadows)
static var show_fps := true     # small frame-rate readout in the corner (so real phone performance can be reported)
static var auto := true         # adapt render quality to the measured frame rate (never goes above 'عالية' by itself)
static var driver := 2         # 0 = the player drives · 1 = a teammate drives (auto-drive) · 2 = start at the cordon (no drive: lightest and fastest)
static var voice := true
static var primary := "rifle"    # rifle | shotgun
static var gear := "flash"       # flash | smoke | shield
static var autofire := false   # sights on a gunman while aiming = the weapon fires by itself (on by default on phones)

const QUALITY_NAMES := ["خفيفة", "متوسطة", "عالية"]

static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var mobile := OS.has_feature("mobile")
	quality = 1 if mobile else 2
	autofire = mobile
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		quality = clampi(int(cf.get_value("settings", "quality", quality)), 0, 3)
		driver = clampi(int(cf.get_value("settings", "driver2", driver)), 0, 2)
		auto = bool(cf.get_value("settings", "auto", true))
		show_fps = bool(cf.get_value("settings", "show_fps", true))
		voice = bool(cf.get_value("settings", "voice", true))
		autofire = bool(cf.get_value("settings", "autofire", autofire))
		primary = str(cf.get_value("settings", "primary", "rifle"))
		gear = str(cf.get_value("settings", "gear", "flash"))
		if not primary in ["rifle", "shotgun"]:
			primary = "rifle"
		if not gear in ["flash", "smoke", "shield"]:
			gear = "flash"
	if OS.has_environment("FALCON_DRIVER"):
		driver = clampi(int(OS.get_environment("FALCON_DRIVER")), 0, 2)
	if OS.has_environment("FALCON_QUALITY"):
		quality = clampi(int(OS.get_environment("FALCON_QUALITY")), 0, 3)
		auto = false

static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	cf.set_value("settings", "quality", quality)
	cf.set_value("settings", "driver2", driver)
	cf.set_value("settings", "auto", auto)
	cf.set_value("settings", "show_fps", show_fps)
	cf.set_value("settings", "voice", voice)
	cf.set_value("settings", "autofire", autofire)
	cf.set_value("settings", "primary", primary)
	cf.set_value("settings", "gear", gear)
	cf.save(SAVE)

static func traffic_count() -> int:
	load_all()
	# starting at the cordon: the streets only matter for the backdrop and the chase, so far fewer cars
	return [6, 9, 13, 16][quality] if driver == 2 else [14, 20, 26, 30][quality]

static func ped_count() -> int:
	load_all()
	return [4, 6, 10, 14][quality] if driver == 2 else [8, 13, 22, 28][quality]

static func crowd_count() -> int:
	load_all()
	return [5, 8, 14, 18][quality]

## Renderer side of the quality level (resolution scale, shadows, glow).
static func apply(vp: Viewport, env: Environment, sun: DirectionalLight3D) -> void:
	load_all()
	var vulkan := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	# Vulkan: AMD FSR 1 upscaling keeps a lowered resolution sharp; the old GL path only has bilinear
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if vulkan and quality < 2 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = [0.6, 0.8, 1.0, 1.0][quality]
	vp.msaa_3d = Viewport.MSAA_4X if quality >= 3 else (Viewport.MSAA_2X if vulkan and quality == 2 else Viewport.MSAA_DISABLED)       # smooth edges on roofs, rails and wires
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if vulkan and quality == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	if vulkan:
		RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][quality])
		RenderingServer.positional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW][quality])
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality >= 3 else 2048, true)
	vp.mesh_lod_threshold = [6.0, 3.0, 1.5, 1.0][quality]      # switch to simpler car/prop meshes sooner on weak phones
	if env:
		env.glow_enabled = quality > 0
		env.fog_enabled = true
	if sun:
		sun.shadow_enabled = quality > 0
		sun.directional_shadow_max_distance = [0.0, 45.0, 70.0, 120.0][quality]
		sun.directional_shadow_mode = [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][quality]

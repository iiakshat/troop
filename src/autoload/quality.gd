extends Node
## Phone heat (owner 2026-11-13: "my phone heated with the game"): less work per second, the
## same look. Numbers in config/quality.json. Nothing calls this; it watches the scene tree:
##
## - Frame cap: 60 fps while a level or Bottle Shot plays (a 90/120 Hz phone would otherwise
##   draw 90-120 frames a second), 30 fps on the map, the menus, the result, revive, pause and
##   the age screen. Any touch lifts the menus to 60 for a moment, so scrolling the map and
##   opening a panel stay smooth; idle animations (the pulsing Play) run at 30.
## - The 3D street is not drawn while the map covers it (Viewport.disable_3d): no sky, shadow
##   map, glow or tonemap behind the menus. Low-processor mode in the menus skips frames in
##   which nothing changed.
## - The 3D scene draws about `render_width` pixels across and is stretched to the screen
##   (Viewport.scaling_3d_scale); the 2D HUD and menus stay full size. A 720-wide phone draws
##   at 1.0, a 1080-wide one at 0.75.
## - The sun's shadow is one cascade (orthogonal) instead of two: the crowds' shadows are drawn
##   once a frame, not twice.
## - Low-end phones (little RAM or a weak GPU family, config `low_end`) draw smaller still,
##   with no glow, no spotlight shadows in the Bottle Shot stash and the cheapest depth of
##   field. No settings toggle: the game picks.
##
## A no-op headless (tests, tune, autoplay batch runs). Debug args after `--`:
##   fps=0 (no frame caps: perf runs)  render_scale=0.75 (force the 3D scale)
##   tier=low|normal (force the device tier)  q_<key>=<json value> (override one config key)
##   abtest=glow|scale|shadows|split|msaa|dof|spotshadow|crowdshadow|menu3d|phone (measuring: flips
##   that one setting every 8 frames and logs "frame phase gpu_ms state" to _local/ab.log, so
##   both sides share the GPU's clocks and the same moment of the level)

const CFG := "res://config/quality.json"

var cfg: Dictionary = {}
var tier := "normal"            # "normal" or "low" (low-end phone)
var mode := ""                  # "play" (full rate) or "menu" (capped)
var _caps := true               # frame caps on (fps=0 turns them off)
var _forced_scale := -1.0       # render_scale= (debug)
var _boost_t := 0.0             # seconds of full rate left after the last touch in the menus
var _view: Node = null          # the running LevelView, if any
var _world: Node3D = null       # the street (World)
var _age: Node = null           # the age screen while it waits
var _done_t := 0.0              # seconds since the level ended (its burst still plays at 60)
var _ab := ""                   # abtest=: the setting being flipped
var _ab_log: FileAccess = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var data: Variant = Config.load_json(CFG)
	cfg = data if data is Dictionary else {}
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	tier = String(args.get("tier", detect_tier()))
	if tier == "low" and cfg.get("low_end") is Dictionary:
		for k in cfg["low_end"]:
			if not String(k).begins_with("_") and k != "detect":
				cfg[k] = cfg["low_end"][k]
	for k in args:
		if String(k).begins_with("q_"):
			var v: Variant = JSON.parse_string(String(args[k]))
			cfg[String(k).trim_prefix("q_")] = v if v != null else String(args[k])
	_caps = String(args.get("fps", "1")) != "0"
	_forced_scale = float(args.get("render_scale", -1.0))
	_apply_render_scale()
	get_viewport().size_changed.connect(_apply_render_scale)
	if cfg.has("soft_shadows"):
		RenderingServer.directional_soft_shadow_filter_set_quality(int(cfg["soft_shadows"]) as RenderingServer.ShadowQuality)
	if String(cfg.get("dof", "low")) == "very_low":
		RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_VERY_LOW, false)
		RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_BOX)
	get_tree().node_added.connect(_on_node_added)
	if args.has("abtest"):
		_ab = String(args["abtest"])
		_ab_log = FileAccess.open(ProjectSettings.globalize_path("res://_local/ab.log"), FileAccess.WRITE)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


## "low" on a phone with little RAM or a GPU from a weak family (config low_end.detect).
func detect_tier() -> String:
	if not OS.has_feature("mobile"):
		return "normal"
	var det: Dictionary = cfg.get("low_end", {}).get("detect", {})
	var ram_gb := float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	if ram_gb > 0.0 and ram_gb <= float(det.get("ram_gb_max", 3.0)):
		return "low"
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	for pat in det.get("gpus", []):
		if gpu.match(String(pat).to_lower()):
			return "low"
	return "normal"


## The 3D draws about render_width pixels across (never above 1.0, never below the floor).
func _apply_render_scale() -> void:
	var vp := get_viewport()
	var w := float(DisplayServer.window_get_size().x)
	var s := 1.0
	if _forced_scale > 0.0:
		s = _forced_scale
	elif w > 0.0:
		s = clampf(float(cfg.get("render_width", 810)) / w, float(cfg.get("render_scale_min", 0.6)), 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if String(cfg.get("scaling", "bilinear")) == "fsr" else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s


func _on_node_added(n: Node) -> void:
	if n is SpotLight3D and not bool(cfg.get("spot_shadows", true)):
		(n as SpotLight3D).shadow_enabled = false   # added after its setup: this wins
		return
	# By class name, so this autoload never loads the level code at boot.
	var sc: Script = n.get_script()
	if sc == null:
		return
	match sc.get_global_name():
		&"World":
			_world = n
			n.ready.connect(_tune_world.bind(n), CONNECT_ONE_SHOT)
		&"LevelView":
			_view = n
			_done_t = 0.0
		&"AgeScreen":
			_age = n


## Shadows and glow of the street (World builds them in its _ready).
func _tune_world(w: Node3D) -> void:
	var sun: DirectionalLight3D = w.get("_sun")
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if String(cfg.get("shadow_mode", "split2")) == "orthogonal" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = float(cfg.get("shadow_distance", 70.0))
		sun.shadow_enabled = bool(cfg.get("shadows", true))
	var env: Environment = w.get("_env")
	if env and not bool(cfg.get("glow", true)):
		env.glow_enabled = false


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag or e is InputEventMouseButton or e is InputEventKey \
			or (e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask != 0):
		_boost_t = float(cfg.get("menu_boost_s", 1.5))


func _process(delta: float) -> void:
	if _ab_log:
		_ab_step()
	_boost_t = maxf(_boost_t - delta, 0.0)
	var m := "play" if _playing(delta) else "menu"
	if m != mode:
		mode = m
		OS.low_processor_usage_mode = mode == "menu" and bool(cfg.get("menu_low_processor", true))
	var off := bool(cfg.get("menu_3d_off", true)) and _world != null and is_instance_valid(_world) and not _world.is_visible_in_tree()
	if get_viewport().disable_3d != off:
		get_viewport().disable_3d = off
	if _caps:
		var fps := int(cfg.get("fps_play", 60))
		if mode == "menu" and _boost_t <= 0.0:
			fps = int(cfg.get("fps_menu", 30))
		if Engine.max_fps != fps:
			Engine.max_fps = fps


## A level or Bottle Shot is running on screen and not paused (its end burst counts too); the
## boot screens count as well. The map, the menus, pause and the age screen do not.
func _playing(delta: float) -> bool:
	if _world == null or not is_instance_valid(_world) or not _world.is_visible_in_tree():
		return false
	if _view == null or not is_instance_valid(_view):
		return _age == null or not is_instance_valid(_age)
	if _view.get("paused") == true:
		return false
	if String(_view.get("_state")).begins_with("done"):
		_done_t += delta
		return _done_t < float(cfg.get("end_full_s", 2.5))
	_done_t = 0.0
	return true


## abtest=: phase B for 8 frames, then phase A for 8; a frame's GPU time is logged with the
## phase that has been on for at least 4 frames (the measured time lags a frame or two).
func _ab_step() -> void:
	var f := Engine.get_process_frames()
	var b := (f / 8) % 2 == 1
	if f % 8 >= 4:
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		var st := String(_view.get("_state")) if _view != null and is_instance_valid(_view) else "menu"
		_ab_log.store_line("%d %s %.3f %s" % [f, "B" if b else "A", gpu, st])
	if f % 8 != 0:
		return
	var vp := get_viewport()
	var has_world := _world != null and is_instance_valid(_world)
	var sun: DirectionalLight3D = _world.get("_sun") if has_world else null
	var env: Environment = _world.get("_env") if has_world else null
	match _ab:
		"glow":
			if env:
				env.glow_enabled = not b
		"scale":
			vp.scaling_3d_scale = 0.75 if b else 1.0
		"shadows":
			if sun:
				sun.shadow_enabled = not b
		"split":   # A = two cascades (as before), B = one
			if sun:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if b else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		"msaa":
			vp.msaa_3d = Viewport.MSAA_DISABLED if b else Viewport.MSAA_2X
		"dof":   # B = the cheapest depth-of-field blur (very low quality, box bokeh)
			RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_VERY_LOW if b else RenderingServer.DOF_BLUR_QUALITY_LOW, false)
			RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_BOX if b else RenderingServer.DOF_BOKEH_HEXAGON)
		"spotshadow":   # B = the stash spotlights cast no shadow
			for c in get_tree().root.find_children("*", "SpotLight3D", true, false):
				(c as Light3D).shadow_enabled = not b
		"crowdshadow":   # B = the crowds cast no shadow
			for c in get_tree().root.find_children("Crowd_*", "MultiMeshInstance3D", true, false):
				(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if b else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		"menu3d":   # B = nothing 3D drawn behind the map
			cfg["menu_3d_off"] = b
		"phone":   # A = before 2026-11-13 (two cascades, full size), B = now on a 1080-wide phone
			vp.scaling_3d_scale = 0.75 if b else 1.0
			if sun:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if b else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if f % 480 == 0:
		_ab_log.flush()

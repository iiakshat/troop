class_name BootSequence
extends CanvasLayer
## The brand boot screens over everything (spec v2 §1; owner 2026-11-12: no wordmark):
##   axnex intro (BootIntro) -> loading (LoadingScreen: a cinematic key-art shot)
## The loading screen's bar follows real loading: the first screen's heavy resources load on
## threads; once they are in, `flow` is called once (main.gd builds the map or level 1 under
## the still-opaque screen, so that hitch is hidden), the bar fills, then the screens fade
## out, `finished` is emitted and the layer frees itself.
## The first launch plays the intro in full and records the `intro` hint; later launches
## skip the intro with a tap. The loading bar is never skipped.
## Driven by advance(dt) (from _process, or directly in tests).

signal finished

const BG := Color(0.043, 0.078, 0.188)  # = project boot_splash/bg_color, so no seam
const FADE := 0.35
const MAX_DT := 1.0 / 20.0  # a long first frame must not skip the show
const CROWDS := "res://assets/characters/"
const MAP_LAYOUT := "res://assets/city/map_layout.json"

var stage := "intro"   # intro | loading | fade | done
var first_launch := true
var write_seen := true  # false in tests: never write the save
var shot := 0
var _flow: Callable
var _warm := PackedStringArray()
var _built := false
var _root: Control
var _bg: ColorRect
var _cur: Control
var _fade_t := 0.0


## True until the intro has played in full once (save: seen_hints "intro").
static func is_first_launch() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game") if tree else null
	if game == null or not (game.get("save") is Dictionary):
		return true
	return not (game.save.get("seen_hints", []) as Array).has("intro")


## What the first screen loads, warmed on threads behind the loading bar. A brand-new player
## goes straight into level 1, whose LevelView builds every crowd (all the characters'
## meshes and animation textures); anyone else opens on the map (its painted image, or its
## five tiles where the GPU cannot take one 8192 px texture, as CityMap decides).
static func default_warm() -> PackedStringArray:
	var out := PackedStringArray()
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game") if tree else null
	if game == null or not (game.get("save") is Dictionary):
		return out
	if int(game.save.get("unlocked", 1)) <= 1 and not game.level_beaten(1):
		for f in ResourceLoader.list_directory(CROWDS):
			if f.ends_with(".res"):
				out.append(CROWDS + f)
		return out
	var layout: Variant = Config.load_json(MAP_LAYOUT) if FileAccess.file_exists(MAP_LAYOUT) else {}
	if not (layout is Dictionary):
		return out
	var rd := RenderingServer.get_rendering_device()
	var need := int((layout.get("size", [0, 8192]) as Array)[1])
	if String(layout.get("image", "")) != "" and rd != null and rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D) >= need:
		out.append("res://assets/city/" + String(layout["image"]))
	else:
		for d in layout.get("districts", []):
			if String(d.get("tile", "")) != "":
				out.append("res://assets/city/" + String(d["tile"]))
	return out


## shot: the key art to show (-1 = the next one in turn); warm: the paths to load behind the
## bar (null = default_warm()).
func _init(first := true, flow := Callable(), shot_index := -1, warm: Variant = null) -> void:
	first_launch = first
	_flow = flow
	shot = shot_index if shot_index >= 0 else LoadingScreen.pick_shot()
	_warm = default_warm() if warm == null else PackedStringArray(warm)
	# the shot loads on a thread while the intro plays
	var art := String(LoadingScreen.SHOTS[shot]["path"])
	if ResourceLoader.exists(art):
		ResourceLoader.load_threaded_request(art)
	layer = 128
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing under it takes taps meanwhile
	add_child(_root)
	_bg = ColorRect.new()
	_bg.color = BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)
	_show(BootIntro.new(not first_launch))


func _process(delta: float) -> void:
	advance(minf(delta, MAX_DT))


func _input(event: InputEvent) -> void:
	if stage == "fade" or stage == "done":
		return
	# Mouse clicks arrive as touches too (emulate_touch_from_mouse), so only touches count.
	if event is InputEventScreenTouch and event.pressed:
		tap()
	get_viewport().set_input_as_handled()


func tap() -> void:
	if stage == "intro" and bool(_cur.get("skippable")):
		_next()


## The loading screen while it is up (else null).
func loading_screen() -> LoadingScreen:
	return _cur as LoadingScreen if stage == "loading" else null


func advance(dt: float) -> void:
	match stage:
		"intro":
			_cur.call("advance", dt)
			if bool(_cur.call("is_done")):
				_next()
		"loading":
			var ls := _cur as LoadingScreen
			ls.advance(dt)
			if not _built and ls.loaded():
				_built = true
				if _flow.is_valid():
					_flow.call()
				ls.mark_built()
			if ls.is_done():
				_next()
		"fade":
			_fade_t += dt
			_root.modulate.a = clampf(1.0 - _fade_t / FADE, 0.0, 1.0)
			if _fade_t >= FADE:
				stage = "done"
				finished.emit()
				if is_inside_tree():
					queue_free()


func _next() -> void:
	match stage:
		"intro":
			_mark_intro_seen()
			stage = "loading"
			_show(LoadingScreen.new(-1, shot, _warm))
		"loading":
			stage = "fade"
			_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _show(c: Control) -> void:
	if _cur:
		_root.remove_child(_cur)
		_cur.free()
	_cur = c
	_root.add_child(c)


func _mark_intro_seen() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game") if tree else null
	if game == null or not (game.get("save") is Dictionary):
		return
	var seen: Array = game.save.get("seen_hints", [])
	if seen.has("intro"):
		return
	seen.append("intro")
	game.save["seen_hints"] = seen
	if write_seen:
		game.write_save()

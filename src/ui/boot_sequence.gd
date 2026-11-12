class_name BootSequence
extends CanvasLayer
## The brand boot screens over everything (spec v2 §1):
##   axnex intro (BootIntro) -> Siren Squad logo (TitleLogo) -> loading (LoadingScreen)
## When the loading bar is full, `flow` is called once (main.gd builds the map or level 1
## under the still-opaque screen, so that hitch is hidden), then the screens fade out,
## `finished` is emitted and the layer frees itself.
## The first launch plays the intro in full and records the `intro` hint; later launches
## skip the intro and the logo with a tap. The loading bar is never skipped.
## Driven by advance(dt) (from _process, or directly in tests).

signal finished

const BG := Color(0.043, 0.078, 0.188)  # = project boot_splash/bg_color, so no seam
const FADE := 0.35
const MAX_DT := 1.0 / 20.0  # a long first frame must not skip the show

var stage := "intro"   # intro | logo | loading | fade | done
var first_launch := true
var write_seen := true  # false in tests: never write the save
var _flow: Callable
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


func _init(first := true, flow := Callable()) -> void:
	first_launch = first
	_flow = flow
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
	if stage in ["intro", "logo"] and bool(_cur.get("skippable")):
		_next()


func advance(dt: float) -> void:
	match stage:
		"intro", "logo", "loading":
			_cur.call("advance", dt)
			if bool(_cur.call("is_done")):
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
			stage = "logo"
			_show(TitleLogo.new(not first_launch))
		"logo":
			stage = "loading"
			_show(LoadingScreen.new())
		"loading":
			stage = "fade"
			_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if _flow.is_valid():
				_flow.call()


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

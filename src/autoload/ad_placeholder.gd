extends CanvasLayer
## Blank placeholder ad (owner, 2026-11-08): shows how ads will feel before the real SDK is
## connected. Full-screen near-black panel on top of everything, a big countdown number inside
## a shrinking ring, the ad icon small at the top, a close X. No words.
##   rewarded:     counts down `seconds`; at 0 it finishes with completed = true. The X is
##                 there from the start; closing early finishes with completed = false.
##   interstitial: counts down `seconds`, then the X appears; it closes itself `close_after`
##                 seconds later. Always closable once the X shows.
## The countdown uses real time (Engine.time_scale and pause do not slow it). Ads owns the
## pausing; this node only draws and reports `finished` once. Drive it with step(now_ms) in tests.

signal finished(completed: bool)

const BG := Color(0.03, 0.03, 0.045, 0.97)
const RING_BG := Color(1, 1, 1, 0.1)
const RING_SIZE := 340.0
const RING_WIDTH := 22.0

var kind := "rewarded"
var seconds := 5.0
var close_after := 2.0
var done := false

var _start_ms := -1
var _left := 0
var _root: Control
var _safe: Control
var _ring: Control
var _number: Label
var _close: Button
var _fraction := 1.0


## Builds the nodes. `start_ms` < 0 starts the clock when the popup enters the tree.
func setup(ad_kind: String, ad_seconds: float, ad_close_after := 2.0, start_ms := -1) -> void:
	kind = ad_kind
	seconds = maxf(ad_seconds, 0.0)
	close_after = maxf(ad_close_after, 0.0)
	_start_ms = start_ms
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_left = ceili(seconds)
	_number.text = str(_left)


func _ready() -> void:
	if _root == null:
		setup(kind, seconds, close_after, _start_ms)
	if _start_ms < 0:
		_start_ms = Time.get_ticks_msec()
	UiKit.safe_rect(_safe)


func _process(_delta: float) -> void:
	step(Time.get_ticks_msec())


func _input(event: InputEvent) -> void:
	# Android back / Esc acts like the X, but only while the X is showing.
	if not done and _close.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close()


## Advances the countdown to the given time (ms, same clock as start_ms).
func step(now_ms: int) -> void:
	if done:
		return
	var t := maxf(float(now_ms - _start_ms) / 1000.0, 0.0)
	var left := maxf(seconds - t, 0.0)
	_fraction = left / seconds if seconds > 0.0 else 0.0
	_left = ceili(left)
	_number.text = str(_left)
	_ring.queue_redraw()
	if left > 0.0:
		return
	if kind == "rewarded":
		_finish(true)
		return
	if not _close.visible:
		_number.visible = false
		_ring.visible = false
		_close.visible = true
		if _close.is_inside_tree():
			UiKit.pop(_close)
	if t >= seconds + close_after:
		_finish(true)


## Whole seconds still to go, as the number shows.
func seconds_left() -> int:
	return _left


func close_visible() -> bool:
	return _close.visible


## Same as tapping the X (does nothing while the X is hidden).
func press_close() -> void:
	if _close.visible:
		_on_close()


func _on_close() -> void:
	# Rewarded: closing before 0 means no reward. Interstitial: the X only shows after the
	# countdown, so it counts as watched.
	_finish(kind != "rewarded")


func _finish(completed: bool) -> void:
	if done:
		return
	done = true
	finished.emit(completed)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing underneath gets taps
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_safe = Control.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_safe)

	# Small ad icon at the top centre.
	var tex := _texture(["ad_play", "play"])
	if tex:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = Color(1, 1, 1, 0.75)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.set_anchors_preset(Control.PRESET_CENTER_TOP)
		ic.offset_left = -36
		ic.offset_right = 36
		ic.offset_top = 40
		ic.offset_bottom = 112
		_safe.add_child(ic)

	# Ring + number in the middle.
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_preset(Control.PRESET_CENTER)
	_ring.offset_left = -RING_SIZE * 0.5
	_ring.offset_right = RING_SIZE * 0.5
	_ring.offset_top = -RING_SIZE * 0.5
	_ring.offset_bottom = RING_SIZE * 0.5
	_ring.draw.connect(_draw_ring)
	_safe.add_child(_ring)

	_number = UiKit.label("", 170, Color.WHITE, 14)
	_number.set_anchors_preset(Control.PRESET_CENTER)
	_number.offset_left = -RING_SIZE * 0.5
	_number.offset_right = RING_SIZE * 0.5
	_number.offset_top = -RING_SIZE * 0.5
	_number.offset_bottom = RING_SIZE * 0.5
	_safe.add_child(_number)

	# Close X, top right.
	_close = UiKit.icon_button("close", "red", 104, "round")
	_close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close.offset_left = -136
	_close.offset_right = -32
	_close.offset_top = 32
	_close.offset_bottom = 136
	_close.process_mode = Node.PROCESS_MODE_ALWAYS
	_close.pressed.connect(_on_close)
	_close.visible = kind == "rewarded"
	_safe.add_child(_close)


func _draw_ring() -> void:
	var c := _ring.size * 0.5
	var r := minf(c.x, c.y) - RING_WIDTH * 0.5
	_ring.draw_arc(c, r, 0.0, TAU, 96, RING_BG, RING_WIDTH, true)
	if _fraction > 0.0:
		var col := UiKit.YELLOW if kind == "rewarded" else Color(1, 1, 1, 0.85)
		var start := -PI * 0.5
		_ring.draw_arc(c, r, start, start + TAU * _fraction, maxi(int(96 * _fraction), 4), col, RING_WIDTH, true)


## First texture that exists among glossy icons and white SVG glyphs (never errors).
static func _texture(names: Array) -> Texture2D:
	for n in names:
		for p in ["res://assets/icons/gloss/%s.png" % n, "res://assets/icons/%s.svg" % n]:
			if ResourceLoader.exists(p):
				return load(p)
	return null

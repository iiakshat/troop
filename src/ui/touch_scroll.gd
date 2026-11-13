class_name TouchScroll
extends Node
## Finger-drag scrolling for a ScrollContainer full of cards and buttons (owner play-test: the
## Armory list would not scroll on a phone). Godot only drags a ScrollContainer when the press
## reaches it, and a card (PanelContainer, mouse_filter STOP) or a button swallows the press.
## This node listens to gui_input of the scroll and of every Control inside it (the signal runs
## before the control's own handling), so a drag that starts anywhere in the list scrolls it:
## - a press is only noted, so a short tap still presses a button as before;
## - once the finger has moved DRAG_START px up or down it is a drag: the list follows the
##   finger, every button in the list drops its pending press (the release never buys), and the
##   drag's motion and release are taken (nothing under the finger reacts);
## - after the release the list glides on with the finger's speed and slows down (FRICTION).
## The mouse wheel and the scroll bar work as before. Attach with UiKit.touch_scroll(scroll).

const DRAG_START := 14.0     ## px a press must travel (vertically) before it becomes a drag
const FRICTION := 5.0        ## glide decay per second
const STOP_MS := 90          ## the finger rested this long before lifting: no glide

var scroll: ScrollContainer
var _down := false
var _drag := false
var _start := Vector2.ZERO   # finger at the drag's start (global canvas px)
var _start_v := 0.0          # scroll position then
var _pos := 0.0              # scroll position as a float (scroll_vertical is an int)
var _last_y := 0.0
var _last_ms := 0
var _vel := 0.0              # px/s of content, + = towards the end


static func attach(s: ScrollContainer) -> TouchScroll:
	var t := TouchScroll.new()
	t.scroll = s
	t.name = "TouchScroll"
	s.add_child(t, false, Node.INTERNAL_MODE_BACK)
	return t


func _ready() -> void:
	_hook(scroll)
	for c in scroll.find_children("*", "Control", true, false):
		_hook(c)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is Control and scroll.is_ancestor_of(n):
		_hook(n)


func _hook(c: Control) -> void:
	if not c.gui_input.is_connected(_on_input):
		c.gui_input.connect(_on_input.bind(c))


## True while a drag is moving the list (tests).
func dragging() -> bool:
	return _drag


func _on_input(ev: InputEvent, c: Control) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var g := c.get_global_transform() * mb.position
		if mb.pressed:
			_down = true
			_drag = false
			_start = g
			_last_y = g.y
			_last_ms = Time.get_ticks_msec()
			_vel = 0.0
			_pos = float(scroll.scroll_vertical)
			_start_v = _pos
			if c == scroll:
				c.accept_event()  # our drag replaces the container's own (no double scroll)
		elif _down:
			var was := _drag
			_down = false
			_drag = false
			if was:
				c.accept_event()  # a drag's release never presses what is under the finger
				if Time.get_ticks_msec() - _last_ms > STOP_MS:
					_vel = 0.0
	elif ev is InputEventMouseMotion and _down:
		var g := c.get_global_transform() * (ev as InputEventMouseMotion).position
		if not _drag and absf(g.y - _start.y) > DRAG_START:
			_drag = true
			_cancel_presses()
			_start = g
			_last_y = g.y
		if _drag:
			_set_pos(_start_v - (g.y - _start.y))
			var ms := Time.get_ticks_msec()
			var dt := maxf((ms - _last_ms) / 1000.0, 0.004)
			_vel = lerpf(_vel, -(g.y - _last_y) / dt, 0.4)
			_last_y = g.y
			_last_ms = ms
			c.accept_event()


## Every button in the list forgets the press the drag started on (toggling disabled clears a
## BaseButton's pending press without any other effect), so lifting the finger buys nothing.
func _cancel_presses() -> void:
	for b in scroll.find_children("*", "BaseButton", true, false):
		var bb := b as BaseButton
		if not bb.disabled:
			bb.disabled = true
			bb.disabled = false


func _set_pos(v: float) -> void:
	var bar := scroll.get_v_scroll_bar()
	var top := maxf(bar.max_value - bar.page, 0.0) if bar else v
	_pos = clampf(v, 0.0, top)
	scroll.scroll_vertical = int(round(_pos))


func _process(delta: float) -> void:
	if _down or _vel == 0.0:
		return
	var before := _pos
	_set_pos(_pos + _vel * delta)
	_vel *= exp(-FRICTION * delta)
	if absf(_vel) < 15.0 or is_equal_approx(before, _pos):
		_vel = 0.0

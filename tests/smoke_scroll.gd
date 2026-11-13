extends SceneTree
## Headless smoke test of finger scrolling in the menus (owner play-test: the Armory list would
## not scroll). Builds the real Armory, Codex and Settings panels on a blank save (never
## written) and pushes real input events through the viewport, like a finger with Godot's
## touch-to-mouse emulation:
## - a drag that starts on a buy button scrolls the list and buys nothing;
## - a drag that starts on a card scrolls the other way;
## - a short tap on a buy button still buys exactly one step;
## - the Codex and the Settings credits scroll the same way.
## Needs a running tree (layout, the panels' pop-in), so it is not part of run_tests.gd:
##   godot --headless --path . --script res://tests/smoke_scroll.gd
## Prints "SMOKE SCROLL: N checks, 0 failed" and exits 1 on any failure.

var _frame := 0
var _panel: Control
var _checks := 0
var _fails: Array[String] = []
var _step := 0
var _wait := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_g().save_path = ""
		_g().boot({})
		_g().save["coins"] = 1000000
		_open("res://src/ui/armory_panel.gd")
	elif _frame > 2 and _frame >= _wait:
		_step += 1
		match _step:
			1: _armory_drag_from_button()
			2: _armory_drag_from_card()
			3: _armory_tap_buys()
			4: _armory_touch_drag()
			5: _open("res://src/ui/codex_panel.gd")
			6: _list_drags("codex")
			7: _open("res://src/ui/settings_panel.gd")
			8: _list_drags("settings credits")
			_:
				print("SMOKE SCROLL: %d checks, %d failed" % [_checks, _fails.size()])
				for f in _fails:
					print("  FAIL " + f)
				quit(1 if _fails.size() > 0 or _checks == 0 else 0)
				return false
	return false


func _open(path: String) -> void:
	if is_instance_valid(_panel):
		_panel.free()
	_panel = load(path).new()
	root.add_child(_panel)
	_wait = _frame + 40  # layout and the pop-in tween settle


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


func _g() -> Node:
	return root.get_node("/root/Game")


func _scroll() -> ScrollContainer:
	return _panel.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer


# ---------------------------------------------------------------- input, as the viewport gets it

func _button(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position = p
	e.global_position = p
	root.push_input(e, true)


func _move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = p
	e.global_position = p
	e.relative = rel
	root.push_input(e, true)


## Press at `from`, move by `by` in `steps`, release there.
func _drag(from: Vector2, by: Vector2, steps := 10) -> void:
	_button(from, true)
	var p := from
	for i in steps:
		var q := from + by * float(i + 1) / steps
		_move(q, q - p)
		p = q
	_button(p, false)


## The first squad weapon's buy button that is enabled and inside the visible list.
func _visible_buy() -> Dictionary:
	var view := _scroll().get_global_rect()
	for id in _panel.call("card_ids"):
		var b: Button = _panel._cards[id]["buy"]
		var r := b.get_global_rect()
		if not b.disabled and view.encloses(r):
			return {"id": id, "button": b}
	return {}


## A card fully inside the visible list.
func _visible_card() -> Control:
	var view := _scroll().get_global_rect()
	for id in _panel.call("card_ids"):
		var card: Control = _panel._cards[id]["card"]
		if view.encloses(card.get_global_rect()):
			return card
	return null


func _armory_drag_from_button() -> void:
	var s := _scroll()
	_check(s.get_v_scroll_bar().max_value > s.size.y + 100.0, "the armory list is taller than its view")
	var hit := _visible_buy()
	_check(not hit.is_empty(), "an enabled buy button is on screen")
	if hit.is_empty():
		return
	var id := String(hit["id"])
	var coins := int(_g().save["coins"])
	var idx := Armory.index(_g().save, id)
	var c: Vector2 = (hit["button"] as Button).get_global_rect().get_center()
	var before := s.scroll_vertical
	_drag(c, Vector2(0, -320))
	_check(s.scroll_vertical >= before + 250, "a drag that starts on a buy button scrolls the list (%d -> %d)" % [before, s.scroll_vertical])
	_check(int(_g().save["coins"]) == coins, "the drag bought nothing (coins)")
	_check(Armory.index(_g().save, id) == idx, "the drag bought nothing (weapon step)")
	_wait = _frame + 30  # the glide settles


func _armory_drag_from_card() -> void:
	var s := _scroll()
	var card := _visible_card()
	if card == null:
		_check(false, "a card is on screen after the first drag")
		return
	var r := card.get_global_rect()
	var before := s.scroll_vertical
	_drag(Vector2(r.position.x + r.size.x * 0.45, r.get_center().y), Vector2(0, 420))
	_check(s.scroll_vertical <= maxi(before - 250, 0), "a drag that starts on a card scrolls back (%d -> %d)" % [before, s.scroll_vertical])
	_wait = _frame + 30


func _armory_tap_buys() -> void:
	var hit := _visible_buy()
	_check(not hit.is_empty(), "an enabled buy button is on screen for the tap")
	if hit.is_empty():
		return
	var id := String(hit["id"])
	var coins := int(_g().save["coins"])
	var cost: int = _g().weapon_cost(id)
	var idx := Armory.index(_g().save, id)
	var s := _scroll()
	var before := s.scroll_vertical
	var c: Vector2 = (hit["button"] as Button).get_global_rect().get_center()
	_button(c, true)
	_move(c + Vector2(0, 5), Vector2(0, 5))  # a finger wobbles a little; still a tap
	_button(c + Vector2(0, 5), false)
	_check(Armory.index(_g().save, id) == idx + 1, "a tap on a buy button buys one step")
	_check(int(_g().save["coins"]) == coins - cost, "a tap pays the price once")
	_check(s.scroll_vertical == before, "a tap does not scroll")


## A real finger: screen touch and drag events through Input, which emulates the mouse from
## them (project setting), exactly as on a phone.
func _armory_touch_drag() -> void:
	var hit := _visible_buy()
	if hit.is_empty():
		_check(false, "an enabled buy button is on screen for the touch drag")
		return
	var s := _scroll()
	var coins := int(_g().save["coins"])
	var before := s.scroll_vertical
	var from: Vector2 = (hit["button"] as Button).get_global_rect().get_center()
	# Input takes window pixels: map the viewport points through the stretch transform.
	var w := root.get_final_transform()
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = w * from
	Input.parse_input_event(t)
	Input.flush_buffered_events()
	var p := from
	for i in 8:
		var q := from + Vector2(0, -35.0 * (i + 1))
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = w * q
		d.relative = w.basis_xform(q - p)
		Input.parse_input_event(d)
		Input.flush_buffered_events()
		p = q
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.pressed = false
	u.position = w * p
	Input.parse_input_event(u)
	Input.flush_buffered_events()
	_check(s.scroll_vertical >= before + 200, "a touch drag from a buy button scrolls (%d -> %d)" % [before, s.scroll_vertical])
	_check(int(_g().save["coins"]) == coins, "the touch drag bought nothing")
	_wait = _frame + 30


func _list_drags(what: String) -> void:
	var s := _scroll()
	var bar := s.get_v_scroll_bar()
	_check(bar.max_value > bar.page + 30.0, what + ": the list is taller than its view")
	var r := s.get_global_rect()
	var before := s.scroll_vertical
	_drag(r.get_center() + Vector2(0, 60), Vector2(0, -120), 6)
	var want := mini(before + 80, int(bar.max_value - bar.page))
	_check(s.scroll_vertical >= want, what + ": a drag scrolls (%d -> %d, end %d)" % [before, s.scroll_vertical, int(bar.max_value - bar.page)])
	_wait = _frame + 30

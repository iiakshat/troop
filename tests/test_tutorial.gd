extends "res://tests/test_case.gd"
## First-run tutorials (v1.1 item 11): the lane the gate tutorial lights and red-gate detection.


func test_first_gate_of_level_1_lights_the_plus_ten() -> void:
	var row := {"gates": [{"lane": 0, "op": "num", "v": 4}, {"lane": 1, "op": "num", "v": -1, "step": 0.5, "max": 3}, {"lane": 2, "op": "num", "v": 10}]}
	eq(Tutorial.best_lane(row, 1.0, 1), 2, "+10 beats +4 and the red -1")


func test_multiplier_wins_for_a_big_squad_only() -> void:
	var row := {"gates": [{"lane": 0, "op": "num", "v": 10}, {"lane": 2, "op": "mul", "k": 3}]}
	eq(Tutorial.best_lane(row, 1.0, 1), 0, "1 troop: +10 beats x3")
	eq(Tutorial.best_lane(row, 20.0, 1), 2, "20 troops: x3 beats +10")


func test_tie_keeps_the_current_lane() -> void:
	var row := {"gates": [{"lane": 0, "op": "num", "v": 5}, {"lane": 2, "op": "num", "v": 5}]}
	eq(Tutorial.best_lane(row, 3.0, 2), 2, "equal offers: stay")


func test_red_gate_detection() -> void:
	check(Tutorial._is_red({"op": "num", "v": -4, "step": 1.5, "max": 8}), "ticking negative gate is red")
	check(Tutorial._is_red({"op": "pct", "v": -40, "step": 12.4, "max": 40}), "negative percent gate is red")
	check(not Tutorial._is_red({"op": "num", "v": 2, "step": 1.5, "max": 8}), "shot up past 0: an offer")
	check(not Tutorial._is_red({"op": "num", "v": -4}), "no step: a plain minus gate")


func test_owned_hints_cover_the_level_data_ids() -> void:
	for id in ["swipe", "red_gate", "shield", "bomb", "barrel"]:
		check(Tutorial.OWNS.has(id), id)


# ---------------------------------------------------------------- v2 §11: one hint language

## The Game autoload is not booted under the test runner: boot it on a blank in-memory save
## (save_path "" = it never writes).
func _game() -> void:
	if not Game.save.has("seen_hints"):
		Game.save_path = ""
		Game.boot({})


func _fresh_hints(seen: Array) -> Array:
	_game()
	var keep: Array = (Game.save["seen_hints"] as Array).duplicate()
	Game.save["seen_hints"] = seen.duplicate()
	return keep


## A level view that is never put in the tree (no visuals), with a Tutorial on top.
func _view(n: int) -> LevelView:
	return LevelView.new().setup(Config.level(n), {}, null, Fx.new(), UiKit.FONT)


func _tut(v: LevelView) -> Tutorial:
	var t := Tutorial.new().setup(v, null)
	t.build()
	return t


func _free(v: LevelView, t: Tutorial) -> void:
	if t:
		t.free()
	v.fx.free()
	v.free()


func _touch(t: Tutorial, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.pressed = pressed
	t._input(e)


func test_tap_lesson_runs_first_on_level_1() -> void:
	var keep := _fresh_hints([])
	var v := _view(1)
	var t := _tut(v)
	t.screen = Vector2(720, 1280)
	t._look(1.0)
	eq(t._step, "tap", "the tap lesson opens before anything else on a fresh save")
	check(v.hold, "the street holds while the lesson waits")
	check(t._hand.visible, "the gesture hand shows the tap")
	eq(t._gesture, "tap", "the hand taps")
	_touch(t, Vector2(360, 300), true)    # upper half: not the tap zone
	_touch(t, Vector2(360, 300), false)
	for i in 2:
		_touch(t, Vector2(360, 1000), true)
		t._t += 0.1
		_touch(t, Vector2(362, 1001), false)
		t._run_step(0.1)
	eq(t._step, "tap", "two taps: still waiting")
	_touch(t, Vector2(360, 1000), true)
	t._t += 0.1
	_touch(t, Vector2(360, 1000), false)
	t._run_step(0.1)
	eq(t._step, "", "the third tap ends it")
	check(not v.hold, "the street runs again")
	check(Game.hint_seen("tap"), "once ever")
	_free(v, t)
	Game.save["seen_hints"] = keep


func test_a_drag_is_not_a_lesson_tap() -> void:
	var keep := _fresh_hints([])
	var v := _view(1)
	var t := _tut(v)
	t.screen = Vector2(720, 1280)
	t._look(1.0)
	for i in 3:
		_touch(t, Vector2(200, 1000), true)
		t._t += 0.1
		_touch(t, Vector2(400, 1000), false)
		t._run_step(0.1)
	eq(t._step, "tap", "swipes do not count as taps")
	_free(v, t)
	Game.save["seen_hints"] = keep


func test_hint_events_open_card_not_hand() -> void:
	var keep := _fresh_hints(["tap", "swipe"])
	var v := _view(4)
	v._handle_events([{"type": "hint", "ev": {"at": 6, "type": "hint", "id": "sergeant", "icon": "sergeant"}}])
	check(v.item_card != null, "a hint event opens the new-item card")
	if v.item_card:
		check(v.item_card.showing(), "the card is up")
		eq(v.item_card.card_icon(), "sergeant", "card shows the sergeant")
		check(v.item_card.find_child("*Hand*", true, false) == null, "no hand on the card")
		v.item_card.tick(3.0)
		check(not v.item_card.showing(), "the card hides by itself after about 2 s")
	check(not v.hold, "no freeze")
	eq(v._time_scale, 1.0, "the street keeps its speed")
	eq(Engine.time_scale, 1.0, "no engine slow-down")
	check(Game.hint_seen("sergeant"), "shown once ever")
	_free(v, null)
	Game.save["seen_hints"] = keep


func test_card_effects_read_numbers_from_the_object() -> void:
	_game()
	var ob := {"kind": "barrel", "kill": 40, "lane": 1, "z": -20.0}
	var fx: Array = NewItemCard.effects("barrel", ob, {})
	eq(fx.size(), 3, "barrel: shoot, fuse, blast")
	eq(String(fx[2]["text"]), "-40", "blast kills the barrel's own number")
	ob["kill"] = 25
	eq(String(NewItemCard.effects("barrel", ob, {})[2]["text"]), "-25", "a level override shows")
	var hole := {"kind": "pothole", "fall": 4, "fall_pct": 30}
	eq(String(NewItemCard.effects("pothole", hole, {})[0]["text"]), "-30%", "percent form wins when set")


func test_hint_table_covers_the_level_hint_ids() -> void:
	_game()
	var items: Dictionary = NewItemCard.table().get("items", {})
	for n in range(1, 51):
		for e in Config.level(n).get("events", []):
			if String(e.get("type", "")) == "hint" and String(e.get("id", "")) != "swipe":
				check(items.has(String(e["id"])), "hints.json has %s (L%d)" % [e["id"], n])
	for id in items:
		var it: Dictionary = items[id]
		check(UiKit.is_gloss(String(it["icon"])) or ResourceLoader.exists("res://assets/icons/%s.svg" % it["icon"]), "%s icon exists" % id)
		for f in it.get("effects", []):
			var ic := String((f as Dictionary).get("icon", ""))
			check(UiKit.is_gloss(ic) or ResourceLoader.exists("res://assets/icons/%s.svg" % ic), "%s effect icon %s exists" % [id, ic])


func test_gate_pick_uses_chevrons() -> void:
	var keep := _fresh_hints(["tap", "swipe"])
	var v := _view(1)
	var t := _tut(v)
	v.sim.rows.append({"id": 900, "z": -15.0, "gates": [{"lane": 0, "op": "num", "v": 4}, {"lane": 2, "op": "mul", "k": 3}]})
	v.sim.lane = 1
	t._look(0.1)
	eq(t._step, "gate_pick", "the first gate choice opens the lesson")
	t._run_step(0.1)
	check(not t._hand.visible, "no hand during gate_pick")
	check(t._chevrons, "chevrons painted towards the best lane")
	var n := v.sim.squad.total()
	eq(t._lane, 0, "1 troop: +4 beats x3")
	eq(t._preview, [n, n + 4], "result preview: squad now > after the best gate (exact)")
	v.sim.lane = 0
	t._run_step(2.0)
	eq(t._step, "", "ends once the squad is in the best lane")
	_free(v, t)
	Game.save["seen_hints"] = keep


func test_power_lesson_has_no_hand() -> void:
	for id in ["tap", "swipe", "barrel", "bottle_knives", "bottle_reload"]:
		check(Tutorial.uses_hand(id), "%s is a gesture lesson" % id)
	for id in ["gate_pick", "red_gate", "shield", "bomb"]:
		check(not Tutorial.uses_hand(id), "%s has no hand" % id)


func test_pointer_hand_puts_the_fingertip_on_the_spot() -> void:
	var b := Control.new()
	b.size = Vector2(200, 100)
	var h := PointerHand.on(b, Vector2(0.5, 0.5), 100.0)
	h.place()
	var tip := h.position + h.tip_offset()
	check(tip.distance_to(Vector2(100, 50)) < 1.0, "fingertip on the spot (got %s)" % tip)
	b.free()


func test_buy_tag_shows_icon_then_before_and_after() -> void:
	var tag := PointerHand.tag("coin", "10", "20", 30)
	var texts: Array = []
	var icons := 0
	for c in tag.get_child(0).get_children():
		if c is Label:
			texts.append((c as Label).text)
		elif c is TextureRect:
			icons += 1
	eq(texts, ["10", "20"], "before, then after")
	eq(icons, 2, "the item's icon and the ▸ between the numbers")
	eq(tag.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the tag never blocks a tap on the map")
	tag.free()

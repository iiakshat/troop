extends SceneTree
## Headless smoke test of the city map lobby (MAP-UI). Builds the real Lobby on a fresh save
## (never written), drives taps and a drag through the map's own input handling, opens and
## closes the panels, and checks a coin collection. Needs a running tree, so it is not part of
## run_tests.gd:
##   godot --headless --path . --script res://tests/smoke_lobby.gd
## Prints "SMOKE: N checks, 0 failed" and exits 1 on any failure.

var _frame := 0
var _lobby: Control   # Lobby (loaded at run time: autoloads do not exist when this compiles)
var _checks := 0
var _fails: Array[String] = []
var _played := []
var _opened := []


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_g().save_path = ""
		_g().boot({})
		_lobby = load("res://src/ui/lobby.gd").new()
		root.add_child(_lobby)
		_lobby.play_pressed.connect(func(n): _played.append(n))
		_lobby.map.building_pressed.connect(func(id): _opened.append(id))
	elif _frame == 4:
		_run()
		print("SMOKE: %d checks, %d failed" % [_checks, _fails.size()])
		for f in _fails:
			print("  FAIL " + f)
		quit(1 if _fails.size() > 0 or _checks == 0 else 0)
	return false


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


## A tap at a content point (base px), through _gui_input like a real finger.
func _tap_at(map: Control, q: Vector2) -> void:
	var p: Vector2 = q * map._k + map._content.position
	_mouse(map, p, true)
	_mouse(map, p, false)


func _mouse(map: Control, p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	map._gui_input(e)


func _run() -> void:
	var map: Control = _lobby.map
	_check(map._nodes.size() == 50, "50 level nodes")
	_check(map._bld.size() == 25, "every building on the map")
	_check(map.selected == 1, "new player: level 1 selected")
	_check(map._scroll > 0.0, "map scrolled down to level 1 (bottom)")

	_tap_at(map, map._nodes[1]["c"])
	_check(_played == [1], "tapping the current level plays it")
	_tap_at(map, map._nodes[2]["c"])
	_check(_played == [1], "a locked level does not play")

	_tap_at(map, map._bld["cafe"]["pos"] - Vector2(0, map._bw * 0.3))
	_check(_opened == ["cafe"], "tapping a building opens it")
	_check(String(_lobby._overlay.get_script().resource_path).ends_with("building_panel.gd"), "building panel is the overlay")
	_check(_lobby.close_overlay(), "back closes the building panel")
	_check(not _lobby.close_overlay(), "nothing left to close")
	_lobby.open_panel(load("res://src/ui/station_panel.gd").new())
	_check(_lobby.close_overlay(), "back closes the station")

	# A drag scrolls and does not tap.
	var before: float = map._scroll
	var start: Vector2 = Vector2(360, 600)
	_mouse(map, start, true)
	for i in 6:
		var m := InputEventMouseMotion.new()
		m.position = start + Vector2(0, 40 * (i + 1))
		map._gui_input(m)
	_mouse(map, start + Vector2(0, 240), false)
	_check(map._scroll < before, "dragging down scrolls up the map")
	_check(_played == [1] and _opened == ["cafe"], "a drag is not a tap")

	# Rebuild the cafe, let it earn, collect through its bubble.
	_g().save["coins"] = 1000
	_check(_g().start_build("cafe"), "cafe build starts")
	var e: Dictionary = _g().save["city"]["cafe"]
	e["built_at"] = _g().now() - 7200
	e["ready_at"] = _g().now() - 3600
	_g().save["city_collected_at"] = _g().now() - 3600
	map.refresh_buildings()
	_check((map._bld["cafe"]["bubble"] as Control).visible, "coin bubble over the earning cafe")
	var coins := int(_g().save["coins"])
	var pending: int = _g().city_pending()
	_check(pending > 0, "storage holds coins")
	_check(map.collect_any(), "bubble collected")
	_check(int(_g().save["coins"]) == coins + pending, "coins added exactly")
	map.refresh_buildings()
	_check(not (map._bld["cafe"]["bubble"] as Control).visible, "bubble gone after collecting")
	_check(_lobby._flying == 1, "coins are flying to the counter")


## The Game autoload (not a compile-time global in a SceneTree script).
func _g() -> Node:
	return root.get_node("/root/Game")

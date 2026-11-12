extends "res://tests/test_case.gd"
## LevelView rules (spec v2 §3-§5) checked on a real view, headless, frame by frame.


var _keep: Array = []


## Builds a playing LevelView for level n with its own World and Fx under the root.
## Returns [view, world, fx]; free them with _drop.
func _view(n: int) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node("Game")
	_keep = [game.save.duplicate(true), game.save_path]
	game.save_path = ""
	game.boot({})
	var world := World.new()
	tree.root.add_child(world)
	var fx := Fx.new()
	fx.font = UiKit.FONT
	tree.root.add_child(fx)
	for node in [world, fx]:
		if not node.is_node_ready():
			node._ready()   # a SceneTree script's root is not live yet: ready by hand
	var view := LevelView.new().setup(Config.level(n), {}, world, fx, UiKit.FONT)
	view.input_enabled = false
	tree.root.add_child(view)
	if not view.is_node_ready():
		view._ready()
	return [view, world, fx]


func _drop(parts: Array) -> void:
	for n in parts:
		(n as Node).get_parent().remove_child(n)
		(n as Node).free()
	var game: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Game")
	game.save = _keep[0]
	game.save_path = _keep[1]


## Spec v2 §3: no slow-downs during a level. L7 has a first rank join (the old 0.3x
## spotlight) and red gates (the old 0.3x lesson) in the first 20 s.
func test_level_view_never_slows_time() -> void:
	var parts := _view(7)
	var view: LevelView = parts[0]
	var lv := Config.level(7)
	var route: Array = lv.get("route", [2, 1, 1, 0, 0])
	var pilot := Autopilot.new(route if not route.is_empty() else [2, 1, 1, 0, 0], true)
	var slow := 0
	var joined := [false]
	view.rank_joined.connect(func(_u, _f): joined[0] = true)
	for f in 1200:
		if view.sim.state != "run":
			break
		pilot.drive(view.sim)
		view._process(1.0 / 60.0)
		if view.time_scale() != 1.0:
			slow += 1
	check(joined[0], "a rank joined during the run (the old spotlight case)")
	eq(slow, 0, "frames run at anything but full speed")
	_drop(parts)


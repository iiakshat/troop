extends "res://tests/test_case.gd"
## Flow pieces owned by main.gd (WIRE): the liberation panel and the per-kind kill counter
## that feeds the missions.


func _add(tree: SceneTree, n: Node) -> void:
	tree.root.add_child(n)
	if not n.is_node_ready() and n.has_method("_ready"):
		n._ready()


func test_liberation_panel_builds_and_closes() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({})
	for d in [1, 5]:
		var p := LiberationPanel.new(d)
		var closed := [false]
		p.closed.connect(func(): closed[0] = true)
		_add(tree, p)
		check(p.get_child_count() >= 2, "liberation %d built its frame" % d)
		check(is_instance_valid(p._close_btn) and p._close_btn.visible, "liberation %d has a visible X" % d)
		p._close_btn.pressed.emit()
		check(closed[0], "liberation %d emits closed" % d)
		tree.root.remove_child(p)
		p.free()
	game.save = keep
	game.save_path = keep_path


func test_kills_are_counted_per_enemy_kind() -> void:
	var sim := LevelSim.new(Config.level(1), Config.units(), {})
	var pilot := Autopilot.new([2, 1, 1, 0, 0], true)
	var guard := 0
	while sim.state == "run" and guard < 20000:
		pilot.drive(sim)
		sim.step(1.0 / 30.0)
		sim.drain()
		guard += 1
	var sum := 0
	for kind in sim.kills_by:
		sum += int(sim.kills_by[kind])
	check(sim.kills > 0, "level 1 autoplay kills someone")
	eq(sum, sim.kills, "per-kind kills add up to the total")

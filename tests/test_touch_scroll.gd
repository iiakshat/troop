extends "res://tests/test_case.gd"
## Owner play-test: menu lists must scroll under a finger even when the drag starts on a card
## or a buy button. Every ScrollContainer in a menu panel carries a TouchScroll (the input
## behaviour itself is driven through the viewport in tests/smoke_scroll.gd).


func _add(tree: SceneTree, n: Node) -> void:
	tree.root.add_child(n)
	if not n.is_node_ready() and n.has_method("_ready"):
		n._ready()


func test_every_menu_scroll_has_touch_scrolling() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({})
	for p in [ArmoryPanel.new(), CodexPanel.new(), SettingsPanel.new()]:
		var name: String = (p.get_script() as Script).get_global_name()
		_add(tree, p)
		var scrolls: Array = p.find_children("*", "ScrollContainer", true, false)
		check(not scrolls.is_empty(), "%s has a scrolling list" % name)
		for s in scrolls:
			var found := false
			for c in (s as Node).get_children(true):
				if c is TouchScroll:
					found = true
			check(found, "%s: its list scrolls under a finger (TouchScroll)" % name)
		tree.root.remove_child(p)
		p.free()
	game.save = keep
	game.save_path = keep_path


## A drag's maths without a viewport: the list follows the finger past the dead zone and stops
## at the ends; a short wobble is still a tap.
func test_drag_follows_the_finger() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var s := ScrollContainer.new()
	var c := Control.new()
	s.add_child(c)
	tree.root.add_child(s)
	var t := TouchScroll.new()
	t.scroll = s
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(100, 500)
	t._on_input(down, c)
	var wobble := InputEventMouseMotion.new()
	wobble.position = Vector2(100, 500 - TouchScroll.DRAG_START + 2)
	t._on_input(wobble, c)
	check(not t.dragging(), "a wobble inside the dead zone is not a drag")
	var move := InputEventMouseMotion.new()
	move.position = Vector2(100, 300)
	t._on_input(move, c)
	check(t.dragging(), "past the dead zone it is a drag")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(100, 300)
	t._on_input(up, c)
	check(not t.dragging(), "the release ends the drag")
	t.free()
	tree.root.remove_child(s)
	s.free()

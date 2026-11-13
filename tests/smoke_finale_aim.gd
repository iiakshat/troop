extends SceneTree
## Runs tests/finale_aim_cases.gd (Bottle Shot held aim and bullet cam) inside a running tree:
## those cases drive real finales, whose global transforms need it. tests/test_finale_aim.gd
## starts this in its own process, so run_tests.gd (and build_apk.bat) gate on it. By hand:
##   godot --headless --path . --script res://tests/smoke_finale_aim.gd
## Prints "FINALE AIM: N tests, F failed" and exits 1 on any failure. Never writes a save.

var _frame := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var game: Node = root.get_node_or_null("Game")
		if game:
			game.save_path = ""
		var script: GDScript = load("res://tests/finale_aim_cases.gd")
		var suite = script.new()
		var total := 0
		var failed := 0
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			suite.failures.clear()
			suite.call(name)
			if suite.failures.is_empty():
				print("  ok    finale_aim_cases.gd :: %s" % name)
			else:
				failed += 1
				print("  FAIL  finale_aim_cases.gd :: %s" % name)
				for message in suite.failures:
					print("        " + message)
		print("FINALE AIM: %d tests, %d failed" % [total, failed])
		quit(1 if failed > 0 or total == 0 else 0)
	return false

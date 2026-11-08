extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exit code is 1 if any test fails, so CI can gate builds on it.


func _initialize() -> void:
	var total := 0
	var failed := 0
	for file in DirAccess.get_files_at("res://tests"):
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		var suite = script.new()
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			suite.failures.clear()
			suite.call(name)
			if suite.failures.is_empty():
				print("  ok    %s :: %s" % [file, name])
			else:
				failed += 1
				print("  FAIL  %s :: %s" % [file, name])
				for message in suite.failures:
					print("        " + message)
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)

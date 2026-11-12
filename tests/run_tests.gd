extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exit code is 1 if any test fails, so CI can gate builds on it.
##
## Tests never touch the player's save: the Game autoload exists here before its _ready runs
## (so its own guard has not kicked in yet), so the runner points it at a throwaway file first,
## and every test that saves and restores Game.save_path restores that throwaway path. Game's
## write_save also refuses user://save.json under any SceneTree script.

const TEST_SAVE := "user://_test_run_save.json"


func _initialize() -> void:
	var game: Node = root.get_node_or_null("Game")
	if game:
		game.save_path = TEST_SAVE
	var total := 0
	var failed := 0
	# `-- only=test_squad,test_level_sim` runs just those files (quick loops while building).
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.trim_prefix("only=").split(",")
	for file in DirAccess.get_files_at("res://tests"):
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == "test_case.gd":
			continue
		if not only.is_empty() and not only.has(file.trim_suffix(".gd")):
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
			if game and game.save_path != TEST_SAVE and game.save_path != "":
				failed += 1
				print("  FAIL  %s :: %s left Game.save_path at %s" % [file, name, game.save_path])
				game.save_path = TEST_SAVE
	for ext in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(TEST_SAVE + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + ext))
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)

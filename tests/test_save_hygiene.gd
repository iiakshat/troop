extends "res://tests/test_case.gd"
## Tests and headless tools never write the player's real save (user://save.json).


func test_runner_points_game_at_a_throwaway_save() -> void:
	var game: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	check(game != null, "Game autoload present")
	if game:
		check(String(game.save_path) != "user://save.json", "Game.save_path is not the real save (%s)" % game.save_path)


func test_game_knows_it_runs_under_a_script() -> void:
	var g: Script = load("res://src/autoload/game.gd")
	check(bool(g.call("scripted")), "a SceneTree script run counts as scripted (write_save refuses save.json)")

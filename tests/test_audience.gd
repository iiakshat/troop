extends "res://tests/test_case.gd"
## Who counts as a child (spec v2 §8, rule 4): under 13 everywhere, under 18 when the device
## region or locale is India (DPDP Act). Unknown age = child. The result decides, before any
## SDK starts, whether Firebase may start and how ads are requested.


func test_under_13_is_child() -> void:
	check(Audience.is_child(2015, 2026, "US", "en_US"), "11 in the US is a child")
	check(Audience.is_child(2014, 2026, "DE", "de_DE"), "12 (born 2014, 2026) is a child")
	check(not Audience.is_child(2013, 2026, "US", "en_US"), "13 by birth year is not a child outside India")


func test_india_under_18_is_child() -> void:
	check(Audience.is_child(2011, 2026, "IN", "en_IN"), "15 in India (region and locale) is a child")
	check(Audience.is_child(2011, 2026, "IN", "en_US"), "15 with region IN is a child")
	check(Audience.is_child(2011, 2026, "", "hi_IN"), "15 with an Indian locale is a child")
	check(Audience.is_child(2009, 2026, "in", "en"), "17 with region 'in' (any case) is a child")
	check(not Audience.is_child(2008, 2026, "IN", "en_IN"), "18 in India is an adult")


func test_adult_outside_india() -> void:
	check(not Audience.is_child(1990, 2026, "US", "en_US"), "36 in the US is an adult")
	check(not Audience.is_child(2011, 2026, "GB", "en_GB"), "15 in the UK is not a child for this rule")
	check(not Audience.is_child(2011, 2026, "", "en"), "15 with no India signal is not a child")


func test_unknown_age_treated_as_child() -> void:
	check(Audience.is_child(0, 2026, "US", "en_US"), "no birth year = child")
	check(Audience.is_child(-5, 2026, "US", "en_US"), "a negative year = child")
	check(Audience.is_child(2031, 2026, "US", "en_US"), "a year in the future = child")
	check(Audience.is_child(1800, 2026, "US", "en_US"), "an impossible year = child")


func test_wheel_years() -> void:
	# The wheel offers this year back to 100 years ago, newest first. It starts with nothing
	# chosen (neutral: no pre-set answer to accept).
	var years := Audience.wheel_years(2026)
	eq(years[0], 2026, "newest first")
	eq(years[years.size() - 1], 1926, "100 years back")
	check(Audience.valid_year(2000, 2026) and not Audience.valid_year(2027, 2026), "valid_year")


func test_region_from_locale() -> void:
	eq(Audience.region_of("en_IN"), "IN", "region from en_IN")
	eq(Audience.region_of("hi-IN"), "IN", "region from hi-IN")
	eq(Audience.region_of("en"), "", "no region in a bare language")


func test_india_clock_counts_as_india() -> void:
	# Godot has no device-region API. An Indian phone set to English (US) still runs on India
	# Standard Time (UTC+5:30, bias 330 minutes), so that clock counts as the region India.
	eq(Audience.region_from("en_US", 330), "IN", "en_US on an Indian clock is India")
	eq(Audience.region_from("en_US", -300), "US", "en_US on a US clock")
	eq(Audience.region_from("hi_IN", 0), "IN", "an Indian locale anywhere")
	eq(Audience.region_from("en", 60), "", "no signal")
	check(Audience.is_child(2011, 2026, Audience.region_from("en_US", 330), "en_US"), "15 on an Indian clock is a child")


func test_game_stores_birth_year_and_child_flag() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({})
	check(game.needs_age(), "a new player has not answered the age screen")
	check(game.is_child(), "unknown age = child")
	var fired := [0]
	var cb := func(): fired[0] += 1
	game.audience_ready.connect(cb)
	game.set_birth_year(1990, "US", "en_US")
	check(not game.needs_age(), "answered")
	check(not game.is_child(), "an adult in the US")
	eq(int(game.save["birth_year"]), 1990, "birth year saved")
	eq(bool(game.save["is_child"]), false, "child flag saved")
	eq(fired[0], 1, "audience_ready fired once")
	game.set_birth_year(2012, "IN", "en_IN")
	check(game.is_child(), "14 in India is a child")
	eq(bool(game.save["is_child"]), true, "child flag saved")
	game.audience_ready.disconnect(cb)
	game.save = keep
	game.save_path = keep_path


func test_age_screen_is_neutral_and_saves() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({})
	check(not AgeScreen.needed({"autoplay": "1"}), "never under autoplay")
	check(not AgeScreen.needed({"save": "_local/x.json"}), "never in debug runs")
	check(AgeScreen.needed({"age": "1"}), "age=1 forces it")
	var s := AgeScreen.new(2026)
	var finished := [0]
	s.done.connect(func(): finished[0] += 1)
	tree.root.add_child(s)
	eq(s.chosen_year(), 0, "nothing chosen at the start")
	check(not s.can_confirm(), "play is off until a year is picked")
	s.confirm()
	eq(finished[0], 0, "confirm does nothing without a year")
	check(game.needs_age(), "still unanswered")
	s.select_year(1995)
	eq(s.chosen_year(), 1995, "wheel moved")
	s.confirm()
	eq(finished[0], 1, "done once")
	eq(int(game.save["birth_year"]), 1995, "answer saved")
	if is_instance_valid(s):
		tree.root.remove_child(s)
		s.free()
	game.save = keep
	game.save_path = keep_path
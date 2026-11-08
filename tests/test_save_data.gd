extends "res://tests/test_case.gd"

var eco := Config.economy()


func test_v1_save_migrates_to_station() -> void:
	var s := SaveData.migrate({"coins": 120, "unlocked": 3, "upgrades": {"knife": 2, "speed": 1, "squad": 9}}, eco)
	eq(s["coins"], 120, "coins kept")
	eq(s["station"]["armory"], 2, "knife -> armory")
	eq(s["station"]["range"], 1, "speed -> range")
	eq(s["station"]["training"], 4, "squad -> training, clamped to max")
	check(not s.has("upgrades"), "old key dropped")
	check((s["owned"] as Array).has("street"), "default outfit owned")


func test_garbage_save_is_safe() -> void:
	var s := SaveData.migrate("not a dict", eco)
	eq(s["coins"], 0, "fresh coins")
	eq(s["unlocked"], 1, "fresh unlock")
	var s2 := SaveData.migrate({"coins": -50, "unlocked": 99, "station": {"armory": 7, "bogus": 3}}, eco)
	eq(s2["coins"], 0, "no negative coins")
	eq(s2["unlocked"], Config.LEVEL_COUNT, "unlock clamped")
	eq(s2["station"]["armory"], 4, "room clamped")
	check(not s2["station"].has("bogus"), "unknown room dropped")


func test_every_room_is_open_and_caps_out() -> void:
	var st := {}
	for room in eco["station"]:
		check(SaveData.room_cost(eco, st, room) > 0, room + " open from the start")
	st["armory"] = 4
	eq(SaveData.room_cost(eco, st, "armory"), -1, "maxed")


func test_station_effects() -> void:
	var fx := SaveData.effects(eco, {"armory": 2, "range": 1, "training": 3, "barracks": 2, "evidence": 2, "garage": 2})
	eq(fx["capacity"], 50, "barracks +25 each")
	eq(fx["knife"], 2, "knife damage")
	eq(fx["squad"], 3, "starting constables")
	eq(fx["coins"], 0.2, "evidence +20%")
	eq(fx["shield"], 1, "garage shield")
	eq(fx["bomb"], 1, "garage bomb")

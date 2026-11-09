extends "res://tests/test_case.gd"

var eco := Config.economy()


func test_v1_save_migrates_to_station() -> void:
	var s := SaveData.migrate({"coins": 120, "unlocked": 3, "upgrades": {"knife": 2, "speed": 1, "squad": 19}}, eco)
	eq(s["coins"], 120, "coins kept")
	eq(s["station"]["armory"], 2, "knife -> armory")
	eq(s["station"]["range"], 1, "speed -> range")
	eq(s["station"]["training"], Economy.room_max("training", eco), "squad -> training, clamped to max")
	check(not s.has("upgrades"), "old key dropped")
	check((s["owned"] as Array).has("street"), "default outfit owned")


func test_garbage_save_is_safe() -> void:
	var s := SaveData.migrate("not a dict", eco)
	eq(s["coins"], 0, "fresh coins")
	eq(s["unlocked"], 1, "fresh unlock")
	var s2 := SaveData.migrate({"coins": -50, "unlocked": 99, "station": {"armory": 17, "bogus": 3}}, eco)
	eq(s2["coins"], 0, "no negative coins")
	eq(s2["unlocked"], Config.LEVEL_COUNT, "unlock clamped")
	eq(s2["station"]["armory"], 10, "room clamped")
	check(not s2["station"].has("bogus"), "unknown room dropped")
	var s3 := SaveData.migrate({"version": 3, "stars": "x", "city": [1], "boosters": {"bomb": "lots"},
		"daily": 5, "missions": {"list": [7, {"nostat": 1}]}, "spin": null, "stats": {"win": "3"}, "rank_seen": [1, "swat", "swat"]}, eco)
	eq(s3["stars"], {}, "junk stars")
	eq(s3["city"], {}, "junk city")
	eq(s3["boosters"]["bomb"], 0, "junk booster count")
	eq(s3["daily"]["day"], 0, "junk daily")
	eq((s3["missions"]["list"] as Array).size(), 0, "junk missions dropped")
	eq(s3["spin"]["ad_used"], 0, "junk spin")
	eq(s3["stats"]["win"], 3, "numeric string stat")
	eq(s3["rank_seen"], ["swat"], "rank_seen cleaned")


func test_rooms_open_by_district_and_cap_out() -> void:
	var st := {}
	for room in eco["station"]:
		check(SaveData.room_cost(eco, st, room, 0) > 0, room + " level 1 open from the start")
	st["armory"] = 3
	eq(SaveData.room_cost(eco, st, "armory", 0), -1, "level 4 needs district 1")
	eq(SaveData.room_lock(eco, st, "armory", 0), 1, "lock names district 1")
	check(SaveData.room_cost(eco, st, "armory", 1) > 0, "open once district 1 is liberated")
	eq(SaveData.room_lock(eco, st, "armory", 1), 0, "no lock")
	st["armory"] = 10
	eq(SaveData.room_cost(eco, st, "armory", 5), -1, "maxed")
	eq(SaveData.room_lock(eco, st, "armory", 0), 0, "maxed is not locked")


func test_station_effects() -> void:
	var fx := SaveData.effects(eco, {"armory": 2, "range": 1, "training": 3, "barracks": 2, "evidence": 2, "garage": 2})
	eq(fx["capacity"], 50, "barracks +25 each")
	eq(fx["knife"], 2, "knife damage")
	eq(fx["squad"], 3, "starting constables")
	eq(fx["coins"], 0.2, "evidence +20%")
	eq(fx["shield"], 1, "garage shield")
	eq(fx["bomb"], 1, "garage bomb")
	var fx4 := SaveData.effects(eco, {"garage": 3})
	eq([fx4["shield"], fx4["bomb"]], [2, 1], "garage 3: shield 2, bomb 1")
	fx4 = SaveData.effects(eco, {"garage": 1})
	eq([fx4["shield"], fx4["bomb"]], [1, 0], "garage 1: shield only")


func test_v2_save_migrates_to_v3() -> void:
	var v2 := {"version": 2, "coins": 900, "unlocked": 4, "station": {"armory": 4, "evidence": 3, "garage": 2},
		"owned": ["street", "steel", "gold", "fire"], "outfit": "gold", "knife": "gold",
		"seen_hints": ["swipe"], "sound": false, "music": true, "vibration": true}
	var s := SaveData.migrate(v2, eco)
	eq(s["version"], SaveData.VERSION, "version bumped")
	eq(SaveData.VERSION, 3, "v3")
	eq(s["coins"], 900, "coins kept")
	eq(s["unlocked"], 4, "progress kept")
	eq(s["station"]["armory"], 4, "station level kept")
	eq(s["station"]["evidence"], 3, "evidence kept")
	eq(s["station"]["garage"], 2, "garage kept")
	eq(s["seen_hints"], ["swipe"], "hints kept")
	eq(s["sound"], false, "settings kept")
	eq(s["outfit"], "gold", "gold outfit stays")
	eq(s["knife"], "golden", "gold knife renamed")
	check((s["owned"] as Array).has("gold") and (s["owned"] as Array).has("golden"), "both gold items kept")
	eq(s["stars"], {"1": 1, "2": 1, "3": 1}, "a star per beaten level")
	for b in SaveData.BOOSTERS:
		eq(s["boosters"][b], int(eco["boosters"]["start"][b]), "starter " + b)
	for k in ["city", "stats"]:
		eq(s[k], {}, k + " empty")
	eq(s["daily"], {"day": 0, "last_claim_date": "", "streak": 0}, "daily fresh")
	eq(s["missions"]["list"], [], "no missions yet")
	eq(s["star_chests_opened"], 0, "no chests")
	eq(s["rank_seen"], [], "no ranks seen")
	eq(s["last_interstitial_level"], 0, "no interstitials yet")


func test_v3_save_round_trips() -> void:
	var s := SaveData.migrate({}, eco)
	s["stars"] = {"1": 3, "2": 2}
	s["city"] = {"cafe": {"lv": 2, "built_at": 100, "ready_at": 145}}
	s["boosters"] = {"headstart": 0, "shield": 4, "bomb": 2}
	s["daily"] = {"day": 3, "last_claim_date": "2026-11-08", "streak": 3}
	s["spin"] = {"date": "2026-11-08", "free_used": 1, "ad_used": 2}
	s["stats"] = {"win": 7, "kill": 1500}
	s["star_chests_opened"] = 1
	s["rank_seen"] = ["sergeant"]
	var back := SaveData.migrate(JSON.parse_string(JSON.stringify(s)), eco)
	for k in ["stars", "boosters", "daily", "spin", "stats", "star_chests_opened", "rank_seen"]:
		eq(back[k], s[k], k + " survives a JSON round trip")
	eq(back["city"]["cafe"]["lv"], 2, "city level survives")
	eq(back["city"]["cafe"]["ready_at"], 145, "city timer survives")
	var bad := SaveData.migrate({"version": 3, "city": {"cafe": {"lv": 9, "built_at": 50, "ready_at": 10}, "nope": {"lv": 1}}}, eco)
	eq(bad["city"]["cafe"]["lv"], City.max_level(eco), "building level clamped")
	eq(bad["city"]["cafe"]["ready_at"], 50, "ready never before built")
	check(not bad["city"].has("nope"), "unknown building dropped")


func test_new_save_gets_starter_boosters() -> void:
	var s := SaveData.migrate({}, eco)
	for b in SaveData.BOOSTERS:
		eq(s["boosters"][b], int(eco["boosters"]["start"][b]), "starter " + b)
	eq(s["stars"], {}, "no stars")

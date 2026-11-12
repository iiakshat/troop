extends "res://tests/test_case.gd"

var eco := Config.economy()


func test_v1_save_migrates_to_station() -> void:
	var s := SaveData.migrate({"coins": 120, "unlocked": 3, "upgrades": {"knife": 2, "speed": 1, "squad": 19}}, eco)
	check(int(s["coins"]) >= 120, "coins kept")
	var paid := SaveData.legacy_spent(eco, "armory", 2) + SaveData.legacy_spent(eco, "range", 1)
	check(Armory.spent(s, "knives") >= paid, "knife + speed -> knife track worth what was paid")
	check(not s["station"].has("armory") and not s["station"].has("range"), "old rooms gone")
	eq(s["station"]["training"], Economy.room_max("training", eco), "squad -> training, clamped to max")
	check(not s.has("upgrades"), "old key dropped")
	check((s["owned"] as Array).has("street"), "default outfit owned")


func test_garbage_save_is_safe() -> void:
	var s := SaveData.migrate("not a dict", eco)
	eq(s["coins"], 0, "fresh coins")
	eq(s["unlocked"], 1, "fresh unlock")
	var s2 := SaveData.migrate({"version": 4, "coins": -50, "unlocked": 99, "station": {"training": 17, "bogus": 3},
		"armory": {"knives": {"tier": 9, "step": 40}, "nope": {"tier": 2}, "shotgun": "x"}, "powers": {"bomb": {"stored": -3}}}, eco)
	eq(s2["coins"], 0, "no negative coins")
	eq(s2["unlocked"], Config.LEVEL_COUNT, "unlock clamped")
	eq(s2["station"]["training"], 10, "room clamped")
	check(Armory.is_maxed(s2, "knives"), "junk tier clamped to the track's end")
	check(not s2["armory"].has("nope") and not s2["armory"].has("shotgun"), "unknown / junk tracks dropped")
	eq(int(s2["powers"]["bomb"]["stored"]), 0, "no negative stored charges")
	check(not s2["station"].has("bogus"), "unknown room dropped")
	var s3 := SaveData.migrate({"version": 3, "stars": "x", "city": [1], "boosters": {"bomb": "lots"},
		"daily": 5, "missions": {"list": [7, {"nostat": 1}]}, "spin": null, "stats": {"win": "3"}, "rank_seen": [1, "swat", "swat"]}, eco)
	eq(s3["stars"], {}, "junk stars")
	eq(s3["city"], {}, "junk city")
	eq(int(s3["powers"]["bomb"]["stored"]), 0, "junk booster count gives no stored bombs")
	check(not s3["boosters"].has("bomb"), "bomb is not a booster token any more")
	eq(s3["daily"]["day"], 0, "junk daily")
	eq((s3["missions"]["list"] as Array).size(), 0, "junk missions dropped")
	eq(s3["spin"]["ad_used"], 0, "junk spin")
	eq(s3["stats"]["win"], 3, "numeric string stat")
	eq(s3["rank_seen"], ["swat"], "rank_seen cleaned")


func test_rooms_open_by_district_and_cap_out() -> void:
	var st := {}
	for room in eco["station"]:
		check(SaveData.room_cost(eco, st, room, 0) > 0, room + " level 1 open from the start")
	st["training"] = 3
	eq(SaveData.room_cost(eco, st, "training", 0), -1, "level 4 needs district 1")
	eq(SaveData.room_lock(eco, st, "training", 0), 1, "lock names district 1")
	check(SaveData.room_cost(eco, st, "training", 1) > 0, "open once district 1 is liberated")
	eq(SaveData.room_lock(eco, st, "training", 1), 0, "no lock")
	st["training"] = 10
	eq(SaveData.room_cost(eco, st, "training", 5), -1, "maxed")
	eq(SaveData.room_lock(eco, st, "training", 0), 0, "maxed is not locked")


func test_station_effects() -> void:
	var fx := SaveData.effects(eco, {"armory": 2, "range": 1, "training": 3, "barracks": 2, "evidence": 2, "garage": 2})
	eq(fx["capacity"], 50, "barracks +25 each")
	eq(fx["squad"], 3, "starting constables")
	eq(fx["coins"], 0.2, "evidence +20%")
	for gone in ["knife", "speed", "shield", "bomb"]:
		check(not fx.has(gone), gone + " moved out of the station (armory / powers)")


func test_v2_save_migrates_to_v4() -> void:
	var v2 := {"version": 2, "coins": 900, "unlocked": 4, "station": {"armory": 4, "evidence": 3, "garage": 2},
		"owned": ["street", "steel", "gold", "fire"], "outfit": "gold", "knife": "gold",
		"seen_hints": ["swipe"], "sound": false, "music": true, "vibration": true}
	var s := SaveData.migrate(v2, eco)
	eq(s["version"], SaveData.VERSION, "version bumped")
	eq(SaveData.VERSION, 4, "v4")
	check(int(s["coins"]) >= 900, "coins kept")
	eq(s["unlocked"], 4, "progress kept")
	check(Armory.spent(s, "knives") >= SaveData.legacy_spent(eco, "armory", 4), "armory 4 -> knife track")
	eq(s["station"]["evidence"], 3, "evidence kept")
	eq([int(s["powers"]["shield"]["stored"]), int(s["powers"]["bomb"]["stored"])], [1, 1], "garage 2 -> stored shield 1, bomb 1")
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
	s["boosters"] = {"headstart": 2}
	s["powers"] = {"shield": {"stored": 4, "ready_at": 900, "used": 1}, "bomb": {"stored": 2, "ready_at": 0, "used": 0}}
	s["armory"] = {"knives": {"tier": 2, "step": 3}}
	s["last_seen_time"] = 777
	s["daily"] = {"day": 3, "last_claim_date": "2026-11-08", "streak": 3}
	s["spin"] = {"date": "2026-11-08", "free_used": 1, "ad_used": 2}
	s["stats"] = {"win": 7, "kill": 1500}
	s["star_chests_opened"] = 1
	s["rank_seen"] = ["sergeant"]
	var back := SaveData.migrate(JSON.parse_string(JSON.stringify(s)), eco)
	for k in ["stars", "boosters", "daily", "spin", "stats", "star_chests_opened", "rank_seen", "powers", "armory", "last_seen_time"]:
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

func test_v3_station_converts_without_loss() -> void:
	var v3 := {"version": 3, "coins": 50, "unlocked": 12, "station": {"armory": 7, "range": 4, "garage": 3, "training": 2},
		"boosters": {"headstart": 1, "shield": 2, "bomb": 5}}
	var s := SaveData.migrate(v3, eco)
	eq(s["version"], 4, "version 4")
	var paid := 0
	for lv in range(1, 8):
		paid += SaveData.legacy_spent(eco, "armory", lv) - SaveData.legacy_spent(eco, "armory", lv - 1)
	paid += SaveData.legacy_spent(eco, "range", 4)
	eq(paid, SaveData.legacy_spent(eco, "armory", 7) + SaveData.legacy_spent(eco, "range", 4), "legacy prices add up")
	check(paid > 0, "the old rooms cost something")
	var worth := Armory.spent(s, "knives") + (int(s["coins"]) - 50)
	check(worth >= paid, "knife track (+ any refund) worth at least what was paid: %d < %d" % [worth, paid])
	check(Armory.spent(s, "knives") - paid < Armory.cost_at("knives", maxi(Armory.index(s, "knives") - 1, 0)), "rounded up by less than one step")
	eq(int(s["powers"]["shield"]["stored"]), 2 + ceili(3 / 2.0), "stored shields: old tokens + ceil(3/2)")
	eq(int(s["powers"]["bomb"]["stored"]), 5 + floori(3 / 2.0), "stored bombs: old tokens + floor(3/2)")
	eq(s["boosters"], {"headstart": 1}, "boosters keep only the head start")
	eq(s["station"], {"training": 2, "barracks": 0, "evidence": 0}, "station keeps squad, cap and coin rooms")
	# Migrating again changes nothing (a v4 save is not converted twice).
	var again := SaveData.migrate(JSON.parse_string(JSON.stringify(s)), eco)
	eq(again["armory"], s["armory"], "armory stable")
	eq(again["powers"], s["powers"], "powers stable")
	eq(again["coins"], s["coins"], "coins stable")


func test_huge_v3_armory_refunds_the_rest() -> void:
	var s := SaveData.migrate({"version": 3, "coins": 0, "station": {"armory": 10, "range": 10}}, eco)
	var paid := SaveData.legacy_spent(eco, "armory", 10) + SaveData.legacy_spent(eco, "range", 10)
	check(Armory.is_maxed(s, "knives") or Armory.spent(s, "knives") >= paid, "track filled")
	eq(Armory.spent(s, "knives") + int(s["coins"]) >= paid, true, "nothing lost: track + refund >= paid")

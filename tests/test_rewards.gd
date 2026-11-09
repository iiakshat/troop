extends "res://tests/test_case.gd"
## Reward dicts and chests.

var eco := Config.economy()


func test_scale_and_apply() -> void:
	var s := SaveData.migrate({}, eco)
	s["coins"] = 10
	s["boosters"] = {"headstart": 0, "shield": 0, "bomb": 0}
	var r := Rewards.scaled({"coins": 100, "bomb": 2}, 1.5, eco)
	eq(r, {"coins": 150, "bomb": 2}, "coins scaled, boosters not")
	Rewards.apply(s, r)
	eq(int(s["coins"]), 160, "coins added")
	eq(int(s["boosters"]["bomb"]), 2, "bombs added")
	Rewards.apply(s, {"cosmetic": "fire"})
	check((s["owned"] as Array).has("fire"), "cosmetic owned")
	Rewards.apply(s, {"cosmetic": "fire"})
	eq((s["owned"] as Array).count("fire"), 1, "owned once")


func test_merge() -> void:
	eq(Rewards.merge({"coins": 10, "bomb": 1}, {"coins": 5, "chest": "star"}), {"coins": 15, "bomb": 1, "chest": "star"}, "sum and copy")


func test_chest_rolls_in_range() -> void:
	var s := SaveData.migrate({}, eco)
	var rng := RandomNumberGenerator.new()
	for id in eco["chests"]:
		if String(id).begins_with("_"):
			continue
		var c: Dictionary = eco["chests"][id]
		for k in 200:
			rng.seed = k
			var r := Rewards.roll_chest(id, rng, s, 1.0, eco)
			eq(r["chest"], id, "chest id kept")
			var coins := int(r["coins"])
			if not r.has("cosmetic") and coins > int(c["coins"][1]):
				check(float(c.get("cosmetic_chance", 0.0)) > 0.0, "%s over range only via cosmetic coins" % id)
			check(coins >= int(c["coins"][0]), "%s coins >= min" % id)
			var n := 0
			for b in Rewards.BOOSTERS:
				n += int(r.get(b, 0))
			check(n >= int(c.get("min_boosters", 0)), "%s at least min boosters" % id)
			if r.has("cosmetic"):
				check(not (s["owned"] as Array).has(r["cosmetic"]), "cosmetic is new")


func test_chest_cosmetic_falls_back_to_coins() -> void:
	var s := SaveData.migrate({}, eco)
	for kind in ["outfits", "knives"]:
		for c in eco["cosmetics"][kind]:
			s["owned"].append(c["id"])
	eq(Rewards.unowned_cosmetics(s, eco), [], "owns everything")
	var e := eco.duplicate(true)
	e["chests"]["t"] = {"coins": [100, 100], "cosmetic_chance": 1.0, "cosmetic_coins": 50}
	var rng := RandomNumberGenerator.new()
	var r := Rewards.roll_chest("t", rng, s, 1.0, e)
	eq(int(r["coins"]), 150, "coins instead of a cosmetic")
	check(not r.has("cosmetic"), "no cosmetic")


func test_resolve_rolls_chest_and_scales_once() -> void:
	var s := SaveData.migrate({}, eco)
	var e := eco.duplicate(true)
	e["chests"]["t"] = {"coins": [100, 100], "headstart": [1, 1]}
	var rng := RandomNumberGenerator.new()
	var r := Rewards.resolve({"coins": 100, "chest": "t"}, rng, s, 2.0, e)
	eq(int(r["coins"]), 400, "own coins x2 + chest coins x2")
	eq(int(r["headstart"]), 1, "chest booster")
	eq(r["chest"], "t", "chest named for the UI")


func test_counts_are_ints_after_json() -> void:
	var r := Rewards.normalized(JSON.parse_string('{"coins": 150.0, "shield": 1.0, "chest": "daily"}'))
	check(r["coins"] is int and r["shield"] is int, "ints")
	eq(r["chest"], "daily", "other keys untouched")
	check(Daily.reward_for_day(3, eco)["shield"] is int, "daily rewards as ints")

extends "res://tests/test_case.gd"
## Daily missions.

var eco := Config.economy()


func _save(level := 5) -> Dictionary:
	var s := SaveData.migrate({}, eco)
	s["unlocked"] = level
	return s


func test_roll_once_per_day_and_deterministic() -> void:
	var a := _save()
	var b := _save()
	check(Missions.roll(a, "2026-11-08", 1234, 5, eco), "rolled")
	check(Missions.roll(b, "2026-11-08", 1234, 5, eco), "rolled")
	eq(a["missions"], b["missions"], "same seed, same missions")
	var n := int(eco["missions"]["per_day"])
	eq(Missions.list(a).size(), n, "3 missions")
	check(not Missions.roll(a, "2026-11-08", 99, 5, eco), "not again the same day")
	check(Missions.needs_roll(a, "2026-11-09"), "a new day needs a roll")
	var stats := {}
	for m in Missions.list(a):
		check(not stats.has(m["stat"]), "distinct stats")
		stats[m["stat"]] = true
		check(int(m["goal"]) > 0, "positive goal")
		check(int(m["reward"].get("coins", 0)) > 0, "pays coins")


func test_min_level_filter() -> void:
	for seed in 30:
		var s := _save(1)
		Missions.roll(s, "2026-11-08", seed, 1, eco)
		for m in Missions.list(s):
			var def: Dictionary = {}
			for e in eco["missions"]["pool"]:
				if e["id"] == m["id"]:
					def = e
			check(int(def.get("min_level", 1)) <= 1, "%s allowed at level 1" % m["id"])


func test_goals_grow_with_level() -> void:
	var lo := 0
	var hi := 0
	for seed in 20:
		var a := _save(1)
		var b := _save(50)
		var e := eco.duplicate(true)
		e["missions"]["pool"] = [eco["missions"]["pool"][0]]
		e["missions"]["per_day"] = 1
		Missions.roll(a, "d", seed, 1, e)
		Missions.roll(b, "d", seed, 50, e)
		lo += int(Missions.list(a)[0]["goal"])
		hi += int(Missions.list(b)[0]["goal"])
	check(hi > lo, "deeper players get bigger goals")


func test_record_claim_and_bonus() -> void:
	var s := _save()
	var e := eco.duplicate(true)
	e["missions"]["pool"] = [
		{"id": "win", "stat": "win", "goal": [2, 2], "step": 1, "coins": 100, "weight": 1},
		{"id": "bottle", "stat": "bottle", "goal": [5, 5], "step": 1, "coins": 100, "weight": 1, "reward": {"bomb": 1}},
		{"id": "kill", "stat": "kill", "goal": [100, 100], "step": 50, "coins": 100, "weight": 1},
	]
	Missions.roll(s, "2026-11-08", 7, 1, e)
	var idx := {}
	for i in Missions.list(s).size():
		idx[Missions.list(s)[i]["stat"]] = i
	eq(Missions.record(s, "win", 1), [], "1 of 2")
	eq(Missions.record(s, "win", 1), [idx["win"]], "done on the second win")
	eq(int(Missions.list(s)[idx["win"]]["progress"]), 2, "progress capped at goal")
	Missions.record(s, "win", 5)
	eq(int(Missions.list(s)[idx["win"]]["progress"]), 2, "stays at goal")
	eq(int(s["stats"]["win"]), 7, "lifetime stat counts everything")
	eq(Missions.claimable(s), [idx["win"]], "claimable")
	var r := Missions.claim(s, idx["win"])
	eq(int(r["coins"]), 100, "mission reward")
	eq(Missions.claim(s, idx["win"]), {}, "claimed once")
	check(not Missions.bonus_ready(s), "bonus needs all three")
	Missions.record(s, "bottle", 5)
	Missions.record(s, "kill", 250)
	var rb := Missions.claim(s, idx["bottle"])
	eq(int(rb.get("bomb", 0)), 1, "extra reward kept")
	Missions.claim(s, idx["kill"])
	check(Missions.bonus_ready(s), "bonus ready")
	eq(Missions.claim_bonus(s, e), {"chest": String(e["missions"]["bonus_chest"])}, "bonus chest")
	check(not Missions.bonus_ready(s), "bonus once")
	eq(Missions.claim_bonus(s, e), {}, "no second bonus")
	eq(Missions.record(s, "nothing", 0), [], "zero amount ignored")
	eq(Missions.claim(s, 9), {}, "bad index")


func test_clock_going_back_does_not_reroll() -> void:
	var s := _save()
	check(Missions.roll(s, "2026-11-09", 1, 5, eco), "rolled today")
	check(not Missions.needs_roll(s, "2026-11-08"), "a day back: no roll")
	check(not Missions.roll(s, "2026-11-01", 2, 5, eco), "far back: no roll")
	check(not Missions.needs_roll(s, "2026-11-09"), "back to today: same missions")
	check(Missions.needs_roll(s, "2026-11-10"), "a real new day rolls")

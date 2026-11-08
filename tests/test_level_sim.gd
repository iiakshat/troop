extends "res://tests/test_case.gd"

var units := Config.units()


func _run(level: Dictionary, lanes: Array, powers := true) -> Dictionary:
	return Autopilot.run(level, units, lanes, {}, powers)


func _gate_level(gates: Array, extra: Array = []) -> Dictionary:
	var events: Array = [{"at": 20, "type": "gates", "gates": gates}]
	events.append_array(extra)
	events.append({"at": 60, "type": "finish"})
	return {"events": events}


func test_gate_applies_in_chosen_lane_only() -> void:
	var lvl := _gate_level([{"lane": 0, "op": "num", "v": 5}, {"lane": 2, "op": "num", "v": 9}])
	eq(_run(lvl, [2])["troops"], 10, "right lane +9")
	eq(_run(lvl, [0])["troops"], 6, "left lane +5")
	eq(_run(lvl, [1])["troops"], 1, "middle empty")


func test_red_gate_flips_when_shot() -> void:
	var lvl := _gate_level([{"lane": 1, "op": "num", "v": -5, "step": 0.5, "max": 7}])
	var r := _run(lvl, [1])
	eq(r["state"], "strike", "survived")
	eq(r["troops"], 8, "-5 shot up to +7")


func test_unshot_red_gate_can_kill_the_hero() -> void:
	var lvl := _gate_level([{"lane": 1, "op": "num", "v": -5}])
	var r := _run(lvl, [1])
	eq(r["state"], "lost", "hero lost to gate")
	eq(r["cause"], "gate", "cause")


func test_gang_trades_one_for_one_on_contact() -> void:
	# 30 thugs vs hero + 50: some die to fire, the rest take one troop each.
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 50}]},
		{"at": 40, "type": "wave", "groups": [{"enemy": "brute", "n": 3}]},
		{"at": 70, "type": "finish"}]}
	var r := _run(lvl, [1])
	eq(r["state"], "strike", "survived")
	eq(r["troops"], 51 - 3 * 4, "brutes immune to pistols, each takes 4")


func test_armour_off_gate_strips_next_gang() -> void:
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 30}]},
		{"at": 30, "type": "gates", "gates": [{"lane": 0, "op": "foe_strip"}, {"lane": 1, "op": "num", "v": 0}]},
		{"at": 70, "type": "wave", "groups": [{"enemy": "brute", "n": 3}]},
		{"at": 100, "type": "finish"}]}
	eq(_run(lvl, [1, 0])["troops"], 31, "armour off: brutes shot down")
	eq(_run(lvl, [1, 1])["troops"], 31 - 12, "armour on: brutes reach the squad")


func test_foe_halving_and_bomb() -> void:
	var lvl := {"charges": {"bomb": 1}, "events": [
		{"at": 20, "type": "gates", "gates": [{"lane": 0, "op": "foe_div", "k": 2}]},
		{"at": 140, "type": "wave", "groups": [{"enemy": "thug", "n": 100}]},
		{"at": 170, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(0)
	var halved := false
	for i in 3000:
		sim.step(1.0 / 30.0)
		for e in sim.drain():
			if e["type"] == "horde_spawn":
				eq(int(e["horde"]["count"]), 50, "spawned already halved")
				halved = true
		if halved:
			break
	check(halved, "gang spawned")
	var h: Dictionary = sim.hordes[0]
	while float(h["z"]) < -sim.fire_range:
		sim.step(1.0 / 30.0)
	var before: int = h["count"]
	check(sim.use_power("bomb"), "bomb used")
	eq(int(h["count"]), before - maxi(int(before * 0.5), 10), "bomb wipes half")
	check(not sim.use_power("bomb"), "no charges left")


func test_levels_are_winnable_and_reward_planning() -> void:
	var l1 := Config.level(1)
	eq(_run(l1, [2, 1, 1])["state"], "strike", "L1 smart path wins")
	eq(_run(l1, [0, 0, 0])["state"], "strike", "L1 weakest real path still wins")
	var l2 := Config.level(2)
	var smart2 := _run(l2, [0, 2, 2, 0])
	var sloppy2 := _run(l2, [2, 0, 0, 2])
	eq(smart2["state"], "strike", "L2 planned path wins")
	check(int(smart2["troops"]) > int(sloppy2["troops"]), "L2 planning beats sloppy")
	var l3 := Config.level(3)
	eq(_run(l3, [1, 1, 2, 0, 0])["state"], "strike", "L3 planned path wins")
	var greedy := _run(l3, [1, 1, 2, 0, 2])
	check(int(_run(l3, [1, 1, 2, 0, 0])["troops"]) > int(greedy["troops"]), "L3 armour-off beats greedy +20")


func test_save_helpers() -> void:
	var eco := Config.economy()
	eq(SaveData.upgrade_cost(eco, "knife", 0), 60, "first knife cost")
	eq(SaveData.upgrade_cost(eco, "knife", 3), -1, "maxed")
	var clean := SaveData.clean_upgrades({"knife": 99, "bogus": 3}, eco)
	eq(clean["knife"], 3, "clamped")
	check(not clean.has("bogus"), "unknown dropped")
	eq(clean["squad"], 0, "missing filled")

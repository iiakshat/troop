extends "res://tests/test_case.gd"

var units := Config.units()


func _run(level: Dictionary, lanes: Array, powers := true) -> Dictionary:
	return Autopilot.run(level, units, lanes, {}, powers)


func _gate_level(gates: Array, extra: Array = []) -> Dictionary:
	var events: Array = [{"at": 20, "type": "gates", "gates": gates}]
	events.append_array(extra)
	events.append({"at": 60, "type": "finish"})
	return {"events": events}


func _step_until(sim: LevelSim, cond: Callable, max_steps := 6000) -> Array:
	var seen: Array = []
	for i in max_steps:
		sim.step(1.0 / 30.0)
		seen.append_array(sim.drain())
		if cond.call():
			break
	return seen


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
	var r := _run(_gate_level([{"lane": 1, "op": "num", "v": -5}]), [1])
	eq(r["state"], "lost", "hero lost to gate")
	eq(r["cause"], "gate", "cause")


func test_nothing_hurts_until_the_living_front_arrives() -> void:
	# Hero alone vs 30 thugs: the front rows die at range, so the gang's front moves back.
	var lvl := {"events": [{"at": 60, "type": "wave", "groups": [{"enemy": "thug", "n": 30}]}, {"at": 90, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	var first_hurt_front := 999.0
	for i in 6000:
		sim.step(1.0 / 30.0)
		for e in sim.drain():
			if e["type"] == "melee" and first_hurt_front > 900.0:
				first_hurt_front = 0.0
				for h in sim.hordes:
					first_hurt_front = LevelSim.front_z(h)
		if sim.state != "run":
			break
	check(first_hurt_front > sim.contact_z - 1.0, "first melee only once the living front reached the squad (front %.2f)" % first_hurt_front)


func test_melee_trades_row_by_row() -> void:
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 60}]},
		{"at": 50, "type": "wave", "groups": [{"enemy": "brute", "n": 10}]},
		{"at": 90, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	var seen := _step_until(sim, func(): return sim.state != "run")
	var melees := seen.filter(func(e): return e["type"] == "melee")
	eq(melees.size(), 2, "10 brutes in rows of 5 strike in two rows")
	eq(int(melees[0]["lost"]), 20, "a row of 5 brutes takes 4 each")
	eq(sim.squad.total(), 61 - 40, "squad paid 4 per brute")
	eq(sim.state, "strike", "survived")


func test_bigger_gang_wipes_the_squad() -> void:
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 5}]},
		{"at": 40, "type": "wave", "groups": [{"enemy": "brute", "n": 5}]},
		{"at": 80, "type": "finish"}]}
	var r := _run(lvl, [1], false)
	eq(r["state"], "lost", "5 brutes x4 beat 6 troops")
	eq(r["cause"], "brute", "cause")


func test_bullets_hit_the_nearest_thing_in_the_lane() -> void:
	# A red gate in front of a gang soaks the bullets until it is maxed out.
	var lvl := {"events": [
		{"at": 30, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": -3, "step": 1, "max": 4}]},
		{"at": 60, "type": "wave", "groups": [{"enemy": "thug", "n": 4}]},
		{"at": 90, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	var saw_gate_target := false
	for i in 3000:
		sim.step(1.0 / 30.0)
		sim.drain()
		if sim.target_kind == "gate":
			saw_gate_target = true
			for h in sim.hordes:
				check(LevelSim.front_z(h) < float(sim.target_ref["z"]), "gang was behind the gate while the gate was shot")
		if sim.state != "run":
			break
	check(saw_gate_target, "the gate was shot")
	eq(sim.state, "strike", "survived")


func test_barrel_blows_up_a_passing_gang() -> void:
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 2}]},
		{"at": 70, "type": "obstacle", "kind": "barrel", "lane": 1, "hp": 6, "radius": 8, "kill": 40},
		{"at": 64, "type": "wave", "groups": [{"enemy": "thug", "n": 45}]},
		{"at": 90, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	var seen := _step_until(sim, func(): return sim.state != "run")
	var booms := seen.filter(func(e): return e["type"] == "barrel_boom")
	eq(booms.size(), 1, "barrel exploded")
	check(int(booms[0]["killed"]) > 0, "blast killed gang members")


func test_turncoat_converts_part_of_the_next_gang() -> void:
	var lvl := {"events": [
		{"at": 20, "type": "gates", "gates": [{"lane": 1, "op": "turncoat", "n": 8}]},
		{"at": 140, "type": "wave", "groups": [{"enemy": "thug", "n": 5}]},
		{"at": 170, "type": "finish"}]}
	var r := _run(lvl, [1])
	eq(r["troops"], 1 + 5, "only the 5 that exist can switch sides")
	eq(r["state"], "strike", "nothing left to fight")


func test_riot_shields_soak_pistols_but_not_inspectors() -> void:
	var stats: Dictionary = units["allies"]
	var cops := Squad.new()
	cops.add("constable", 10)
	check(cops.pierce_dps(stats, {}, 1.0) == 0.0, "pistols don't pierce")
	var insp := Squad.new()
	insp.add("inspector", 2)
	check(insp.pierce_dps(stats, {}, 1.0) > 0.0, "inspectors pierce")


func test_swat_bursts_hit_two_weak_enemies() -> void:
	var stats: Dictionary = units["allies"]
	var s := Squad.new()
	s.counts["hero"] = 0
	s.add("swat", 1)
	eq(s.dps(stats, {}, 0, 1.0), 6.0, "1 dmg x 3/s x 2 enemies")
	eq(s.dps(stats, {}, 0, 8.0), 3.0, "no double hit on tough enemies")


func test_foe_halving_and_bomb() -> void:
	var lvl := {"charges": {"bomb": 1}, "events": [
		{"at": 20, "type": "gates", "gates": [{"lane": 0, "op": "foe_div", "k": 2}]},
		{"at": 200, "type": "wave", "groups": [{"enemy": "thug", "n": 100}]},
		{"at": 230, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(0)
	var spawned := _step_until(sim, func(): return not sim.hordes.is_empty())
	for e in spawned:
		if e["type"] == "horde_spawn":
			eq(int(e["horde"]["count"]), 50, "spawned already halved")
	var h: Dictionary = sim.hordes[0]
	_step_until(sim, func(): return LevelSim.front_z(h) > -40.0)
	var before: int = h["count"]
	check(sim.use_power("bomb"), "bomb used")
	eq(int(h["count"]), before - maxi(int(before * 0.5), 10), "bomb wipes half")
	check(not sim.use_power("bomb"), "no charges left")


func test_bomb_on_the_boss_is_flat_damage() -> void:
	var lvl := {"charges": {"bomb": 1}, "events": [
		{"at": 60, "type": "wave", "groups": [{"enemy": "boss", "n": 1}]}, {"at": 200, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	_step_until(sim, func(): return not sim.hordes.is_empty() and LevelSim.front_z(sim.hordes[0]) > -40.0)
	check(sim.use_power("bomb"), "bomb used on boss")
	eq(int(sim.hordes[0]["count"]), 1, "boss survives a single bomb")


func test_levels_are_winnable_and_reward_planning() -> void:
	var l1 := Config.level(1)
	eq(_run(l1, [2, 1, 1])["state"], "strike", "L1 smart path wins")
	eq(_run(l1, [0, 0, 0])["state"], "strike", "L1 weakest real path still wins")
	var l2 := Config.level(2)
	var smart2 := _run(l2, [2, 2, 2, 0])
	eq(smart2["state"], "strike", "L2 planned path wins")
	check(int(smart2["troops"]) > int(_run(l2, [2, 0, 0, 2])["troops"]), "L2 add-then-multiply beats the reverse")
	eq(_run(Config.level(3), [0, 2, 1])["state"], "strike", "L3 planned path wins")
	eq(_run(Config.level(4), [1, 2, 0])["state"], "strike", "L4 planned path wins")
	eq(_run(Config.level(5), [1, 2, 1, 0])["state"], "strike", "L5 planned path beats the Kingpin")

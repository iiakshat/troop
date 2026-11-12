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
	# Brutes too tough to shoot down in time, so this checks melee alone.
	var tough: Dictionary = units.duplicate(true)
	tough["enemies"]["brute"]["hp"] = 100000
	var sim := LevelSim.new(lvl, tough)
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
	var one: float = float(stats["swat"]["dmg"]) * float(stats["swat"]["rate"])
	eq(s.dps(stats, {}, 0, 1.0), one * 2.0, "dmg x rate x 2 enemies")
	eq(s.dps(stats, {}, 0, 8.0), one, "no double hit on tough enemies")


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
	# Every level stores a winning lane route found by tests/tune.gd (`route`; levels 1-10
	# also `route_np`, which wins without powers). Random routes (sampled, seeded) must not
	# do better than the planned one on average: planning pays.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var planned_better := 0
	for n in range(1, Config.LEVEL_COUNT + 1):
		var lv := Config.level(n)
		var route: Array = lv.get("route", [])
		check(not route.is_empty(), "L%d has a stored route" % n)
		var best := _run(lv, route)
		eq(best["state"], "strike", "L%d planned route wins" % n)
		if n <= 10:
			eq(_run(lv, lv.get("route_np", route), false)["state"], "strike", "L%d wins without powers" % n)
		if n % 3 != 1 and n > 3:
			continue  # sample: random routes on a third of the levels keep the suite fast
		var rows := Autopilot.gate_row_count(lv)
		var sum := 0
		for i in 4:
			var r: Array = []
			for j in rows:
				r.append(rng.randi_range(0, 2))
			var res := _run(lv, r)
			sum += int(res["troops"]) if res["state"] == "strike" else 0
		check(int(best["troops"]) * 4 >= sum, "L%d planned route beats random routes on average" % n)
		if int(best["troops"]) * 4 > sum:
			planned_better += 1
	check(planned_better >= 10, "planning clearly pays on most sampled levels (%d)" % planned_better)
	# Operation order (level 2, rows 2-3): +12 then x3 beats x3 then +12.
	var l2 := Config.level(2)
	var smart := LevelSim.new(l2, units)
	Autopilot.play(smart, Autopilot.new([0, 2, 2]), 1.0 / 30.0, 3)
	var rev := LevelSim.new(l2, units)
	Autopilot.play(rev, Autopilot.new([0, 0, 0]), 1.0 / 30.0, 3)
	check(smart.squad.total() > rev.squad.total(), "L2 add-then-multiply beats the reverse (%d vs %d)" % [smart.squad.total(), rev.squad.total()])


# ---------------------------------------------------------------- v1 rules

func _events_of(seen: Array, type: String) -> Array:
	return seen.filter(func(e): return e["type"] == type)


## Steps until an event of `type` appears; returns that event ({} if it never did).
func _until_event(sim: LevelSim, type: String, max_steps := 6000) -> Dictionary:
	for i in max_steps:
		sim.step(1.0 / 30.0)
		var found := _events_of(sim.drain(), type)
		if not found.is_empty():
			return found[0]
		if sim.state != "run":
			break
	return {}


func test_boss_walks_in_shooting_and_never_holds_distance() -> void:
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 80}]},
		{"at": 120, "type": "wave", "label": "KINGPIN", "groups": [{"enemy": "boss", "n": 1, "hp": 1200}]},
		{"at": 150, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	var hits: Array = []
	var shots_walking := 0
	var last_front := -INF
	var closing := true
	var halted := true
	var finish_early := false
	for i in 9000:
		sim.step(1.0 / 30.0)
		for e in sim.drain():
			match String(e["type"]):
				"boss_hit":
					hits.append({"t": sim.time, "hp": int(e["hp"]), "max": int(e["max"])})
				"hurt":
					for h in sim.hordes:
						if h["boss"] and String(e["cause"]) == "boss" and not h["stopped"] and not h["melee"]:
							shots_walking += 1
				"finish":
					finish_early = finish_early or not sim.hordes.is_empty()
		for h in sim.hordes:
			if not h["boss"]:
				continue
			check(not h["stopped"], "a boss never stops to hold a distance")
			check(int(h.get("max_hp", 0)) == 1200, "boss carries max_hp")
			var f := LevelSim.front_z(h)
			if f < last_front - 1e-4:
				closing = false
			last_front = f
			if f >= -sim.boss_halt + 3.0 and sim.S > 0.0:
				halted = false
		if sim.state != "run":
			break
	check(closing, "the boss only ever comes closer")
	check(halted, "the street stops while the boss walks in, so he never drifts backwards")
	check(shots_walking > 0, "the boss shoots while walking")
	eq(sim.state, "strike", "planned squad beats the boss")
	check(not finish_early, "no finish while the boss lives")
	check(hits.size() >= 3, "boss_hit events (%d)" % hits.size())
	if hits.size() < 3:
		return
	eq(int(hits[-1]["hp"]), 0, "last boss_hit reports 0 hp")
	eq(int(hits[0]["max"]), 1200, "boss_hit max")
	for n in range(1, hits.size() - 1):
		check(float(hits[n]["t"]) - float(hits[n - 1]["t"]) >= sim.boss_hit_every - 1e-3, "boss_hit throttled")
	for n in range(1, hits.size()):
		check(int(hits[n]["hp"]) <= int(hits[n - 1]["hp"]), "boss hp only falls")


func test_failing_squad_meets_the_boss_in_melee() -> void:
	var lvl := {"events": [
		{"at": 60, "type": "wave", "groups": [{"enemy": "boss", "n": 1, "hp": 5000, "shot_dmg": 0}]},
		{"at": 90, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	var seen := _step_until(sim, func(): return sim.state != "run", 20000)
	eq(sim.state, "lost", "hero alone loses")
	check(not _events_of(seen, "melee_start").is_empty(), "the boss walked all the way into melee")


func test_finish_waits_for_every_gang_and_always_ends() -> void:
	# A wave scheduled after the HQ: the squad holds short of it, the gang pours out early.
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 30}]},
		{"at": 50, "type": "wave", "groups": [{"enemy": "brute", "n": 6}]},
		{"at": 200, "type": "wave", "groups": [{"enemy": "thug", "n": 20}]},
		{"at": 60, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	var bad := false
	var seen: Array = []
	for i in 20000:
		sim.step(1.0 / 30.0)
		var ev := sim.drain()
		seen.append_array(ev)
		var live: bool = not sim.hordes.is_empty() or sim._pending_hordes > 0
		if live and sim.traveled > sim.finish_at - sim.finish_hold + 0.1:
			bad = true
		for e in ev:
			if e["type"] == "finish" and live:
				bad = true
		if sim.state != "run":
			break
	check(not bad, "the HQ never scrolls past a live or pending gang")
	eq(sim.state, "strike", "the level ended")
	eq(_events_of(seen, "horde_spawn").size(), 2, "both gangs came out")


func _ranged_level(enemy: String, n: int) -> Dictionary:
	return {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 60}]},
		{"at": 90, "type": "wave", "groups": [{"enemy": enemy, "n": n, "hp": 4000}]},
		{"at": 140, "type": "finish"}]}


func test_molotov_firebomb_hits_the_lane_it_was_thrown_at() -> void:
	var sim := LevelSim.new(_ranged_level("molotov", 2), units)
	sim.set_lane(1)
	var throw := _until_event(sim, "firebomb_throw")
	check(not throw.is_empty(), "a firebomb was thrown")
	if throw.is_empty():
		return
	eq(int(throw["lane"]), 1, "thrown at the squad's lane")
	check(float(throw["t"]) > 0.0, "flight time given")
	var burn := 2 * int(units["enemies"]["molotov"]["burn"])
	# Stay: burn. Step aside: nothing. Shield: blocked.
	var stay := sim.clone()
	var hit := _until_event(stay, "firebomb_hit")
	eq(int(hit.get("lost", -1)), burn, "stayed in the lane: burned")
	eq(bool(hit.get("blocked", true)), false, "not blocked")
	var dodge := sim.clone()
	dodge.set_lane(0)
	var before := dodge.squad.total()
	hit = _until_event(dodge, "firebomb_hit")
	eq(int(hit.get("lost", -1)), 0, "stepped aside: no burn")
	eq(dodge.squad.total(), before, "squad intact")
	var shield := sim.clone()
	shield.charges["shield"] = 1
	check(shield.use_power("shield"), "shield up")
	hit = _until_event(shield, "firebomb_hit")
	eq(bool(hit.get("blocked", false)), true, "shield blocks the firebomb")
	eq(int(hit.get("lost", -1)), 0, "no burn under the shield")


func test_sniper_foe_aims_then_fires() -> void:
	var sim := LevelSim.new(_ranged_level("sniper_foe", 3), units)
	sim.set_lane(1)
	check(not _until_event(sim, "snipe_aim").is_empty(), "laser telegraph")
	var aim_t := sim.time
	var shielded := sim.clone()
	var shot := _until_event(sim, "snipe")
	eq(int(shot.get("lost", -1)), 3 * int(units["enemies"]["sniper_foe"]["shot_dmg"]), "each sniper kills shot_dmg")
	var aim := float(units["enemies"]["sniper_foe"]["aim"])
	check(absf(sim.time - aim_t - aim) < 0.1, "laser shows `aim` seconds before the shot")
	shielded.charges["shield"] = 1
	check(shielded.use_power("shield"), "shield up")
	shot = _until_event(shielded, "snipe")
	eq(bool(shot.get("blocked", false)), true, "shield blocks the sniper")
	eq(int(shot.get("lost", -1)), 0, "nobody lost")


func test_grenadier_shot_kills_three() -> void:
	var sim := LevelSim.new(_ranged_level("grenadier", 2), units)
	sim.set_lane(1)
	var hurt := _until_event(sim, "hurt")
	eq(String(hurt.get("cause", "")), "grenadier", "cause")
	eq(int(hurt.get("n", -1)), 2 * int(units["enemies"]["grenadier"]["shot_dmg"]), "2 grenadiers x 3")


func test_pothole_costs_troops_in_its_lane_only() -> void:
	var lvl := _gate_level([{"lane": 0, "op": "num", "v": 10}, {"lane": 1, "op": "num", "v": 10}, {"lane": 2, "op": "num", "v": 10}],
		[{"at": 40, "type": "obstacle", "kind": "pothole", "lane": 1, "fall": 3},
		 {"at": 45, "type": "obstacle", "kind": "pothole", "lane": 2, "fall_pct": 50}])
	eq(_run(lvl, [0])["troops"], 11, "left lane: no hole")
	eq(_run(lvl, [1])["troops"], 8, "middle: fell in, -3")
	eq(_run(lvl, [2])["troops"], 6, "right: -50% rounded down")
	var deep := {"events": [{"at": 30, "type": "obstacle", "kind": "pothole", "lane": 1, "fall": 9}, {"at": 60, "type": "finish"}]}
	var alone := _run(deep, [1])
	eq(alone["state"], "strike", "the hero hops over: a pothole never ends the level")
	eq(alone["troops"], 1, "hero alone")
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	var seen := _step_until(sim, func(): return sim.state != "run")
	var pass_ev := _events_of(seen, "pothole_pass")
	eq(pass_ev.size(), 1, "one pothole_pass")
	if pass_ev.size() == 1:
		eq(int(pass_ev[0]["lost"]), 3, "lost 3")
		eq(int(pass_ev[0]["lane"]), 1, "lane")
	for e in seen:
		check(not (e["type"] == "obstacle_broken" and String(e["ob"]["kind"]) == "pothole"), "potholes can't be shot away")


func _barricade_level(hp: int) -> Dictionary:
	return {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 10}]},
		{"at": 60, "type": "obstacle", "kind": "barricade", "lane": 1, "hp": hp, "dmg": 4},
		{"at": 66, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 20}]},
		{"at": 100, "type": "finish"}]}


func test_barricade_shoot_it_or_pay_and_lose_the_gate() -> void:
	eq(_run(_barricade_level(3), [1, 1])["troops"], 31, "barricade shot down: gate behind it counts")
	var sim := LevelSim.new(_barricade_level(100000), units)
	sim.set_lane(1)
	var seen := _step_until(sim, func(): return sim.state != "run")
	var hit := _events_of(seen, "barricade_hit")
	eq(hit.size(), 1, "crashed into the barricade")
	if hit.size() == 1:
		eq(int(hit[0]["lost"]), 4, "cost dmg troops")
	var rp := _events_of(seen, "row_pass")
	eq(bool(rp[-1]["blocked"]), true, "the gate behind it is wrecked")
	eq(sim.squad.total(), 11 - 4, "no +20")


func test_sniper_rank_shoots_the_toughest_gang() -> void:
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "recruit", "unit": "sniper", "n": 3}]},
		{"at": 90, "type": "wave", "groups": [{"enemy": "thug", "n": 60}, {"enemy": "brute", "n": 3, "gap": 6}]},
		{"at": 140, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	var both := func() -> bool:
		if sim.hordes.size() < 2:
			return false
		for h in sim.hordes:
			if LevelSim.front_z(h) < -sim.fire_range:
				return false
		return sim.snipe_ref != null
	_step_until(sim, both)
	check(sim.snipe_ref != null and String(sim.snipe_ref["enemy"]) == "brute", "snipers pick the brutes behind the thugs")
	check(sim.target_ref != null and String(sim.target_ref["enemy"]) == "thug", "everyone else shoots the front")


func test_rank_join_reports_the_first_arrival() -> void:
	var lvl := _gate_level([{"lane": 1, "op": "recruit", "unit": "sergeant", "n": 3}],
		[{"at": 40, "type": "gates", "gates": [{"lane": 1, "op": "recruit", "unit": "sergeant", "n": 2}]}])
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	var seen := _step_until(sim, func(): return sim.state != "run")
	var joins := _events_of(seen, "rank_join")
	eq(joins.size(), 2, "two recruit gates")
	if joins.size() == 2:
		eq(bool(joins[0]["first_time"]), true, "first sergeants")
		eq(bool(joins[1]["first_time"]), false, "then not first")
	eq(sim.squad.count("sergeant"), 5, "5 sergeants")


func test_stars_peak_and_revive() -> void:
	var lvl := _gate_level([{"lane": 1, "op": "num", "v": 19}], [{"at": 40, "type": "obstacle", "kind": "pothole", "lane": 1, "fall": 10}])
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	check(sim.stars() == 0, "no stars before the finish")
	_step_until(sim, func(): return sim.state != "run")
	eq(sim.peak_squad, 20, "peak squad")
	eq(sim.stars(), 2, "half the peak left: 2 stars (30/55)")
	lvl["stars"] = {"star2": 60, "star3": 80}
	var strict := LevelSim.new(lvl, units)
	strict.set_lane(1)
	_step_until(strict, func(): return strict.state != "run")
	eq(strict.stars(), 1, "level thresholds")
	eq(_run(_gate_level([{"lane": 1, "op": "num", "v": 9}]), [1])["stars"], 3, "untouched squad: 3 stars")

	var lose := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 20}]},
		{"at": 60, "type": "wave", "groups": [{"enemy": "brute", "n": 10, "hp": 100000}]},
		{"at": 100, "type": "finish"}]}
	var ls := LevelSim.new(lose, units)
	ls.set_lane(1)
	_step_until(ls, func(): return ls.state != "run")
	eq(ls.state, "lost", "lost to brutes")
	eq(ls.stars(), 0, "a loss has no stars")
	check(not LevelSim.new(lose, units).revive(5), "no revive while running")
	var n := ls.revive_troops()
	eq(n, 11, "50% of the peak of 21, rounded up")
	check(ls.revive(n), "revived")
	eq(ls.state, "run", "running again")
	eq(ls.squad.total(), 11, "squad back")
	var rev := _events_of(ls.drain(), "revive")
	eq(rev.size(), 1, "revive event")
	if rev.size() == 1:
		eq(int(rev[0]["troops"]), 11, "revive event troops")
	for h in ls.hordes:
		check(LevelSim.front_z(h) <= -float(units["revive"]["push"]) + 0.01, "gangs pushed back")
	check(ls.shield_t > 0.0, "a short shield covers the restart")
	_step_until(ls, func(): return ls.state != "run")
	check(not ls.revive(n), "only once per level")


func test_boosters_come_in_through_upgrades() -> void:
	var lvl := {"charges": {"shield": 1}, "events": [{"at": 60, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units, {"headstart": 2, "shield": 1, "bomb": 2})
	eq(sim.squad.total(), 1 + 2 * int(units["boosters"]["headstart"]), "head start constables")
	eq(int(sim.charges["shield"]), 2, "level shield + token")
	eq(int(sim.charges["bomb"]), 2, "bomb tokens")
	eq(sim.peak_squad, sim.squad.total(), "peak starts at the starting squad")


func test_generated_levels_follow_the_rules() -> void:
	var hint_ids := {}
	var lucky_levels: Array = []
	var offers := ["num+", "mul", "recruit", "weapon", "power", "foe_div", "foe_strip", "turncoat", "pct+"]
	for n in range(1, Config.LEVEL_COUNT + 1):
		var lv := Config.level(n)
		check(not lv.is_empty(), "level %d exists" % n)
		if lv.is_empty():
			continue
		eq(int(lv.get("district", 0)), int(ceil(n / 10.0)), "L%d district" % n)
		check(lv.has("stars") and int(lv["stars"]["star2"]) < int(lv["stars"]["star3"]), "L%d star thresholds" % n)
		var bosses := 0
		var lucky := 0
		var finish := 0.0
		var obstacle_lanes := {}
		for e in lv["events"]:
			if e["type"] == "obstacle":
				obstacle_lanes["%d:%d" % [int(e["at"]), int(e["lane"])]] = true
		for e in lv["events"]:
			match String(e["type"]):
				"finish":
					finish = float(e["at"])
				"hint":
					check(not hint_ids.has(e["id"]), "hint %s shows once ever (again in L%d)" % [e["id"], n])
					hint_ids[e["id"]] = true
				"wave":
					for g in e["groups"]:
						check(int(units["enemies"][g["enemy"]]["unlock"]) <= n, "L%d: %s before its unlock" % [n, g["enemy"]])
						if g["enemy"] == "boss":
							bosses += 1
				"gates":
					var n_off := 0
					var lanes := {}
					for g in e["gates"]:
						lanes[int(g["lane"])] = true
						var op := String(g["op"])
						if op == "num" or op == "pct":
							op += "+" if int(g["v"]) > 0 else "-"
						if offers.has(op):
							n_off += 1
						if op == "recruit":
							check(int(units["allies"][g["unit"]]["unlock"]) <= n, "L%d: %s recruit before its unlock" % [n, g["unit"]])
					for l in 3:
						if not lanes.has(l) and not obstacle_lanes.has("%d:%d" % [int(e["at"]), l]):
							failures.append("L%d row at %d: lane %d holds neither a gate nor an obstacle" % [n, int(e["at"]), l])
					check(n_off >= 1, "L%d row at %d has an offer" % [n, int(e["at"])])
					if n_off >= 3:
						lucky += 1
		eq(bosses, 1 if n % 10 == 0 else 0, "L%d boss" % n)
		check(lucky <= 1, "L%d at most one lucky row" % n)
		if lucky > 0:
			lucky_levels.append(n)
		var secs := finish / float(units["world"]["scroll_speed"])
		check(secs >= 58.0 and secs <= 92.0, "L%d track %.0f s" % [n, secs])
	for i in range(1, lucky_levels.size()):
		check(int(lucky_levels[i]) - int(lucky_levels[i - 1]) >= 3, "lucky rows at most 1 per 3 levels (%s)" % str(lucky_levels))


# ---------------------------------------------------------------- v1.1 round

func _obstacle_row(x: float, cost := 100) -> LevelSim:
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 39}]},
		{"at": 40, "type": "obstacle", "kind": "barricade", "lane": 1, "hp": 1000000, "dmg": cost},
		{"at": 80, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	sim.set_squad_x(x)
	return sim


func test_obstacle_hits_spatially() -> void:
	# 40 troops; the barricade could take 100 but only the overlapping troops die.
	var centred := _obstacle_row(0.0)
	var seen := _step_until(centred, func(): return centred.state != "run")
	var hit := _events_of(seen, "obstacle_hit")
	eq(hit.size(), 1, "one hit")
	eq(centred.state, "lost", "centred on a 100-cost barricade: all 40 overlap, the hero too")
	var half := _obstacle_row(1.4)
	seen = _step_until(half, func(): return half.state != "run")
	hit = _events_of(seen, "obstacle_hit")
	eq(hit.size(), 1, "half past: still a hit")
	var lost := int(hit[0]["lost"]) if hit.size() == 1 else -1
	check(lost > 5 and lost < 35, "half past saves about half the squad (lost %d)" % lost)
	eq(half.state, "strike", "and the level goes on")
	eq(half.squad.total(), 40 - lost, "exact")
	eq((hit[0]["slots"] as Array).size() > 0, true, "the event names the slots that fell")
	var away := _obstacle_row(2.8)
	seen = _step_until(away, func(): return away.state != "run")
	# Spec v2 §4: the squad is about one lane wide, so from the next lane's centre only its
	# outermost figures brush the barricade (intended: steering matters more).
	var brushed := 40 - away.squad.total()
	check(brushed <= 3, "steered fully into the next lane: at most the outer edge brushes it (lost %d)" % brushed)
	eq(away.state, "strike", "and the level goes on")
	# Capacity: centred on a cost-6 barricade loses exactly 6.
	var six := _obstacle_row(0.0, 6)
	_step_until(six, func(): return six.state != "run")
	eq(six.squad.total(), 34, "a missed obstacle costs exactly its number")


func test_autopilot_stands_at_lane_centres() -> void:
	var sim := LevelSim.new(_gate_level([]), units)
	sim.set_lane(2)
	eq(sim.squad_x, 2.8, "lane 2 centre")
	sim.set_lane(0)
	eq(sim.squad_x, -2.8, "lane 0 centre")
	sim.set_squad_x(1.1)
	sim.set_lane(1)
	eq(sim.squad_x, 1.1, "the view's steering wins once it drives x")


func test_red_percent_gate_at_zero_is_harmless_and_ticks_fast() -> void:
	# A -40% gate with a huge authored step: a weak squad still shoots it to 0 in ~2.5 s.
	var lvl := {"events": [
		{"at": 5, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 9}]},
		{"at": 70, "type": "gates", "gates": [{"lane": 1, "op": "pct", "v": -40, "inc": 10, "step": 500.0, "max": 40}]},
		{"at": 140, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	var first := -1.0
	var zero := -1.0
	var ticks := 0
	for i in 6000:
		sim.step(1.0 / 30.0)
		for e in sim.drain():
			if e["type"] == "gate_tick":
				ticks += 1
				if first < 0.0:
					first = sim.time
				if int(e["to"]) >= 0 and zero < 0.0:
					zero = sim.time
		if sim.state != "run":
			break
	eq(sim.state, "strike", "survived")
	check(ticks >= 4, "the gate visibly ticks (%d)" % ticks)
	var since := zero - (first - sim.gate_clear_s / 4.0)
	check(zero > 0.0 and since <= sim.gate_clear_s + 0.2, "reached 0 within ~2.5 s of fire (%.2f s)" % since)
	# 0% exactly: no change at all.
	var z := {"events": [
		{"at": 5, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 9}]},
		{"at": 30, "type": "gates", "gates": [{"lane": 1, "op": "pct", "v": 0}]},
		{"at": 60, "type": "finish"}]}
	var r := _run(z, [1, 1])
	eq(r["state"], "strike", "0% is harmless")
	eq(r["troops"], 10, "0% = no change")


func test_red_gate_climb_past_zero_keeps_the_level_step() -> void:
	# The dps-scaled step only speeds the climb to 0; the troop offer above 0 still costs
	# the level's step per tick, so a weak squad cannot max out any red gate in seconds.
	var lvl := {"events": [
		{"at": 5, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 2}]},
		{"at": 70, "type": "gates", "gates": [{"lane": 1, "op": "pct", "v": -36, "inc": 3, "step": 13.5, "max": 40}]},
		{"at": 140, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	var zero := -1.0
	var top := 0
	for i in 6000:
		sim.step(1.0 / 30.0)
		for e in sim.drain():
			if e["type"] == "gate_tick":
				if int(e["to"]) >= 0 and zero < 0.0:
					zero = sim.time
				top = maxi(top, int(e["to"]))
		if sim.state != "run":
			break
	check(zero > 0.0, "a 3-troop squad still shoots it up to 0")
	check(top < 40, "but cannot climb it to +40 in the time it is in range (got %d)" % top)
	var g := {"op": "pct", "v": 0, "inc": 3, "step": 13.5, "max": 40, "progress": 0.0, "step_eff": 0.5}
	var s2 := LevelSim.new(lvl, units)
	s2._shoot_lane(g, 3.0, Squad.Fire.ALL)
	var d := s2.squad.dps(s2.stats, s2.weapons, 0, 1000.0, 1, Squad.Fire.ALL) * 3.0
	eq(int(g["v"]), 3 * int(floor(d / 13.5)), "ticks above 0 use the level step")


func test_standoff_stops_the_street() -> void:
	var lvl := {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 30}]},
		{"at": 90, "type": "wave", "groups": [{"enemy": "gunman", "n": 6, "hp": 30, "shot_dmg": 0}]},
		{"at": 160, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	sim.set_lane(1)
	var stood := 0
	var slid := 0.0
	var resumed := false
	var was := false
	for i in 9000:
		var before := sim.traveled
		sim.step(1.0 / 30.0)
		sim.drain()
		var standing := sim.standoff()
		if standing and was:
			slid += sim.traveled - before
		if standing:
			stood += 1
		if was and not standing:
			resumed = true
		was = standing
		if sim.state != "run":
			break
	check(stood > 10, "the gunmen stopped and a standoff happened (%d frames)" % stood)
	check(slid < 1.5, "traveled stops during a standoff (only the brake: %.2f m)" % slid)
	check(resumed, "the street rolls again once they fall")
	eq(sim.state, "strike", "won")


# ---------------------------------------------------------------- v2: tap heat, gang priority

func _sim_l1() -> LevelSim:
	return LevelSim.new(Config.level(1), units)


func test_hero_rate_rises_with_taps_and_decays() -> void:
	var sim := _sim_l1()
	eq(sim.hero_rate_mult(), 0.4, "idle hero fires at auto_rate")
	for i in 8:
		sim.tap()
		sim.step(0.25)  # 4 taps/s
	check(sim.hero_rate_mult() > 0.95, "steady 4/s tapping holds full rate (%.2f)" % sim.hero_rate_mult())
	check(sim.tap_heat > 0.9 and sim.tap_heat <= 1.0, "heat stays in 0..1 (%.2f)" % sim.tap_heat)
	for i in 8:
		sim.step(0.25)  # 2 s idle
	eq(sim.hero_rate_mult(), 0.4, "back to auto_rate after decay")
	eq(sim.tap_heat, 0.0, "heat is cold again")
	sim.tap()
	var c := sim.clone()
	eq(c.tap_heat, sim.tap_heat, "clone copies the heat")


func test_followers_ignore_tap_heat() -> void:
	# A constable-only squad deals the same dps with and without taps.
	var sim := _sim_l1()
	sim.squad.counts["hero"] = 0
	sim.squad.add("constable", 10)
	var cold := sim.squad.dps(sim.stats, sim.weapons, 0)
	for i in 4:
		sim.tap()
	sim.step(1.0 / 30.0)
	eq(sim.squad.dps(sim.stats, sim.weapons, 0), cold, "followers fire at full rate either way")
	# The hero alone scales with the heat, and so does a held PISTOL.
	var hero := _sim_l1()
	hero.squad.hero_weapon = "pistol"
	var idle := hero.squad.dps(hero.stats, hero.weapons, 0)
	var full := idle / 0.4
	for i in 4:
		hero.tap()
	hero.step(1.0 / 30.0)
	var hot := hero.squad.dps(hero.stats, hero.weapons, 0)
	check(absf(hot - full) < 0.001, "a hot hero (knife + pistol) fires at full rate (%.2f vs %.2f)" % [hot, full])


func _priority_sim(gang_front_z: float) -> LevelSim:
	var lvl := {"events": [
		{"at": 120, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": -3, "step": 1, "max": 4}]},
		{"at": 121, "type": "wave", "groups": [{"enemy": "thug", "n": 4}]},
		{"at": 200, "type": "finish"}]}
	var sim := LevelSim.new(lvl, units)
	_step_until(sim, func(): return not sim.rows.is_empty() and not sim.hordes.is_empty())
	sim.rows[0]["z"] = -10.0
	for g in sim.rows[0]["gates"]:
		g["z"] = -10.0
	var h: Dictionary = sim.hordes[0]
	h["z"] = gang_front_z + LevelSim.killed_rows(h) * float(h["row_gap"])
	return sim


func test_gang_within_priority_takes_fire_before_red_gate() -> void:
	eq(float(units["world"].get("gang_priority_m", 0.0)), 15.0, "priority reach is in config")
	var near := _priority_sim(-14.0)
	check(not near.rows.is_empty() and not near.hordes.is_empty(), "gate and gang on screen")
	near._shoot(1.0 / 30.0)
	eq(near.target_kind, "horde", "a gang inside 15 m is shot before the nearer red gate")
	var far := _priority_sim(-25.0)
	far._shoot(1.0 / 30.0)
	eq(far.target_kind, "gate", "a gang outside 15 m: the nearer red gate is shot first")

extends "res://tests/test_case.gd"
## Levels as a player meets them (spec v2.1). The TUNE part (plan v2.1 Task 7): the greedy and
## noisy calibration players of spec §2 (tests/tune.gd), the difficulty bands, and the level
## test's profile checks: the §2 guard checks on every level, so "Harder" never silently
## regresses. The profile checks need the v2.1 fights (plan Task 1) and a calibration (Task 8).

const Tune := preload("res://tests/tune.gd")
const DT := 1.0 / 30.0

var units := Config.units()
var _watched := {}   # level -> Tune.watch_greedy result at the model pace (filled once)
var _pace := {}


# ---------------------------------------------------------------- TUNE: the calibration players

## A street whose best lane flips with the squad's size, so a pilot that read the wrong row,
## a stale squad or kept a first guess would take another route.
func _flip_level() -> Dictionary:
	return {"district": 1, "events": [
		{"at": 40, "type": "gates", "gates": [{"lane": 0, "op": "num", "v": 4}, {"lane": 2, "op": "num", "v": 10}]},
		{"at": 90, "type": "gates", "gates": [{"lane": 0, "op": "num", "v": 10}, {"lane": 2, "op": "mul", "k": 3}]},
		{"at": 140, "type": "gates", "gates": [{"lane": 0, "op": "mul", "k": 2}, {"lane": 1, "op": "num", "v": 40}]},
		{"at": 190, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 5}, {"lane": 2, "op": "num", "v": 5}]},
		{"at": 230, "type": "finish"}]}


## Plays `sim` with `pilot`; every frame a gate row is in view the squad's lane must be the
## gate lesson's pick (Tutorial.best_lane for the squad right now), and it must still be that
## lane when the row passes. Returns the lanes the rows were passed in.
func _check_lanes(sim: LevelSim, pilot: Autopilot, label: String) -> Array:
	var crossed: Array = []
	var want := {}   # row id -> the lesson's pick on the frame before it passed
	var bad := 0
	while sim.state == "run" and sim.time < 200.0:
		pilot.drive(sim)
		var row: Dictionary = Tune.GreedyPilot.next_row(sim)
		if not row.is_empty() and float(row["z"]) > -Tune.GreedyPilot.LOOK_M:
			var pick := Tutorial.best_lane(row, float(sim.squad.total()), sim.lane)
			want[int(row["id"])] = pick
			if sim.lane != pick and bad < 3:
				bad += 1
				failures.append("%s: row %d at %.0f m, lane %d but the lesson picks %d" % [label, int(row["id"]), float(row["z"]), sim.lane, pick])
		sim.step(DT)
		for e in sim.drain():
			if e["type"] == "row_pass":
				var id := int(e["row"]["id"])
				crossed.append(sim.lane)
				eq(sim.lane, int(want.get(id, -1)), "%s: row %d passed in the lesson's lane" % [label, id])
	return crossed


func test_greedy_matches_tutorial_best_lane() -> void:
	var lv := _flip_level()
	var sim := LevelSim.new(lv, units)
	var pilot: Autopilot = Tune.GreedyPilot.new(2.0, true, 0.0, 1, 0.0)
	var lanes := _check_lanes(sim, pilot, "flip street")
	# 1 -> +10 (11) beats +4; 11 -> x3 (33) beats +10; 33 -> +40 (73) beats x2; a tie stays.
	eq(lanes, [2, 2, 1, 1], "greedy route on the flip street")
	eq(sim.squad.total(), 78, "greedy squad on the flip street")
	eq(pilot.choices.slice(0, 4), [2, 2, 1, 1], "the pilot's route is the lanes it passed")
	eq(int(pilot.tap_rate), 2, "greedy taps 2/s (spec v2.1 §2)")
	check(pilot.use_powers, "greedy uses its shield and bomb")
	# Real streets with red gates (their value changes as they are shot) and gangs, at the pace.
	var pace := _model_pace()
	for n in [2, 5, 8, 12]:
		var lv2 := Config.level(n)
		var s2 := LevelSim.new(lv2, units, pace.get(str(n), {}))
		var p2: Autopilot = Tune.GreedyPilot.new(2.0, true, 0.0, n, 0.0)
		var passed := _check_lanes(s2, p2, "L%d" % n)
		eq(passed.size(), Autopilot.gate_row_count(lv2) if s2.state == "strike" else passed.size(), "L%d every row passed" % n)


func test_noisy_pilot_is_greedy_with_random_rows() -> void:
	var lv := Config.level(12)
	var up: Dictionary = _model_pace().get("12", {})
	var greedy := _route(lv, up, 0.0, 5)
	eq(_route(lv, up, 0.0, 99), greedy, "noise 0: the seed does not matter, it is the greedy player")
	eq(_route(lv, up, Tune.NOISY_SHARE, 7), _route(lv, up, Tune.NOISY_SHARE, 7), "the same seed plays the same route")
	# Over many seeded runs about a fifth of the rows are random picks.
	var picked := 0
	var rows := 0
	var differs := 0
	for s in 40:
		var sim := LevelSim.new(lv, units, up)
		var p = Tune.GreedyPilot.new(2.0, true, Tune.NOISY_SHARE, Tune.noisy_seed(12, s), 0.0)
		Autopilot.play(sim, p, DT)
		picked += p.random_rows()
		rows += p.rows_seen()
		if p.choices != greedy:
			differs += 1
	var share := float(picked) / maxf(rows, 1.0)
	check(share > 0.12 and share < 0.28, "noisy rows taken at random: %.2f (want about 0.2)" % share)
	check(differs >= 10, "noisy routes differ from the greedy one (%d of 40)" % differs)
	eq(Tune.NOISY_RUNS, 40, "the first-try fail rate is measured on 40 noisy runs")


func _route(lv: Dictionary, up: Dictionary, noise: float, s: int) -> Array:
	var sim := LevelSim.new(lv, units, up)
	var p = Tune.GreedyPilot.new(2.0, true, noise, s, 0.0)
	Autopilot.play(sim, p, DT)
	return p.choices


func test_band_classification() -> void:
	# Spec v2.1 §2: L1-L4 the tutorial band; slot 9, lieutenants (slot 5) and bosses are hard.
	for n in [1, 2, 3, 4]:
		eq(Tune.band(n, {}), "tutorial", "L%d" % n)
	for n in [5, 9, 10, 15, 19, 20, 25, 29, 30, 35, 39, 40, 45, 49, 50]:
		eq(Tune.band(n, {}), "hard", "L%d by slot" % n)
	for n in [6, 7, 8, 11, 12, 13, 14, 16, 17, 18, 21, 26, 31, 41, 48]:
		eq(Tune.band(n, {}), "normal", "L%d by slot" % n)
	# A level's archetype (tools/gen_levels.py ARCHETYPES) wins over its slot.
	eq(Tune.band(9, {"archetype": "storm"}), "normal", "a storm level in slot 9")
	eq(Tune.band(13, {"archetype": "hard_gauntlet"}), "hard", "hard gauntlet")
	eq(Tune.band(13, {"archetype": "Hard gauntlet"}), "hard", "archetype names are matched loosely")
	eq(Tune.band(17, {"archetype": "lieutenant"}), "hard", "lieutenant")
	eq(Tune.band(18, {"archetype": "boss"}), "hard", "boss archetype")
	eq(Tune.band(18, {"boss": true}), "hard", "a boss level")
	eq(Tune.band(3, {"archetype": "hard_gauntlet"}), "tutorial", "L1-L4 stay the tutorial band")
	# The targets of each band, and the in-band test the calibration and the checks share.
	eq(Tune.BANDS["tutorial"]["keep"], [0.70, 0.85], "tutorial keep")
	eq(Tune.BANDS["normal"]["keep"], [0.40, 0.70], "normal keep")
	eq(Tune.BANDS["hard"]["keep"], [0.35, 0.60], "hard keep")
	eq(Tune.BANDS["tutorial"]["fail"], [0.0, 0.10], "tutorial first-try fails")
	eq(Tune.BANDS["normal"]["fail"], [0.10, 0.20], "normal first-try fails")
	eq(Tune.BANDS["hard"]["fail"], [0.30, 0.40], "hard first-try fails")
	check(Tune.in_band(0.55, Tune.BANDS["normal"]["keep"]), "55% kept is a normal level")
	check(not Tune.in_band(0.96, Tune.BANDS["normal"]["keep"]), "96% kept is too easy")
	check(not Tune.in_band(0.30, Tune.BANDS["hard"]["keep"]), "30% kept is too hard")
	check(Tune.in_band(0.40, Tune.BANDS["hard"]["fail"]), "the band's ends are inside")
	near(Tune.band_mid(Tune.BANDS["hard"]["keep"]), 0.475, "the fit aims at the middle")


func test_guard_checks_read_the_fight_events() -> void:
	# Spec v2.1 §2 guard checks from a hand-fed event log (plan v2.1 Task 1 event names).
	var w := Tune.new_watch()
	var gang := {"id": 7, "enemy": "gunman", "count": 20, "boss": false, "rf_rate": 0.5, "attack": "gun"}
	var quiet := {"id": 8, "enemy": "thug", "count": 20, "boss": false, "rf_rate": 0.0, "attack": ""}
	var boss := {"id": 9, "enemy": "boss", "count": 1, "boss": true, "rf_rate": 0.0, "attack": "gun"}
	var lt := {"id": 10, "enemy": "boss", "count": 1, "boss": true, "rf_rate": 0.0, "attack": "gun"}
	Tune.watch_events(w, [{"type": "horde_spawn", "horde": gang}, {"type": "horde_spawn", "horde": quiet},
		{"type": "horde_spawn", "horde": boss}, {"type": "horde_spawn", "horde": lt, "lieutenant": true}], 2)
	Tune.watch_events(w, [{"type": "return_fire", "horde": 7, "shots": 1, "lost": 3, "blocked": false, "opening": true}], 40)
	Tune.watch_events(w, [{"type": "telegraph", "kind": "barrage", "lane": 1, "src": 9, "x": 0.0, "z": -30.0, "land_t": 1.0},
		{"type": "attack_land", "kind": "barrage", "lane": 1, "lost": 12, "blocked": false, "hit": true},
		{"type": "boss_shot", "horde": 9, "lost": 2, "blocked": false},
		{"type": "telegraph", "kind": "lt_barrage", "lane": 0, "src": 10, "x": 0.0, "z": -30.0, "land_t": 1.0}], 40)
	eq(w["armed"].size(), 3, "gunmen, the boss and the lieutenant are armed; thugs are not")
	eq(w["fired"].size(), 3, "all three fired")
	eq(int(w["enemy_lost"]), 17, "troops lost to enemies: 3 + 12 + 2")
	eq(int(w["bosses"][9]["barrages"]), 1, "the boss's barrage")
	check(not bool(w["bosses"][9]["lt"]), "the boss is not a lieutenant")
	check(bool(w["bosses"][10]["lt"]), "the lieutenant is flagged by horde_spawn")
	eq(int(w["bosses"][10]["barrages"]), 1, "the lieutenant's barrage")
	# Today's (v2) events count too: a gun volley's hurt, a snipe, a firebomb.
	var w2 := Tune.new_watch()
	Tune.watch_events(w2, [{"type": "horde_spawn", "horde": gang}], 40)
	Tune.watch_events(w2, [{"type": "hurt", "n": 4, "cause": "gunman", "source": 7}], 40)
	eq(int(w2["enemy_lost"]), 4, "a gun's hurt is an enemy loss")
	check(w2["fired"].has(7), "and the gang fired")
	# Hero alone (never had followers): a ranged kill is a one-shot; a melee kill is not.
	var w3 := Tune.new_watch()
	Tune.watch_events(w3, [{"type": "horde_spawn", "horde": gang}], 1)
	Tune.watch_events(w3, [{"type": "return_fire", "horde": 7, "shots": 1, "lost": 1, "blocked": false},
		{"type": "lost", "cause": "gunman", "source": 7}], 1)
	eq(String(w3["solo_shot"]), "gunman", "a ranged kill of the hero alone is a one-shot")
	var w4 := Tune.new_watch()
	Tune.watch_events(w4, [{"type": "horde_spawn", "horde": quiet}], 1)
	Tune.watch_events(w4, [{"type": "melee", "horde": 8, "enemies": 3, "lost": 1, "shielded": false},
		{"type": "lost", "cause": "thug", "source": 8}], 1)
	eq(String(w4["solo_shot"]), "", "a gang that reaches the hero alone is the tap lesson, not a one-shot")
	var w5 := Tune.new_watch()
	Tune.watch_events(w5, [{"type": "horde_spawn", "horde": gang}], 30)
	Tune.watch_events(w5, [{"type": "lost", "cause": "gunman", "source": 7}], 1)
	eq(String(w5["solo_shot"]), "", "once followers joined, the hero may fall last")
	# The guard list itself.
	var r := {"level": 12, "band": "normal", "state": "strike", "keep": 0.55, "armed": 10, "fired": 9,
		"enemy_lost": 40, "bosses": [], "solo_shot": ""}
	eq(Tune.guard_failures(r), [], "a level in band where 9 of 10 armed gangs fire")
	r["fired"] = 8
	r["keep"] = 0.9
	r["enemy_lost"] = 0
	r["bosses"] = [{"lt": false, "halt": 5.0, "barrages": 1}, {"lt": true, "halt": 4.5, "barrages": 2}]
	r["solo_shot"] = "gunman"
	eq(Tune.guard_failures(r).size(), 6, "fire share, cost, band, boss halt and barrages, one-shot: %s" % str(Tune.guard_failures(r)))
	var early := {"level": 2, "band": "tutorial", "state": "strike", "keep": 0.8, "armed": 2, "fired": 0,
		"enemy_lost": 0, "bosses": [], "solo_shot": ""}
	eq(Tune.guard_failures(early), [], "L2: no fire share or cost guard yet")


# ---------------------------------------------------------------- the level test's profile checks

func _model_pace() -> Dictionary:
	if _pace.is_empty():
		_pace = Tune.model_pace()
	return _pace


## The greedy player (spec v2.1 §2) on level n at the model's no-ad pace, watched (cached).
func _greedy(n: int) -> Dictionary:
	if not _watched.has(n):
		var lv := Config.level(n)
		_watched[n] = Tune.watch_greedy(n, lv, units, _model_pace().get(str(n), {}))
	return _watched[n]


func _guard_failures(pick: Callable) -> Array:
	var out: Array = []
	for n in range(1, Config.LEVEL_COUNT + 1):
		for f in Tune.guard_failures(_greedy(n)):
			if pick.call(String(f)):
				out.append(f)
	return out


func test_profile_greedy_keeps_inside_its_band() -> void:
	# Needs the v2.1 calibration (plan Task 8): today the greedy player keeps 96-100%.
	var bad := _guard_failures(func(f): return f.contains("keeps") or f.contains("lost the level"))
	check(bad.is_empty(), "greedy keep outside the band on %d levels: %s" % [bad.size(), str(bad.slice(0, 8))])


func test_profile_armed_gangs_fire_from_l11() -> void:
	var bad := _guard_failures(func(f): return f.contains("armed gangs fired"))
	check(bad.is_empty(), "%d levels: %s" % [bad.size(), str(bad.slice(0, 8))])


func test_profile_enemies_cost_troops_from_l3() -> void:
	var bad := _guard_failures(func(f): return f.contains("cost no troops"))
	check(bad.is_empty(), "%d levels: %s" % [bad.size(), str(bad.slice(0, 8))])


func test_profile_bosses_and_lieutenants_fight() -> void:
	var bad := _guard_failures(func(f): return f.contains("halted") or f.contains("barrage"))
	check(bad.is_empty(), "%d: %s" % [bad.size(), str(bad.slice(0, 8))])


func test_profile_hero_alone_opening_never_one_shot() -> void:
	# A hero with zero upgrades, before any follower joins: a gang that reaches him is the tap
	# lesson, but nothing may shoot him dead in one go (spec v2.1 anti-goals).
	var bad: Array = []
	for n in range(1, Config.LEVEL_COUNT + 1):
		var shot := Tune.solo_one_shot(n, Config.level(n), units)
		if shot != "":
			bad.append("L%d %s" % [n, shot])
	check(bad.is_empty(), "the hero alone is one-shot on: %s" % str(bad))

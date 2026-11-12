extends "res://tests/test_case.gd"
## Spec v2.1 §4-§5 (plan Task 4): level archetypes by district slot, unique names, something new
## every 3 levels, the hostage-cage rescue, and the adult L1 (trap row, danger beats, leader).

var units := Config.units()

## The archetype of each slot in a district (tools/gen_levels.py ARCHETYPES).
const ARCH := ["gauntlet", "rush", "ambush", "night", "lieutenant", "rescue", "horde", "storm", "hard", "boss"]


func _slot(n: int) -> int:
	return (n - 1) % 10 + 1


func _waves(lv: Dictionary) -> Array:
	return (lv["events"] as Array).filter(func(e): return e["type"] == "wave")


func _of(lv: Dictionary, type: String) -> Array:
	return (lv["events"] as Array).filter(func(e): return e["type"] == type)


func _finish(lv: Dictionary) -> float:
	for e in lv["events"]:
		if e["type"] == "finish":
			return float(e["at"])
	return 0.0


func _speed(lv: Dictionary) -> float:
	return float(lv.get("scroll_speed", units["world"]["scroll_speed"]))


func _is_lieutenant(g: Dictionary) -> bool:
	return bool(g.get("lieutenant", false)) or String(g.get("enemy", "")) == "lieutenant"


## Enemy kinds that fight in a level: wave groups and cage guards.
func _kinds(lv: Dictionary) -> Dictionary:
	var out := {}
	for e in lv["events"]:
		if e["type"] == "wave":
			for g in e["groups"]:
				out[String(g["enemy"])] = true
		elif e["type"] == "cage":
			out[String(e["guards"]["enemy"])] = true
	return out


func _mul_gates(lv: Dictionary) -> int:
	var n := 0
	for e in _of(lv, "gates"):
		for g in e["gates"]:
			if String(g["op"]) == "mul":
				n += 1
	return n


func test_archetype_by_slot() -> void:
	var base := float(units["world"]["scroll_speed"])
	for n in range(1, Config.LEVEL_COUNT + 1):
		var lv := Config.level(n)
		var want: String = ARCH[_slot(n) - 1]
		eq(String(lv.get("archetype", "")), want, "L%d archetype" % n)
		var d := int(lv["district"])
		var hand := n <= 3   # district 1 slots 1-3 keep the tap-lesson layouts (spec §4.1)
		match want:
			"rush":
				if not hand:
					near(_speed(lv), base * 1.2, "L%d rush scrolls 1.2x" % n)
					var gaunt := Config.level(n - 1)
					check(_finish(lv) / _speed(lv) < _finish(gaunt) / _speed(gaunt), "L%d rush is shorter than L%d" % [n, n - 1])
					check(_of(lv, "gates").size() >= _of(gaunt, "gates").size(), "L%d rush has at least as many gate rows" % n)
			"ambush":
				if not hand:
					# The first gang is already in fire range while the squad runs at the first row.
					var first: Dictionary = _waves(lv)[0]
					var first_row := _of(lv, "gates")[0] as Dictionary
					var reach := float(units["world"]["fire_range"]) * _speed(lv) / (_speed(lv) + float(units["enemies"][first["groups"][0]["enemy"]]["speed"]))
					check(float(first["at"]) - float(first_row["at"]) < reach, "L%d ambush: the first gang is in range before the first row" % n)
					eq(String(first.get("label", "")), "AMBUSH", "L%d ambush banner" % n)
					var specials := 0
					for w in _waves(lv):
						for g in w["groups"]:
							if String(g["enemy"]) in ["gunman", "molotov", "sniper_foe", "grenadier", "biker"]:
								specials += 1
					check(specials >= 3, "L%d ambush is heavy on specials (%d)" % [n, specials])
			"night":
				eq(String(lv.get("look", "")), "night", "L%d night look" % n)
			"storm":
				eq(String(lv.get("look", "")), "storm", "L%d storm look" % n)
				var gaunt := Config.level(n - 7)
				check(_of(lv, "obstacle").size() > _of(gaunt, "obstacle").size(), "L%d storm has more obstacles than L%d" % [n, n - 7])
			"lieutenant":
				var last: Dictionary = _waves(lv).back()
				check((last["groups"] as Array).any(_is_lieutenant), "L%d: the last wave is a lieutenant" % n)
				check(not bool(lv.get("boss", false)), "L%d: a lieutenant is not a district boss" % n)
			"rescue":
				check(_of(lv, "cage").size() >= 2, "L%d rescue has cages" % n)
			"horde":
				var gaunt := Config.level(n - 6)
				check(_waves(lv).size() < _waves(gaunt).size(), "L%d horde has fewer gangs than L%d" % [n, n - 6])
				check(_mul_gates(lv) > _mul_gates(gaunt), "L%d horde has more x gates than L%d" % [n, n - 6])
			"hard":
				var kinds := _kinds(lv)
				for e in units["enemies"]:
					if e != "boss" and int(units["enemies"][e]["unlock"]) <= n and int(units["enemies"][e]["unlock"]) <= d * 10:
						check(kinds.has(e), "L%d hard gauntlet fields every kind of the district (%s missing)" % [n, e])
			"boss":
				check(bool(lv.get("boss", false)), "L%d boss" % n)


func test_unique_names() -> void:
	var seen := {}
	for n in range(1, Config.LEVEL_COUNT + 1):
		var name := String(Config.level(n).get("name", ""))
		check(name != "", "L%d has a name" % n)
		check(not seen.has(name), "L%d name %s is unique (also L%s)" % [n, name, str(seen.get(name, ""))])
		seen[name] = n


func test_new_thing_every_3_levels() -> void:
	var finale: Dictionary = Config.load_json("res://config/finale.json")
	var guests: Dictionary = finale.get("level_weapon", {})
	var seen := {}
	var arch_seen := {}
	var fresh := {}   # level -> why it is fresh
	for n in range(1, Config.LEVEL_COUNT + 1):
		var lv := Config.level(n)
		var why: Array = []
		var keys: Array = []
		for e in lv["events"]:
			match String(e["type"]):
				"wave":
					for g in e["groups"]:
						keys.append("enemy:" + String(g["enemy"]))
				"cage":
					keys.append("cage")
				"obstacle":
					keys.append("obstacle:" + String(e["kind"]))
				"gates":
					for g in e["gates"]:
						var op := String(g["op"])
						if op == "recruit":
							op += ":" + String(g["unit"])
						elif op == "weapon" or op == "power":
							op += ":" + String(g["id"])
						keys.append("gate:" + op)
		for k in keys:
			if not seen.has(k):
				seen[k] = n
				why.append(k)
		var ak := "%d:%s" % [int(lv["district"]), String(lv.get("archetype", ""))]
		if not arch_seen.has(ak):
			arch_seen[ak] = true
			why.append("archetype")
		if guests.has(str(n)):
			why.append("guest")
		fresh[n] = why
	for n in range(1, Config.LEVEL_COUNT - 1):
		check(not (fresh[n] as Array).is_empty() or not (fresh[n + 1] as Array).is_empty() or not (fresh[n + 2] as Array).is_empty(),
			"something new in L%d-L%d" % [n, n + 2])
	# Spec §4.2: the late unlocks moved earlier, each with its first-appearance hint card.
	for pair in [["sniper_foe", 15, "enemies"], ["sniper", 19, "allies"], ["grenadier", 22, "enemies"], ["commando", 26, "allies"]]:
		eq(int(units[pair[2]][pair[0]]["unlock"]), int(pair[1]), "%s unlocks at L%d" % [pair[0], pair[1]])
		var lv := Config.level(int(pair[1]))
		var hinted := _of(lv, "hint").any(func(h): return String(h["id"]) == String(pair[0]))
		check(hinted, "L%d shows the %s hint card on its first appearance" % [int(pair[1]), pair[0]])
	var armory: Dictionary = Config.armory()
	eq(int(armory["tracks"]["sniper_rifle"]["unlock_level"]), 19, "the sniper's Armory track opens with the rank")
	eq(int(armory["tracks"]["launcher"]["unlock_level"]), 26, "the commando's Armory track opens with the rank")
	# No two levels in a row share an archetype (spec goal 4).
	for n in range(2, Config.LEVEL_COUNT + 1):
		check(String(Config.level(n).get("archetype", "")) != String(Config.level(n - 1).get("archetype", "-")), "L%d differs from L%d" % [n, n - 1])


## A gate row (+n troops), a hostage cage guarded by `guards`, then the finish.
func _cage_level(n: int, guards: Dictionary, hostages := 15) -> Dictionary:
	return {"events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": n}]},
		{"at": 130, "type": "cage", "lane": 0, "hostages": hostages, "guards": guards},
		{"at": 190, "type": "finish"}]}


func _play(sim: LevelSim) -> Array:
	var seen: Array = []
	for i in 9000:
		sim.step(1.0 / 30.0)
		seen.append_array(sim.drain())
		if sim.state != "run":
			break
	return seen


func test_rescue_cage_frees_or_loses() -> void:
	# A strong squad shoots the guards down at range: the cage opens, then the hostages join
	# (exact) when it reaches the squad.
	var sim := LevelSim.new(_cage_level(59, {"enemy": "thug", "n": 30}), units)
	sim.set_lane(1)
	var seen := _play(sim)
	var spawn := seen.filter(func(e): return e["type"] == "cage_spawn")
	var opened := seen.filter(func(e): return e["type"] == "cage_open")
	var freed := seen.filter(func(e): return e["type"] == "cage_free")
	eq(spawn.size(), 1, "the cage rides in")
	eq(opened.size(), 1, "the guards fall and the cage opens")
	eq(freed.size(), 1, "the hostages are freed")
	eq(seen.filter(func(e): return e["type"] == "cage_lost").size(), 0, "nothing lost")
	eq(sim.state, "strike", "level won")
	eq(sim.squad.total(), 60 + 15, "the 15 hostages joined the 60 troops exactly")
	if freed.size() == 1:
		eq(int(freed[0]["n"]), 15, "the event carries the troops that joined")
		check(opened.size() == 1 and seen.find(opened[0]) < seen.find(freed[0]), "it opens before it reaches the squad")
	# The guards ride with the cage (they stand guard, never charge ahead) and never halt the street.
	var g := LevelSim.new(_cage_level(59, {"enemy": "gunman", "n": 3}), units)
	g.set_lane(1)
	var standoff := false
	for i in 9000:
		g.step(1.0 / 30.0)
		g.drain()
		for h in g.hordes:
			check(float(h["speed"]) == 0.0, "guards stand by the cage")
		standoff = standoff or g.standoff()
		if g.state != "run":
			break
	check(not standoff, "gunmen guards never stop the street (the cage would never arrive)")
	# A guard too tough to kill in time: the cage reaches the squad still locked and its people
	# are lost; the squad pays the guard's melee and nothing joins.
	var weak := LevelSim.new(_cage_level(39, {"enemy": "brute", "n": 1, "hp": 400}), units)
	weak.set_lane(1)
	seen = _play(weak)
	eq(seen.filter(func(e): return e["type"] == "cage_lost").size(), 1, "the cage is lost")
	eq(seen.filter(func(e): return e["type"] == "cage_free").size(), 0, "no one joins")
	eq(weak.state, "strike", "the squad lives on")
	check(weak.squad.total() < 40, "and it took the brute's blow (%d)" % weak.squad.total())
	check(weak.cages.is_empty(), "the cage is gone")
	# The cap holds: hostages never push a squad past it.
	var full := LevelSim.new(_cage_level(298, {"enemy": "thug", "n": 10}, 50), units)
	full.set_lane(1)
	_play(full)
	eq(full.squad.total(), full.squad.cap, "hostages fill the squad only up to its cap")
	# A clone carries the cages on the road.
	var c := LevelSim.new(_cage_level(59, {"enemy": "thug", "n": 30}), units)
	c.set_lane(1)
	for i in 300:
		c.step(1.0 / 30.0)
	c.drain()
	eq(c.clone().cages.size(), c.cages.size(), "clone copies the cages")
	# Generated rescue levels: guards of unlocked kinds, real hostages.
	for n in range(6, Config.LEVEL_COUNT + 1, 10):
		for e in _of(Config.level(n), "cage"):
			check(int(e["hostages"]) > 0, "L%d cage holds people" % n)
			check(int(units["enemies"][e["guards"]["enemy"]]["unlock"]) <= n, "L%d guards are unlocked" % n)
			check(int(e["guards"]["n"]) > 0, "L%d cage has guards" % n)


## Plays L1 at `taps`/s with zero upgrades, taking Tutorial.best_lane at every row except the
## trap row, where it takes `trap_lane`. Returns {state, troops, peak, trap_before (the squad
## just past the trap row), trap_after (just before the next row: the gang behind it fought),
## opening_t (seconds from the first gang in range to the opening's last kill)}.
func _l1(lv: Dictionary, trap_row: int, trap_lane: int, taps: float) -> Dictionary:
	var sim := LevelSim.new(lv, units)
	var pilot := Autopilot.new([], false, false, taps)
	var rows: Array = _of(lv, "gates")
	var before := -1
	var after := -1
	var first_in := -1.0
	var opening_done := -1.0
	var opening_n := 0
	for g in _waves(lv)[0]["groups"]:
		opening_n += int(g["n"])
	for i in 40000:
		if sim.state != "run":
			break
		# The row about to be passed decides the lane (greedy), except the trap row.
		if sim.rows_passed < rows.size():
			var row: Dictionary = rows[sim.rows_passed]
			var lane := trap_lane if sim.rows_passed == trap_row else Tutorial.best_lane(row, float(sim.squad.total()), sim.lane)
			pilot.choices = []
			for j in sim.rows_passed:
				pilot.choices.append(0)
			pilot.choices.append(lane)
		pilot.drive(sim)
		sim.step(1.0 / 30.0)
		sim.drain()
		if first_in < 0.0 and not sim.hordes.is_empty() and sim.hordes.any(func(h): return LevelSim.front_z(h) >= -sim.fire_range):
			first_in = sim.time
		if opening_done < 0.0 and first_in >= 0.0 and sim.kills >= opening_n:
			opening_done = sim.time
		# The squad right after the trap row, and just before the next row (the gang is behind).
		if trap_row >= 0 and sim.rows_passed == trap_row + 1:
			if before < 0:
				before = sim.squad.total()
			after = sim.squad.total()
	return {"state": sim.state, "troops": sim.squad.total(), "peak": sim.peak_squad, "trap_before": before,
		"trap_after": after, "opening_t": opening_done - first_in if opening_done >= 0.0 else -1.0, "time": sim.time}


func test_l1_trap_row_and_beats() -> void:
	var lv := Config.level(1)
	var s := _speed(lv)
	var secs := _finish(lv) / s
	check(secs >= 45.0 and secs <= 50.0, "L1 runs 45-50 s (%.1f)" % secs)
	var rows := _of(lv, "gates")
	eq(rows.size(), 5, "L1 has 5 gate rows")
	# Danger beats: gangs reach the squad at about 8, 20 and 35 s, and a leader closes it.
	var arrivals: Array = []
	for w in _waves(lv):
		var last_gap := 0.0
		for g in w["groups"]:
			last_gap = maxf(last_gap, float(g.get("gap", 0.0)))
		arrivals.append((float(w["at"]) + last_gap) / s)
	for beat in [8.0, 20.0, 35.0]:
		check(arrivals.any(func(t): return absf(float(t) - beat) <= 4.0), "a danger beat near %d s (%s)" % [int(beat), str(arrivals)])
	var last: Dictionary = _waves(lv).back()
	var leader: Array = (last["groups"] as Array).filter(func(g): return int(g["n"]) == 1 and float(g.get("hp", 1)) > float(units["enemies"][g["enemy"]]["hp"]) * 10.0)
	eq(leader.size(), 1, "a small gang leader at the end")
	# The trap row: a x2 lane next to a safer + lane, with a gang right behind it.
	var trap := -1
	var mul_lane := -1
	var add_lane := -1
	for i in rows.size():
		var ml := -1
		var al := -1
		for g in rows[i]["gates"]:
			if String(g["op"]) == "mul" and int(g["k"]) == 2:
				ml = int(g["lane"])
			elif String(g["op"]) == "num" and int(g["v"]) > 0:
				al = int(g["lane"])
		if bool(rows[i].get("trap", false)):
			trap = i
			mul_lane = ml
			add_lane = al
	check(trap >= 1 and mul_lane >= 0 and add_lane >= 0, "L1 marks a trap row with x2 and + lanes")
	if trap < 0 or mul_lane < 0 or add_lane < 0:
		return
	var safe := _l1(lv, trap, add_lane, 2.0)
	var greedy := _l1(lv, -1, 0, 2.0)
	var doubled := _l1(lv, trap, mul_lane, 2.0)
	eq(safe["state"], "strike", "the + lane wins L1 (2 taps/s, no upgrades)")
	eq(greedy["state"], "strike", "the best-lane player wins L1")
	check(int(safe["trap_after"]) * 10 >= int(safe["trap_before"]) * 9, "the + lane beats the gang behind the trap row (%d -> %d)" % [int(safe["trap_before"]), int(safe["trap_after"])])
	check(doubled["state"] == "lost" or int(doubled["trap_after"]) * 2 <= int(doubled["trap_before"]),
		"the doubled squad cannot beat that gang (%s, %d -> %d)" % [doubled["state"], int(doubled["trap_before"]), int(doubled["trap_after"])])
	var ratio := float(greedy["troops"]) / maxf(float(greedy["peak"]), 1.0)
	check(ratio >= 0.7 and ratio <= 0.85, "the best-lane player keeps a tutorial-band share of his peak (%.2f)" % ratio)
	# The tap lesson: the hero alone needs about 1.5 taps/s for 6-8 s; not tapping loses.
	var light := _l1(lv, trap, add_lane, 1.5)
	eq(light["state"], "strike", "1.5 taps/s wins L1")
	var t := float(light["opening_t"])
	check(t >= 5.5 and t <= 9.0, "the hero-alone opening lasts 6-8 s (%.1f)" % t)
	var cold := _l1(lv, trap, add_lane, 0.0)
	check(cold["state"] == "lost" and float(cold["time"]) < 12.0, "a hero who never taps falls in the opening")


func test_map_badge_per_archetype() -> void:
	# Spec v2.1 §4.1: every archetype has its own map-node icon (no words); bosses keep the crown.
	var icons := {}
	for n in range(1, Config.LEVEL_COUNT + 1):
		var icon := CityMap.archetype_icon(n)
		if _slot(n) == 10:
			eq(icon, "", "L%d boss: the crown, no badge" % n)
			continue
		eq(icon, "arch_" + ARCH[_slot(n) - 1], "L%d badge" % n)
		icons[icon] = true
	eq(icons.size(), 9, "nine archetype badges")
	for icon in icons:
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % icon), "%s.svg exists" % icon)


## Levels as a player meets them (spec v2.1). The TUNE part (plan v2.1 Task 7): the greedy and
## noisy calibration players of spec §2 (tests/tune.gd), the difficulty bands, and the level
## test's profile checks: the §2 guard checks on every level, so "Harder" never silently
## regresses. The profile checks need the v2.1 fights (plan Task 1) and a calibration (Task 8).

const Tune := preload("res://tests/tune.gd")
const DT := 1.0 / 30.0

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
	eq(Tune.band(13, {"archetype": "hard-gauntlet"}), "hard", "hard gauntlet, dashed")
	eq(Tune.band(5, {"archetype": "gauntlet"}), "normal", "a plain gauntlet in slot 5")
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

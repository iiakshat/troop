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
					var first: Dictionary = _waves(lv)[0]
					var first_row := _of(lv, "gates")[0] as Dictionary
					check(float(first["at"]) < float(first_row["at"]), "L%d ambush: a gang is on the squad before any gate" % n)
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
## trap row, where it takes `trap_lane`. Returns {state, troops, peak, trap_before, trap_after,
## opening_t (seconds from the first gang in range to the opening's last kill)}.
func _l1(lv: Dictionary, trap_row: int, trap_lane: int, taps: float) -> Dictionary:
	var sim := LevelSim.new(lv, units)
	var pilot := Autopilot.new([], false, false, taps)
	var trap_wave_at := -1.0
	var rows: Array = _of(lv, "gates")
	for w in _waves(lv):
		if trap_row >= 0 and float(w["at"]) > float(rows[trap_row]["at"]):
			trap_wave_at = float(w["at"])
			break
	var before := -1
	var after := -1
	var first_in := -1.0
	var opening_done := -1.0
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
		if opening_done < 0.0 and sim.rows_passed == 0 and first_in >= 0.0 and sim.hordes.is_empty() and sim.traveled > 40.0:
			opening_done = sim.time
		if trap_wave_at > 0.0 and before < 0 and sim.traveled >= float(rows[trap_row]["at"]) + 0.5:
			before = sim.squad.total()
		if trap_wave_at > 0.0 and after < 0 and before >= 0 and sim.traveled >= trap_wave_at + 6.0:
			after = sim.squad.total()
	return {"state": sim.state, "troops": sim.squad.total(), "peak": sim.peak_squad, "trap_before": before,
		"trap_after": after if after >= 0 else sim.squad.total(), "opening_t": opening_done - first_in, "time": sim.time}


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
	check(ratio >= 0.6 and ratio <= 0.95, "the best-lane player keeps a tutorial-band share of his peak (%.2f)" % ratio)
	# The tap lesson: the hero alone needs about 1.5 taps/s for 6-8 s; not tapping loses.
	var light := _l1(lv, trap, add_lane, 1.5)
	eq(light["state"], "strike", "1.5 taps/s wins L1")
	var t := float(light["opening_t"])
	check(t >= 5.5 and t <= 9.0, "the hero-alone opening lasts 6-8 s (%.1f)" % t)
	var cold := _l1(lv, trap, add_lane, 0.0)
	check(cold["state"] == "lost" and float(cold["time"]) < 12.0, "a hero who never taps falls in the opening")

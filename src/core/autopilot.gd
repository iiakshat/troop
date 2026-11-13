class_name Autopilot
extends RefCounted
## Plays a LevelSim with a fixed lane choice per gate row. Used by tests, the tuning
## tool and the debug --autoplay flag. `use_powers` fires shield/bomb at sensible moments;
## `dodge` steps out of a telegraphed attack's lane (a skilled player), each one with
## probability `dodge_p` (spec v2.1 §1.5; decided once per attack, deterministically).
## `tap_rate` taps the fire zone that many times per second of sim time (0 = a non-tapper).

## A pilot reacts this many seconds before a telegraphed attack lands (a human sees the mark,
## then moves).
const DODGE_REACT_S := 0.6
## It does not leave its lane when a gate row is this close (it would miss its gate).
const ROW_COMMIT_M := 8.0

var choices: Array      # lane per gate row, in arrival order
var use_powers := true
var dodge := false
var tap_rate := 4.0
var dodge_p := 1.0      # share of telegraphed attacks a dodging pilot steps out of
var _next_tap := 0.0    # sim time of the next tap


func _init(lane_choices: Array, powers := true, dodges := false, taps := 4.0, dodge_chance := 1.0) -> void:
	choices = lane_choices
	use_powers = powers
	dodge = dodges
	tap_rate = taps
	dodge_p = clampf(dodge_chance, 0.0, 1.0)


func drive(sim: LevelSim) -> void:
	_tap(sim)
	# Aim for the next gate row that hasn't passed yet.
	var want := sim.lane
	if sim.rows_passed < choices.size():
		want = int(choices[sim.rows_passed])
	if dodge:
		want = _dodge(sim, want)
	sim.set_lane(want)
	if not use_powers:
		return
	# Spec v2.1 §1.5: the shield goes up when an armed gang is in range (its guns or a special
	# attacking), a gang is in melee, or a telegraphed attack is about to land on the squad.
	var danger := false
	for a in sim.attacks:
		if int(a["lane"]) == sim.squad_lane() and float(a["land"]) - sim.time < 0.25:
			danger = true
	for h in sim.hordes:
		if int(h["count"]) <= 0:
			continue
		if h["melee"] or LevelSim.fires_back(h) or LevelSim.is_attacking(h):
			danger = true
		var big: bool = int(h["count"]) >= 40 or float(h["shield"]) > 40.0 or float(h["hp"]) >= 50.0
		if big and LevelSim.front_z(h) > -sim.fire_range * 0.6 and int(sim.charges.get("bomb", 0)) > 0 and sim.bombs.is_empty():
			sim.use_power("bomb")
	if danger and int(sim.charges.get("shield", 0)) > 0 and sim.shield_t <= 0.0:
		sim.use_power("shield")


## Taps at tap_rate per second of sim time. A fresh pilot on a cloned sim starts tapping now.
func _tap(sim: LevelSim) -> void:
	if tap_rate <= 0.0 or sim.time < _next_tap:
		return
	sim.tap()
	var gap := 1.0 / tap_rate
	_next_tap = _next_tap + gap if sim.time - _next_tap < gap else sim.time + gap


## Steps out of the lane a telegraphed attack is about to land in (within DODGE_REACT_S), for
## the attacks this pilot dodges (will_dodge), into a neighbouring lane that is clear, unless
## a gate row is about to pass (it keeps its gate then).
func _dodge(sim: LevelSim, want: int) -> int:
	var hot := {}
	var flee := false
	for a in sim.attacks:
		hot[int(a["lane"])] = true
		if int(a["lane"]) == want and float(a["land"]) - sim.time <= DODGE_REACT_S and will_dodge(int(a["id"])):
			flee = true
	if not flee:
		return want
	for row in sim.rows:
		if float(row["z"]) > -ROW_COMMIT_M and float(row["z"]) < 0.0:
			return want
	for l in [want - 1, want + 1, want - 2, want + 2]:
		if l < 0 or l > 2 or hot.has(l) or not _clear(sim, l):
			continue
		return l
	return want


## Whether this pilot dodges the attack with this id: a fixed hash of the id against dodge_p,
## so a run replays the same and clones agree.
func will_dodge(id: int) -> bool:
	if dodge_p >= 1.0:
		return true
	if dodge_p <= 0.0:
		return false
	var hsh := ((id * 2654435761) >> 7) & 0xFFFF
	return float(hsh) / 65536.0 < dodge_p


## No gate row or obstacle in lane `l` about to reach the squad.
func _clear(sim: LevelSim, l: int) -> bool:
	for row in sim.rows:
		if float(row["z"]) > -10.0:
			for g in row["gates"]:
				if int(g["lane"]) == l:
					return false
	for ob in sim.obstacles:
		if int(ob["lane"]) == l and float(ob["z"]) > -10.0:
			return false
	return true


## Runs a whole level headless. Returns {state, troops, kills, time, peak, stars}.
static func run(level: Dictionary, units_cfg: Dictionary, lanes: Array, upgrades := {}, powers := true, dt := 1.0 / 30.0, dodges := false, tap_rate := 4.0, dodge_chance := 1.0) -> Dictionary:
	var sim := LevelSim.new(level, units_cfg, upgrades)
	return play(sim, Autopilot.new(lanes, powers, dodges, tap_rate, dodge_chance), dt)


## Plays `sim` to the end (or `max_rows` gate rows) with `pilot`.
static func play(sim: LevelSim, pilot: Autopilot, dt := 1.0 / 30.0, max_rows := 1 << 30) -> Dictionary:
	var guard := 0
	while sim.state == "run" and guard < 40000 and sim.rows_passed < max_rows:
		pilot.drive(sim)
		sim.step(dt)
		sim.drain()
		guard += 1
	return result(sim)


static func result(sim: LevelSim) -> Dictionary:
	return {"state": sim.state, "troops": sim.squad.total(), "kills": sim.kills,
		"time": sim.time, "cause": sim.lose_cause, "peak": sim.peak_squad, "stars": sim.stars()}


static func gate_row_count(level: Dictionary) -> int:
	var n := 0
	for e in level.get("events", []):
		if e["type"] == "gates":
			n += 1
	return n


## Spec v2.1 §1.3, the boss HP rule's "expected squad": the squad's damage per second against
## the level's boss (or lieutenant) when he halts the street, playing `lanes` with `upgrades`
## at `tap_rate` (no powers). tools/gen_levels.py sets his HP to hp_secs x this (calibration.json
## `boss_dps`). The boss gets endless health for the run, so he always reaches the halt. A
## level with no boss (yet; a lieutenant slot): the squad's dps against boss armour when its
## last wave's first gang comes out. 0 if the squad falls first. `pilot` (optional) drives
## instead of a lane-route autopilot: tools/boss_dps.gd passes the calibration profile's greedy
## player (tests/tune.gd GreedyPilot), the spec's expected squad.
static func boss_dps(level: Dictionary, units_cfg: Dictionary, lanes: Array, upgrades := {}, tap_rate := 2.0, dt := 1.0 / 30.0,
		pilot: Autopilot = null) -> float:
	var lv := level.duplicate(true)
	var has_boss := false
	var last_wave := -1
	var wave := 0
	for e in lv.get("events", []):
		if e.get("type", "") != "wave":
			continue
		last_wave = wave
		wave += 1
		for g in e.get("groups", []):
			if g["enemy"] == "boss":
				g["hp"] = 1.0e12
				has_boss = true
	var sim := LevelSim.new(lv, units_cfg, upgrades)
	if pilot == null:
		pilot = Autopilot.new(lanes, false, true, tap_rate, 1.0)
	var bdef: Dictionary = units_cfg["enemies"]["boss"]
	var guard := 0
	while sim.state == "run" and guard < 40000:
		pilot.drive(sim)
		sim.step(dt)
		sim.drain()
		guard += 1
		for h in sim.hordes:
			var at_boss: bool = has_boss and h["boss"] and LevelSim.front_z(h) >= -sim.boss_halt
			var at_last: bool = not has_boss and int(h["wave"]) == last_wave
			if at_boss or at_last:
				return sim.squad.dps(sim.stats, sim.weapons, int(bdef["armour"]), 1.0e9, 1)
	return 0.0

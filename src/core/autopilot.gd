class_name Autopilot
extends RefCounted
## Plays a LevelSim with a fixed lane choice per gate row. Used by tests, the tuning
## tool and the debug --autoplay flag. `use_powers` fires shield/bomb at sensible moments;
## `dodge` steps out of a firebomb's lane when that is safe (a skilled player).

var choices: Array      # lane per gate row, in arrival order
var use_powers := true
var dodge := false


func _init(lane_choices: Array, powers := true, dodges := false) -> void:
	choices = lane_choices
	use_powers = powers
	dodge = dodges


func drive(sim: LevelSim) -> void:
	# Aim for the next gate row that hasn't passed yet.
	var want := sim.lane
	if sim.rows_passed < choices.size():
		want = int(choices[sim.rows_passed])
	if dodge:
		want = _dodge(sim, want)
	sim.set_lane(want)
	if not use_powers:
		return
	var danger := false
	for fb in sim.firebombs:
		if int(fb["lane"]) == sim.lane and float(fb["land"]) - sim.time < 0.25:
			danger = true
	for h in sim.hordes:
		var threatening: bool = LevelSim.is_attacking(h) or h["melee"]
		if threatening and (h["melee"] or int(h["count"]) * int(h["shot_dmg"]) >= 3 or h["boss"]):
			danger = true
		var big: bool = int(h["count"]) >= 40 or float(h["shield"]) > 40.0 or float(h["hp"]) >= 50.0
		if big and LevelSim.front_z(h) > -sim.fire_range * 0.6 and int(sim.charges.get("bomb", 0)) > 0:
			sim.use_power("bomb")
	if danger and int(sim.charges.get("shield", 0)) > 0 and sim.shield_t <= 0.0:
		sim.use_power("shield")


## Leaves the lane a firebomb is about to land in, if a neighbouring lane is clear.
func _dodge(sim: LevelSim, want: int) -> int:
	var hot := {}
	for fb in sim.firebombs:
		hot[int(fb["lane"])] = true
	if not hot.has(want):
		return want
	for l in [want - 1, want + 1, want - 2, want + 2]:
		if l < 0 or l > 2 or hot.has(l) or not _clear(sim, l):
			continue
		return l
	return want


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
static func run(level: Dictionary, units_cfg: Dictionary, lanes: Array, upgrades := {}, powers := true, dt := 1.0 / 30.0, dodges := false) -> Dictionary:
	var sim := LevelSim.new(level, units_cfg, upgrades)
	return play(sim, Autopilot.new(lanes, powers, dodges), dt)


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

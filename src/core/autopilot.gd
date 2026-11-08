class_name Autopilot
extends RefCounted
## Plays a LevelSim with a fixed lane choice per gate row. Used by tests, the tuning
## tool and the debug --autoplay flag. `use_powers` fires shield/bomb at sensible moments.

var choices: Array      # lane per gate row, in arrival order
var use_powers := true


func _init(lane_choices: Array, powers := true) -> void:
	choices = lane_choices
	use_powers = powers


func drive(sim: LevelSim) -> void:
	# Aim for the next gate row that hasn't passed yet.
	if sim.rows_passed < choices.size():
		sim.set_lane(int(choices[sim.rows_passed]))
	if not use_powers:
		return
	for h in sim.hordes:
		var threatening: bool = h["stopped"] or h["melee"]
		if threatening and int(sim.charges.get("shield", 0)) > 0 and sim.shield_t <= 0.0:
			sim.use_power("shield")
		var big: bool = int(h["count"]) >= 40 or float(h["shield"]) > 40.0 or float(h["hp"]) >= 50.0
		if big and LevelSim.front_z(h) > -sim.fire_range * 0.6 and int(sim.charges.get("bomb", 0)) > 0:
			sim.use_power("bomb")


## Runs a whole level headless. Returns {state, troops, kills, time}.
static func run(level: Dictionary, units_cfg: Dictionary, lanes: Array, upgrades := {}, powers := true, dt := 1.0 / 30.0) -> Dictionary:
	var sim := LevelSim.new(level, units_cfg, upgrades)
	var pilot := Autopilot.new(lanes, powers)
	var guard := 0
	while sim.state == "run" and guard < 20000:
		pilot.drive(sim)
		sim.step(dt)
		sim.drain()
		guard += 1
	return {"state": sim.state, "troops": sim.squad.total(), "kills": sim.kills,
		"time": sim.time, "cause": sim.lose_cause}


static func gate_row_count(level: Dictionary) -> int:
	var n := 0
	for e in level.get("events", []):
		if e["type"] == "gates":
			n += 1
	return n

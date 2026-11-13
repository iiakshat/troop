extends SceneTree
## Spec v2.1 §1.3, the boss HP rule's "expected squad": measures Autopilot.boss_dps (the
## squad's damage per second against the boss or lieutenant when he halts the street) for the
## calibration profile's greedy player (tests/tune.gd GreedyPilot: the best lane at every row,
## tapping 2/s, powers on, dodge_p 0.7) at the no-ad pace (tests/econ_model.gd), and writes a
## report that tools/gen_levels.py --merge folds into calibration.json as `boss_dps`. The
## generator then gives every boss boss.hp_secs (a lieutenant lieutenant.hp_secs) of it.
## route=1 measures on each level's stored route instead (no powers), as before v2.1 pass 3.
##   godot --headless --path . --script res://tools/boss_dps.gd -- out=_local/boss_dps.json [levels=5,10,15] [taps=2] [route=1]
##   python -I tools/gen_levels.py --merge _local/boss_dps.json
## Default levels: every boss level and slot 5 of each district (the lieutenants). A level with
## no boss yet is measured when its last wave comes in range. Run it after the plain tune run
## that stores the routes (and after any change to the pace or the waves before the boss).

const DT := 1.0 / 30.0


func _initialize() -> void:
	var out := ""
	var levels: Array = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]
	var taps := 2.0
	var on_route := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("levels="):
			levels = Array(a.substr(7).split(",")).map(func(s): return int(s))
		elif a.begins_with("taps="):
			taps = float(a.substr(5))
		elif a == "route=1":
			on_route = true
	var units := Config.units()
	var Model = load("res://tests/econ_model.gd")
	var pace: Dictionary = Model.pace(Model.run(Config.economy(), Config.load_json("res://config/finale.json"), units))
	var rows: Array = []
	for n in levels:
		var lv := Config.level(int(n))
		var route: Array = lv.get("route", [])
		var pilot: Autopilot = null
		if not on_route:
			var Tune = load("res://tests/tune.gd")
			var s: int = Tune.noisy_seed(int(n), 1000)
			seed(s)
			pilot = Tune.GreedyPilot.new(taps, true, 0.0, s, Tune.GreedyPilot.DODGE_P)
		var dps := Autopilot.boss_dps(lv, units, route, pace.get(str(n), {}), taps, DT, pilot)
		print("L%d boss_dps %.1f" % [int(n), dps])
		if dps > 0.0:
			rows.append({"level": int(n), "boss_dps": snappedf(dps, 0.1)})
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, " ") + "\n")
		f.close()
		print("wrote ", out)
	quit()

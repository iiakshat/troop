extends SceneTree
## Prints the economy simulation (tests/econ_model.gd): one row per level won.
##   godot --headless --path . --script res://tests/econ_sim.gd 
## Columns: level, coins at session start (welcome-back city coins, daily, spin) and what
## they bought, win coins, extra (missions, star chests, liberation), city
## coins collected after the win, coins on the map, affordable progress items (rooms + buildings) / all incl.
## cosmetics, cheapest progress price, what got bought, coins left, Squad Power vs the
## recommended power of the next level, city income per hour.

const Model := preload("res://tests/econ_model.gd")


func _initialize() -> void:
	var rows: Array = Model.run(Config.economy(), Config.load_json("res://config/finale.json"), Config.units())
	print("L   boot(buys)  win  extra city  coins aff/all cheap  left  power/rec  inc/h buys bought")
	var per_d := {}
	for r in rows:
		print("%-3d %5d(%d)    %4d %5d %4d %6d   %d/%-2d %5d %5d  %6.2f/%-6.2f %5d  %d   %s" % [
			r["level"], r["boot"], r["boot_buys"], r["income"], r["extra"], r["city"], r["coins"], r["affordable_progress"],
			r["affordable"], r["cheapest"], r["left"], r["power"], r["rec"], r["income_h"], r["buys"],
			" ".join(PackedStringArray(r["bought"]))])
		var d := Economy.district_of(int(r["level"]))
		if not per_d.has(d):
			per_d[d] = [0, 0, 0]
		per_d[d][0] += int(r["buys"])
		per_d[d][1] += int(r["boot"]) + int(r["income"]) + int(r["extra"]) + int(r["city"])
		per_d[d][2] += 1
	for d in per_d:
		print("district %d: %.1f buys per win, %d coins per win" % [d, float(per_d[d][0]) / per_d[d][2], per_d[d][1] / per_d[d][2]])
	var s: Dictionary = Model.summary(rows)
	print("in band (1-3 bought): %d%%  none at: %s  over 3 at: %s" % [int(round(float(s["in_band"]) * 100.0)), str(s["none"]), str(s["over"])])
	# Plan v2 Task 13: the no-ad pace (what the levels are calibrated against) and its check.
	print("\nL   pace (armory steps; station squad/cap%%/coins)   coins: power spent / earned by playing  replays")
	var pc: Dictionary = Model.pace_check(rows)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var p: Dictionary = r["pace"]
		print("%-3d %-46s %6d / %-6d  %d" % [r["level"], "%s; %d/%d/%.1f" % [str(p["armory"]), p["squad"], p["capacity"], p["coins"]],
			r["power_cost"], r["play_before"], pc["replays"][i]])
	print("no_ad_pace_reaches_every_level: %s (worst %d replays of the previous level; over 2 at %s)" % [
		"PASS" if (pc["fails"] as Array).is_empty() else "FAIL", pc["worst"], str(pc["fails"])])
	var out := "res://_local/pace.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("pace="):
			out = a.substr(5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(Model.pace(rows), " "))
		print("pace written to ", out)
	quit()

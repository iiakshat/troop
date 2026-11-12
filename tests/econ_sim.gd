extends SceneTree
## Prints the economy simulation (tests/econ_model.gd): one row per level won.
##   godot --headless --path . --script res://tests/econ_sim.gd [-- profile=pace|ads|engaged]
##       [pace=res://_local/pace.json] [pace_ads=res://_local/pace_ads.json]
## The table is the chosen profile's (default: pace, the no-ad pace the levels are calibrated
## on). Columns: level, coins at session start (welcome-back city coins, daily, spin) and what
## they bought, win coins, x2 ad coins, extra (missions, star chests, liberation), city coins
## collected after the win, coins on the map, affordable progress items (rooms + buildings) / all
## incl. cosmetics, cheapest progress price, what got bought, coins left, Squad Power vs the
## recommended power of the next level, city income per hour.
## Then (spec v2.1 section 3.5): the pace's upgrades per level and the no-ad check, the ceiling
## check of the engaged no-ad player (power <= 1.6x recommended), the with-ads pace, and the
## recommended anchors fitted to the pace (paste into economy.json power.recommended and re-run
## until they stop moving). Writes the pace to _local/pace.json and the with-ads pace to
## _local/pace_ads.json (same format: {level: upgrades}).

const Model := preload("res://tests/econ_model.gd")


func _initialize() -> void:
	var eco: Dictionary = Config.economy()
	var finale: Dictionary = Config.load_json("res://config/finale.json")
	var units: Dictionary = Config.units()
	var profile := "pace"
	var out := "res://_local/pace.json"
	var out_ads := "res://_local/pace_ads.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("profile="):
			profile = a.substr(8)
		elif a.begins_with("pace="):
			out = a.substr(5)
		elif a.begins_with("pace_ads="):
			out_ads = a.substr(9)
	var rows: Array = Model.run(eco, finale, units, Model.PROFILES.get(profile, {}))
	print("profile %s %s" % [profile, str(Model.PROFILES.get(profile, {}))])
	print("L   boot(buys)  win   ad extra city  coins aff/all cheap  left  power/rec  inc/h buys bought")
	var per_d := {}
	for r in rows:
		print("%-3d %5d(%d)    %4d %4d %5d %4d %6d   %d/%-2d %5d %5d  %6.2f/%-6.2f %5d  %d   %s" % [
			r["level"], r["boot"], r["boot_buys"], r["income"], r["ad"], r["extra"], r["city"], r["coins"], r["affordable_progress"],
			r["affordable"], r["cheapest"], r["left"], r["power"], r["rec"], r["income_h"], r["buys"],
			" ".join(PackedStringArray(r["bought"]))])
		var d := Economy.district_of(int(r["level"]))
		if not per_d.has(d):
			per_d[d] = [0, 0, 0]
		per_d[d][0] += int(r["buys"])
		per_d[d][1] += int(r["boot"]) + int(r["income"]) + int(r["ad"]) + int(r["extra"]) + int(r["city"])
		per_d[d][2] += 1
	for d in per_d:
		print("district %d: %.1f buys per win, %d coins per win" % [d, float(per_d[d][0]) / per_d[d][2], per_d[d][1] / per_d[d][2]])
	var s: Dictionary = Model.summary(rows)
	print("in band (1-3 bought): %d%%  none at: %s  over 3 at: %s" % [int(round(float(s["in_band"]) * 100.0)), str(s["none"]), str(s["over"])])
	var pace_rows: Array = rows if profile == "pace" else Model.run(eco, finale, units, Model.PROFILES["pace"])
	# Plan v2 Task 13: the no-ad pace (what the levels are calibrated against) and its check.
	print("\nL   pace (armory steps; station squad/cap%%/coins)   coins: power spent / earned by playing  replays")
	var pc: Dictionary = Model.pace_check(pace_rows)
	for i in pace_rows.size():
		var r: Dictionary = pace_rows[i]
		var p: Dictionary = r["pace"]
		print("%-3d %-46s %6d / %-6d  %d" % [r["level"], "%s; %d/%d/%.1f" % [str(p["armory"]), p["squad"], p["capacity"], p["coins"]],
			r["power_cost"], r["play_before"], pc["replays"][i]])
	print("no_ad_pace_reaches_every_level: %s (worst %d replays of the previous level; over 2 at %s)" % [
		"PASS" if (pc["fails"] as Array).is_empty() else "FAIL", pc["worst"], str(pc["fails"])])
	# Spec v2.1 section 3.5: the ceiling (engaged no-ad <= 1.6x recommended) and the with-ads pace.
	var ads_rows: Array = Model.run(eco, finale, units, Model.PROFILES["ads"])
	var eng_rows: Array = Model.run(eco, finale, units, Model.PROFILES["engaged"])
	print("\nL   pace power  ads power  engaged power  recommended(L+1)  engaged/rec  ads/rec")
	var worst := 0.0
	var worst_l := 0
	for i in pace_rows.size():
		var L := int(pace_rows[i]["level"])
		var rec := Economy.recommended_power(L + 1, eco)
		var er := float(eng_rows[i]["power"]) / maxf(rec, 0.001)
		if er > worst:
			worst = er
			worst_l = L
		print("%-3d %10.1f %10.1f %14.1f %17.1f %12.2f %8.2f" % [L, pace_rows[i]["power"], ads_rows[i]["power"], eng_rows[i]["power"],
			rec, er, float(ads_rows[i]["power"]) / maxf(rec, 0.001)])
	print("engaged_power_ceiling (<= 1.6x recommended): %s (worst %.2fx after L%d)" % ["PASS" if worst <= 1.6 + 0.0001 else "FAIL", worst, worst_l])
	# The pointer reads recommended, so the pace moves with it: refit by taking the lower of the
	# current anchors and the fit, and re-run until it says stable (it only goes down, so it ends).
	var start := Economy.save_power(SaveData.default_save(), units, eco)
	var fit: Array = Model.fit_recommended(pace_rows, start)
	var cur: Array = eco["power"]["recommended"]
	var same_levels := cur.size() == fit.size()
	var lower := []
	var stable := same_levels
	for k in fit.size():
		if same_levels and int(cur[k][0]) == int(fit[k][0]):
			lower.append([fit[k][0], minf(float(fit[k][1]), float(cur[k][1]))])
			stable = stable and float(fit[k][1]) + 0.0001 >= float(cur[k][1])
		else:
			same_levels = false
			stable = false
	print("recommended: %s" % ("stable (every anchor is met by the pace)" if stable else
		"refit, paste into economy.json power.recommended and re-run: %s" % JSON.stringify(lower if same_levels else fit)))
	_write(out, Model.pace(pace_rows))
	_write(out_ads, Model.pace(ads_rows))
	quit()


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " "))
		print("pace written to ", path)

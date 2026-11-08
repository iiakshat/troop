extends SceneTree
## Tuning report: plays every lane combination of every level and prints the outcomes.
##   godot --headless --path . --script res://tests/tune.gd -- [level=N] [upgrades=k,s,q]


func _initialize() -> void:
	var only := 0
	var upgrades := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			only = int(a.substr(6))
		if a.begins_with("upgrades="):
			var p := a.substr(9).split(",")
			upgrades = {"knife": int(p[0]), "speed": int(p[1]), "squad": int(p[2])}
	var units := Config.units()
	for n in range(1, Config.LEVEL_COUNT + 1):
		if only > 0 and n != only:
			continue
		var level := Config.level(n)
		var rows := Autopilot.gate_row_count(level)
		var results: Array = []
		for combo in _combos(rows):
			var r := Autopilot.run(level, units, combo, upgrades, true)
			var r2 := Autopilot.run(level, units, combo, upgrades, false)
			results.append({"lanes": combo, "r": r, "np": r2})
		results.sort_custom(func(a, b): return _score(a["r"]) > _score(b["r"]))
		var wins := 0
		var wins_np := 0
		for x in results:
			if x["r"]["state"] == "strike":
				wins += 1
			if x["np"]["state"] == "strike":
				wins_np += 1
		print("\n=== Level %d '%s'  rows=%d  combos=%d  wins=%d (no powers: %d)" % [n, level["name"], rows, results.size(), wins, wins_np])
		for i in results.size():
			var x: Dictionary = results[i]
			if i < 8 or i >= results.size() - 4 or results.size() <= 30:
				print("  %s  -> %s troops=%d kills=%d t=%.1fs %s | no-powers: %s %d" % [str(x["lanes"]), x["r"]["state"], x["r"]["troops"], x["r"]["kills"], x["r"]["time"], x["r"]["cause"], x["np"]["state"], x["np"]["troops"]])
		var causes := {}
		for x in results:
			if x["r"]["state"] == "lost":
				causes[x["r"]["cause"]] = int(causes.get(x["r"]["cause"], 0)) + 1
		print("  loss causes: ", causes)
	quit(0)


func _score(r: Dictionary) -> float:
	return (10000.0 if r["state"] == "strike" else 0.0) + float(r["troops"])


func _combos(rows: int) -> Array:
	var out: Array = [[]]
	for i in rows:
		var next: Array = []
		for c in out:
			for l in 3:
				var cc: Array = (c as Array).duplicate()
				cc.append(l)
				next.append(cc)
		out = next
	return out

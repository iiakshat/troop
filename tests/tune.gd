extends SceneTree
## Tuning report. For each level: a beam search finds the best lane route (with and without
## powers), and a fixed sample of random routes measures how forgiving the level is (the
## share that wins). Levels with few rows are brute-forced instead of sampled.
##
##   godot --headless --path . --script res://tests/tune.gd -- [levels=A-B | level=N]
##       [list=1,5,9] [routes=100] [beam=6] [upgrades=k,s,q] [out=path.json] [calibrate=1] [verbose=1]
##       [k=0.5 kf=2 (evaluate with every gang scaled, the last wave kf times more)]
##       [ratio=0 (calibrate the win rate only; keep the last wave's current scale)]
##       [tap_rate=4 (the autopilot's taps per second; 0 = a non-tapper)]
##       [powers=0 (no shield/bomb anywhere: sampled routes, the best route and calibration)]
##
## calibrate=1 searches, per level, the scale for every gang's size (bosses: hp) that makes
## the sampled win rate match the level's `target_win`, while the best route still wins
## (and, for levels 1-10, wins without powers). It writes the factor relative to the
## current files; `python -I tools/gen_levels.py --merge <out.json>...` folds it into
## config/levels/calibration.json and regenerates the levels.

const DT := 1.0 / 30.0
const BRUTE_MAX := 6     # rows up to which every route is played
const MAX_TIME := 92.0   # seconds the best route may take (levels last 60-90 s)
const KF_MAX := 4.0      # largest extra scale for the last wave
const KF_FALLBACK := 1.5 # last-wave scale when no kf can reach the best-route target

var units: Dictionary
var upgrades := {}
var n_routes := 100
var beam := 6
var verbose := false
var fit_ratio := true
var tap_rate := 4.0      # autopilot taps per second (spec v2 section 2)
var use_powers := true   # powers=0: every run plays without shield/bomb


func _initialize() -> void:
	var lo := 1
	var hi := Config.LEVEL_COUNT
	var out_path := ""
	var calibrate := false
	var only: Array = []
	var k_eval := 1.0
	var kf_eval := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			lo = int(a.substr(6))
			hi = lo
		elif a.begins_with("levels="):
			var p := a.substr(7).split("-")
			lo = int(p[0])
			hi = int(p[1]) if p.size() > 1 else lo
		elif a.begins_with("list="):
			for x in a.substr(5).split(","):
				only.append(int(x))
		elif a.begins_with("routes="):
			n_routes = int(a.substr(7))
		elif a.begins_with("beam="):
			beam = int(a.substr(5))
		elif a.begins_with("upgrades="):
			var p := a.substr(9).split(",")
			upgrades = {"knife": int(p[0]), "speed": int(p[1]), "squad": int(p[2])}
		elif a.begins_with("out="):
			out_path = a.substr(4)
		elif a == "calibrate=1":
			calibrate = true
		elif a == "verbose=1":
			verbose = true
		elif a == "ratio=0":
			fit_ratio = false
		elif a.begins_with("tap_rate="):
			tap_rate = float(a.substr(9))
		elif a == "powers=0":
			use_powers = false
		elif a.begins_with("k="):
			k_eval = float(a.substr(2))
		elif a.begins_with("kf="):
			kf_eval = float(a.substr(3))
	units = Config.units()
	var t0 := Time.get_ticks_msec()
	var report: Array = []
	print("tap_rate %.1f, powers %s" % [tap_rate, "on" if use_powers else "off"])
	print("level | rows | wins/total | target | no-pow best | best troops/peak | stars | time s | k / kf")
	if only.is_empty():
		only = range(lo, hi + 1)
	for n in only:
		var level := Config.level(n)
		var r: Dictionary = calibrate_level(n, level) if calibrate else evaluate(n, level, k_eval, kf_eval)
		r["target_ratio"] = float(level.get("target_ratio", -1.0))
		report.append(r)
		print("%5d | %4d | %4d/%-5d | %5.0f%% | %-11s | %4d/%-4d %3.0f%% | %5d | %6.1f | %.3f / %.3f" % [
			n, r["rows"], r["wins"], r["total"], float(r["target"]) * 100.0,
			"win" if r["np_win"] else "LOSE", r["best_troops"], r["best_peak"], float(r["best_ratio"]) * 100.0,
			r["best_stars"], r["best_time"], r["k"], r["kf"]])
		if not r["best_win"]:
			print("      !! no winning route found for level %d" % n)
	print("total %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
	quit(0)


## Plays the level at gang scale `k` (final wave x `kf` more) and summarises it.
func evaluate(n: int, base: Dictionary, k: float, kf := 1.0, samples := -1) -> Dictionary:
	var level := scaled_level(base, k, kf)
	var rows := Autopilot.gate_row_count(level)
	var routes := sample_routes(n, rows, n_routes if samples < 0 else samples)
	var wins := 0
	var causes := {}
	for route in routes:
		var r := Autopilot.run(level, units, route, upgrades, use_powers, DT, false, tap_rate)
		if r["state"] == "strike":
			wins += 1
		else:
			causes[r["cause"]] = int(causes.get(r["cause"], 0)) + 1
	if verbose:
		print("      loss causes ", causes)
	var best := best_route(level, use_powers)
	var np := best_route(level, false) if n <= 10 else {"result": {"state": "?"}}
	var br: Dictionary = best["result"]
	if verbose:
		print("      best route %s -> %s troops=%d peak=%d t=%.1f" % [str(best["route"]), br["state"], br["troops"], br["peak"], br["time"]])
	return {"level": n, "rows": rows, "wins": wins, "total": routes.size(),
		"win_rate": float(wins) / maxf(routes.size(), 1.0), "target": float(base.get("target_win", 0.5)),
		"best_win": br["state"] == "strike", "best_route": best["route"], "best_troops": br["troops"],
		"best_peak": br["peak"], "best_ratio": _ratio(br),
		"best_stars": br["stars"], "best_time": br["time"], "np_win": np["result"]["state"] == "strike" or n > 10,
		"route": best["route"] if br["state"] == "strike" else [],
		"route_np": np["route"] if n <= 10 and np["result"]["state"] == "strike" else [],
		"k": k, "kf": kf}


static func _ratio(r: Dictionary) -> float:
	if r["state"] != "strike":
		return 0.0
	return float(r["troops"]) / maxf(float(r["peak"]), 1.0)


## Fits two scales: `k` for every gang so the sampled win rate matches `target_win`, and
## `kf` for the final wave alone so the best route finishes with about `target_ratio` of its
## peak squad (mid and late levels). Then backs off until the best route wins (without
## powers too for levels 1-10).
func calibrate_level(n: int, base: Dictionary) -> Dictionary:
	var target := float(base.get("target_win", 0.5))
	var ratio_target := float(base.get("target_ratio", -1.0)) if fit_ratio else -1.0
	var rows := Autopilot.gate_row_count(base)
	var routes := sample_routes(n, rows, 48)
	var kf := 1.0
	var k := _fit_win(base, routes, target, kf)
	if ratio_target > 0.0:
		for round_i in 2:
			kf = _fit_ratio(base, k, ratio_target)
			if kf >= KF_MAX * 0.97:
				# Even a huge last gang can't dent the best route: keep a modest climax
				# instead, so the share of winning routes isn't sacrificed for nothing.
				kf = KF_FALLBACK
				k = _fit_win(base, routes, target, kf)
				break
			k = _fit_win(base, routes, target, kf)
	for i in 14:
		var lv := scaled_level(base, k, kf)
		var b: Dictionary = best_route(lv, use_powers)["result"]
		var won: bool = b["state"] == "strike"
		var ok: bool = won and float(b["time"]) <= MAX_TIME
		if ok and n <= 10:
			ok = best_route(lv, false)["result"]["state"] == "strike"
		if ok:
			break
		if won and float(b["time"]) > MAX_TIME:
			kf = maxf(kf * 0.8, 0.4)  # the last gang takes too long to clear
		else:
			k *= 0.9
			kf = maxf(kf * 0.92, 0.4)
	return evaluate(n, base, k, kf)


func _fit_win(base: Dictionary, routes: Array, target: float, kf: float) -> float:
	var lo := log(0.15)
	var hi := log(5.0)
	for i in 9:
		var mid := (lo + hi) * 0.5
		var lv := scaled_level(base, exp(mid), kf)
		var wins := 0
		for route in routes:
			if Autopilot.run(lv, units, route, upgrades, use_powers, DT, false, tap_rate)["state"] == "strike":
				wins += 1
		if float(wins) / routes.size() > target:
			lo = mid
		else:
			hi = mid
	return exp((lo + hi) * 0.5)


## kf (final wave only, on top of k) that leaves the best route about `want` of its peak.
func _fit_ratio(base: Dictionary, k: float, want: float) -> float:
	var lo := log(0.4)
	var hi := log(KF_MAX)
	for i in 8:
		var mid := (lo + hi) * 0.5
		var r := _ratio(best_route(scaled_level(base, k, exp(mid)), use_powers)["result"])
		if r > want:
			lo = mid
		else:
			hi = mid
	return exp((lo + hi) * 0.5)


## Every gang's size (bosses: hp) and barrel blast times k, the last wave times kf more;
## rounded the same way as tools/gen_levels.py.
static func scaled_level(base: Dictionary, k: float, kf := 1.0) -> Dictionary:
	if absf(k - 1.0) < 1e-9 and absf(kf - 1.0) < 1e-9:
		return base
	var lv: Dictionary = base.duplicate(true)
	if absf(k - 1.0) > 1e-9:
		for e in lv["events"]:
			if e["type"] == "obstacle" and String(e.get("kind", "")) == "barrel" and e.has("kill"):
				e["kill"] = maxi(5, int(floor(float(e["kill"]) * k + 0.5)))
	var last := -1
	for i in lv["events"].size():
		if lv["events"][i]["type"] == "wave":
			last = i
	for i in lv["events"].size():
		var e: Dictionary = lv["events"][i]
		if e["type"] != "wave":
			continue
		var m := k * (kf if i == last else 1.0)
		for g in e["groups"]:
			if g["enemy"] == "boss":
				g["hp"] = maxi(50, int(floor(float(g.get("hp", 360)) * m + 0.5)))
			else:
				g["n"] = maxi(1, int(floor(float(g["n"]) * m + 0.5)))
	return lv


## A fixed, level-seeded sample of lane routes (all of them when there are few rows).
func sample_routes(n: int, rows: int, count: int) -> Array:
	if rows <= BRUTE_MAX and int(pow(3, rows)) <= maxi(count, 243):
		return _all_routes(rows)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * n + 17
	var out: Array = []
	for i in count:
		var r: Array = []
		for j in rows:
			r.append(rng.randi_range(0, 2))
		out.append(r)
	return out


func _all_routes(rows: int) -> Array:
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


## Beam search over lane choices: after each gate row keep the `beam` strongest squads.
func best_route(level: Dictionary, powers: bool) -> Dictionary:
	var rows := Autopilot.gate_row_count(level)
	var states: Array = [{"sim": LevelSim.new(level, units, upgrades), "route": []}]
	var dead: Dictionary = {}
	for r in rows:
		var next: Array = []
		for st in states:
			for l in 3:
				var s2: LevelSim = (st["sim"] as LevelSim).clone()
				var route: Array = (st["route"] as Array).duplicate()
				route.append(l)
				Autopilot.play(s2, Autopilot.new(route, powers, false, tap_rate), DT, r + 1)
				if s2.state == "lost":
					if dead.is_empty() or s2.traveled > float(dead["sim"].traveled):
						dead = {"sim": s2, "route": route}
					continue
				next.append({"sim": s2, "route": route, "score": _score(s2)})
		if next.is_empty():
			return {"route": dead["route"], "result": Autopilot.result(dead["sim"])}
		next.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
		states = next.slice(0, beam)
	var best: Dictionary = {}
	for st in states:
		var sim: LevelSim = st["sim"]
		var res := Autopilot.play(sim, Autopilot.new(st["route"], powers, false, tap_rate), DT)
		var s := (100000.0 if res["state"] == "strike" else 0.0) + float(res["troops"])
		if best.is_empty() or s > float(best["s"]):
			best = {"route": st["route"], "result": res, "s": s}
	return best


## How promising a mid-level state is: firepower plus a little for spare powers.
func _score(sim: LevelSim) -> float:
	var power := sim.squad.dps(sim.stats, sim.weapons, 0, 1.0, 1 << 30) / 1.6
	return power + 4.0 * (int(sim.charges.get("shield", 0)) + int(sim.charges.get("bomb", 0))) + 0.01 * sim.squad.total()

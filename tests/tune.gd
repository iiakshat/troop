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
##       [profile=paced (plan v2 Task 13, the calibration profile: each level gets the no-ad
##        pace's upgrades (pace=path, default _local/pace.json from tests/econ_sim.gd, else the
##        model is run here), tap_rate=4, powers=0; later args override)] [zero=1 (no upgrades)]
##       [checks=1 (per level: the stored route paced / non-tapper / L1 at 1.5 taps/s, and the
##        best route with zero upgrades; no calibration)]
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
const NEED_KF_MAX := 8.0 # need_upgrades: the most the last wave may grow to beat zero upgrades
const NEED_MARGIN := 1.08 # ... and how far past the point where zero upgrades lose it goes

var units: Dictionary
var upgrades := {}
var n_routes := 100
var beam := 6
var verbose := false
var fit_ratio := true
var tap_rate := 4.0      # autopilot taps per second (spec v2 section 2)
var use_powers := true   # powers=0: every run plays without shield/bomb
var pace := {}           # profile=paced: level (String) -> upgrades (tests/econ_model.gd)
var profile := ""
var fixed_upgrades := {} # upgrades=k,s,q (legacy station rooms) when no pace is used


func _initialize() -> void:
	var lo := 1
	var hi := Config.LEVEL_COUNT
	var out_path := ""
	var calibrate := false
	var checks := false
	var only: Array = []
	var k_eval := 1.0
	var kf_eval := 1.0
	var pace_path := "res://_local/pace.json"
	var zero := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("pace="):
			pace_path = a.substr(5)
		elif a == "profile=paced":
			profile = "paced"
			tap_rate = 4.0
			use_powers = false
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
			fixed_upgrades = {"knife": int(p[0]), "speed": int(p[1]), "squad": int(p[2])}
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
		elif a == "powers=1":
			use_powers = true
		elif a == "zero=1":
			zero = true
		elif a == "checks=1":
			checks = true
		elif a.begins_with("k="):
			k_eval = float(a.substr(2))
		elif a.begins_with("kf="):
			kf_eval = float(a.substr(3))
	units = Config.units()
	if profile == "paced" and not zero:
		pace = load_pace(pace_path)
	if checks:
		run_checks(lo, hi, only)
		quit(0)
		return
	var t0 := Time.get_ticks_msec()
	var report: Array = []
	print("profile %s%s, tap_rate %.1f, powers %s" % [profile if profile != "" else "plain", " zero upgrades" if zero else "",
		tap_rate, "on" if use_powers else "off"])
	print("level | rows | wins/total | target | no-pow best | best troops/peak | stars | time s | k / kf")
	if only.is_empty():
		only = range(lo, hi + 1)
	for n in only:
		var level := Config.level(n)
		upgrades = level_upgrades(n)
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
	var np := best if not use_powers else (best_route(level, false) if n <= 10 else {"result": {"state": "?"}})
	var br: Dictionary = best["result"]
	if verbose:
		print("      best route %s -> %s troops=%d peak=%d t=%.1f" % [str(best["route"]), br["state"], br["troops"], br["peak"], br["time"]])
	return {"level": n, "rows": rows, "wins": wins, "total": routes.size(),
		"win_rate": float(wins) / maxf(routes.size(), 1.0), "target": float(base.get("target_win", 0.5)),
		"best_win": br["state"] == "strike", "best_route": best["route"], "best_troops": br["troops"],
		"best_peak": br["peak"], "best_ratio": _ratio(br),
		"best_stars": br["stars"], "best_time": br["time"], "np_win": np["result"]["state"] == "strike" or (use_powers and n > 10),
		"route": best["route"] if br["state"] == "strike" else [],
		# powers=0: `route` already wins without powers, so no separate route_np is stored.
		"route_np": np["route"] if n <= 10 and use_powers and np["result"]["state"] == "strike" else [],
		"k": k, "kf": kf}


## The no-ad pace: _local/pace.json (tests/econ_sim.gd writes it), else the model run here.
static func load_pace(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and not (d as Dictionary).is_empty():
			return d
	var model = load("res://tests/econ_model.gd")
	return model.pace(model.run(Config.economy(), Config.load_json("res://config/finale.json"), Config.units()))


func level_upgrades(n: int) -> Dictionary:
	if pace.is_empty():
		return fixed_upgrades
	return pace.get(str(n), fixed_upgrades)


## checks=1 (plan v2 Task 13 step 4): per level, the stored route with the paced upgrades and
## no powers for a tapper (4/s), a non-tapper (0) and, at L1, a light tapper (1.5/s); the best
## route a tapper with zero upgrades can find; and for L1-L5 the best route of a non-tapper.
func run_checks(lo: int, hi: int, only: Array) -> void:
	if pace.is_empty():
		pace = load_pace("res://_local/pace.json")
	if only.is_empty():
		only = range(lo, hi + 1)
	print("level | paced 4/s       | paced 0/s       | zero-up best    | extra")
	var zero_losses := []
	for n in only:
		var lv := Config.level(n)
		var route: Array = lv.get("route", [])
		var up := level_upgrades(n)
		var a := Autopilot.run(lv, units, route, up, false, DT, false, 4.0)
		var b := Autopilot.run(lv, units, route, up, false, DT, false, 0.0)
		var keep_up := upgrades
		var keep_tap := tap_rate
		upgrades = {}
		tap_rate = 4.0
		var z: Dictionary = best_route(lv, false)["result"]
		var extra := ""
		if n == 1:
			upgrades = up
			var l1 := Autopilot.run(lv, units, route, up, false, DT, false, 1.5)
			extra += "1.5/s %s " % _cell(l1)
		if n <= 5:
			upgrades = up
			tap_rate = 0.0
			extra += "non-tapper best %s" % _cell(best_route(lv, false)["result"])
		upgrades = keep_up
		tap_rate = keep_tap
		if z["state"] != "strike":
			zero_losses.append(n)
		print("%5d | %-15s | %-15s | %-15s | %s" % [n, _cell(a), _cell(b), _cell(z), extra])
	print("zero upgrades lose: %s" % str(zero_losses))


static func _cell(r: Dictionary) -> String:
	if r["state"] == "strike":
		return "win %d/%d" % [r["troops"], r["peak"]]
	return "LOSE %.0fs %s" % [float(r["time"]), str(r["cause"])]


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
		if ok and n <= 10 and use_powers:
			ok = best_route(lv, false)["result"]["state"] == "strike"
		if ok:
			break
		if won and float(b["time"]) > MAX_TIME:
			kf = maxf(kf * 0.8, 0.4)  # the last gang takes too long to clear
		else:
			k *= 0.9
			kf = maxf(kf * 0.92, 0.4)
	if bool(base.get("need_upgrades", false)) and not pace.is_empty():
		var kk: Array = _fit_need(n, base, routes, target, k, kf)
		k = kk[0]
		kf = kk[1]
	return evaluate(n, base, k, kf)


## Spec v2 calibration rule 1, for levels with `need_upgrades` (tools/gen_levels.py): the last
## wave grows until the best route a tapping player with ZERO upgrades can find loses (plus a
## small margin); then the earlier waves are refitted to the win target (never made harder)
## with that last wave held. The no-ad pace must still win: its best route while tapping, and
## a non-tapper on that same route. Returns [k, kf].
func _fit_need(n: int, base: Dictionary, routes: Array, target: float, k: float, kf: float) -> Array:
	if _zero_loses(base, k, kf) and _paced_ok(base, k, kf):
		return [k, kf]
	var lo := log(kf)
	var hi := log(kf * NEED_KF_MAX)
	if not _zero_loses(base, k, exp(hi)):
		print("      need: L%d zero upgrades still win with the last wave x%.0f" % [n, NEED_KF_MAX])
		return [k, kf]
	for i in 6:
		var mid := (lo + hi) * 0.5
		if _zero_loses(base, k, exp(mid)):
			hi = mid
		else:
			lo = mid
	var final := k * exp(hi) * NEED_MARGIN   # the last wave's absolute scale
	var k2 := minf(_fit_win_final(base, routes, target, final), k)
	var kf2 := final / k2
	for j in 6:
		var ok := _paced_ok(base, k2, kf2)
		var zl := _zero_loses(base, k2, kf2)
		if ok and zl:
			return [k2, kf2]
		kf2 *= 0.96 if not ok else 1.05
	print("      need: L%d no last wave splits zero upgrades from the pace; kept the win fit" % n)
	return [k, kf]


## The win-rate fit with the last wave held at the absolute scale `final` (kf = final / k).
func _fit_win_final(base: Dictionary, routes: Array, target: float, final: float) -> float:
	var lo := log(0.15)
	var hi := log(5.0)
	for i in 9:
		var mid := (lo + hi) * 0.5
		var lv := scaled_level(base, exp(mid), final / exp(mid))
		var wins := 0
		for route in routes:
			if Autopilot.run(lv, units, route, upgrades, use_powers, DT, false, tap_rate)["state"] == "strike":
				wins += 1
		if float(wins) / routes.size() > target:
			lo = mid
		else:
			hi = mid
	return exp((lo + hi) * 0.5)


## The best route a tapping player with zero upgrades finds (no powers) loses.
func _zero_loses(base: Dictionary, k: float, kf: float) -> bool:
	var keep := upgrades
	var keep_tap := tap_rate
	upgrades = {}
	tap_rate = 4.0
	var r: Dictionary = best_route(scaled_level(base, k, kf), false)["result"]
	upgrades = keep
	tap_rate = keep_tap
	return r["state"] != "strike"


## The no-ad pace wins: its best route while tapping (in time), and a non-tapper on that route.
func _paced_ok(base: Dictionary, k: float, kf: float) -> bool:
	var lv := scaled_level(base, k, kf)
	var keep_tap := tap_rate
	tap_rate = 4.0
	var b: Dictionary = best_route(lv, false)
	tap_rate = keep_tap
	var r: Dictionary = b["result"]
	if r["state"] != "strike" or float(r["time"]) > MAX_TIME:
		return false
	return Autopilot.run(lv, units, b["route"], upgrades, false, DT, false, 0.0)["state"] == "strike"


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
		if e["type"] != "wave" or bool(e.get("fixed", false)):
			continue  # "fixed": an opening gang sized by hand (gen_levels.py OPENING)
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

extends SceneTree
## Tuning report. For each level: a beam search finds the best lane route (with and without
## powers), and a fixed sample of random routes measures how forgiving the level is (the
## share that wins). Levels with few rows are brute-forced instead of sampled.
##
##   godot --headless --path . --script res://tests/tune.gd -- [levels=A-B | level=N]
##       [list=1,5,9] [routes=100] [beam=6] [upgrades=k,s,q] [out=path.json] [calibrate=1] [verbose=1]
##       [fit_routes=48 (routes the calibration fits on; 100 = the report's own sample)]
##       [k=0.5 kf=2 (evaluate with every gang scaled, the last wave kf times more)]
##       [ratio=0 (calibrate the win rate only; keep the last wave's current scale)]
##       [tap_rate=4 (the autopilot's taps per second; 0 = a non-tapper)]
##       [powers=0 (no shield/bomb anywhere: sampled routes, the best route and calibration)]
##       [profile=paced (plan v2 Task 13, the calibration profile: each level gets the no-ad
##        pace's upgrades (pace=path, default _local/pace.json from tests/econ_sim.gd, else the
##        model is run here), tap_rate=4, powers=0; later args override)] [zero=1 (no upgrades)]
##       [profile=greedy | profile=noisy (spec v2.1 §2 "Harder", plan v2.1 Task 7): the no-ad
##        pace's upgrades, taps 2/s, powers on, telegraphs dodged at dodge_p=0.7. The report and
##        calibrate=1 use the four §2 targets below; profile=noisy also prints the noisy runs'
##        loss causes] [dodge_p=0.7]
##       [checks=1 (spec v2.1 §2 guard checks with the greedy profile unless another is named,
##        asserted: exits 1 on any failure: the greedy keep inside its band ±KEEP_SLACK, the
##        no-ad guarantee, the random-route floor, armed gangs fire from L11, enemies cost troops
##        from L3, bosses and lieutenants hold the street and barrage, the hero alone is never
##        one-shot. The noisy first-try fail rate is printed against its band, a soft target
##        (~), never asserted. With profile=paced: the v2 table,
##        per level the stored route paced / non-tapper / L1 at 1.5 taps/s, and the best route
##        with zero upgrades; no calibration)]
##
## calibrate=1 (profile=paced or none) searches, per level, the scale for every gang's size
## (bosses: hp) that makes the sampled win rate match the level's `target_win`, while the best
## route still wins (and, for levels 1-10, wins without powers). It writes the factor relative
## to the current files; `python -I tools/gen_levels.py --merge <out.json>...` folds it into
## config/levels/calibration.json and regenerates the levels.
##
## calibrate=1 with profile=greedy|noisy fits the level's enemy fire intensity fire_k (then,
## when that cannot get there, k and the last wave's kf) to the v2.1 targets of the level's band
## (tutorial L1-L4, hard = slot 9, lieutenants and bosses, else normal; BANDS): only the greedy
## player's keep share, aimed at the band's midpoint (calibrate_harder, at most FIT_PROBES
## deterministic greedy runs of about 1 s); then the floors: the no-ad guarantee (a route
## without powers at the pace wins tapping 4/s and 2/s, at 1.5/s on L1, and not tapping at all
## from L6, stepping out of telegraphs) and the random floor (5% of VALID_ROUTES random routes
## win); while one breaks every gang shrinks and fire_k is refitted. The noisy first-try fail
## rate is reported, not fitted (a soft target). The plain run with the same profile stores the
## no-power route. fire_k is relative like k (gen_levels.py --merge multiplies it in). When
## units.json carries the v2.1 boss rule (boss hp_secs), boss and lieutenant hp are left out of
## k x kf, as tools/gen_levels.py does.
## A level costs about 15 s to report and 15-60 s to calibrate (LEVEL_CAP_S at most): run 6
## processes over level lists at below-normal priority (CLAUDE.md "Level calibration").
##   [k_max=40 kf_max=12 (the relative k and kf ranges the keep fit may try)] [fk=2 (evaluate
##    with the level's fire_k x 2)]

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
var fit_routes := 48     # routes the calibration fits on (fit_routes=100: the report's own sample)
var beam := 6
var verbose := false
var fit_ratio := true
var tap_rate := 4.0      # autopilot taps per second (spec v2 section 2)
var use_powers := true   # powers=0: every run plays without shield/bomb
var pace := {}           # profile=paced: level (String) -> upgrades (tests/econ_model.gd)
var profile := ""
var fixed_upgrades := {} # upgrades=k,s,q (legacy station rooms) when no pace is used
var fit_k := [0.05, 40.0]  # k range the v2.1 keep fit may try (relative; k_max=)
var fit_kf := [0.3, 12.0]  # ... and the last wave's kf (kf_max=)
var dodge_share := GreedyPilot.DODGE_P  # profile=greedy|noisy: telegraphs dodged (dodge_p=)
var cal_all := {}        # config/levels/calibration.json (the current k and kf of every level)
var _weak := {}          # weak_units() cache
var _floor_broke := false  # a floor broke during this level's fit (calibrate_harder)
var random_floor := RANDOM_FLOOR  # the fit's random floor (floor=0.01: an experiment, never the checks)
var _last_cap := -1      # this level's fit: the most people its last wave may hold (LAST_MAX x the greedy peak)
var cap_last := false    # cap=1: the fit holds the last wave at LAST_MAX x the greedy peak (an experiment)
var mistakes := true     # evaluate_harder measures the one-mistake routes (mistakes=0: skip, a quicker report)
static var boss_hp_fixed := false  # units.json has the v2.1 boss rule: boss hp is not scaled

# ---- spec v2.1 §2 targets (plan v2.1 Task 7)
## Per band: the greedy player's end ÷ peak squad, and the noisy player's first-try fail rate.
const BANDS := {
	"tutorial": {"keep": [0.70, 0.85], "fail": [0.0, 0.10]},
	"normal": {"keep": [0.40, 0.70], "fail": [0.10, 0.20]},
	"hard": {"keep": [0.35, 0.60], "fail": [0.30, 0.40]},
}
const TUTORIAL_LEVELS := 4      # L1-L4 are the tutorial band
const HARD_SLOTS := [5, 9, 10]  # lieutenant, hard gauntlet, boss (when a level has no archetype)
const HARD_ARCHETYPES := ["lieutenant", "hard_gauntlet", "boss"]
const RANDOM_FLOOR := 0.05      # at least this share of random routes wins (spec v2.1 §2; back at 5 % once every row has a second good lane, review v2.1)
## Review v2.1 asked for the last wave at most 4x the greedy peak squad. Tried (cap=1): at 4x the
## Harder band was out of reach (keep 89-100 % with every gang x5-12 and fire_k 2; the squad's fire
## melts a crowd of its own size in moments), so the number stays the fit's dial and the view shows
## each gang's honest danger beside its count instead (LevelView reach bar). The report lists it.
const LAST_MAX := 4.0
const LAST_SLACK := 1.02        # ... the checks allow this much rounding
const CAP_CHECK := false        # the checks assert LAST_MAX (off: see above)
## Review v2.1 (gate cliff): at most this share of the one-mistake routes (the greedy route with
## exactly one row in another lane) may lose, per band.
const MISTAKE_MAX := {"tutorial": 0.25, "normal": 0.25, "hard": 0.40}
const NOISY_RUNS := 40          # noisy runs per first-try fail rate
const NOISY_SHARE := 0.2        # the noisy player's share of random rows
const FIRE_FROM := 11           # guard: from this level ...
const FIRE_SHARE := 0.9         # ... at least this share of armed gangs fire
const COST_FROM := 3            # guard: enemies cost troops on every level from here
const HALT_BOSS := 6.0          # guard: seconds a boss holds the street, at least
const HALT_LT := 4.0            # ... a lieutenant
const BARRAGES_MIN := 2         # guard: barrages each boss or lieutenant fires, at least
const KEEP_SLACK := 0.05        # the greedy keep guard allows this much either side of the band
# ---- the keep fit (calibrate=1 with profile=greedy|noisy)
const FIT_PROBES := 30          # greedy runs the fit may spend on one level (about 1 s each)
const AXIS_PROBES := 9          # ... one dial may take this many
const FIRE_K := [0.5, 2.0]      # the level fire intensity range the fit may use (absolute; advisor R2)
const BOSS_K := [0.6, 0.8, 1.0, 1.25, 1.5]  # the boss/lieutenant gun and barrage steps (advisor R4)
const K_ABS := [0.1, 8.0]       # every gang's scale the fit may use (absolute, calibration.json k)
const KF_ABS := [0.25, 16.0]    # the last wave's extra scale (absolute; above the advisor's A5 4: DECISIONS.md)
const LOST_SLACK := 0.15        # lost ÷ peak may be at most 1 - band low + this (advisor R5)
const SLOW_GRACE := 20.0        # a win slower than MAX_TIME fades to keep 0 over this many s (R5)
const WEAK_FP := 0.75           # the A2 floor: the greedy player wins normal levels at this firepower
const STRONG_FP := 1.25         # ... and keeps at most the band's top + 15 points at this one
const SWEEP_STEPS := [0.8, 0.9, 1.0, 1.1, 1.2, 1.4]  # sweep=1: k and kf steps (advisor A1)
const SWEEP_JUMP := 0.15        # ... the most the keep may move between two steps
const GAP_MIN := 0.9            # checks: the median gap between telegraphs (s), at least (A3)
const AIR_MAX := 2              # ... and never more marks in the air than this
const FIT_TOL := 0.025          # a probe this close to the band's midpoint ends the fit
const VALID_ROUTES := 100       # random routes the floor is validated on (the report's sample)
const VALID_NOISY := 20         # noisy runs the fit reports (measured, not fitted)
const BACKOFF_STEPS := 4        # bisections back toward a scale that holds the floors
const LEVEL_CAP_S := 300.0      # wall-time cap of one level's fit (s)


func _initialize() -> void:
	var lo := 1
	var hi := Config.LEVEL_COUNT
	var out_path := ""
	var calibrate := false
	var checks := false
	var only: Array = []
	var k_eval := 1.0
	var kf_eval := 1.0
	var fk_eval := 1.0
	var bk_eval := 1.0
	var pace_path := "res://_local/pace.json"
	var zero := false
	var full := false
	var sweep := false
	var fp := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("pace="):
			pace_path = a.substr(5)
		elif a == "profile=paced":
			profile = "paced"
			tap_rate = 4.0
			use_powers = false
		elif a == "profile=greedy" or a == "profile=noisy":
			profile = a.substr(8)
	if profile == "" and OS.get_cmdline_user_args().has("checks=1"):
		profile = "greedy"  # checks=1 alone: the v2.1 guard checks
	if profile == "greedy" or profile == "noisy":
		tap_rate = GreedyPilot.TAPS
		use_powers = true
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
		elif a.begins_with("fit_routes="):
			fit_routes = int(a.substr(11))
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
		elif a == "full=1":
			full = true
		elif a.begins_with("floor="):
			random_floor = float(a.substr(6))
		elif a == "mistakes=0":
			mistakes = false
		elif a == "cap=1":
			cap_last = true
		elif a == "sweep=1":
			sweep = true
		elif a.begins_with("fp="):
			fp = float(a.substr(3))
		elif a.begins_with("dodge_p="):
			dodge_share = float(a.substr(8))
		elif a.begins_with("kf_max="):
			fit_kf[1] = float(a.substr(7))
		elif a.begins_with("k_max="):
			fit_k[1] = float(a.substr(6))
		elif a.begins_with("k="):
			k_eval = float(a.substr(2))
		elif a.begins_with("kf="):
			kf_eval = float(a.substr(3))
		elif a.begins_with("fk="):
			fk_eval = float(a.substr(3))
		elif a.begins_with("bk="):
			bk_eval = float(a.substr(3))
	units = Config.units()
	if absf(fp - 1.0) > 1e-9:
		units = scaled_units(units, fp)   # fp=0.75: every fire rate x fp (advisor A2)
	boss_hp_fixed = has_boss_rule(units)
	var cal_text := FileAccess.get_file_as_string("res://config/levels/calibration.json")
	var cal_v: Variant = JSON.parse_string(cal_text) if cal_text != "" else {}
	if cal_v is Dictionary:
		cal_all = cal_v
	var harder := profile == "greedy" or profile == "noisy"
	if (profile == "paced" or harder) and not zero:
		pace = load_pace(pace_path)
	if sweep:
		if not zero and pace.is_empty():
			pace = load_pace(pace_path)
		quit(1 if run_sweep(lo, hi, only) > 0 else 0)
		return
	if checks:
		if profile == "paced":
			run_checks(lo, hi, only)
			quit(0)
			return
		if not zero and pace.is_empty():
			pace = load_pace(pace_path)
		quit(1 if run_guard_checks(lo, hi, only, full) > 0 else 0)
		return
	var t0 := Time.get_ticks_msec()
	var report: Array = []
	print("profile %s%s, tap_rate %.1f, powers %s%s" % [profile if profile != "" else "plain", " zero upgrades" if zero else "",
		tap_rate, "on" if use_powers else "off", ", dodge_p %.2f" % dodge_share if harder else ""])
	if harder:
		print("level | band     | greedy keeps (band)    | lost/peak, melee/rf % | noisy fails (soft)  | random wins | no-ad | best troops/peak | time s | halt s | k / kf / fire_k / boss_k | guards")
	else:
		print("level | rows | wins/total | target | no-pow best | best troops/peak | stars | time s | k / kf")
	if only.is_empty():
		only = range(lo, hi + 1)
	for n in only:
		var level := Config.level(n)
		upgrades = level_upgrades(n)
		var r: Dictionary
		if harder:
			r = calibrate_harder(n, level) if calibrate else evaluate_harder(n, level, k_eval, kf_eval, NOISY_RUNS, fk_eval, bk_eval)
		else:
			r = calibrate_level(n, level) if calibrate else evaluate(n, level, k_eval, kf_eval)
		r["target_ratio"] = float(level.get("target_ratio", -1.0))
		report.append(r)
		if harder:
			print(harder_row(r))
		else:
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
	return model_pace()


## The no-ad pace straight from the economy model (what tests/econ_sim.gd writes to pace.json).
static func model_pace() -> Dictionary:
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
		if n == 2 or n == 3:
			# A casual tapper (2/s) wins the hero-alone opening (START_HEAT in gen_levels.py).
			extra += "2/s %s " % _cell(Autopilot.run(lv, units, route, up, false, DT, false, 2.0))
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
	var routes := sample_routes(n, rows, fit_routes)
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
## rounded the same way as tools/gen_levels.py. With the v2.1 boss rule (boss_hp_fixed) a
## boss's or lieutenant's hp is designed in seconds of damage and never scaled.
static func scaled_level(base: Dictionary, k: float, kf := 1.0, fk := 1.0, bk := 1.0) -> Dictionary:
	if absf(k - 1.0) < 1e-9 and absf(kf - 1.0) < 1e-9 and absf(fk - 1.0) < 1e-9 and absf(bk - 1.0) < 1e-9:
		return base
	var lv: Dictionary = base.duplicate(true)
	if absf(bk - 1.0) > 1e-9:
		# The boss's or lieutenant's gun and barrage scale (LevelSim.boss_k), relative like k.
		lv["boss_k"] = float(base.get("boss_k", 1.0)) * bk
	if absf(fk - 1.0) > 1e-9:
		# The level's enemy fire intensity (LevelSim.fire_k), relative like k (gen_levels.py
		# --merge multiplies calibration.json fire_k by it).
		lv["fire_k"] = float(base.get("fire_k", 1.0)) * fk
	if absf(k - 1.0) > 1e-9:
		for e in lv["events"]:
			if e["type"] == "obstacle" and String(e.get("kind", "")) == "barrel" and e.has("kill"):
				e["kill"] = maxi(5, int(floor(float(e["kill"]) * k + 0.5)))
			elif e["type"] == "cage" and e.get("guards") is Dictionary:
				# A rescue cage's guards are a gang like the others (gen_levels.py apply_scale).
				e["guards"]["n"] = maxi(1, int(floor(float(e["guards"]["n"]) * k + 0.5)))
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
			if _is_boss_group(g):
				if not boss_hp_fixed:
					g["hp"] = maxi(50, int(floor(float(g.get("hp", 360)) * m + 0.5)))
			else:
				g["n"] = maxi(1, int(floor(float(g["n"]) * m + 0.5)))
	return lv


static func _is_boss_group(g: Dictionary) -> bool:
	return String(g["enemy"]) == "boss" or String(g["enemy"]) == "lieutenant" or bool(g.get("lieutenant", false))


## units.json carries the v2.1 boss rule (plan v2.1 Task 1: boss hp = hp_secs x the expected
## squad's dps, left out of the calibration scale).
static func has_boss_rule(units_cfg: Dictionary) -> bool:
	var top: Variant = units_cfg.get("boss", {})
	var enemy: Variant = units_cfg.get("enemies", {}).get("boss", {})
	return (top is Dictionary and (top as Dictionary).has("hp_secs")) or (enemy is Dictionary and (enemy as Dictionary).has("hp_secs"))


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


# ---------------------------------------------------------------- spec v2.1 §2 profiles (plan v2.1 Task 7)

## The "greedy" player of spec v2.1 §2: at each gate row the lane whose gate leaves the biggest
## squad right now, exactly as the gate lesson teaches (Tutorial.best_lane, the same squad and
## lane it reads), decided once the row is within LOOK_M and read again every frame (a red
## gate's value changes while it is shot). Taps TAPS per second, fires a free shield or bomb
## on a threat (Autopilot's powers) and dodges telegraphs at `dodge_p` (Autopilot, plan v2.1
## Task 1; before that, today's firebomb dodge). `noise` > 0 makes it the "noisy" player: that
## share of the rows (seeded) takes a random lane instead.
class GreedyPilot extends Autopilot:
	const LOOK_M := 40.0
	const TAPS := 2.0
	const DODGE_P := 0.7
	var noise := 0.0
	var rng := RandomNumberGenerator.new()
	var _rand := {}   # row id -> its random lane (-1: the lesson's pick)
	# Tutorial, loaded when a pilot is made: naming the class here would compile it with this
	# script, before the Game autoload it reads exists (tune.gd runs as the main script).
	var _lesson: GDScript = load("res://src/ui/tutorial.gd")

	func _init(taps := TAPS, powers := true, noise_share := 0.0, seed_v := 0, dodge_share := DODGE_P) -> void:
		# Steps out of telegraphs at dodge_share (Autopilot dodge_p; it used to set only
		# dodge_p and leave `dodge` off, so the greedy player never dodged at all).
		super([], powers, dodge_share > 0.0, taps, dodge_share)
		noise = noise_share
		rng.seed = seed_v

	func drive(sim: LevelSim) -> void:
		var row := next_row(sim)
		if not row.is_empty() and float(row["z"]) > -LOOK_M:
			while choices.size() <= sim.rows_passed:
				choices.append(sim.lane)
			choices[sim.rows_passed] = pick(row, sim)
		super.drive(sim)

	## The next gate row to reach the squad ({} when none is on the street).
	static func next_row(sim: LevelSim) -> Dictionary:
		var near := {}
		for row in sim.rows:
			if float(row["z"]) < 0.0 and (near.is_empty() or float(row["z"]) > float(near["z"])):
				near = row
		return near

	func pick(row: Dictionary, sim: LevelSim) -> int:
		var id := int(row["id"])
		if not _rand.has(id):
			_rand[id] = rng.randi_range(0, 2) if noise > 0.0 and rng.randf() < noise else -1
		var l := int(_rand[id])
		return l if l >= 0 else _lesson.best_lane(row, float(sim.squad.total()), sim.lane)

	## Rows this pilot took at random, and rows it has seen.
	func random_rows() -> int:
		return _rand.values().filter(func(v): return int(v) >= 0).size()

	func rows_seen() -> int:
		return _rand.size()


## The level's difficulty band (spec v2.1 §2): "tutorial" for L1-L4; "hard" for slot 9 of each
## district, lieutenants and bosses, read from the level's `archetype` when it has one (else
## by slot); otherwise "normal".
static func band(n: int, level: Dictionary) -> String:
	if n <= TUTORIAL_LEVELS:
		return "tutorial"
	if bool(level.get("boss", false)):
		return "hard"
	var arch := String(level.get("archetype", "")).strip_edges().to_lower().replace(" ", "_").replace("-", "_")
	if arch != "":
		var hard := HARD_ARCHETYPES.has(arch) or arch.begins_with("hard") or arch.contains("lieutenant") or arch.contains("boss")
		return "hard" if hard else "normal"
	return "hard" if HARD_SLOTS.has((n - 1) % 10 + 1) else "normal"


static func in_band(v: float, b: Array, slack := 0.0) -> bool:
	return v >= float(b[0]) - slack - 1e-9 and v <= float(b[1]) + slack + 1e-9


static func band_mid(b: Array) -> float:
	return (float(b[0]) + float(b[1])) * 0.5


## Seed of noisy run `i` on level n (also seeds the global RNG for the pilot's dodges).
static func noisy_seed(n: int, i: int) -> int:
	return 104729 * n + 7919 * i + 13


# ---- watching a run for the guard checks

static func new_watch() -> Dictionary:
	return {"hordes": {}, "armed": {}, "fired": {}, "enemy_lost": 0, "bosses": {}, "max_squad": 0, "solo_shot": "",
		# troops enemies took, by kind (advisor A4): the clash, return fire, telegraphed attacks,
		# the boss's gun and barrage, anything else; and every telegraph's sim time (A3)
		"mix": {"melee": 0, "rf": 0, "tele": 0, "boss": 0, "other": 0}, "marks": [], "max_air": 0}


static func _mix(w: Dictionary, key: String, n: int) -> void:
	w["mix"][key] = int(w["mix"][key]) + n


## Reads one tick's events. `squad` is the squad before the tick: a hero who never had a
## follower this level is "alone", and a ranged kill of him (not melee, not a telegraphed lane
## attack he could dodge) is the one-shot spec v2.1 forbids. Knows the v2.1 fight events
## (return_fire, telegraph, attack_land, boss_shot; plan Task 1) and today's (hurt, snipe,
## firebomb_*).
static func watch_events(w: Dictionary, events: Array, squad: int) -> void:
	w["max_squad"] = maxi(int(w["max_squad"]), squad)
	var melee := {}
	var dodgeable := false
	for e in events:
		match String(e["type"]):
			"melee":
				melee[int(e.get("horde", -1))] = true
			"attack_land", "firebomb_hit":
				dodgeable = true
	for e in events:
		match String(e["type"]):
			"horde_spawn":
				var h: Dictionary = e["horde"]
				var id := int(h["id"])
				w["hordes"][id] = true
				var lt := bool(e.get("lieutenant", h.get("lieutenant", false))) or String(h.get("enemy", "")) == "lieutenant"
				if lt or bool(h.get("boss", false)):
					w["bosses"][id] = {"lt": lt, "halt": 0.0, "barrages": 0}
				if float(h.get("rf_rate", 0.0)) > 0.0 or String(h.get("attack", "")) != "" or w["bosses"].has(id):
					w["armed"][id] = true
			"return_fire":
				if int(e.get("shots", 1)) > 0:
					_fired(w, int(e.get("horde", -1)))
				w["enemy_lost"] = int(w["enemy_lost"]) + int(e.get("lost", 0))
				_mix(w, "rf", int(e.get("lost", 0)))
			"blocked", "snipe_aim", "firebomb_throw":
				_fired(w, int(e.get("horde", -1)))
			"snipe", "boss_shot":
				_fired(w, int(e.get("horde", -1)))
				w["enemy_lost"] = int(w["enemy_lost"]) + int(e.get("lost", 0))
				_mix(w, "boss" if String(e["type"]) == "boss_shot" else "tele", int(e.get("lost", 0)))
			"telegraph":
				var src := int(e.get("src", -1))
				_fired(w, src)
				if ["barrage", "lt_barrage"].has(String(e.get("kind", ""))) and w["bosses"].has(src):
					w["bosses"][src]["barrages"] = int(w["bosses"][src]["barrages"]) + 1
			"attack_land", "firebomb_hit", "melee":
				w["enemy_lost"] = int(w["enemy_lost"]) + int(e.get("lost", 0))
				var key := "melee" if String(e["type"]) == "melee" else "tele"
				if ["barrage", "lt_barrage"].has(String(e.get("kind", ""))):
					key = "boss"
				_mix(w, key, int(e.get("lost", 0)))
			"hurt":
				var src := int(e.get("source", -1))
				if w["hordes"].has(src):
					_fired(w, src)
					w["enemy_lost"] = int(w["enemy_lost"]) + int(e.get("n", 0))
					_mix(w, "other", int(e.get("n", 0)))
			"lost":
				var src := int(e.get("source", -1))
				if int(w["max_squad"]) <= 1 and w["hordes"].has(src) and not melee.has(src) and not dodgeable \
						and String(w["solo_shot"]) == "":
					w["solo_shot"] = String(e.get("cause", "?"))


static func _fired(w: Dictionary, id: int) -> void:
	if w["hordes"].has(id):
		w["fired"][id] = true
		w["armed"][id] = true  # whatever fired was armed


## Seconds each boss or lieutenant holds the street (alive within his halt while the squad
## stands its ground), and the most telegraphs in the air at once.
static func watch_sim(w: Dictionary, sim: LevelSim, dt: float) -> void:
	w["max_air"] = maxi(int(w["max_air"]), sim.attacks.size())
	if not sim.halted:
		return
	for h in sim.hordes:
		var id := int(h["id"])
		if w["bosses"].has(id) and int(h["count"]) > 0 and LevelSim.front_z(h) >= -sim.boss_halt:
			w["bosses"][id]["halt"] = float(w["bosses"][id]["halt"]) + dt


## Autopilot.play, watching every tick. `opening_only` stops once a follower has joined.
static func play_watched(sim: LevelSim, pilot: Autopilot, opening_only := false) -> Dictionary:
	var w := new_watch()
	var guard := 0
	while sim.state == "run" and guard < 40000:
		if opening_only and int(w["max_squad"]) > 1:
			break
		pilot.drive(sim)
		var before := sim.squad.total()
		sim.step(DT)
		var evs := sim.drain()
		for e in evs:
			if e["type"] == "telegraph":
				w["marks"].append(sim.time)
		watch_events(w, evs, before)
		watch_sim(w, sim, DT)
		guard += 1
	w["result"] = Autopilot.result(sim)
	return w


## The greedy player on level n with upgrades `up`, watched: the numbers guard_failures reads.
static func watch_greedy(n: int, level: Dictionary, units_cfg: Dictionary, up: Dictionary,
		dodge_share := GreedyPilot.DODGE_P, taps := GreedyPilot.TAPS, powers := true) -> Dictionary:
	var s := noisy_seed(n, 1000)
	seed(s)
	var sim := LevelSim.new(level, units_cfg, up)
	var pilot := GreedyPilot.new(taps, powers, 0.0, s, dodge_share)
	var w := play_watched(sim, pilot)
	var res: Dictionary = w["result"]
	var fired := 0
	for id in w["armed"]:
		if w["fired"].has(id):
			fired += 1
	return {"level": n, "band": band(n, level), "state": res["state"], "cause": res["cause"],
		"troops": res["troops"], "peak": res["peak"], "time": res["time"], "stars": res["stars"],
		"keep": keep_of(res), "armed": w["armed"].size(), "fired": fired, "enemy_lost": w["enemy_lost"],
		"floor_bound": bool(level.get("floor_bound", false)),
		"lost": float(w["enemy_lost"]) / maxf(float(res["peak"]), 1.0), "mix": w["mix"],
		"gap_med": median_gap(w["marks"]), "max_air": w["max_air"], "marks": (w["marks"] as Array).size(),
		"last_wave": last_wave_count(level),
		"bosses": w["bosses"].values(), "solo_shot": w["solo_shot"], "route": pilot.choices.duplicate()}


## The median gap (s) between consecutive telegraphs; -1 with fewer than two.
static func median_gap(times: Array) -> float:
	if times.size() < 2:
		return -1.0
	var gaps: Array = []
	for i in range(1, times.size()):
		gaps.append(float(times[i]) - float(times[i - 1]))
	gaps.sort()
	var m := gaps.size() / 2
	return float(gaps[m]) if gaps.size() % 2 == 1 else (float(gaps[m - 1]) + float(gaps[m])) * 0.5


## Spec v2.1 §2 guard checks on a watch_greedy result: one line per failure ([] = all pass).
static func guard_failures(r: Dictionary) -> Array:
	var n := int(r["level"])
	var out: Array = []
	var b: Dictionary = BANDS[String(r["band"])]
	if String(r["state"]) != "strike":
		out.append("L%d greedy lost the level (%s)" % [n, str(r.get("cause", "?"))])
	elif not in_band(float(r["keep"]), b["keep"], KEEP_SLACK) and not (bool(r.get("floor_bound", false))
			and float(r["keep"]) > float(b["keep"][1])):
		# (floor_bound: the calibration could not go harder without breaking a floor; a known
		# exception the level file records, gen_levels.py --merge.)
		out.append("L%d greedy keeps %.0f%% (%s band %.0f-%.0f%%, ±%.0f)" % [n, float(r["keep"]) * 100.0, r["band"],
			float(b["keep"][0]) * 100.0, float(b["keep"][1]) * 100.0, KEEP_SLACK * 100.0])
	var armed := int(r["armed"])
	if n >= FIRE_FROM and armed > 0 and float(r["fired"]) < FIRE_SHARE * armed - 1e-9:
		out.append("L%d %d of %d armed gangs fired (want %.0f%%)" % [n, int(r["fired"]), armed, FIRE_SHARE * 100.0])
	if n >= COST_FROM and int(r["enemy_lost"]) <= 0:
		out.append("L%d enemies cost no troops" % n)
	for bo in r["bosses"]:
		var lt := bool(bo["lt"])
		var who := "lieutenant" if lt else "boss"
		var need := HALT_LT if lt else HALT_BOSS
		if float(bo["halt"]) < need - 1e-6:
			out.append("L%d %s halted %.1f s (want %.0f)" % [n, who, float(bo["halt"]), need])
		if int(bo["barrages"]) < BARRAGES_MIN:
			out.append("L%d %s fired %d barrages (want %d)" % [n, who, int(bo["barrages"]), BARRAGES_MIN])
	if String(r.get("solo_shot", "")) != "":
		out.append("L%d the hero alone was one-shot (%s)" % [n, r["solo_shot"]])
	# Review v2.1: with cap=1 the last wave is at most LAST_MAX x the peak (else report only).
	if CAP_CHECK and r.has("last_wave") and float(r["last_wave"]) > LAST_MAX * LAST_SLACK * maxf(float(r["peak"]), 1.0):
		out.append("L%d last wave %d is %.1fx the greedy peak %d (want at most %.0fx)" % [n, int(r["last_wave"]),
			float(r["last_wave"]) / maxf(float(r["peak"]), 1.0), int(r["peak"]), LAST_MAX])
	# Advisor A3: a human can read the marks (one at a time, about a second apart).
	if float(r.get("gap_med", -1.0)) >= 0.0 and int(r.get("marks", 0)) >= 3 and float(r["gap_med"]) < GAP_MIN - 1e-6:
		out.append("L%d telegraphs %.2f s apart (median, want %.1f)" % [n, float(r["gap_med"]), GAP_MIN])
	if int(r.get("max_air", 0)) > AIR_MAX:
		out.append("L%d %d marks in the air at once (want %d)" % [n, int(r["max_air"]), AIR_MAX])
	return out


## A hero with zero upgrades and no powers, until his first follower joins: the greedy player
## (tapping 2/s, not dodging) and a non-tapper on the stored route. Returns what one-shot him
## at range ("" = nothing did).
static func solo_one_shot(n: int, level: Dictionary, units_cfg: Dictionary) -> String:
	seed(noisy_seed(n, 2000))
	var a := play_watched(LevelSim.new(level, units_cfg, {}), GreedyPilot.new(GreedyPilot.TAPS, false, 0.0, n, 0.0), true)
	if String(a["solo_shot"]) != "":
		return String(a["solo_shot"])
	var b := play_watched(LevelSim.new(level, units_cfg, {}), Autopilot.new(level.get("route", []), false, false, 0.0), true)
	return String(b["solo_shot"])


# ---- the v2.1 report, fits and checks (profile=greedy|noisy)

## First-try fail rate of the noisy player (`runs` seeded runs, no revive).
func noisy_fail(n: int, level: Dictionary, causes := {}, runs := NOISY_RUNS) -> float:
	var fails := 0
	for i in runs:
		var s := noisy_seed(n, i)
		seed(s)
		var sim := LevelSim.new(level, units, upgrades)
		var r := Autopilot.play(sim, GreedyPilot.new(tap_rate, use_powers, NOISY_SHARE, s, dodge_share), DT)
		if r["state"] != "strike":
			fails += 1
			causes[r["cause"]] = int(causes.get(r["cause"], 0)) + 1
	return float(fails) / maxf(runs, 1.0)


## The share of `routes` that win (stops counting at `enough` wins). With the v2.1 profiles a
## random route is the profile's player on random lanes: it steps out of telegraphs at dodge_p.
func _win_share(level: Dictionary, routes: Array, enough := -1) -> float:
	var wins := 0
	var dodges := profile == "greedy" or profile == "noisy"
	for i in routes.size():
		if enough > 0 and wins + routes.size() - i < enough:
			break   # the floor cannot hold any more
		if Autopilot.run(level, units, routes[i], upgrades, use_powers, DT, dodges, tap_rate, dodge_share)["state"] == "strike":
			wins += 1
			if enough > 0 and wins >= enough:
				break   # the floor holds; the rest of the sample would not change that
	return float(wins) / maxf(routes.size(), 1.0)


## The no-ad guarantee for `route` at this level's pace, without powers: it wins tapping 4/s
## and 2/s (in time), at 1.5/s on L1, and not tapping at all from L6, stepping out of every
## telegraphed attack (a boss's barrage, a sniper's laser, a grenade or firebomb mark: the
## v2.1 hint cards teach "change lane"), as test_level_sim's level test asks of the stored route.
func noad_ok(n: int, level: Dictionary, route: Array) -> bool:
	if route.is_empty():
		return false
	var dodge := true
	var taps := [2.0, 4.0]
	if n == 1:
		taps.append(1.5)
	if n >= 6:
		taps.append(0.0)
	for t in taps:
		var r := Autopilot.run(level, units, route, upgrades, false, DT, dodge, t)
		if r["state"] != "strike" or (t == 2.0 and float(r["time"]) > MAX_TIME):
			return false
	return true


## The no-ad route: the first of the best route without powers (beam search), the greedy
## player's lanes and `stored` (the level file's route) that keeps the no-ad guarantee
## (noad_ok). `beam_first` = false tries the cheap two first (the fits). The plain run stores
## the route this returns.
func noad(n: int, level: Dictionary, stored: Array = [], beam_first := true) -> Dictionary:
	var tried := {}
	var order := ["beam", "greedy", "stored"] if beam_first else ["stored", "greedy", "beam"]
	var first := {}
	for which in order:
		var route: Array = stored
		if which == "beam":
			route = best_route(level, false)["route"]
		elif which == "greedy":
			route = greedy_probe(n, level)["route"]
		if route.is_empty() or tried.has(str(route)):
			continue
		tried[str(route)] = true
		var ok := noad_ok(n, level, route)
		if ok or first.is_empty():
			var r := Autopilot.run(level, units, route, upgrades, false, DT, true, tap_rate)
			first = {"ok": ok, "route": route, "result": r}
		if ok:
			return first
	if first.is_empty():
		return {"ok": false, "route": [], "result": {"state": "lost", "troops": 0, "peak": 0, "time": 0.0}}
	return first


## The v2.1 report of level n at scales k / kf / fire_k / boss_k (relative to the files): the
## greedy keep and lost shares, its loss mix and the guard checks, the noisy first-try fail
## rate, random-route wins, the no-ad route (stored by `--merge` from a plain run) and the best
## route with powers (its share sets the star thresholds).
func evaluate_harder(n: int, base: Dictionary, k: float, kf := 1.0, noisy_runs := NOISY_RUNS, fk := 1.0, bk := 1.0) -> Dictionary:
	var level := scaled_level(base, k, kf, fk, bk)
	var rows := Autopilot.gate_row_count(level)
	var g := watch_greedy(n, level, units, upgrades, dodge_share, tap_rate, use_powers)
	var causes := {}
	var fail := noisy_fail(n, level, causes, noisy_runs)
	if profile == "noisy":
		print("      L%d noisy losses %s" % [n, str(causes)])
	var routes := sample_routes(n, rows, n_routes)
	var share := _win_share(level, routes)
	var best := best_route(level, use_powers)
	var br: Dictionary = best["result"]
	var na := noad(n, level, base.get("route", []))
	var nr: Dictionary = na["result"]
	var halt := -1.0   # the shortest boss or lieutenant halt (s); -1: none on this level
	for bo in g["bosses"]:
		halt = float(bo["halt"]) if halt < 0.0 else minf(halt, float(bo["halt"]))
	var won: bool = nr["state"] == "strike"
	var mk := one_mistakes(n, level, units, upgrades, g["route"]) if mistakes else {"lost": 0, "total": 0}
	return {"level": n, "rows": rows, "k": k, "kf": kf, "fire_k": fk, "boss_k": bk, "band": g["band"],
		"mistake_lost": mk["lost"], "mistake_total": mk["total"], "last_wave": g["last_wave"], "peak": g["peak"],
		"greedy_keep": g["keep"], "greedy_lost": g["lost"], "greedy_mix": g["mix"], "gap_med": g["gap_med"],
		"max_air": g["max_air"], "greedy_win": g["state"] == "strike", "greedy_time": g["time"],
		"greedy_route": g["route"], "guards": guard_failures(g), "boss_halt": halt,
		"noisy_fail": fail, "wins": int(round(share * routes.size())), "total": routes.size(), "win_rate": share,
		"target": RANDOM_FLOOR, "noad": na["ok"], "np_win": na["ok"],
		"best_win": br["state"] == "strike" or won, "best_route": best["route"], "best_troops": br["troops"],
		"best_peak": br["peak"], "best_ratio": _ratio(br), "best_stars": br["stars"], "best_time": br["time"],
		# The stored route keeps the no-ad guarantee: it is the best route without powers.
		"route": na["route"] if won else [], "route_np": [], "route_troops": nr["troops"] if won else 0}


static func harder_row(r: Dictionary) -> String:
	var b: Dictionary = BANDS[String(r["band"])]
	var keep := float(r["greedy_keep"])
	var fail := float(r["noisy_fail"])
	var halt := float(r.get("boss_halt", -1.0))
	var mix: Dictionary = r.get("greedy_mix", {})
	var mt := int(r.get("mistake_total", 0))
	var ms := float(r.get("mistake_lost", 0)) / float(mt) if mt > 0 else 0.0
	var lw := float(r.get("last_wave", 0)) / maxf(float(r.get("peak", 1)), 1.0)
	return "%5d | %-8s | %-4s %3.0f%% (%2.0f-%2.0f%%) %s | %3.0f%% %s m%3.0f r%3.0f | %3.0f%% (%2.0f-%2.0f%%) %s | %3.0f%% %s | %-5s | %5d/%-5d %3.0f%% | %6.1f | %5s | %.3f / %.3f / %.3f / %.2f | 1-miss %2d/%-2d %3.0f%% %s | last x%.1f %s | %s" % [
		r["level"], r["band"], "win" if r["greedy_win"] else "LOSE", keep * 100.0,
		float(b["keep"][0]) * 100.0, float(b["keep"][1]) * 100.0, "ok" if r["greedy_win"] and in_band(keep, b["keep"], KEEP_SLACK) else "!!",
		float(r.get("greedy_lost", 0.0)) * 100.0, "ok" if float(r.get("greedy_lost", 0.0)) <= lost_max(b) + 1e-9 else "!!",
		mix_share(mix, "melee") * 100.0, mix_share(mix, "rf") * 100.0,
		fail * 100.0, float(b["fail"][0]) * 100.0, float(b["fail"][1]) * 100.0, "ok" if in_band(fail, b["fail"]) else "~",
		float(r["win_rate"]) * 100.0, "ok" if float(r["win_rate"]) >= RANDOM_FLOOR - 1e-9 else "!!",
		"ok" if r["noad"] else "LOSE", r["best_troops"], r["best_peak"], float(r["best_ratio"]) * 100.0,
		float(r["greedy_time"]), "-" if halt < 0.0 else "%.1f" % halt, r["k"], r["kf"], float(r.get("fire_k", 1.0)),
		float(r.get("boss_k", 1.0)), int(r.get("mistake_lost", 0)), mt, ms * 100.0,
		"ok" if ms <= float(MISTAKE_MAX[String(r["band"])]) + 1e-9 else "!!", lw, "" if lw <= LAST_MAX * LAST_SLACK else "~",
		"ok" if (r["guards"] as Array).is_empty() else "; ".join(r["guards"])]


## The most of its peak the greedy player may lose to enemies over a level of band `b` (advisor
## R5: lost ÷ peak beside end ÷ peak, so early attrition the end/peak share cannot see counts).
static func lost_max(b: Dictionary) -> float:
	return 1.0 - float(b["keep"][0]) + LOST_SLACK


## A loss-mix share: `key`'s troops over everything enemies took (0 when they took nothing).
static func mix_share(mix: Dictionary, key: String) -> float:
	var total := 0
	for k in mix:
		total += int(mix[k])
	return float(mix.get(key, 0)) / float(total) if total > 0 else 0.0


## The v2.1 keep fit (plan v2.1 Task 8; advisor R3, 2026-11-13). Only the greedy player is
## fitted, one deterministic run per probe: its end ÷ peak squad (keep) aimed at the band's
## midpoint, with lost ÷ peak (every troop enemies took) at most lost_max. Since the crowd clash
## (spec v2.1 §1.4) losses are graded: a gang that reaches the squad grinds into it 1:1 at a
## capped pace, so the keep falls smoothly as the gangs grow. The dials, in order (_axes): the
## last wave's size kf (the end/peak dial), every gang's size k (the visible crowd number), the
## level's fire intensity fire_k within FIRE_K (the "they shoot at me" texture) and, on boss and
## lieutenant levels, boss_k in BOSS_K steps (his gun and barrage). Each is fitted from the best
## point so far (_fit_axis: walk out to bracket the midpoint, then secant or bisection; at most
## AXIS_PROBES), the next only while the keep is still outside the band. Then the floors once
## (_floors): the no-ad guarantee, the random floor and, on normal levels, a greedy win at
## WEAK_FP of the pace's firepower (advisor A2); if one breaks it backs off toward easier scales.
## The noisy fail rate is only measured and reported. A level stops after LEVEL_CAP_S.
func calibrate_harder(n: int, base: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var bname := band(n, base)
	var b: Dictionary = BANDS[bname]
	var want := band_mid(b["keep"])
	var probes: Array = []
	_floor_broke = false
	# Stale values from before the fire_k bounds are clamped into them first.
	var sc := {"k": _clamp_rel(n, base, "k", 1.0), "kf": _clamp_rel(n, base, "kf", 1.0),
		"fk": _clamp_rel(n, base, "fk", 1.0), "bk": _clamp_rel(n, base, "bk", 1.0)}
	# cap=1 (review v2.1, an experiment): the last wave holds at most LAST_MAX x the greedy peak
	# squad. The peak comes from the gate rows, so the first run sets the cap for the whole fit;
	# every probe trims kf to it (_probe).
	_last_cap = -1
	if cap_last:
		var first := greedy_probe(n, scaled_level(base, sc["k"], sc["kf"], sc["fk"], sc["bk"]))
		_last_cap = int(floor(LAST_MAX * float(first["peak"])))
	var best := _probe(n, base, sc, probes)
	var chosen := {}
	if _fits(best, b) and _floors(n, base, sc)["ok"]:
		chosen = best   # already in band with the floors: nothing to fit (passes converge)
	else:
		var from := best   # where the next dial starts: the easy end of the last bracket
		for axis in _axes(base):
			if _fits(best, b) or _over(t0) or probes.size() >= FIT_PROBES:
				break
			var f := _fit_axis(n, base, axis, _scales(from), want, mini(AXIS_PROBES, FIT_PROBES - probes.size()), probes, t0)
			if _closer(f["best"], best, want):
				best = f["best"]
			from = best
			if not (f["easy"] as Dictionary).is_empty() and not (f["hard"] as Dictionary).is_empty() 					and float(f["easy"]["keep"]) > float(b["keep"][1]):
				from = f["easy"]   # the crossing is just past it: the next dial finishes the job
		if _floors(n, base, _scales(best))["ok"]:
			chosen = best
		else:
			chosen = _back_off(n, base, _scales(best), t0)
			# The floors bind (a weaker route walks into a gang sized for the greedy squad): the
			# rest comes from fire, a share of whatever squad it hits, so a weaker route pays the
			# same share. fire_k (then boss_k) up toward the band, the floors checked again.
			for axis in ["fk", "bk"]:
				if chosen.is_empty() or not bool(chosen["win"]) or float(chosen["keep"]) <= float(b["keep"][1]) or _over(t0):
					break
				if axis == "bk" and not _axes(base).has("bk"):
					break
				var f2 := _fit_axis(n, base, axis, _scales(chosen), want, AXIS_PROBES, probes, t0)
				# The probes nearest the midpoint first: the first that holds the floors wins.
				var cands: Array = (f2["all"] as Array).filter(func(q): return bool(q["win"]) and _closer(q, chosen, want))
				cands.sort_custom(func(a, c): return _closer(a, c, want))
				for cand in cands:
					if _over(t0):
						break
					if _floors(n, base, _scales(cand))["ok"]:
						chosen = cand
						break
	var fin := _scales(chosen)
	if verbose:
		print("      L%d fit k %.3f kf %.3f fire_k x%.3f boss_k x%.3f keep %.0f%% lost %.0f%% (%s, want %.0f%%) in %d probes" % [n,
			fin["k"], fin["kf"], fin["fk"], fin["bk"], float(chosen.get("keep", -1.0)) * 100.0,
			float(chosen.get("lost", -1.0)) * 100.0, bname, want * 100.0, probes.size()])
	var r := evaluate_harder(n, base, fin["k"], fin["kf"], VALID_NOISY, fin["fk"], fin["bk"])
	r["probes"] = probes.size()
	r["fit_s"] = (Time.get_ticks_msec() - t0) / 1000.0
	# Left above its band because going harder broke a floor (gen_levels.py --merge records it).
	r["floor_bound"] = _floor_broke and bool(r["greedy_win"]) and float(r["greedy_keep"]) > float(b["keep"][1]) + KEEP_SLACK
	return r


## The dials the fit turns, in order (advisor R3): kf; k when kf alone cannot get there, then
## kf again from that point (k brings a far-too-easy level to where its last wave bites, kf
## sets it); fire_k; and boss_k on a level with a boss or lieutenant.
static func _axes(base: Dictionary) -> Array:
	var out: Array = ["kf", "k", "kf", "fk"]
	for e in base.get("events", []):
		if e["type"] == "wave":
			for g in e["groups"]:
				if _is_boss_group(g):
					out.append("bk")
					return out
	return out


## A probe meets the band: a win, keep inside the band, lost inside lost_max.
static func _fits(p: Dictionary, b: Dictionary) -> bool:
	return bool(p["win"]) and in_band(float(p["keep"]), b["keep"]) and float(p.get("lost", 0.0)) <= lost_max(b) + 1e-9


static func _scales(p: Dictionary) -> Dictionary:
	return {"k": float(p["k"]), "kf": float(p["kf"]), "fk": float(p["fk"]), "bk": float(p.get("bk", 1.0))}


## A run's keep share: end ÷ peak squad, 0 for a loss. A win slower than MAX_TIME fades over
## SLOW_GRACE s instead of dropping to 0 (advisor R5: no holes for the fit to fall into).
static func keep_of(r: Dictionary) -> float:
	var k := _ratio(r)
	var t := float(r["time"])
	if t > MAX_TIME:
		k *= clampf((MAX_TIME + SLOW_GRACE - t) / SLOW_GRACE, 0.0, 1.0)
	return k


## The greedy player's run at this level plus the lanes it took: one probe of the keep fit.
## `ucfg` = other units (the weaker squad of the A2 floor); {} = the run's own.
func greedy_probe(n: int, level: Dictionary, ucfg := {}) -> Dictionary:
	var s := noisy_seed(n, 1000)
	seed(s)
	var pilot := GreedyPilot.new(tap_rate, use_powers, 0.0, s, dodge_share)
	var w := play_watched(LevelSim.new(level, units if ucfg.is_empty() else ucfg, upgrades), pilot)
	var r: Dictionary = w["result"]
	r["route"] = pilot.choices.duplicate()
	r["keep"] = keep_of(r)
	r["lost"] = float(w["enemy_lost"]) / maxf(float(r["peak"]), 1.0)
	r["mix"] = w["mix"]
	return r


func _probe(n: int, base: Dictionary, sc: Dictionary, probes: Array) -> Dictionary:
	sc = _capped(base, sc)
	var r := greedy_probe(n, scaled_level(base, sc["k"], sc["kf"], sc["fk"], sc.get("bk", 1.0)))
	var p := {"k": sc["k"], "kf": sc["kf"], "fk": sc["fk"], "bk": sc.get("bk", 1.0), "keep": float(r["keep"]),
		"lost": float(r["lost"]), "win": r["state"] == "strike", "time": float(r["time"])}
	p["over"] = maxf(float(p["lost"]) - lost_max(BANDS[band(n, base)]), 0.0)
	probes.append(p)
	if verbose:
		print("        probe k %.4f kf %.4f fk %.4f bk %.3f -> %s keep %.1f%% lost %.1f%% %.0fs (m%.0f r%.0f)" % [sc["k"], sc["kf"],
			sc["fk"], sc.get("bk", 1.0), r["state"], float(p["keep"]) * 100.0, float(p["lost"]) * 100.0, float(p["time"]),
			mix_share(r["mix"], "melee") * 100.0, mix_share(r["mix"], "rf") * 100.0])
	return p


## `sc` with kf trimmed so the last wave holds at most _last_cap people (review v2.1; no cap set:
## unchanged). The last wave scales with k x kf, so a larger k leaves a smaller kf.
func _capped(base: Dictionary, sc: Dictionary) -> Dictionary:
	if _last_cap <= 0:
		return sc
	var out := sc.duplicate()
	for i in 4:
		var lw := last_wave_count(scaled_level(base, out["k"], out["kf"]))
		if lw <= _last_cap:
			break
		out["kf"] = float(out["kf"]) * float(_last_cap) / float(lw) * 0.995
	return out


## The people in a level's last wave (its boss or lieutenant left out).
static func last_wave_count(level: Dictionary) -> int:
	var last: Dictionary = {}
	for e in level.get("events", []):
		if e["type"] == "wave":
			last = e
	var n := 0
	for g in last.get("groups", []):
		if not _is_boss_group(g):
			n += int(g["n"])
	return n


## Review v2.1 (gate cliff): the greedy route with exactly one row taken in another lane, every
## such route played like the greedy player (taps, powers, dodging). {lost, total}.
static func one_mistakes(n: int, level: Dictionary, units_cfg: Dictionary, up: Dictionary, route: Array) -> Dictionary:
	var lost := 0
	var total := 0
	for i in route.size():
		for l in 3:
			if l == int(route[i]):
				continue
			var r := route.duplicate()
			r[i] = l
			seed(noisy_seed(n, 3000 + i * 3 + l))
			var res := Autopilot.play(LevelSim.new(level, units_cfg, up),
				Autopilot.new(r, true, true, GreedyPilot.TAPS, GreedyPilot.DODGE_P))
			total += 1
			if String(res["state"]) != "strike":
				lost += 1
	return {"lost": lost, "total": total}


func _over(t0: int) -> bool:
	return (Time.get_ticks_msec() - t0) / 1000.0 > LEVEL_CAP_S


## Whether probe a is a better fit than b: a win beats a loss, then the keep nearer `want`
## (a probe over lost_max counts as LOST_SLACK further away); within a point of each other,
## the one nearer the current files.
static func _closer(a: Dictionary, b: Dictionary, want: float) -> bool:
	if b.is_empty():
		return true
	if bool(a["win"]) != bool(b["win"]):
		return bool(a["win"])
	var da := absf(float(a["keep"]) - want) + float(a.get("over", 0.0))
	var db := absf(float(b["keep"]) - want) + float(b.get("over", 0.0))
	if absf(da - db) < 0.01 and a.has("fk") and b.has("fk"):
		return _moved(a) < _moved(b)
	return da < db


static func _moved(p: Dictionary) -> float:
	return absf(log(float(p["k"]))) + absf(log(float(p["kf"]))) + absf(log(float(p["fk"]))) + absf(log(float(p.get("bk", 1.0))))


## The level's current value of a dial (its files: calibration.json k, kf; the level's fire_k
## and boss_k).
func _current(n: int, base: Dictionary, axis: String) -> float:
	match axis:
		"fk":
			return maxf(float(base.get("fire_k", 1.0)), 1e-6)
		"bk":
			return maxf(float(base.get("boss_k", 1.0)), 1e-6)
	var c: Dictionary = cal_all.get(str(n), {})
	return maxf(float(c.get(axis, 1.0)), 1e-6)


## The relative range one dial may try: its absolute bounds (K_ABS, KF_ABS, FIRE_K, BOSS_K)
## over the level's current value.
func _axis_range(n: int, base: Dictionary, axis: String) -> Array:
	var lim: Array = {"k": K_ABS, "kf": KF_ABS, "fk": FIRE_K, "bk": [BOSS_K[0], BOSS_K[BOSS_K.size() - 1]]}[axis]
	var cur := _current(n, base, axis)
	return [float(lim[0]) / cur, float(lim[1]) / cur]


## `x` (relative) clamped into the dial's range.
func _clamp_rel(n: int, base: Dictionary, axis: String, x: float) -> float:
	var r := _axis_range(n, base, axis)
	return clampf(x, float(r[0]), float(r[1]))


## One dial (`axis`: "kf" the last wave, "k" every gang, "fk" fire intensity, "bk" the boss)
## fitted from `sc` so the greedy keep is `want` (the keep falls as the dial grows). Returns
## {best: the probe closest to want, a win if any won; easy: the hardest probe that kept more;
## hard: the easiest that kept less} ({} when there is none). boss_k takes BOSS_K steps.
func _fit_axis(n: int, base: Dictionary, axis: String, sc: Dictionary, want: float, budget: int,
		probes: Array, t0: int) -> Dictionary:
	if axis == "bk":
		return _fit_steps(n, base, sc, want, budget, probes, t0)
	var lims := _axis_range(n, base, axis)
	var lo_lim := log(float(lims[0]))
	var hi_lim := log(float(lims[1]))
	var x := clampf(log(float(sc[axis])), lo_lim, hi_lim)
	var mine: Array = []
	var p := _probe(n, base, _with(sc, axis, x), probes)
	mine.append(p)
	var easy := {}   # {x, keep, p}: the hardest probe so far that keeps more than want
	var hard := {}   # ... the easiest that keeps less
	if float(p["keep"]) > want:
		easy = {"x": x, "keep": p["keep"], "p": p}
	else:
		hard = {"x": x, "keep": p["keep"], "p": p}
	var step := log(1.6)
	# Walk out until the keep crosses want.
	while mine.size() < budget and absf(float(p["keep"]) - want) > FIT_TOL and (easy.is_empty() or hard.is_empty()) and not _over(t0):
		var nx := clampf(x + (step if hard.is_empty() else -step), lo_lim, hi_lim)
		if absf(nx - x) < 1e-6:
			break   # the range ends here
		x = nx
		p = _probe(n, base, _with(sc, axis, x), probes)
		mine.append(p)
		if float(p["keep"]) > want:
			easy = {"x": x, "keep": p["keep"], "p": p}
		else:
			hard = {"x": x, "keep": p["keep"], "p": p}
		step *= 1.5
	# Narrow the bracket: secant when both ends won, else bisection.
	while mine.size() < budget and not easy.is_empty() and not hard.is_empty() and absf(float(p["keep"]) - want) > FIT_TOL \
			and absf(float(hard["x"]) - float(easy["x"])) > log(1.004) and not _over(t0):
		var xe := float(easy["x"])
		var xh := float(hard["x"])
		var nx := (xe + xh) * 0.5
		if float(hard["keep"]) > 0.0:
			var t := (float(easy["keep"]) - want) / maxf(float(easy["keep"]) - float(hard["keep"]), 1e-6)
			nx = lerpf(xe, xh, clampf(t, 0.15, 0.85))
		p = _probe(n, base, _with(sc, axis, nx), probes)
		mine.append(p)
		if float(p["keep"]) > want:
			easy = {"x": nx, "keep": p["keep"], "p": p}
		else:
			hard = {"x": nx, "keep": p["keep"], "p": p}
	var best := {}
	for q in mine:
		if _closer(q, best, want):
			best = q
	return {"best": best, "easy": easy.get("p", {}), "hard": hard.get("p", {}), "all": mine}


## boss_k in BOSS_K steps (coarse, advisor R4: a fourth dial invites overfitting): from the
## step nearest `sc`, one step at a time toward the band's midpoint until the keep crosses it.
func _fit_steps(n: int, base: Dictionary, sc: Dictionary, want: float, budget: int, probes: Array, t0: int) -> Dictionary:
	var cur := _current(n, base, "bk")
	var steps: Array = []
	for v in BOSS_K:
		steps.append(float(v) / cur)
	var i := 0
	for j in steps.size():
		if absf(log(float(steps[j]) / float(sc["bk"]))) < absf(log(float(steps[i]) / float(sc["bk"]))):
			i = j
	var s2 := sc.duplicate()
	s2["bk"] = steps[i]
	var p := _probe(n, base, s2, probes)
	var mine: Array = [p]
	var dir := 1 if float(p["keep"]) > want else -1
	while mine.size() < budget and not _over(t0) and absf(float(p["keep"]) - want) > FIT_TOL:
		i += dir
		if i < 0 or i >= steps.size():
			break
		s2 = sc.duplicate()
		s2["bk"] = steps[i]
		p = _probe(n, base, s2, probes)
		mine.append(p)
		if (float(p["keep"]) > want) != (dir > 0):
			break   # crossed the midpoint
	var best := {}
	for q in mine:
		if _closer(q, best, want):
			best = q
	return {"best": best, "easy": {}, "hard": {}, "all": mine}


static func _with(sc: Dictionary, axis: String, x: float) -> Dictionary:
	var s2 := sc.duplicate()
	s2[axis] = exp(x)
	return s2


## The floors at these scales: the random-route floor, the no-ad guarantee and, on normal
## levels, the greedy player still wins with WEAK_FP of the pace's firepower (advisor A2).
func _floors(n: int, base: Dictionary, sc: Dictionary) -> Dictionary:
	var lv := scaled_level(base, sc["k"], sc["kf"], sc["fk"], sc.get("bk", 1.0))
	var routes := sample_routes(n, Autopilot.gate_row_count(lv), VALID_ROUTES)
	var share := _win_share(lv, routes, int(ceil(random_floor * routes.size() - 1e-9)))
	var floor_ok := share >= random_floor - 1e-9
	var weak_ok := true
	if floor_ok and band(n, base) == "normal":
		weak_ok = greedy_probe(n, lv, weak_units())["state"] == "strike"
	var ok := floor_ok and weak_ok and bool(noad(n, lv, base.get("route", []), false)["ok"])
	_floor_broke = _floor_broke or not ok
	if verbose:
		print("        floors k %.4f kf %.4f fk %.4f bk %.3f: random wins %.0f%%, weak %s, no-ad %s" % [sc["k"], sc["kf"], sc["fk"],
			sc.get("bk", 1.0), share * 100.0, "ok" if weak_ok else "LOSE", ("ok" if ok else "LOSE") if floor_ok and weak_ok else "-"])
	return {"ok": ok, "share": share}


## The units with every ally's and hero weapon's fire rate x WEAK_FP (cached): the pace minus
## about one Armory tier (advisor A2).
func weak_units() -> Dictionary:
	if _weak.is_empty():
		_weak = scaled_units(units, WEAK_FP)
	return _weak


## `u` with every ally's and hero weapon's rate x fp (firepower; a one-hit kill stays one hit).
static func scaled_units(u: Dictionary, fp: float) -> Dictionary:
	var out: Dictionary = u.duplicate(true)
	for table in ["allies", "hero_weapons"]:
		for key in out.get(table, {}):
			var d: Variant = out[table][key]
			if d is Dictionary and (d as Dictionary).has("rate"):
				d["rate"] = float(d["rate"]) * fp
	return out


## Backs off from scales that broke a floor toward ones that hold them: easier steps from the
## fit (_easier) until the floors hold and the greedy player still wins, then BACKOFF_STEPS
## bisections in log scale between the two. Returns the probe it settled on.
func _back_off(n: int, base: Dictionary, sc: Dictionary, t0: int) -> Dictionary:
	var ga := _easier(n, sc, base)
	var good_p := {}
	for j in 6:
		var p := _probe(n, base, ga, [])
		if bool(p["win"]) and _floors(n, base, ga)["ok"]:
			good_p = p
			break
		ga = _easier(n, ga, base)
		if _over(t0):
			break
	if good_p.is_empty():
		print("      !! L%d no scale tried holds the floors; kept k %.3f kf %.3f fk %.3f bk %.3f" % [n, ga["k"], ga["kf"], ga["fk"], ga["bk"]])
		return _probe(n, base, ga, [])
	var good := 0.0
	var bad := 1.0
	for i in BACKOFF_STEPS:
		if _over(t0):
			break
		var t := (good + bad) * 0.5
		var mid := _lerp_scales(ga, sc, t)
		var p := _probe(n, base, mid, [])
		if bool(p["win"]) and _floors(n, base, mid)["ok"]:
			good = t
			good_p = p
		else:
			bad = t
	return good_p


## One step easier: the last wave x0.85, every gang x0.9, the boss's gun and barrage x0.85
## (not below their bounds: a weaker squad stands under a boss longer); fire_k x0.85 but not
## below the files' value (fire is the floors' friend: _back_off's caller turns it up again).
func _easier(n: int, sc: Dictionary, base: Dictionary) -> Dictionary:
	return {"k": maxf(float(sc["k"]) * 0.9, float(_axis_range(n, base, "k")[0])),
		"kf": maxf(float(sc["kf"]) * 0.85, float(_axis_range(n, base, "kf")[0])),
		"fk": maxf(float(sc["fk"]) * 0.85, minf(float(sc["fk"]), 1.0)),
		"bk": maxf(float(sc.get("bk", 1.0)) * 0.85, float(_axis_range(n, base, "bk")[0])) if _axes(base).has("bk") else float(sc.get("bk", 1.0))}


static func _lerp_scales(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in ["k", "kf", "fk", "bk"]:
		out[key] = exp(lerpf(log(float(a.get(key, 1.0))), log(float(b.get(key, 1.0))), t))
	return out


## sweep=1 (advisor A1 and A2): per level, the greedy keep at the files' scales x SWEEP_STEPS for
## k and for kf (every adjacent step within SWEEP_JUMP, no win -> loss within ±10 %), and at the
## pace's firepower x WEAK_FP (normal levels must win) and x STRONG_FP (keep at most the band's
## top + 15 points). Returns the number of failures.
func run_sweep(lo: int, hi: int, only: Array) -> int:
	if only.is_empty():
		only = range(lo, hi + 1)
	print("sweep (advisor A1/A2): greedy keep %% at k and kf x %s; firepower x%.2f / x%.2f" % [str(SWEEP_STEPS), WEAK_FP, STRONG_FP])
	var fails: Array = []
	var strong := scaled_units(units, STRONG_FP)
	for n in only:
		var base := Config.level(n)
		upgrades = level_upgrades(n)
		var b: Dictionary = BANDS[band(n, base)]
		var line := "%5d | %-8s" % [n, band(n, base)]
		for axis in ["k", "kf"]:
			var keeps: Array = []
			var wins: Array = []
			for s in SWEEP_STEPS:
				var sc := {"k": 1.0, "kf": 1.0, "fk": 1.0, "bk": 1.0}
				sc[axis] = s
				var p := _probe(n, base, sc, [])
				keeps.append(float(p["keep"]))
				wins.append(bool(p["win"]))
			var cells := ""
			var jump := 0.0
			for i in keeps.size():
				cells += "%s%3.0f" % [" " if wins[i] else "x", float(keeps[i]) * 100.0]
				if i > 0:
					jump = maxf(jump, absf(float(keeps[i]) - float(keeps[i - 1])))
			line += " | %s %s (jump %2.0f)" % [axis, cells, jump * 100.0]
			if jump > SWEEP_JUMP + 1e-9:
				fails.append("L%d %s: keep jumps %.0f points in one step" % [n, axis, jump * 100.0])
			var mid := SWEEP_STEPS.find(1.0)
			if mid >= 0 and wins[mid]:
				for i in SWEEP_STEPS.size():
					if absf(float(SWEEP_STEPS[i]) - 1.0) <= 0.1 + 1e-9 and not wins[i]:
						fails.append("L%d %s x%.1f: the win flips to a loss" % [n, axis, float(SWEEP_STEPS[i])])
		var lv := base
		var wk := greedy_probe(n, lv, scaled_units(units, WEAK_FP))
		var st := greedy_probe(n, lv, strong)
		line += " | fp x%.2f %s %3.0f%% | x%.2f %s %3.0f%%" % [WEAK_FP, "win" if wk["state"] == "strike" else "LOSE",
			float(wk["keep"]) * 100.0, STRONG_FP, "win" if st["state"] == "strike" else "LOSE", float(st["keep"]) * 100.0]
		if band(n, base) == "normal" and wk["state"] != "strike":
			fails.append("L%d loses at x%.2f firepower" % [n, WEAK_FP])
		if float(st["keep"]) > float(b["keep"][1]) + 0.15 + 1e-9:
			fails.append("L%d keeps %.0f%% at x%.2f firepower (band top + 15 = %.0f%%)" % [n, float(st["keep"]) * 100.0,
				STRONG_FP, (float(b["keep"][1]) + 0.15) * 100.0])
		print(line)
	print("sweep: %d failed" % fails.size())
	for f in fails:
		print("  FAIL " + String(f))
	return fails.size()


## checks=1 (spec v2.1 §2 guard checks): per level the greedy player at the pace (keep share
## in band ±KEEP_SLACK, armed gangs fire, enemies cost troops, bosses and lieutenants fight),
## the hero alone with zero upgrades never one-shot, the stored route's no-ad guarantee and
## the random-route floor (RANDOM_FLOOR of the report's n_routes sample wins). full=1 adds the
## noisy first-try fail rate, printed against its band (~ when outside) and never asserted:
## it is a soft target. Returns the number of failures.
func run_guard_checks(lo: int, hi: int, only: Array, full: bool) -> int:
	if only.is_empty():
		only = range(lo, hi + 1)
	print("guard checks (spec v2.1 §2): greedy at the pace, tap %.1f/s, powers %s, dodge_p %.2f" % [tap_rate,
		"on" if use_powers else "off", dodge_share])
	print("level | band     | greedy keeps         | lost  melee rf | gap s air | fired/armed | enemy cost | bosses (halt s/barrages) | no-ad | extra")
	var fails: Array = []
	for n in only:
		var lv := Config.level(n)
		upgrades = level_upgrades(n)
		var r := watch_greedy(n, lv, units, upgrades, dodge_share, tap_rate, use_powers)
		var solo := solo_one_shot(n, lv, units)
		if solo != "":
			r["solo_shot"] = solo
		var f := guard_failures(r)
		var na := noad_ok(n, lv, lv.get("route", []))
		if not na:
			f.append("L%d the stored route loses at the no-ad pace without powers" % n)
		var share := _win_share(lv, sample_routes(n, Autopilot.gate_row_count(lv), n_routes))
		if share < RANDOM_FLOOR - 1e-9:
			f.append("L%d random routes win %.0f%% (floor %.0f%%)" % [n, share * 100.0, RANDOM_FLOOR * 100.0])
		var mk := one_mistakes(n, lv, units, upgrades, r["route"])
		var mshare := float(mk["lost"]) / maxf(float(mk["total"]), 1.0)
		if mshare > float(MISTAKE_MAX[String(r["band"])]) + 1e-9:
			f.append("L%d %d of %d one-mistake routes lose (%.0f%%, want at most %.0f%%)" % [n, int(mk["lost"]),
				int(mk["total"]), mshare * 100.0, float(MISTAKE_MAX[String(r["band"])]) * 100.0])
		var bosses := ""
		for bo in r["bosses"]:
			bosses += "%s %.1f/%d " % ["lt" if bo["lt"] else "boss", float(bo["halt"]), int(bo["barrages"])]
		var extra := "random wins %.0f%%, 1-miss loses %d/%d, last x%.1f" % [share * 100.0, int(mk["lost"]), int(mk["total"]),
			float(r["last_wave"]) / maxf(float(r["peak"]), 1.0)]
		if full:
			var bd: Dictionary = BANDS[String(r["band"])]
			var nf := noisy_fail(n, lv)
			extra += ", noisy fails %.0f%% (soft %.0f-%.0f%%)%s" % [nf * 100.0, float(bd["fail"][0]) * 100.0,
				float(bd["fail"][1]) * 100.0, "" if in_band(nf, bd["fail"]) else " ~"]
		print("%5d | %-8s | %-4s %3.0f%% %5d/%-5d | %3.0f%% %3.0f%% %3.0f%% | %4.2f %d | %4d/%-6d | %10d | %-24s | %-5s | %s%s" % [n, r["band"],
			"win" if r["state"] == "strike" else "LOSE", float(r["keep"]) * 100.0, int(r["troops"]), int(r["peak"]),
			float(r["lost"]) * 100.0, mix_share(r["mix"], "melee") * 100.0, mix_share(r["mix"], "rf") * 100.0,
			float(r["gap_med"]), int(r["max_air"]),
			int(r["fired"]), int(r["armed"]), int(r["enemy_lost"]), bosses, "ok" if na else "LOSE", extra,
			"" if f.is_empty() else "  !! %d" % f.size()])
		fails.append_array(f)
	print("guard checks: %d failed" % fails.size())
	for f in fails:
		print("  FAIL " + String(f))
	return fails.size()

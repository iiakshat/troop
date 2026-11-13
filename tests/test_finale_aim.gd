extends "res://tests/test_case.gd"
## Bottle Shot aim and bullet cam (owner play-test 2026-11-13): the pure parts here; the cases
## that drive real finales (an 8 s held finger at 30, 60 and uneven fps for the pistol, bow and
## sniper, a second finger, the bullet cam's framing, skip and clean-up) need a running tree, so
## they run in their own process (tests/smoke_finale_aim.gd) and are checked from here.


func _w(weapon: String) -> Dictionary:
	return Config.load_json("res://config/finale.json")["weapons"][weapon]


## The sniper's hold profile: smooth, capped at the full sway, resting at worse_k.
func test_sniper_hold_never_jumps_and_stays_gentle() -> void:
	var w := _w("sniper")
	var prev := WeaponSniper.hold_k(0.0, w)
	var worst := 0.0
	var top := prev
	for i in range(1, 20001):
		var k := WeaponSniper.hold_k(i * 0.001, w)
		worst = maxf(worst, absf(k - prev))
		top = maxf(top, k)
		prev = k
	check(worst < 0.002, "no millisecond changes the hold by more than 0.2 %% (%.4f)" % worst)
	check(top <= 1.0 + 1e-6, "a long hold never sways more than sway_deg (%.2f)" % top)
	near(prev, float(w["worse_k"]), "after a long hold it rests at worse_k")
	check(float(w["worse_k"]) <= 1.0, "worse_k is at most 1 (it was 2.4)")
	near(WeaponSniper.hold_k(float(w["steady_s"]) * 0.5, w), float(w["steady_k"]), "steady inside the window")
	near(WeaponSniper.steady_left(0.0, w), 1.0, "the breath arc starts full")
	near(WeaponSniper.steady_left(float(w["steady_s"]), w), 0.0, "and is empty when the steady window ends")
	near(WeaponSniper.tiredness(float(w["steady_s"]) - 0.1, w), 0.0, "no amber inside the window")
	check(WeaponSniper.tiredness(float(w["steady_s"]) + float(w["worse_s"]), w) > 0.99, "fully amber once the drift is back")


## The scope's drift and the bow's tired-arm drift, sampled at 30 and 60 fps over 10 s: small
## steps, slow, and no frequency high enough to alias into jumps at a low frame rate.
func test_drift_is_slow_and_small() -> void:
	var sw := _w("sniper")
	var noise := FastNoiseLite.new()
	noise.seed = 41
	noise.frequency = 3.0
	var bw := _w("bow")
	for fps in [30.0, 60.0]:
		var dt: float = 1.0 / float(fps)
		var prev_s := Vector2.ZERO
		var prev_b := Vector2.ZERO
		var step_s := 0.0
		var step_b := 0.0
		var max_s := 0.0
		var max_b := 0.0
		for i in int(10.0 * float(fps)):
			var t: float = (i + 1) * dt
			var s := WeaponSniper.sway_at(t, WeaponSniper.hold_k(t, sw), sw, noise)
			var b := WeaponBow.shake_at(t + float(bw["draw_s"]), bw)
			step_s = maxf(step_s, rad_to_deg((s - prev_s).length()) / float(sw["scope_fov"]))
			step_b = maxf(step_b, rad_to_deg((b - prev_b).length()) / float(bw["fov"]))
			max_s = maxf(max_s, rad_to_deg(s.length()) / float(sw["scope_fov"]))
			max_b = maxf(max_b, rad_to_deg(b.length()) / float(bw["fov"]))
			prev_s = s
			prev_b = b
		check(step_s < 0.004, "%d fps: the scope never steps more than 0.4 %% of its view (%.2f %%)" % [fps, step_s * 100.0])
		check(step_b < 0.004, "%d fps: the pin never steps more than 0.4 %% of the view (%.2f %%)" % [fps, step_b * 100.0])
		check(max_s < 0.07, "%d fps: the scope drifts at most 7 %% of its view (%.1f %%)" % [fps, max_s * 100.0])
		check(max_b < 0.03, "%d fps: the pin drifts at most 3 %% of the view (%.1f %%)" % [fps, max_b * 100.0])
	eq(WeaponBow.shake_at(float(bw["steady_s"]) - 0.01, bw), Vector2.ZERO, "the bow holds still through steady_s")


## The view eases onto the finger the same way at any frame rate.
func test_aim_ease_is_frame_rate_independent() -> void:
	var a := 0.0
	for i in 30:
		a = lerpf(a, 1.0, FinaleWeapon.ease_k(1.0 / 30.0, 0.05))
	var b := 0.0
	for i in 60:
		b = lerpf(b, 1.0, FinaleWeapon.ease_k(1.0 / 60.0, 0.05))
	near(a, b, "1 s of easing at 30 fps = at 60 fps")
	eq(FinaleWeapon.ease_k(0.0, 0.05), 0.0, "a zero-length frame moves nothing")


## The bullet cam's rider: follows the projectile, then eases to a stop short of the bottle,
## continuously.
func test_film_anchor_stops_short_smoothly() -> void:
	var arrive := 0.4
	var stop := 0.05
	var prev := 0.0
	var worst := 0.0
	for i in range(1, 801):
		var t := i * 0.0005
		var a := FinaleWeapon.film_anchor_t(t, arrive, stop)
		worst = maxf(worst, a - prev)
		check(a <= t + 1e-6, "never ahead of the projectile (%.3f)" % t)
		prev = a
	check(worst <= 0.0005 + 1e-6, "never faster than the projectile")
	check(FinaleWeapon.film_anchor_t(arrive, arrive, stop) < arrive - stop * 0.9, "stops about `stop` short")
	near(FinaleWeapon.film_anchor_t(0.1, arrive, stop), 0.1, "rides with it early on")


## The pinwheel's aim assist (owner 2026-11-13: "hard to control"): the swipe's line decides,
## within a small cone; on a line through two bottles the lift point picks (a short flick takes
## the first); nothing inside the cone is an honest miss.
func test_stars_aim_assist_reads_the_swipe() -> void:
	var cone := deg_to_rad(8.0)
	# Two columns of two bottles, 40 px radius, seen from a thumb at the bottom.
	var c := [{"s": Vector2(300, 700), "r": 40.0}, {"s": Vector2(300, 520), "r": 40.0},
		{"s": Vector2(460, 700), "r": 40.0}, {"s": Vector2(460, 520), "r": 40.0}]
	var a := Vector2(300, 1150)
	eq(WeaponStars.pick_target(a, Vector2(300, 1000), c, cone), 0, "a short flick straight up: the first bottle on the line")
	eq(WeaponStars.pick_target(a, Vector2(300, 525), c, cone), 1, "lifted on the upper bottle: that one")
	eq(WeaponStars.pick_target(a, Vector2(300, 690), c, cone), 0, "lifted on the lower bottle: that one")
	eq(WeaponStars.pick_target(a, Vector2(316, 1000), c, cone), 0, "a little off the line (well inside the cone): still the bottle")
	eq(WeaponStars.pick_target(a, a + (Vector2(460, 700) - a) * 0.4, c, cone), 2, "towards the right column: its first bottle")
	eq(WeaponStars.pick_target(a, Vector2(100, 1000), c, cone), -1, "well off to the side: nothing (an honest miss)")
	eq(WeaponStars.pick_target(a, a, c, cone), -1, "no swipe: nothing")
	# The line beats the lift point: lifted short, but pointing at the far bottle.
	var d := [{"s": Vector2(345, 760), "r": 30.0}, {"s": Vector2(300, 560), "r": 30.0}]
	eq(WeaponStars.pick_target(Vector2(300, 1150), Vector2(300, 900), d, cone), 1,
		"pointing straight at the far bottle, lifted short: not the near one beside the line")
	# No target: the line is carried on to the middle of the set's height.
	var lp := WeaponStars.line_point(Vector2(300, 1150), Vector2(300, 1050), c)
	near(lp.y, 610.0, "a short flick at nothing still flies on to the set's height")


## The live cases (real finales in a running tree), in their own process.
func test_live_finale_aim_and_bullet_cam() -> void:
	var out: Array = []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/smoke_finale_aim.gd"]
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(out)
	var summary := ""
	for line in text.split("\n"):
		if line.begins_with("FINALE AIM:"):
			summary = line
		elif line.strip_edges().begins_with("FAIL") or line.begins_with("        "):
			failures.append(line.strip_edges())
	check(summary != "", "the live cases ran (exit %d)" % code)
	eq(code, 0, "the live cases pass (%s)" % summary)

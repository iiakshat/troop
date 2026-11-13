extends "res://tests/test_case.gd"
## Bottle Shot aim and bullet cam (owner play-test 2026-11-13).
##   "holding doesnt work, it fluctuates a lot ... after 2-3 s ... it moves so aggressively":
##   a finger held still for 8 s at 30 fps, 60 fps and an uneven frame rate keeps every weapon's
##   aim steady (small frame-to-frame steps, slow drift, small total wander), the same at any
##   frame rate; a second finger neither steers nor fires.
##   "no slow motion for bullets in the pistol and sniper and bow ... not bullet itself visible":
##   a hit is filmed in slow motion with the round or arrow inside the frame and close to the
##   lens, it ends on the shatter, a tap skips it, and the clock is exactly 1 afterwards.
## These drive real finales (global transforms), so they need a running tree: not named test_*,
## they run inside tests/smoke_finale_aim.gd, which tests/test_finale_aim.gd starts and checks.

const VP := Vector2(540, 960)   # a portrait phone (the game camera keeps the width)
const LEVELS := {"pistol": 11, "bow": 21, "sniper": 41}

var _keep: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _ready_by_hand(n: Node) -> void:
	if n != null and not n.is_node_ready():
		n._ready()


func _drop_node(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.free()


func _boot() -> void:
	var game: Node = _tree().root.get_node("Game")
	_keep = [game.save.duplicate(true), game.save_path]
	game.save_path = ""
	game.boot({})


func _unboot() -> void:
	var game: Node = _tree().root.get_node("Game")
	game.save = _keep[0]
	game.save_path = _keep[1]


## [world, fx]: the street the finale plays in.
func _stage() -> Array:
	var world := World.new()
	_tree().root.add_child(world)
	var fx := Fx.new()
	fx.font = UiKit.FONT
	_tree().root.add_child(fx)
	for n in [world, fx]:
		_ready_by_hand(n)
	return [world, fx]


## The level's finale, built at load, woken in front of the hero and played to the aim.
func _finale(lv: int, stage: Array) -> BottleShot:
	var s := BottleShot.new().setup(stage[0], stage[1], UiKit.FONT, lv, 40, Vector3.ZERO, 0.0)
	s.dormant = true
	_tree().root.add_child(s)
	_ready_by_hand(s)
	_ready_by_hand(s.hud)
	_ready_by_hand(s._mode)
	s.rest()
	s.wake(40, Vector3.ZERO, 0.0)
	var guard := 0
	while s._state != "aim" and guard < 600:
		s._process(1.0 / 60.0)
		guard += 1
	return s


func _press(s: BottleShot, index: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = down
	s._unhandled_input(e)


func _drag(s: BottleShot, index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	s._unhandled_input(e)


## Where the shot would go now (what the crosshair, pin or scope shows).
func _aim(s: BottleShot) -> Vector3:
	var m := s._mode
	match s.logic.weapon:
		"sniper":
			var sw: Vector2 = (m as WeaponSniper)._sway * (m as WeaponSniper)._scope_k
			return m.aim_dir(sw.x, sw.y)
		"bow":
			var sh: Vector2 = (m as WeaponBow)._shake
			return m.aim_dir(sh.x, sh.y)
	return m.aim_dir()


## The view's width in degrees (the scope for the sniper).
func _view_deg(s: BottleShot) -> float:
	if s.logic.weapon == "sniper":
		return float(s.logic.wcfg.get("scope_fov", 2.8))
	return float(s.logic.wcfg.get("fov", 30.0))


## Holds a finger down for `seconds` with frame times cycling through `dts` (still, or with a
## pixel of finger jitter). Returns the worst frame-to-frame step, the fastest drift (per
## second), the widest wander from the aim at the press (all as shares of the view's width)
## and the final aim.
func _hold(weapon: String, dts: Array, seconds: float, jitter: bool) -> Dictionary:
	var stage := _stage()
	var s := _finale(int(LEVELS[weapon]), stage)
	var view := deg_to_rad(_view_deg(s))
	var at := Vector2(270, 620)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_press(s, 0, at, true)
	var a0 := _aim(s)
	var prev := a0
	var t := 0.0
	var i := 0
	var jump := 0.0
	var speed := 0.0
	var wander := 0.0
	while t < seconds - 0.0001:
		var dt := float(dts[i % dts.size()])
		i += 1
		if jitter:
			_drag(s, 0, at + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)))
		s._process(dt)
		t += dt
		var a := _aim(s)
		var step := a.angle_to(prev) / view
		jump = maxf(jump, step)
		speed = maxf(speed, step / dt)
		wander = maxf(wander, a.angle_to(a0) / view)
		prev = a
	var out := {"jump": jump, "speed": speed, "wander": wander, "final": prev, "view": view,
		"fired": s.logic.shots_fired}
	_drop_node(s)
	for n in stage:
		_drop_node(n)
	return out


func test_held_aim_is_steady_at_any_frame_rate() -> void:
	_boot()
	var rates := {"30 fps": [1.0 / 30.0], "60 fps": [1.0 / 60.0],
		"uneven": [1.0 / 60.0, 1.0 / 24.0, 1.0 / 45.0, 1.0 / 30.0, 1.0 / 90.0, 1.0 / 20.0]}
	for weapon in LEVELS:
		var finals := {}
		for rate in rates:
			for jitter in [false, true]:
				var r := _hold(weapon, rates[rate], 8.0, jitter)
				var tag := "%s %s%s" % [weapon, rate, " jitter" if jitter else ""]
				check(float(r["jump"]) < 0.006, "%s: no frame steps the aim more than 0.6 %% of the view (%.2f %%)" % [tag, float(r["jump"]) * 100.0])
				check(float(r["speed"]) < 0.15, "%s: it never drifts faster than 15 %% of the view a second (%.1f %%)" % [tag, float(r["speed"]) * 100.0])
				check(float(r["wander"]) < 0.12, "%s: 8 s held, it stays within 12 %% of the view (%.1f %%)" % [tag, float(r["wander"]) * 100.0])
				eq(int(r["fired"]), 0, "%s: holding never fires" % tag)
				if not jitter:
					finals[rate] = r
		var d := (finals["30 fps"]["final"] as Vector3).angle_to(finals["60 fps"]["final"]) / float(finals["30 fps"]["view"])
		check(d < 0.003, "%s: 8 s held at 30 and at 60 fps ends at the same aim (%.2f %% apart)" % [weapon, d * 100.0])
	_unboot()


## A thumb resting on the glass neither steers nor fires (it used to make the aim leap between
## the two fingers every frame).
func test_second_finger_neither_steers_nor_fires() -> void:
	_boot()
	var stage := _stage()
	for weapon in ["pistol", "sniper", "bow"]:
		var s := _finale(int(LEVELS[weapon]), stage)
		var view := deg_to_rad(_view_deg(s))
		_press(s, 0, Vector2(270, 620), true)
		for k in 30:
			s._process(1.0 / 60.0)
		var a0 := _aim(s)
		_press(s, 1, Vector2(60, 1100), true)
		for k in 20:
			_drag(s, 1, Vector2(60 + k * 20, 1100 - k * 40))
			s._process(1.0 / 60.0)
		var moved := _aim(s).angle_to(a0) / view
		check(moved < 0.02, "%s: a second finger's drag leaves the aim (%.1f %% of the view)" % [weapon, moved * 100.0])
		_press(s, 1, Vector2(460, 300), false)
		eq(s.logic.shots_fired, 0, "%s: lifting the second finger fires nothing" % weapon)
		_press(s, 0, Vector2(270, 620), false)
		eq(s.logic.shots_fired, 1, "%s: lifting the first finger fires" % weapon)
		_drop_node(s)
	for n in stage:
		_drop_node(n)
	_unboot()


## Fires the autoplay's perfect shot and plays it out at 60 fps, checking the bullet cam.
func _film_shot(s: BottleShot, weapon: String, skip_after := -1) -> Dictionary:
	var m := s._mode
	var broken0 := s.logic.broken_count()
	s.throw_at(Vector2.ZERO)
	var out := {"frames": 0, "out_of_frame": 0, "far": 0, "min_scale": 1.0, "real": 0.0, "held": false,
		"skipped": false, "worst": ""}
	var real := 0.0
	for f in 600:
		var dt := 1.0 / 60.0
		s._process(dt)
		real += dt
		if m.filming() and not m.film_holding() and m.film.has("p"):
			out["frames"] = int(out["frames"]) + 1
			out["real"] = float(out["real"]) + dt
			out["min_scale"] = minf(float(out["min_scale"]), s._scale)
			var p: Vector3 = m.film["p"]
			var q := s._cam.affine_inverse() * p
			var px := FinaleWeapon.project_cam(q, s._fov, VP)
			var inside := q.z < -0.03 and px.x > VP.x * 0.04 and px.x < VP.x * 0.96 and px.y > VP.y * 0.04 and px.y < VP.y * 0.96
			if not inside:
				out["out_of_frame"] = int(out["out_of_frame"]) + 1
				if String(out["worst"]) == "":
					out["worst"] = "frame %d: at %s (z %.2f)" % [int(out["frames"]), px, q.z]
			if q.length() > 1.8:
				out["far"] = int(out["far"]) + 1
			var head := s.to_world(FinaleWeapon.eye_point(s.logic.wcfg))
			if s._cam.origin.distance_to(head) < 1.5 and not s.camera_in_head():
				out["in_hair"] = int(out.get("in_hair", 0)) + 1
			if skip_after >= 0 and int(out["frames"]) >= skip_after:
				_press(s, 0, Vector2(270, 500), true)
				out["skipped"] = true
				out["scale_after_skip"] = s._scale
				out["filming_after_skip"] = m.filming()
				_press(s, 0, Vector2(270, 500), false)
				skip_after = -1
		if m.film_holding():
			out["held"] = true
		if s.logic.shots_fired > 0 and not m.filming() and s._state == "aim":
			break
	out["broke"] = s.logic.broken_count() > broken0
	out["scale_end"] = s._scale
	out["state"] = s._state
	return out


func test_bullet_cam_films_the_round_in_slow_motion() -> void:
	_boot()
	var stage := _stage()
	for weapon in LEVELS:
		var s := _finale(int(LEVELS[weapon]), stage)
		var r := _film_shot(s, weapon)
		check(bool(r["broke"]), "%s: the autoplay shot breaks a bottle" % weapon)
		check(int(r["frames"]) > 20, "%s: the hit is filmed (%d frames)" % [weapon, int(r["frames"])])
		check(float(r["min_scale"]) < 0.7, "%s: in slow motion (time scale %.2f)" % [weapon, float(r["min_scale"])])
		check(float(r["real"]) > 0.5 and float(r["real"]) < 1.3, "%s: the flight lasts about a second on screen (%.2f s)" % [weapon, float(r["real"])])
		eq(int(r["out_of_frame"]), 0, "%s: the round stays in frame (%s)" % [weapon, String(r["worst"])])
		# Close to the lens, except the last moment when the camera has stopped short of the
		# bottle and the round flies on into it.
		check(int(r["far"]) <= int(r["frames"]) / 5, "%s: and close to the lens (%d of %d frames over 1.8 m)" % [weapon, int(r["far"]), int(r["frames"])])
		eq(int(r.get("in_hair", 0)), 0, "%s: the hero is hidden while the film camera is by his head" % weapon)
		check(bool(r["held"]), "%s: it ends holding on the shatter" % weapon)
		eq(float(r["scale_end"]), 1.0, "%s: the clock is exactly 1 afterwards" % weapon)
		check(not s._mode.filming(), "%s: the film is over" % weapon)
		eq(s._state, "aim", "%s: and the aim is back" % weapon)
		# The weapon's own view has the camera again (not a frozen film shot).
		s._process(1.0 / 60.0)
		check(s._cam.origin.distance_to(s._mode.eye()) < 0.05, "%s: the camera is back at the eye" % weapon)
		_drop_node(s)
	for n in stage:
		_drop_node(n)
	_unboot()


func test_a_tap_skips_the_bullet_cam() -> void:
	_boot()
	var stage := _stage()
	for weapon in LEVELS:
		var s := _finale(int(LEVELS[weapon]), stage)
		var r := _film_shot(s, weapon, 6)
		check(bool(r["skipped"]), "%s: tapped mid-film" % weapon)
		check(not bool(r.get("filming_after_skip", true)), "%s: the tap ends the film" % weapon)
		eq(float(r.get("scale_after_skip", 0.0)), 1.0, "%s: at full speed at once" % weapon)
		check(bool(r["broke"]), "%s: the shot still breaks its bottle" % weapon)
		eq(float(r["scale_end"]), 1.0, "%s: the clock is 1 afterwards" % weapon)
		eq(s.logic.shots_fired, 1, "%s: the skipping tap fires nothing" % weapon)
		_drop_node(s)
	for n in stage:
		_drop_node(n)
	_unboot()


## Played to the end by the autoplay, every finale leaves the clock at 1 and gives the street
## its camera back; freed half way through a film, it gives the camera back too.
func test_finale_ends_with_the_clock_and_camera_back() -> void:
	_boot()
	var stage := _stage()
	var world: World = stage[0]
	for weapon in LEVELS:
		var s := _finale(int(LEVELS[weapon]), stage)
		var guard := 0
		while s._state != "finished" and guard < 60 * 90:
			if s._state == "aim":
				s.throw_at(Vector2.ZERO)
			s._process(1.0 / 60.0)
			guard += 1
		eq(s._state, "finished", "%s: the autoplay finishes the finale" % weapon)
		eq(s._scale, 1.0, "%s: the clock is 1" % weapon)
		check(world._cam_override == null, "%s: the street has its camera back" % weapon)
		_drop_node(s)
		var h := _finale(int(LEVELS[weapon]), stage)
		h.throw_at(Vector2.ZERO)
		var g := 0
		while not h._mode.filming() and g < 240:
			h._process(1.0 / 60.0)
			g += 1
		check(h._mode.filming(), "%s: mid-film" % weapon)
		_drop_node(h)
		check(world._cam_override == null, "%s: left mid-film, the street has its camera back" % weapon)
	for n in stage:
		_drop_node(n)
	_unboot()

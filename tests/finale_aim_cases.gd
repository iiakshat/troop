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


# ---------------------------------------------------------------- the pinwheel (owner 2026-11-13)
#   "the pinwheel is hard to control and doesnt tell how to shoot, in 6 level i scored nothing
#   with it"; "when pinwheel fails, the camera angle doesnt reset ... i was stuck there and had
#   to shoot with that angle, nothing being visible".

const ALL := {"knife": 1, "pistol": 11, "bow": 21, "stars": 31, "sniper": 41}
var _root_size := Vector2i.ZERO


## A portrait phone screen for the swipe geometry (headless runs open a square window).
func _boot_phone() -> void:
	_boot()
	var root := _tree().root
	_root_size = root.size
	root.size = Vector2i(720, 1280)


func _unboot_phone() -> void:
	_tree().root.size = _root_size
	_unboot()


## Plays frames until the finale aims again (a guest's gift is tapped through), or ends.
func _settle(s: BottleShot, dt := 1.0 / 60.0, max_s := 8.0) -> void:
	var t := 0.0
	s._process(dt)
	while not (s._state in ["aim", "tally", "finished"]) and t < max_s:
		if s._state == "gift" and s._gift != null:
			s._gift.skip()
		s._process(dt)
		t += dt


## A guest finale opens with the gift: tap through it to the aim.
func _to_aim(s: BottleShot) -> void:
	if s._state == "gift" and s._gift != null:
		s._gift.skip()
	_settle(s)


func _vp(s: BottleShot) -> Vector2:
	return s.hud.get_viewport().get_visible_rect().size


## Bottle `i`'s middle on screen as the player sees it, and its hit radius in pixels.
func _bottle_px(s: BottleShot, i: int) -> Array:
	var cam := s.world.camera
	var c := s._bottle_center(i, s._ft)
	var p := s.logic.position(i, s._ft)
	var w := s.to_world(Vector3(p.x, p.y, -s.logic.distance))
	var r := cam.unproject_position(w).distance_to(cam.unproject_position(w + Vector3(s.logic.hit_radius(), 0, 0)))
	return [cam.unproject_position(c), r]


## A finger's path: down at path[0], drags at the frame rate, up at the last point.
func _swipe(s: BottleShot, path: Array, dt: float) -> void:
	_press(s, 0, path[0], true)
	for k in range(1, path.size()):
		s._process(dt)
		_drag(s, 0, path[k])
	_press(s, 0, path[path.size() - 1], false)


## `seconds` of swipe from a to b sampled at 1/dt, eased out like a thumb (or bent by `bend`
## times its length to one side, like a thumb's arc).
func _path(a: Vector2, b: Vector2, seconds: float, dt: float, bend := 0.0) -> Array:
	var n := maxi(int(round(seconds / dt)), 1)
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * (b - a).length() * bend
	var out: Array = [a]
	for k in range(1, n + 1):
		var u := 1.0 - pow(1.0 - float(k) / n, 2.0)
		out.append(a.lerp(mid, u).lerp(mid.lerp(b, u), u))
	return out


## True when nothing standing sits on the line from `a` to bottle `i` before it (a short flick
## at it meets it first).
func _first_on_line(s: BottleShot, a: Vector2, i: int) -> bool:
	var bi: Array = _bottle_px(s, i)
	var to: Vector2 = (bi[0] as Vector2) - a
	var dir := to.normalized()
	for j in s.logic.count():
		if j == i or s.logic.broken[j]:
			continue
		var bj: Array = _bottle_px(s, j)
		var rel: Vector2 = (bj[0] as Vector2) - a
		var along := rel.dot(dir)
		if along > 0.0 and along < to.length() - float(bi[1]) and absf(rel.cross(dir)) < 2.0 * float(bj[1]):
			return false
	return true


## Typical swipes at a chosen bottle, at 30 and 60 fps, static and moving sets (and a guest):
## long ones onto the bottle, short flicks towards it, slightly off-target ones and curved ones.
## Most break the bottle they were aimed at.
func test_stars_swipes_break_the_aimed_bottle() -> void:
	_boot_phone()
	var stage := _stage()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var styles := ["long", "flick", "off", "curved"]
	var tally := {}
	for st in styles:
		tally[st] = [0, 0]
	var wrong := []
	for lv in [31, 34, 37, 38, 29]:
		for dt in [1.0 / 30.0, 1.0 / 60.0]:
			var s := _finale(lv, stage)
			_to_aim(s)
			s.logic.shots_left = 999
			var vp := _vp(s)
			var n := 0
			while s.logic.remaining() > 0 and n < 40:
				var targets: Array = []
				for i in s.logic.count():
					if not s.logic.broken[i] and not s.logic.is_decoy(i):
						targets.append(i)
				var i: int = targets[n % targets.size()]
				var style: String = styles[n % styles.size()]
				n += 1
				var a := Vector2(vp.x * rng.randf_range(0.36, 0.64), vp.y * rng.randf_range(0.8, 0.92))
				if style == "flick" and not _first_on_line(s, a, i):
					style = "long"
				var bp: Array = _bottle_px(s, i)
				var t: Vector2 = bp[0]
				var r: float = bp[1]
				var path: Array
				match style:
					"long":
						path = _path(a, t + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * r, 0.22, dt)
					"flick":
						path = _path(a, a + (t - a) * rng.randf_range(0.22, 0.45), 0.1, dt)
					"off":
						# Its line passes beside the bottle by 0.6 to 1.2 of its radius (about half
						# of these would miss with no assist), released anywhere from 60 % of the way.
						var side := (t - a).orthogonal().normalized() * r * rng.randf_range(0.6, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
						path = _path(a, a + (t + side - a) * rng.randf_range(0.6, 1.0), 0.18, dt)
					"curved":
						path = _path(a, t, 0.25, dt, 0.12 * (1.0 if rng.randf() < 0.5 else -1.0))
				var fired := s.logic.shots_fired
				_swipe(s, path, dt)
				eq(s.logic.shots_fired, fired + 1, "L%d %s: the swipe throws" % [lv, style])
				_settle(s, dt)
				tally[style][1] += 1
				if s.logic.broken[i]:
					tally[style][0] += 1
				else:
					wrong.append("L%d %.0f fps %s at bottle %d" % [lv, 1.0 / dt, style, i])
			_drop_node(s)
	var hits := 0
	var total := 0
	for st in styles:
		var h: int = tally[st][0]
		var all: int = tally[st][1]
		hits += h
		total += all
		check(all > 0 and float(h) / all >= 0.8, "%s swipes break the aimed bottle %d of %d" % [st, h, all])
	check(float(hits) / maxf(total, 1) >= 0.9, "all swipes: %d of %d break the aimed bottle (missed: %s)" % [hits, total, ", ".join(wrong.slice(0, 6))])
	for n2 in stage:
		_drop_node(n2)
	_unboot_phone()


## The aim aids: the ready star shows while a throw can go; while the finger is down the plan
## names the bottle the ring is on; a tap or a downward swipe throws nothing; a swipe at empty
## wall misses honestly (no snapping from afar).
func test_stars_aim_aids_and_honest_misses() -> void:
	_boot_phone()
	var stage := _stage()
	var s := _finale(31, stage)
	var m := s._mode as WeaponStars
	var vp := _vp(s)
	s._process(1.0 / 60.0)
	check(s.aim_ui_visible(), "a star waits at the bottom of the screen")
	var rs := s.world.camera.unproject_position(m._ready_star.global_position)
	check(rs.y > vp.y * 0.7 and rs.y < vp.y * 0.95 and absf(rs.x - vp.x * 0.5) < vp.x * 0.1, "... at the bottom middle (%s)" % rs)
	var bp: Array = _bottle_px(s, 0)
	var a := Vector2(vp.x * 0.5, vp.y * 0.88)
	_press(s, 0, a, true)
	_drag(s, 0, a.lerp(bp[0], 0.6))
	s._process(1.0 / 60.0)
	var pl: Dictionary = m._plan
	check(bool(pl.get("ok", false)), "dragging up: a throw is planned")
	eq(int((pl.get("target", {}) as Dictionary).get("i", -1)), 0, "the ring is on the bottle the finger points at")
	_drag(s, 0, a + Vector2(0, 8))
	_press(s, 0, a + Vector2(0, 8), false)
	eq(s.logic.shots_fired, 0, "a tap throws nothing")
	_swipe(s, _path(Vector2(vp.x * 0.5, vp.y * 0.5), Vector2(vp.x * 0.5, vp.y * 0.85), 0.2, 1.0 / 60.0), 1.0 / 60.0)
	eq(s.logic.shots_fired, 0, "a downward swipe throws nothing")
	# A swipe whose line passes nowhere near the set: an honest miss.
	_miss(s)
	eq(s.logic.shots_fired, 1, "a swipe away from the set throws")
	_settle(s)
	eq(s.logic.broken_count() + s.logic.broken_count(true), 0, "and misses (the assist never reaches that far)")
	_drop_node(s)
	for n in stage:
		_drop_node(n)
	_unboot_phone()


## A point on the bottle plane well clear of every bottle and plate (hero space, x and height).
func _empty_point(l: BottleLogic) -> Vector2:
	var maxx := 0.0
	var maxy := 0.0
	for b in l.layout["bottles"]:
		maxx = maxf(maxx, absf(float(b["x"])))
		maxy = maxf(maxy, float(b["y"]))
	return Vector2(-(maxx + float(l.layout.get("amp", 0.0)) + 1.5), maxy + 0.9)


## Shoots a deliberate miss with `s`'s weapon, the way that weapon shoots.
func _miss(s: BottleShot) -> void:
	var p := _empty_point(s.logic)
	var m := s._mode
	match s.logic.weapon:
		"knife":
			s._throw_knife(p)
		"stars":
			# Low across the floor, 15 degrees up: its line passes nowhere near the set.
			var vp := _vp(s)
			var a := Vector2(vp.x * 0.06, vp.y * 0.93)
			_swipe(s, _path(a, a + Vector2(1.0, -tan(deg_to_rad(15.0))) * vp.x * 0.44, 0.15, 1.0 / 60.0), 1.0 / 60.0)
		"pistol":
			var wp := m as WeaponPistol
			var v := _v_to(s, wp.eye_h(), p, wp.speed())
			wp.look_along(v, wp.zero())
			wp._fire(v)
		"bow":
			var wb := m as WeaponBow
			var o := wb.eye_h() + Vector3(0, -0.02, 0)
			var v := _v_to(s, o, p, wb.power_speed(1.0))
			wb.look_along(v, wb.base_zero())
			wb._loose(v)
		"sniper":
			var ws := m as WeaponSniper
			ws._scope(true)
			ws._scope_k = 1.0
			var v := _v_to(s, ws.eye_h(), p, ws.speed())
			ws.look_along(v, ws.zero())
			ws._fire(v)


func _v_to(s: BottleShot, o: Vector3, p: Vector2, spd: float) -> Vector3:
	var dt := (o.z + s.logic.distance) / spd
	return Vector3((p.x - o.x) / dt, (p.y - o.y + 0.5 * s.logic.gravity() * dt * dt) / dt, -spd)


## The camera is where the weapon aims from (and, for the knife and stars, with the aim lens).
func _cam_at_rest(s: BottleShot) -> bool:
	var rest := s._rest_view()
	if s._cam.origin.distance_to(rest.origin) > 0.03:
		return false
	if rad_to_deg(s._cam.basis.get_rotation_quaternion().angle_to(rest.basis.get_rotation_quaternion())) > 1.0:
		return false
	if s.logic.weapon in ["knife", "stars"] and absf(s._fov - s._rest_fov()) > 0.5:
		return false
	return true


## Real seconds from the shot's result (`outcome_n` results before it; -1 = from now, a skipping
## tap) until the finale aims again with the camera at rest and the aim aid showing; INF if it
## never does within 8 s. out["left"] counts frames with the camera off its aim view.
func _back_after(s: BottleShot, dt: float, outcome_n: int, out: Dictionary) -> float:
	var t := 0.0
	var since := 0.0 if outcome_n < 0 else -1.0
	while t < 8.0:
		s._process(dt)
		t += dt
		if since < 0.0 and s.outcomes > outcome_n:
			since = t
		if not _cam_at_rest(s):
			out["left"] = int(out.get("left", 0)) + 1
		if since >= 0.0 and s._state == "aim" and _cam_at_rest(s) and s.aim_ui_visible():
			return t - since
	return INF


## After a miss, a hit and a skipped film, every weapon gives the camera back to its own aim
## view with its aiming aid showing within 0.6 s of the result, plus the beat a weapon holds on
## purpose (the knife's and the bullet cam's hold on a shatter, the sniper's look through the
## scope and its bolt). The stars' miss never leaves the aim view at all.
func test_camera_and_aim_come_back_after_every_shot() -> void:
	_boot_phone()
	var stage := _stage()
	var fin: Dictionary = Config.load_json("res://config/finale.json")["weapons"]
	var bolt := 0.6 + float(fin["sniper"]["cycle_s"]) + 0.2
	var beats := {
		"miss": {"knife": 0.0, "stars": 0.0, "pistol": 0.0, "bow": 0.0, "sniper": bolt},
		"hit": {"knife": BottleShot.HOLD_HIT, "stars": 0.0, "pistol": float(fin["pistol"]["cam_hold"]),
			"bow": float(fin["bow"]["cam_hold"]) + 0.1, "sniper": float(fin["sniper"]["cam_hold"]) + bolt},
		"skip": {"knife": 0.0, "stars": 0.0, "pistol": 0.55, "bow": 0.75, "sniper": bolt}}
	for dt in [1.0 / 60.0, 1.0 / 30.0]:
		for weapon in ALL:
			for kind in ["miss", "hit", "skip"]:
				var s := _finale(int(ALL[weapon]), stage)
				_to_aim(s)
				var n0 := s.outcomes
				var out := {}
				var back := INF
				var tag := "%s %s %.0f fps" % [weapon, kind, 1.0 / dt]
				match kind:
					"miss":
						_miss(s)
						back = _back_after(s, dt, n0, out)
						eq(s.logic.broken_count() + s.logic.broken_count(true), 0, "%s: it missed" % tag)
						if weapon == "stars":
							eq(int(out.get("left", 0)), 0, "%s: the camera never left the aim view" % tag)
					"hit":
						s.throw_at(Vector2.ZERO)
						back = _back_after(s, dt, n0, out)
						check(s.logic.broken_count() > 0, "%s: it hit" % tag)
					"skip":
						s.throw_at(Vector2.ZERO)
						var g := 0
						while g < 400 and not _films(s):
							s._process(dt)
							g += 1
						check(_films(s), "%s: the hit is filmed" % tag)
						for k in 3:
							s._process(dt)
						var vp := _vp(s)
						_press(s, 0, vp * 0.5, true)
						_press(s, 0, vp * 0.5, false)
						check(not _films(s) or s._mode == null, "%s: a tap ends the film" % tag)
						back = _back_after(s, dt, n0, out)   # from the break (or the tap, if later)
						eq(s.logic.shots_fired, 1, "%s: the skipping tap fires nothing" % tag)
				var limit: float = 0.6 + float(beats[kind][weapon]) + dt
				check(back <= limit, "%s: aiming again, camera back and aim aid showing in %.2f s (limit %.2f)" % [tag, back, limit])
				_drop_node(s)
	for n in stage:
		_drop_node(n)
	_unboot_phone()


## The weapon is filming a hit (knife: the throw's film; stars: the chase cam; others: the bullet cam).
func _films(s: BottleShot) -> bool:
	if s._mode == null:
		return s._state in ["flying", "impact"]
	return s._mode.filming()


# ---------------------------------------------------------------- weapon lessons

func _lesson_view(lv: int, s: BottleShot) -> Array:
	var v := LevelView.new().setup(Config.level(lv), {}, null, Fx.new(), UiKit.FONT)
	v.finale = s
	var t := Tutorial.new().setup(v, null)
	t.build()
	return [v, t]


func _drop_lesson(vt: Array) -> void:
	(vt[1] as Tutorial).free()
	(vt[0] as LevelView).fx.free()
	(vt[0] as LevelView).free()


func _frame(s: BottleShot, t: Tutorial, dt := 1.0 / 60.0) -> void:
	t._process(dt)
	s._process(dt)


func _both(s: BottleShot, t: Tutorial, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = down
	t._input(e)
	s._unhandled_input(e)


## Every weapon's lesson (the stars as a guest on L13 too) opens the first time the weapon aims,
## survives a stray tap from the street (which shoots nothing), and counts as seen only after
## a real shot with the hand showing.
func test_weapon_lessons_wait_for_a_real_shot() -> void:
	_boot_phone()
	var stage := _stage()
	for lv in [1, 11, 21, 31, 41, 13]:
		Game.save["seen_hints"] = ["tap", "swipe", "gate_pick", "red_gate", "barrel", "shield", "bomb"]
		var s := _finale(lv, stage)
		_to_aim(s)
		var vt := _lesson_view(lv, s)
		var t: Tutorial = vt[1]
		var id := "bottle_" + s.logic.weapon
		_frame(s, t)
		eq(t._step, id, "L%d: the %s lesson opens" % [lv, s.logic.weapon])
		check(t._hand.visible, "L%d: with the hand" % lv)
		check(not Game.hint_seen(id), "L%d: opening it does not use it up" % lv)
		var vp := _vp(s)
		_both(s, t, vp * Vector2(0.5, 0.7), true)
		_frame(s, t)
		_both(s, t, vp * Vector2(0.5, 0.7), false)
		eq(s.logic.shots_fired, 0, "L%d: a stray tap as it opens shoots nothing" % lv)
		for k in 60:
			_frame(s, t)
		eq(t._step, id, "L%d: a tap does not end it" % lv)
		check(t._hand.visible, "L%d: the hand is back after the tap" % lv)
		s.throw_at(Vector2.ZERO)
		for k in 120:
			_frame(s, t)
		check(s.logic.shots_fired >= 1, "L%d: a shot" % lv)
		check(t._step != id, "L%d: the shot ends the lesson" % lv)
		check(Game.hint_seen(id), "L%d: and only now is it seen" % lv)
		_drop_lesson(vt)
		_drop_node(s)
	for n in stage:
		_drop_node(n)
	_unboot_phone()


## The lighter reminder: after the first two throws of a finale both miss, and after 3 s idle
## with nothing broken; a fainter hand, and never once a bottle is broken.
func test_reminder_hand_after_two_misses_or_idle() -> void:
	_boot_phone()
	var stage := _stage()
	Game.save["seen_hints"] = ["bottle_stars", "bottle_knife"]
	var s := _finale(31, stage)
	var vt := _lesson_view(31, s)
	var t: Tutorial = vt[1]
	for k in 30:
		_frame(s, t)
	eq(t._step, "", "a known weapon: no lesson")
	s.logic.shots_left = 99
	for k in 2:
		_miss(s)
		for f in 90:
			_frame(s, t)
			if t._step != "":
				break
		if k == 0:
			eq(t._step, "", "one miss: no reminder yet")
	eq(t._step, "bottle_hint", "two misses: the reminder hand")
	check(t._hand.visible and t._hand.modulate.a < 0.7, "a fainter hand")
	s.throw_at(Vector2.ZERO)
	for k in 90:
		_frame(s, t)
	eq(t._step, "", "a throw ends it")
	check(s.logic.broken_count() > 0, "that throw hit")
	for k in 300:
		_frame(s, t)
	eq(t._step, "", "a bottle broken: no idle reminder")
	_drop_lesson(vt)
	_drop_node(s)
	# Idle: a fresh finale, nothing done for 3 s.
	var s2 := _finale(1, stage)
	var vt2 := _lesson_view(1, s2)
	var t2: Tutorial = vt2[1]
	for k in 150:
		_frame(s2, t2)
	eq(t2._step, "", "2.5 s idle: nothing yet")
	for k in 40:
		_frame(s2, t2)
	eq(t2._step, "bottle_hint", "3 s idle with nothing broken: the reminder")
	check(not Game.hint_seen("bottle_hint"), "the reminder is never 'seen'")
	_drop_lesson(vt2)
	_drop_node(s2)
	for n in stage:
		_drop_node(n)
	_unboot_phone()

class_name WeaponStars
extends FinaleWeapon
## Throwing stars, the "pinwheel" (district 4, the factory; a guest weapon elsewhere). Over the
## shoulder like the knives. Owner play-test 2026-11-13 ("hard to control and doesnt tell how to
## shoot", "when pinwheel fails, the camera angle doesnt reset ... nothing being visible"):
##   - A star sits ready at the bottom of the screen whenever a throw is possible: the aim
##     view's own sign that the camera is back and a throw is ready.
##   - Put a finger down anywhere and swipe towards a bottle: the swipe's direction (from where
##     the finger went down) aims. While the finger is down a dotted arc shows the star's real
##     path and a ring marks what it will hit.
##   - Gentle aim assist (pick_target): the standing bottle, jug or steel plate nearest the
##     swipe's line within assist_deg is the target; on a line through several, the one nearest
##     where the finger lifts (a short flick takes the first on the line). Nothing inside the
##     cone: the star flies along the line and misses honestly.
##   - Every star flies at full speed (the old rule, a lazy swipe drops short, is gone).
##   - A throw that will break something is filmed from behind the star in slow motion (a tap
##     skips it); a miss is watched from the aim view at full speed, so the camera never leaves
##     it. After a film the camera comes back to the aim view in BottleShot.RETURN_S.
##   - A star that hits one of the angled steel plates beside a conveyor ricochets along that
##     row and can break several bottles in one throw (a jug stops it).

const HAND := Vector3(0.25, 1.45, -0.4)   # hero space: the gift flies here (BottleShot._hand_screen)
const SPIN := 26.0                        # rad/s (game time)
const SLOW := 0.35                        # time scale while a hit is filmed
const HOLD_HIT := 0.45                    # real s after a filmed hit lands (the camera comes back meanwhile)
const HOLD_MISS := 0.2                    # real s after a miss lands
const READY_AT := Vector2(0.5, 0.83)      # the ready star's screen point (share of the viewport)
const READY_W := 0.13                     # ... and its width (share of the screen width)
const STAR_D := 0.17                      # m: the star's diameter (WeaponModels.star)
const MIN_SWIPE := 0.045                  # share of the screen width a swipe must cover
const UP_COS := 0.25                      # a swipe must point at least this much upwards (cos to up)
const LINE_SLACK := 0.35                  # pick_target: candidates within this many of their radii
                                          # of the line's best count as "on the line" (the
                                          # direction rules; the lift point only picks among them)

var _star: Node3D                         # the star in flight
var _ready_star: Node3D                   # the star ready at the bottom of the screen
var _flight: Dictionary = {}
var _hold := 0.0
var _spin := 0.0
var _down := Vector2(-1, -1)              # where the finger went down (-1: no swipe)
var _at := Vector2.ZERO                   # where the finger is now
var _plan: Dictionary = {}                # what lifting the finger now would throw (plan)
var _ui: CanvasLayer
var _guide: Control


func _ready() -> void:
	input_while_busy = true   # a finger that went down during the last throw still swipes after it
	_ui = CanvasLayer.new()
	_ui.layer = 1
	add_child(_ui)
	_guide = Control.new()
	_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(_guide)
	_guide.draw.connect(_draw_guide)
	_ui.add_child(_guide)
	_ready_star = WeaponModels.star()
	_ready_star.top_level = true
	_ready_star.visible = false
	add_child(_ready_star)


func rest_view() -> Transform3D:
	return shot._aim_view()


func rest_fov() -> float:
	return shot._aim_fov


## A throw can go now (BottleShot is aiming, no star out, nothing on hold).
func idle() -> bool:
	return shot._state == "aim" and _flight.is_empty() and _hold <= 0.0 and logic.can_fire()


func aim_ui_visible() -> bool:
	return _ready_star.visible and _ready_star.is_visible_in_tree()


func handle_input(event: InputEvent) -> void:
	var t := touch(event)
	if t.is_empty():
		return
	match String(t["kind"]):
		"down":
			_down = t["pos"]
			_at = _down
			_plan = {}
		"drag":
			if _down.x >= 0.0:
				_at = t["pos"]
				_plan = plan(_down, _at) if idle() else {}
		"up":
			if _down.x >= 0.0:
				_at = t["pos"]
				var p := plan(_down, _at) if idle() else {}
				_down = Vector2(-1, -1)
				_plan = {}
				if bool(p.get("ok", false)):
					_throw(p["v"])
		"cancel":
			_down = Vector2(-1, -1)
			_plan = {}
	_guide.queue_redraw()


# ---------------------------------------------------------------- aiming

func _vp() -> Vector2:
	return shot.hud.get_viewport().get_visible_rect().size


## Screen point of a world point as the player sees it (the game camera; the finale camera's own
## numbers when the camera is not in a tree).
func project(p: Vector3) -> Vector2:
	var cam := world.camera if world else null
	if cam != null and cam.is_inside_tree():
		return cam.unproject_position(p)
	return FinaleWeapon.project_cam(shot._cam.affine_inverse() * p, shot._fov, _vp())


## Where the ready star sits for a camera `cam` with lens `fov` (world).
func ready_transform(cam: Transform3D, fov: float) -> Transform3D:
	var vp := _vp()
	var half := tan(deg_to_rad(fov) * 0.5)
	var d := STAR_D / (READY_W * 2.0 * half)
	var x := (READY_AT.x - 0.5) * 2.0 * d * half
	var y := -(READY_AT.y - 0.5) * 2.0 * d * half * vp.y / maxf(vp.x, 1.0)
	var b := cam.basis * Basis(Vector3.RIGHT, deg_to_rad(64.0)) * Basis(Vector3.UP, _spin)
	return Transform3D(b, cam * Vector3(x, y, -d))


## The throw's start (hero space): the ready star's spot in the aim view, so a thrown star leaves
## from the star the player swiped.
func origin_h() -> Vector3:
	return shot.to_hero(ready_transform(rest_view(), rest_fov()).origin)


## Everything a star can be aimed at, as the player sees it now: [{kind, i, s (screen), r (px)}].
## Standing bottles and jugs at the bottle plane, and the steel plates.
func candidates() -> Array:
	var out: Array = []
	var t := shot._ft
	for i in logic.count():
		if logic.broken[i]:
			continue
		var p := logic.position(i, t)
		var w := shot.to_world(Vector3(p.x, p.y, -logic.distance))
		var s := project(w)
		var r := s.distance_to(project(w + Vector3(logic.hit_radius(), 0, 0)))
		out.append({"kind": "bottle", "i": i, "s": s, "r": maxf(r, 4.0)})
	var plates: Array = logic.layout.get("plates", [])
	for k in plates.size():
		var p2 := logic.plate_position(k, t)
		var w2 := shot.to_world(Vector3(p2.x, p2.y, -logic.distance))
		var s2 := project(w2)
		var half := float(wcfg.get("plate_w", 0.4)) * logic.size * 0.5
		out.append({"kind": "plate", "i": k, "s": s2, "r": maxf(s2.distance_to(project(w2 + Vector3(half, 0, 0))), 4.0)})
	return out


## The aim assist (pure): which of `cands` ([{s, r}] screen points and radii) a swipe from `a` to
## `b` means, or -1. A candidate counts when the swipe's line passes within max(1.2 radii,
## assist cone) of it, or the finger lifts on it. The line decides: of those, the ones about as
## near the line as the nearest (LINE_SLACK, or within a radius) are on it, and of those the one
## nearest where the finger lifted along it wins (a lift short of all of them = the first on the
## line, a flick; a lift on a bottle = that bottle).
static func pick_target(a: Vector2, b: Vector2, cands: Array, assist_rad: float) -> int:
	var dv := b - a
	var len := dv.length()
	if len < 0.001:
		return -1
	var dir := dv / len
	var inside: Array = []
	var first := INF
	for k in cands.size():
		var c: Dictionary = cands[k]
		var rel: Vector2 = (c["s"] as Vector2) - a
		var along := rel.dot(dir)
		var r := float(c["r"])
		var perp := absf(rel.cross(dir))
		var on_lift := (c["s"] as Vector2).distance_to(b) <= r * 1.6
		if along <= 0.0 and not on_lift:
			continue
		if perp <= maxf(r * 1.2, along * tan(assist_rad)) or on_lift:
			inside.append({"k": k, "along": along, "perp": perp, "r": r})
			first = minf(first, along)
	if inside.is_empty():
		return -1
	var nearest := INF
	for e in inside:
		nearest = minf(nearest, float(e["perp"]) / float(e["r"]))
	var on_line := maxf(nearest + LINE_SLACK, 1.0)
	var reach := maxf(len, first)
	var best := -1
	var best_d := INF
	for e in inside:
		if float(e["perp"]) / float(e["r"]) > on_line:
			continue
		var d := absf(float(e["along"]) - reach) + float(e["perp"]) * 0.01
		if d < best_d:
			best_d = d
			best = int(e["k"])
	return best


## What a swipe from `a` to `b` throws: {ok, v (hero space), target ({} or a candidate), end
## (world point where it lands)}. ok = false for a tap, a short or a downward swipe.
func plan(a: Vector2, b: Vector2) -> Dictionary:
	var dv := b - a
	var vp := _vp()
	if dv.length() < MIN_SWIPE * vp.x or -dv.y < UP_COS * dv.length():
		return {"ok": false}
	var cands := candidates()
	var k := pick_target(a, b, cands, deg_to_rad(float(wcfg.get("assist_deg", 8.0))))
	var o := origin_h()
	var spd := float(wcfg.get("speed_max", 20.0))
	var v: Vector3
	var target: Dictionary = {}
	if k >= 0:
		target = cands[k]
		if String(target["kind"]) == "bottle":
			v = logic.solve(o, int(target["i"]), spd, shot._ft)
		else:
			var dt := (o.z + logic.distance) / spd
			v = solve_to(o, logic.plate_position(int(target["i"]), shot._ft + dt), spd)
	else:
		v = solve_to(o, shot._screen_to_wall(line_point(a, b, cands)), spd)
	return {"ok": true, "v": v, "target": target}


## Velocity at forward speed `spd` from `o` that crosses the bottle plane at (x, y) = `p`.
func solve_to(o: Vector3, p: Vector2, spd: float) -> Vector3:
	var dt := (o.z + logic.distance) / maxf(spd, 0.01)
	return Vector3((p.x - o.x) / dt, (p.y - o.y + 0.5 * logic.gravity() * dt * dt) / dt, -spd)


## No target: the point on the swipe's line level with the middle of the set (or where the
## finger lifted, if that is further), so a short flick still flies on towards the set.
static func line_point(a: Vector2, b: Vector2, cands: Array) -> Vector2:
	var dv := b - a
	var dir := dv.normalized()
	if cands.is_empty() or dir.y > -0.01:
		return b
	var mid := 0.0
	for c in cands:
		mid += (c["s"] as Vector2).y
	mid /= cands.size()
	var t := (mid - a.y) / dir.y
	return a + dir * maxf(dv.length(), t)


func auto_fire() -> void:
	if not _flight.is_empty() or _hold > 0.0:
		return
	var i := logic.next_target()
	if i < 0:
		return
	_throw(logic.solve(origin_h(), i, float(wcfg.get("speed_max", 20.0)), shot._ft))


func _throw(v: Vector3) -> void:
	var o := origin_h()
	var s0 := logic.streak
	var res := logic.fire(o, v, shot._ft)
	var end := wall_point(o, v, shot._ft, 0.0)
	var film := not (res["hits"] as Array).is_empty()
	_star = WeaponModels.star()
	_star.top_level = true
	add_child(_star)
	_star.global_position = shot.to_world(o)
	_flight = {"o": o, "v": v, "t0": shot._ft, "res": res, "end": end, "streak0": s0,
		"shown": 0, "phase": "fly", "film": film}
	_ready_star.visible = false
	shot._state = "flying"
	shot._scale = SLOW if film else 1.0
	Sfx.play("swoosh", 0.0, 1.5)
	shot.hud.refresh(shot._shown_bottles)
	if shot.on_throw.is_valid():
		shot.on_throw.call()


func tick(delta: float, _d: float) -> void:
	_spin += delta * 1.6
	if _flight.is_empty():
		shot.aim_camera_frame(delta)
		if _hold > 0.0:
			_hold -= delta
			if _hold <= 0.0:
				shot._scale = 1.0
				shot.shot_over()
	else:
		_tick_flight(delta)
	_place_ready()
	if _down.x >= 0.0 or _guide.get_meta("drawn", false):
		_guide.queue_redraw()


func _place_ready() -> void:
	_ready_star.visible = shot._state == "aim" and _flight.is_empty() and _hold <= 0.0 and logic.can_fire()
	_ready_star.global_transform = ready_transform(shot._cam, shot._fov)


## A tap while a hit is filmed: the star arrives at once (its bottles break) and the camera
## heads back to the aim view.
func film_skip() -> bool:
	if _flight.is_empty() or not bool(_flight.get("film", false)):
		return false
	var f := _flight
	var res: Dictionary = f["res"]
	var dir := (f["v"] as Vector3).normalized()
	var p: Vector3
	if int(res["plate"]) >= 0:
		var e2: Vector2 = res["end"]
		p = shot.to_world(Vector3(e2.x, e2.y, (res["point"] as Vector3).z))
	else:
		p = shot.to_world(res["point"])
	_land(p, dir, true)
	return true


func filming() -> bool:
	return not _flight.is_empty() and bool(_flight.get("film", false))


func _tick_flight(delta: float) -> void:
	var f := _flight
	var res: Dictionary = f["res"]
	var hits: Array = res["hits"]
	var times: Array = res["times"]
	var o: Vector3 = f["o"]
	var v: Vector3 = f["v"]
	var t := shot._ft - float(f["t0"])
	var plate := int(res["plate"])
	var arrive := float(res["t"]) - float(f["t0"])
	var p: Vector3
	var dir := v.normalized()
	if plate >= 0 and t >= arrive:
		# Ricochet: skim along the row from the plate to `end`.
		if String(f["phase"]) == "fly":
			f["phase"] = "rico"
			Sfx.play("clink", 2.0, 1.6)
			shot.fx.burst(shot.to_world(res["point"]), Color(1.0, 0.85, 0.4), 12, 2.5, 0.012, 0.25)
			shot._hitstop = 0.04
		var a: Vector3 = res["point"]
		var e2: Vector2 = res["end"]
		var e := Vector3(e2.x, e2.y, a.z)
		var rs := float(wcfg.get("ricochet_speed", 12.0))
		var len := maxf(Vector2(a.x, a.y).distance_to(e2), 0.01)
		var k := clampf((t - arrive) * rs / len, 0.0, 1.0)
		p = shot.to_world(a.lerp(e, k))
		dir = (e - a).normalized()
		if k >= 1.0:
			_land(p, dir, not hits.is_empty())
			return
	elif t >= float(f["end"]["t"]) - float(f["t0"]) and hits.is_empty():
		_land(f["end"]["p"], dir, false)
		return
	else:
		var tt := minf(t, arrive) if not hits.is_empty() and plate < 0 else t
		p = shot.to_world(logic.trajectory(o, v, tt))
		dir = (v + Vector3(0, -logic.gravity(), 0) * tt).normalized()
	_star.global_position = p
	_star.basis = Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.UP, shot._ft * SPIN)
	# Break the bottles as the star reaches them.
	var shown := int(f["shown"])
	while shown < hits.size() and shot._ft >= float(times[shown]):
		var i := int(hits[shown])
		var st := 0 if logic.is_decoy(i) else int(f["streak0"]) + shown + 1
		shot.break_bottle(i, dir, st, shown == 0)
		shown += 1
	f["shown"] = shown
	if shown >= hits.size() and not hits.is_empty() and plate < 0:
		_land(p, dir, true)
		return
	if not bool(f["film"]):
		# A miss is watched from the aim view at full speed: the camera never leaves it.
		shot.aim_camera_frame(delta)
		return
	# Chase camera (a hit): behind and beside the star, looking ahead of it.
	var side := dir.cross(Vector3.UP).normalized()
	var eye := p + side * 0.35 - dir * 0.7 + Vector3.UP * 0.12
	var look := p + dir * 0.4
	shot._cam = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	shot._fov = 52.0
	shot._focus = 2.5
	shot._blur = 0.05
	shot._roll = 0.0


## The star stops: buried in the wall (or skittering on the floor).
func _land(p: Vector3, dir: Vector3, any_hit: bool) -> void:
	var res: Dictionary = _flight["res"]
	var hits: Array = res["hits"]
	var shown := int(_flight["shown"])
	while shown < hits.size():
		var i := int(hits[shown])
		shot.break_bottle(i, dir, 0 if logic.is_decoy(i) else int(_flight["streak0"]) + shown + 1, false)
		shown += 1
	if not any_hit or hits.is_empty():
		shot.show_miss()
	_star.global_position = Vector3(p.x, p.y, maxf(p.z, shot._wall_front - 0.02))
	_star.basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	Sfx.play("thunk", -2.0, 1.4)
	shot.fx.burst(p, Color(0.7, 0.7, 0.75), 6, 1.6, 0.012, 0.3)
	if bool(_flight["film"]):
		shot.begin_return()   # from the chase camera back to the aim view
	_flight = {}
	_hold = HOLD_HIT if not hits.is_empty() else HOLD_MISS
	shot._scale = 1.0


# ---------------------------------------------------------------- the guide

## While the finger is down: a faint line from where it went down, and (for a throw) the
## star's real path as dots with a ring on what it will hit, or a cross where it will land.
func _draw_guide() -> void:
	var drawn := false
	if _down.x >= 0.0 and idle():
		drawn = true
		_guide.draw_line(_down, _at, Color(1, 1, 1, 0.35), 8.0)
		_guide.draw_circle(_down, 14.0, Color(1, 1, 1, 0.35))
		if bool(_plan.get("ok", false)):
			_draw_path(_plan)
	_guide.set_meta("drawn", drawn)


func _draw_path(p: Dictionary) -> void:
	var o := origin_h()
	var v: Vector3 = p["v"]
	var end_t := logic.time_to_plane(o, v)
	if is_inf(end_t):
		return
	var g := logic.gravity()
	var floor_t := end_t
	if g > 0.0:
		var disc := v.y * v.y + 2.0 * g * o.y
		if disc >= 0.0:
			floor_t = (v.y + sqrt(disc)) / g
	end_t = minf(end_t, floor_t)
	var n := 16
	var last := Vector2.ZERO
	for k in range(1, n + 1):
		var t := end_t * float(k) / n
		var s := project(shot.to_world(logic.trajectory(o, v, t)))
		var r := lerpf(9.0, 5.0, float(k) / n)
		_guide.draw_circle(s, r + 3.0, Color(0.05, 0.06, 0.1, 0.55))
		_guide.draw_circle(s, r, Color(1, 1, 1, 0.92))
		last = s
	var target: Dictionary = p.get("target", {})
	if not target.is_empty():
		var c: Vector2 = target["s"]
		var rr := float(target["r"]) * 1.7 + 6.0
		_guide.draw_arc(c, rr, 0, TAU, 40, Color(0.05, 0.06, 0.1, 0.6), 10.0)
		_guide.draw_arc(c, rr, 0, TAU, 40, Color(1.0, 0.78, 0.25, 0.95), 6.0)
	else:
		var q := 14.0
		_guide.draw_line(last + Vector2(-q, -q), last + Vector2(q, q), Color(1, 1, 1, 0.8), 5.0)
		_guide.draw_line(last + Vector2(-q, q), last + Vector2(q, -q), Color(1, 1, 1, 0.8), 5.0)


func warm_parts() -> Array:
	return [WeaponModels.star()]


func finish() -> void:
	visible = false
	_ui.queue_free()

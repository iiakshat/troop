class_name WeaponStars
extends FinaleWeapon
## Throwing stars (district 4, the factory). Over the shoulder like the knives, but no aim
## ring: swipe towards a bottle. The swipe's direction aims, its speed is the throw speed (a
## lazy swipe drops short). A star that hits one of the angled steel plates beside a conveyor
## ricochets along that row and can break several bottles in one throw (a jug stops it).

const HAND := Vector3(0.25, 1.45, -0.4)   # hero space
const SPIN := 26.0                        # rad/s (game time)

var _star: Node3D
var _flight: Dictionary = {}
var _trail: Array = []                    # swipe points {p, t} (screen)
var _line: Line2D
var _ui: CanvasLayer
var _hold := 0.0
var _cam_t := 0.0


func _ready() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 1
	add_child(_ui)
	_line = Line2D.new()
	_line.width = 14.0
	_line.default_color = Color(1, 1, 1, 0.55)
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 0.7))
	_line.gradient = grad
	_ui.add_child(_line)


func rest_view() -> Transform3D:
	return shot._aim_view()


func rest_fov() -> float:
	return shot._aim_fov


func handle_input(event: InputEvent) -> void:
	if not _flight.is_empty() or _hold > 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var t := touch(event)
	if t.is_empty():
		return
	match String(t["kind"]):
		"down":
			_trail = [{"p": t["pos"], "t": now}]
		"drag":
			_trail.append({"p": t["pos"], "t": now})
			while _trail.size() > 2 and now - float(_trail[0]["t"]) > 0.25:
				_trail.pop_front()
		"up":
			_trail.append({"p": t["pos"], "t": now})
			_swipe()
			_trail.clear()
	_draw_line()


func _draw_line() -> void:
	_line.clear_points()
	for s in _trail:
		_line.add_point(s["p"])


## The swipe's last 0.25 s: direction picks the aim point (the release point, carried on a
## little along the swipe), speed picks the throw speed.
func _swipe() -> void:
	if _trail.size() < 2 or not logic.can_fire():
		return
	var a: Dictionary = _trail[0]
	var b: Dictionary = _trail[_trail.size() - 1]
	var dv: Vector2 = (b["p"] as Vector2) - (a["p"] as Vector2)
	var dt := maxf(float(b["t"]) - float(a["t"]), 0.016)
	if dv.length() < 30.0 or dv.y > 0.0:
		return   # a tap or a downward swipe is not a throw
	var px_s := dv.length() / dt
	var k := clampf(px_s / float(wcfg.get("swipe_fast", 2600.0)), 0.0, 1.0)
	var spd := lerpf(float(wcfg.get("speed_min", 7.0)), float(wcfg.get("speed_max", 20.0)), k)
	var aim_px: Vector2 = (b["p"] as Vector2) + dv * 0.3
	var target := shot._screen_to_wall(aim_px)
	# Thrown "at" the point: gravity is allowed for at full speed only, so a lazy throw drops.
	var o := HAND
	var full := float(wcfg.get("speed_max", 20.0))
	var tf := (o.z + logic.distance) / full
	var ts := (o.z + logic.distance) / spd
	var vx := (target.x - o.x) / ts
	var vy := (target.y - o.y) / ts + 0.5 * logic.gravity() * tf * tf / ts
	_throw(Vector3(vx, vy, -spd))


func auto_fire() -> void:
	if not _flight.is_empty() or _hold > 0.0:
		return
	var i := logic.next_target()
	if i < 0:
		return
	_throw(logic.solve(HAND, i, float(wcfg.get("speed_max", 20.0)), shot._ft))


func _throw(v: Vector3) -> void:
	var o := HAND
	var s0 := logic.streak
	var res := logic.fire(o, v, shot._ft)
	var end := wall_point(o, v, shot._ft, 0.0)
	_star = WeaponModels.star()
	_star.top_level = true
	add_child(_star)
	_flight = {"o": o, "v": v, "t0": shot._ft, "res": res, "end": end, "streak0": s0,
		"shown": 0, "phase": "fly", "rico_t": 0.0}
	shot._state = "flying"
	shot._scale = 0.35
	_cam_t = 0.0
	Sfx.play("swoosh", 0.0, 1.5)
	shot.hud.refresh(shot._shown_bottles)
	if shot.on_throw.is_valid():
		shot.on_throw.call()


func tick(delta: float, _d: float) -> void:
	if _flight.is_empty():
		var k := minf(delta * 6.0, 1.0)
		shot._cam = shot._cam.interpolate_with(shot._aim_view(), k)
		shot._fov = lerpf(shot._fov, shot._aim_fov, k)
		shot._focus = lerpf(shot._focus, shot._aim_focus, k)
		shot._roll = 0.0
		if _hold > 0.0:
			_hold -= delta
			if _hold <= 0.0:
				shot._scale = 1.0
				shot.shot_over()
		return
	_tick_flight(delta)


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
			_land(p, dir, true)
			return
	elif t >= float(f["end"]["t"]) - float(f["t0"]) and hits.is_empty():
		p = f["end"]["p"]
		_land(p, dir, false)
		return
	else:
		var tt := minf(t, arrive) if not hits.is_empty() and plate < 0 else t
		p = shot.to_world(logic.trajectory(o, v, tt))
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
	# Chase camera: behind and beside the star, looking ahead of it.
	_cam_t += delta
	var side := dir.cross(Vector3.UP).normalized()
	var eye := p + side * 0.35 - dir * 0.7 + Vector3.UP * 0.12
	var look := p + dir * 0.4
	var target := Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	shot._cam = target
	shot._fov = 52.0
	shot._focus = 2.5
	shot._blur = 0.05


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
	_flight = {}
	_hold = 0.8 if not hits.is_empty() else 0.45
	shot._scale = 1.0


func finish() -> void:
	visible = false
	_ui.queue_free()

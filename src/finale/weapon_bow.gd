class_name WeaponBow
extends FinaleWeapon
## Bow (district 3, the docks). First person with a still camera framing the whole set: touch
## and hold to draw (the string comes back over draw_s; power = how far), drag to move the green
## pin over a bottle, release to loose. The bow sits low left and swings to point at the pin, so
## it never covers a bottle. The pin is set for a full draw with no wind at the base distance:
## a weak draw drops short, wind (shown top left, different every arrow) pushes it sideways.
## Held at full draw past steady_s the pin starts to shake. Arrows leave the bow, fly a real
## gravity arc and stick where they land. A finger held down while an arrow is still out starts
## the next draw as soon as the bow is ready, so no press (and no arrow) is ever lost.

const BOW_AT := Vector3(-0.085, -0.17, -0.42)   # the grip in camera space (low left)
const BOW_SCALE := 0.4                           # the whole bow, so it stays in the corner
const CANT := 0.95                               # radians the bow leans left (upper limb out)
const DRAW_MAX := 0.42                           # metres (bow scale) the nock comes back at full draw
const FLY_SCALE := 1.4                           # a flying arrow is drawn larger to read at range
const BLEND_M := 4.0                             # metres over which a loosed arrow joins the aim line

var _bow: Node3D
var _arrow: Node3D                # the nocked arrow (child of the bow)
var _draw := 0.0                  # 0..1
var _drawing := false
var _held := 0.0                  # seconds at full draw
var _flight: Dictionary = {}      # {node, o, v, t0, wind, res, end, streak, from}
var _stuck: Array = []            # {node, t, basis, tip}
var _hold := 0.0
var _shake := Vector2.ZERO
var _rest := Vector2.ZERO         # (yaw, pitch) of the still camera
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	input_while_busy = true
	_rng.seed = logic.level * 7 + 3
	_rest = rest_aim(logic)
	_bow = WeaponModels.bow()
	add_child(_bow)
	add_fill()
	_arrow = WeaponModels.arrow()
	_bow.add_child(_arrow)
	_update_string()
	shot.hud.set_wind(logic.wind(logic.shots_fired))


func base_zero() -> float:
	# Sight set for a full draw at the weapon's base distance.
	return logic.zero_angle(float(wcfg.get("speed_max", 30.0)), float(wcfg.get("distance", 17.0)))


func power_speed(p: float) -> float:
	return lerpf(float(wcfg.get("speed_min", 12.0)), float(wcfg.get("speed_max", 30.0)), clampf(p, 0.0, 1.0))


## The camera never follows the aim: whatever the pin does, the view stays on the set.
static func view_basis_for(rest: Vector2, _aim: Vector2) -> Basis:
	return Basis.from_euler(Vector3(rest.y, rest.x, 0.0))


## Bow pose in camera space: the grip low left, leaning out, pointing at the aim (`a` = aim
## direction in camera space); a draw pulls it a touch closer.
static func bow_pose(a: Vector3, draw: float) -> Transform3D:
	var g := BOW_AT + Vector3(0, 0, 0.03 * draw)
	var f := (a.normalized() * 15.0 - g).normalized()
	var b := Basis.looking_at(f, Vector3.UP) * Basis(Vector3(0, 0, 1), CANT)
	return Transform3D(b.scaled_local(Vector3.ONE * BOW_SCALE), g)


## Nocks `arrow` (a child of `bow`) on the string at draw 0..1 and redraws the string.
static func place_arrow(bow: Node3D, arrow: Node3D, draw: float) -> void:
	var nock := Vector3(0, 0, WeaponModels.BOW_BRACE + DRAW_MAX * draw)
	WeaponModels.bow_string(bow, nock)
	arrow.position = nock + Vector3(0.024, 0.062, 0)
	arrow.rotation = Vector3.ZERO


## A finger that is down while the bow is idle starts a draw (also one pressed mid-flight).
static func starts_draw(idle: bool, auto: bool, finger_down: bool, drawing: bool) -> bool:
	return idle and not auto and finger_down and not drawing


func _idle() -> bool:
	return _flight.is_empty() and _hold <= 0.0 and shot._state == "aim" and logic.can_fire()


func _start_draw() -> void:
	_drawing = true
	_held = 0.0
	Sfx.play("swoosh", -10.0, 0.5)


func handle_input(event: InputEvent) -> void:
	var t := touch(event)   # always track the finger, even while an arrow is out
	if t.is_empty():
		return
	match String(t["kind"]):
		"down":
			if _idle() and not _auto:
				_start_draw()
		"drag":
			if _idle() and not _auto:
				drag_aim(t["rel"], float(wcfg.get("sens", 0.06)))
				_clamp_aim()
		"up":
			if _drawing and not _auto:
				_drawing = false
				if _draw > 0.12 and _idle():
					_loose(velocity(aim_dir(_shake.x, _shake.y), power_speed(_draw), base_zero()))
				else:
					_draw = 0.0


## Keeps the pin on screen (the camera does not turn to follow it).
func _clamp_aim() -> void:
	var vp := shot.hud.get_viewport().get_visible_rect().size
	var half_h := deg_to_rad(float(wcfg.get("fov", 28.0))) * 0.5
	var half_v := atan(tan(half_h) * vp.y / maxf(vp.x, 1.0))
	yaw = clampf(yaw, _rest.x - half_h * 0.85, _rest.x + half_h * 0.85)
	pitch = clampf(pitch, _rest.y - half_v * 0.6, _rest.y + half_v * 0.6)


## Autoplay: draw fully on the next bottle (allowing for wind and drop), then loose.
func auto_fire() -> void:
	if not _flight.is_empty() or _hold > 0.0 or _auto:
		return
	if logic.next_target() < 0:
		return
	_auto = true
	_drawing = true
	_held = 0.0


func _auto_tick() -> void:
	var i := logic.next_target()
	if i < 0:
		_auto = false
		_drawing = false
		return
	var w := logic.wind(logic.shots_fired)
	var v := logic.solve(eye_h() + Vector3(0, -0.02, 0), i, power_speed(1.0), shot._ft, w)
	look_along(v, base_zero())
	if _draw >= 1.0 and _held >= 0.25:
		_auto = false
		_drawing = false
		_loose(v)


func _loose(v: Vector3) -> void:
	var o := eye_h() + Vector3(0, -0.02, 0)
	var w := logic.wind(logic.shots_fired)
	var res := logic.fire(o, v, shot._ft, w)
	var end := wall_point(o, v, shot._ft, w)
	# The arrow leaves from the bow: remember how far its tip sits from the aim line's start.
	var tip := _arrow.global_transform * Vector3(0, 0, -WeaponModels.ARROW_LEN)
	var node := WeaponModels.arrow()
	node.top_level = true
	add_child(node)
	_flight = {"node": node, "o": o, "v": v, "t0": shot._ft, "wind": w, "res": res, "end": end,
		"streak": logic.streak, "broke": false, "from": tip - shot.to_world(o)}
	_arrow.visible = false
	_draw = 0.0
	_held = 0.0
	shot._state = "flying"
	shot._scale = 0.6
	shot.hud.hide_reticle()
	Sfx.play("swoosh", 0.0, 1.3)
	Sfx.play("thunk", -12.0, 1.8)
	shot.hud.refresh(shot._shown_bottles)


func tick(delta: float, _d: float) -> void:
	if starts_draw(_idle(), _auto, _touch, _drawing):
		_start_draw()
	if _drawing:
		_draw = minf(_draw + delta / float(wcfg.get("draw_s", 0.8)), 1.0)
		if _draw >= 1.0:
			_held += delta
	if _auto:
		_auto_tick()
	# Holding full draw too long: the arm starts to shake (and it shakes the pin and the shot).
	var over := maxf(_held - float(wcfg.get("steady_s", 2.2)), 0.0)
	var amp := deg_to_rad(float(wcfg.get("shake_deg", 0.9))) * minf(over / 1.5, 1.5)
	var tt := Time.get_ticks_msec() / 1000.0
	_shake = Vector2(sin(tt * 13.0) + 0.6 * sin(tt * 29.0 + 1.0), sin(tt * 17.0 + 2.0) + 0.5 * sin(tt * 31.0)) * amp * 0.6
	var cam := Transform3D(view_basis_for(_rest, Vector2(yaw, pitch)), eye())
	var a := cam.basis.inverse() * aim_dir(_shake.x, _shake.y)
	_bow.global_transform = cam * bow_pose(a, _draw)
	_update_string()
	place_fill(cam)
	shot._cam = cam
	shot._fov = float(wcfg.get("fov", 28.0))
	shot._focus = -1.0
	shot._roll = 0.0
	if shot._state == "aim" and _flight.is_empty() and _hold <= 0.0:
		show_reticle(cam, "pin", _shake.x, _shake.y)
	else:
		shot.hud.hide_reticle()
	if not _flight.is_empty():
		_tick_flight(delta)
	elif _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			shot._scale = 1.0
			_arrow.visible = logic.shots_left > 0
			shot.shot_over()
			shot.hud.set_wind(logic.wind(logic.shots_fired))
	_tick_stuck(delta)


func _update_string() -> void:
	place_arrow(_bow, _arrow, _draw)


func _tick_flight(_delta: float) -> void:
	var f := _flight
	var t := shot._ft - float(f["t0"])
	var end: Dictionary = f["end"]
	var t_end := float(end["t"]) - float(f["t0"])
	var res: Dictionary = f["res"]
	var hits: Array = res["hits"]
	var tt := minf(t, t_end)
	var o: Vector3 = f["o"]
	var v: Vector3 = f["v"]
	var w := float(f["wind"])
	var p := shot.to_world(logic.trajectory(o, v, tt, w))
	# It leaves from the bow low left and joins the aim line within a few metres.
	var blend := clampf(v.length() * tt / BLEND_M, 0.0, 1.0)
	p += (f["from"] as Vector3) * (1.0 - blend * blend * (3.0 - 2.0 * blend))
	var vel := v + Vector3(w, -logic.gravity(), 0) * tt
	var node: Node3D = f["node"]
	# The arrow's origin is its nock: put the tip on the flight point.
	var dir := vel.normalized()
	var al := WeaponModels.ARROW_LEN * FLY_SCALE
	node.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP).scaled_local(Vector3.ONE * FLY_SCALE), p - dir * al)
	if not bool(f["broke"]) and not hits.is_empty() and shot._ft >= float(res["t"]):
		f["broke"] = true
		shot.break_bottle(int(hits[0]), dir, int(f["streak"]))
	if t >= t_end:
		if hits.is_empty():
			shot.show_miss()
			Sfx.play("thunk", 1.0, 0.9)
			shot.fx.burst(end["p"], Color(0.55, 0.42, 0.3) if not bool(end["floor"]) else Color(0.5, 0.5, 0.5), 7, 1.4, 0.015, 0.35)
		else:
			Sfx.play("thunk", -6.0)
		# Buried a little: pull the tip in by a few centimetres.
		node.global_position += dir * 0.06
		_stuck.append({"node": node, "t": 0.0, "basis": node.global_transform.basis, "tip": p + dir * 0.06})
		_flight = {}
		_hold = 0.75 if not hits.is_empty() else 0.5
		shot._scale = 1.0


## Stuck arrows quiver about their buried tip.
func _tick_stuck(delta: float) -> void:
	for s in _stuck:
		s["t"] = float(s["t"]) + delta
		var t := float(s["t"])
		if t > 0.8:
			continue
		var a := 0.06 * exp(-t * 7.0) * sin(t * 55.0)
		var node: Node3D = s["node"]
		var b: Basis = (s["basis"] as Basis) * Basis(Vector3.RIGHT, a)
		node.global_transform = Transform3D(b, (s["tip"] as Vector3) - (-b.z.normalized()) * WeaponModels.ARROW_LEN * FLY_SCALE)


func finish() -> void:
	visible = false
	if is_instance_valid(shot.hud):
		shot.hud.hide_reticle()

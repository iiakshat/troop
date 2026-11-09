class_name WeaponBow
extends FinaleWeapon
## Bow (district 3, the docks). First person. Touch and hold to draw (the string comes back
## over draw_s; power = how far), drag to aim with the green pin, release to loose. The pin is
## set for a full draw with no wind at the base distance: a weak draw drops short, wind
## (shown top right, different every arrow) pushes it sideways. Held at full draw past
## steady_s the arm starts to shake. Arrows fly a real gravity arc and stick where they land.

const HOLD_AT := Vector3(-0.07, -0.06, -0.55)   # the bow's grip in camera space
const DRAW_MAX := 0.42                          # metres the nock comes back at full draw

var _bow: Node3D
var _arrow: Node3D                # the nocked arrow (camera space, child of the bow)
var _draw := 0.0                  # 0..1
var _drawing := false
var _held := 0.0                  # seconds at full draw
var _flight: Dictionary = {}      # {node, o, v, t0, wind, res, end, streak, done}
var _stuck: Array = []            # {node, t, basis}
var _hold := 0.0
var _shake := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = logic.level * 7 + 3
	_bow = WeaponModels.bow()
	add_child(_bow)
	_arrow = WeaponModels.arrow()
	_bow.add_child(_arrow)
	_update_string()
	shot.hud.set_wind(logic.wind(logic.shots_fired))


func base_zero() -> float:
	# Sight set for a full draw at the weapon's base distance.
	return logic.zero_angle(float(wcfg.get("speed_max", 30.0)), float(wcfg.get("distance", 17.0)))


func power_speed(p: float) -> float:
	return lerpf(float(wcfg.get("speed_min", 12.0)), float(wcfg.get("speed_max", 30.0)), clampf(p, 0.0, 1.0))


func handle_input(event: InputEvent) -> void:
	if not _flight.is_empty() or _hold > 0.0:
		return
	var t := touch(event)
	if t.is_empty():
		return
	match String(t["kind"]):
		"down":
			_drawing = true
			_held = 0.0
			Sfx.play("swoosh", -10.0, 0.5)
		"drag":
			drag_aim(t["rel"], float(wcfg.get("sens", 0.06)))
		"up":
			if _drawing:
				_drawing = false
				if _draw > 0.12 and logic.can_fire():
					_loose(velocity(aim_dir(_shake.x, _shake.y), power_speed(_draw), base_zero()))
				else:
					_draw = 0.0


func auto_fire() -> void:
	if not _flight.is_empty() or _hold > 0.0:
		return
	var i := logic.next_target()
	if i < 0:
		return
	var w := logic.wind(logic.shots_fired)
	var v := logic.solve(eye_h(), i, power_speed(1.0), shot._ft, w)
	look_along(v, base_zero())
	_draw = 1.0
	_loose(v)


func _loose(v: Vector3) -> void:
	var o := eye_h() + Vector3(0, -0.02, 0)
	var w := logic.wind(logic.shots_fired)
	var res := logic.fire(o, v, shot._ft, w)
	var end := wall_point(o, v, shot._ft, w)
	var node := WeaponModels.arrow()
	node.top_level = true
	add_child(node)
	_flight = {"node": node, "o": o, "v": v, "t0": shot._ft, "wind": w, "res": res, "end": end,
		"streak": logic.streak, "broke": false}
	_arrow.visible = false
	_draw = 0.0
	_held = 0.0
	shot._state = "flying"
	shot._scale = 0.6
	Sfx.play("swoosh", 0.0, 1.3)
	Sfx.play("thunk", -12.0, 1.8)
	shot.hud.refresh(shot._shown_bottles)


func tick(delta: float, _d: float) -> void:
	if _drawing:
		_draw = minf(_draw + delta / float(wcfg.get("draw_s", 0.8)), 1.0)
		if _draw >= 1.0:
			_held += delta
	# Holding full draw too long: the arm starts to shake (and it shakes the shot).
	var over := maxf(_held - float(wcfg.get("steady_s", 2.2)), 0.0)
	var amp := deg_to_rad(float(wcfg.get("shake_deg", 0.9))) * minf(over / 1.5, 1.5)
	var tt := Time.get_ticks_msec() / 1000.0
	_shake = Vector2(sin(tt * 13.0) + 0.6 * sin(tt * 29.0 + 1.0), sin(tt * 17.0 + 2.0) + 0.5 * sin(tt * 31.0)) * amp * 0.6
	var cam := Transform3D(view_basis(_shake.x, _shake.y), eye())
	# Drawing pulls the bow a touch closer and tilts it upright; the camera zooms in slightly.
	var bowx := Transform3D(Basis.from_euler(Vector3(0, 0, deg_to_rad(8.0 - 6.0 * _draw))), HOLD_AT + Vector3(0, 0, 0.04 * _draw))
	_bow.global_transform = cam * bowx
	_update_string()
	# The green pin sits on the line of sight at the grip's distance.
	var pin: Node3D = _bow.get_node("Pin")
	pin.global_position = cam * Vector3(0, 0, HOLD_AT.z + 0.01)
	shot._cam = cam
	shot._fov = float(wcfg.get("fov", 34.0)) * (1.0 - 0.12 * _draw)
	shot._focus = -1.0
	shot._roll = 0.0
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
	var nock := Vector3(0, 0, WeaponModels.BOW_BRACE + DRAW_MAX * _draw)
	WeaponModels.bow_string(_bow, nock)
	# The nocked arrow rests on the shelf: nock on the string, shaft along -Z.
	_arrow.position = nock + Vector3(0.022, 0.06, 0)
	_arrow.rotation = Vector3.ZERO


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
	var vel := v + Vector3(w, -logic.gravity(), 0) * tt
	var node: Node3D = f["node"]
	# The arrow's origin is its nock: put the tip on the flight point.
	var dir := vel.normalized()
	node.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p - dir * WeaponModels.ARROW_LEN)
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
		node.global_transform = Transform3D(b, (s["tip"] as Vector3) - (-b.z) * WeaponModels.ARROW_LEN)


func finish() -> void:
	visible = false

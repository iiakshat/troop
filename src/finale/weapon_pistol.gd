class_name WeaponPistol
extends FinaleWeapon
## Pistol (district 2, carnival shooting gallery). First person: drag to put the crosshair on a
## bottle, release to fire. The gun rides low right in the view (never over a bottle) and turns
## in a little towards the crosshair. Each shot kicks the muzzle up (it settles
## over recover_s; firing early goes high), cycles the slide, throws a brass casing and sends a
## tracer that takes time to arrive and drops a little. The magazine holds `mag` rounds; when
## it runs dry the slide locks back and a swipe down (or a tap) reloads: the empty magazine
## drops, a fresh one goes in, the slide is racked.

const MUZZLE := Vector3(0, -0.026, -0.385)
const PORT := Vector3(0.0145, -0.018, -0.25)
const GRIP := Vector3(0, -0.1, -0.2)
const HOLD := Vector3(0.088, -0.128, -0.3)   # the gun's sight line in camera space: low right,
                                              # below every bottle the narrow lens can show
const TOE_IN := 0.12                         # radians the muzzle turns in towards the crosshair
const TILT := 0.05                           # radians the muzzle lifts towards it
const CANT := -0.1                           # radians of roll (the top leans in a touch)

var _gun: Node3D
var _slide: Node3D
var _mag: Node3D
var _flash: MeshInstance3D
var _light: OmniLight3D
var _snap := 0.0                # gun-only recoil (0..1)
var _slide_t := 1.0             # 0..1 slide cycle
var _locked := false            # slide locked back on an empty magazine
var _casings: Array = []        # {node, vel, spin, t}
var _bullet: Dictionary = {}    # {o, v, t0, arrive, wall, res, tracer, done}
var _hold := 0.0
var _reload_t := -1.0
var _new_mag: Node3D
var _old_mag: Dictionary = {}   # {node, vel, t}
var _down_pos := Vector2.ZERO
var _drag_total := Vector2.ZERO


func _ready() -> void:
	_gun = WeaponModels.pistol()
	add_child(_gun)
	add_fill()
	_slide = _gun.get_node("Gun/Slide")
	_mag = _gun.get_node("Gun/Mag")
	_flash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.05
	_flash.mesh = sm
	_flash.material_override = WeaponModels.mat(Color("ffd27a"), 0.0, 0.5, 8.0)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.position = MUZZLE + Vector3(0, 0, -0.03)
	_flash.visible = false
	_gun.get_node("Gun").add_child(_flash)
	_light = OmniLight3D.new()
	_light.light_color = Color("ffc66b")
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.position = MUZZLE
	_gun.get_node("Gun").add_child(_light)


## The gun's resting pose in camera space (no recoil, no reload): low right, turned in.
static func gun_pose() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(TILT, TOE_IN, CANT)), HOLD)


func speed() -> float:
	return float(wcfg.get("speed", 120.0))


func zero() -> float:
	return logic.zero_angle(speed(), float(wcfg.get("zero", 10.0)))


func handle_input(event: InputEvent) -> void:
	if _reload_t >= 0.0 or not _bullet.is_empty():
		return
	var t := touch(event)
	if t.is_empty():
		return
	match String(t["kind"]):
		"down":
			_down_pos = t["pos"]
			_drag_total = Vector2.ZERO
		"drag":
			_drag_total += t["rel"]
			if not logic.needs_reload():
				drag_aim(t["rel"], float(wcfg.get("sens", 0.06)))
		"up":
			if logic.needs_reload():
				# Swipe down, or a tap: the deliberate reload.
				if _drag_total.y > 40.0 or _drag_total.length() < 20.0:
					_start_reload()
			elif logic.can_fire():
				_fire(velocity(aim_dir(), speed(), zero()))


func auto_fire() -> void:
	if _reload_t >= 0.0 or not _bullet.is_empty():
		return
	if logic.needs_reload():
		_auto = true
		_start_reload()
		return
	var i := logic.next_target()
	if i < 0:
		return
	var v := logic.solve(eye_h(), i, speed(), shot._ft)
	look_along(v, zero())
	_fire(v)


func _fire(v: Vector3) -> void:
	var o := eye_h()
	var res := logic.fire(o, v, shot._ft)
	var wall := wall_point(o, v, shot._ft, 0.0)
	var tracer := FinaleWeapon.streak_mesh(Color(1.0, 0.85, 0.45, 0.9), 0.014)
	add_child(tracer)
	_bullet = {"o": o, "v": v, "t0": shot._ft, "res": res, "wall": wall, "tracer": tracer,
		"broke": false, "streak": logic.streak, "muzzle": _gun.get_node("Gun").to_global(MUZZLE)}
	shot._state = "flying"
	shot._scale = float(wcfg.get("slow", 0.3))
	kick += deg_to_rad(float(wcfg.get("kick_deg", 4.5)))
	_snap = 1.0
	_slide_t = 0.0
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_light.light_energy = 6.0
	_eject()
	Sfx.play("shot", 2.0)
	Game.vibrate(30)
	shot.hud.refresh(shot._shown_bottles)
	if logic.mag_left == 0:
		_locked = true


func _eject() -> void:
	var c := WeaponModels.casing()
	c.top_level = true
	add_child(c)
	var g: Node3D = _gun.get_node("Gun")
	c.global_position = g.to_global(PORT)
	var b := g.global_transform.basis
	var vel := b.x * randf_range(1.4, 2.0) + b.y * randf_range(1.6, 2.2) + b.z * 0.4
	_casings.append({"node": c, "vel": vel, "spin": Vector3(randf_range(-20, 20), randf_range(-30, 30), randf_range(-20, 20)), "t": 0.0})
	_later_clink(0.5)


func _later_clink(t: float) -> void:
	shot._later.append({"t": t, "id": "clink", "vol": -10.0})


func _start_reload() -> void:
	_reload_t = 0.0
	shot._state = "flying"
	shot.hud.show_reload(false)


func tick(delta: float, d: float) -> void:
	# Recoil settles over recover_s; the gun's own snap is quicker.
	var rec := deg_to_rad(float(wcfg.get("kick_deg", 4.5))) / maxf(float(wcfg.get("recover_s", 0.4)), 0.05)
	kick = move_toward(kick, 0.0, rec * delta)
	_snap = move_toward(_snap, 0.0, delta / 0.12)
	_slide_t = minf(_slide_t + delta / 0.09, 1.0)
	if _light.light_energy > 0.0:
		_light.light_energy = maxf(_light.light_energy - delta * 120.0, 0.0)
		if _light.light_energy < 3.0:
			_flash.visible = false
	var cam := Transform3D(view_basis(), eye())
	if _reload_t >= 0.0:
		_tick_reload(delta)
	_tick_casings(d)
	# The gun sits on the line of sight; recoil rotates it up about the grip and pushes it back.
	var r := _reload_pose()
	var local := Transform3D(Basis(), GRIP) * Transform3D(Basis.from_euler(Vector3(deg_to_rad(9.0) * _snap + r.x, r.y, r.z)), -GRIP)
	local.origin += Vector3(0, -0.12 * r.w, 0.045 * _snap + 0.05 * r.w)
	_gun.global_transform = cam * gun_pose() * local
	var back := 0.035 * (sin(_slide_t * PI) if _slide_t < 1.0 else 0.0)
	_slide.position.z = 0.035 if _locked else back
	place_fill(cam)
	shot._cam = cam
	shot._fov = float(wcfg.get("fov", 30.0))
	shot._focus = -1.0
	shot._roll = 0.0
	if shot._state == "aim" and _bullet.is_empty() and _hold <= 0.0 and _reload_t < 0.0:
		show_reticle(cam, "cross")
	else:
		shot.hud.hide_reticle()
	if not _bullet.is_empty():
		_tick_bullet(delta)
	elif _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			shot._scale = 1.0
			shot.shot_over()
			if shot._state == "aim" and logic.needs_reload():
				shot.hud.show_reload(true)


func _tick_bullet(_delta: float) -> void:
	var b := _bullet
	var t := shot._ft - float(b["t0"])
	var res: Dictionary = b["res"]
	var arrive := float(res["t"]) - float(b["t0"]) if not (res["hits"] as Array).is_empty() else float(b["wall"]["t"]) - float(b["t0"])
	var end_t := minf(t, arrive)
	var p := shot.to_world(logic.trajectory(b["o"], b["v"], end_t))
	# The tracer leaves the muzzle and blends onto the line of sight within a few metres.
	var blend := clampf(end_t * speed() / 3.0, 0.0, 1.0)
	p += ((b["muzzle"] as Vector3) - eye()) * (1.0 - blend)
	var tail := shot.to_world(logic.trajectory(b["o"], b["v"], maxf(end_t - 1.4 / speed(), 0.0)))
	FinaleWeapon.place_streak(b["tracer"], tail, p)
	if t >= arrive:
		(b["tracer"] as Node3D).queue_free()
		var hits: Array = res["hits"]
		var dir := (b["v"] as Vector3).normalized()
		if hits.is_empty():
			var w: Dictionary = b["wall"]
			impact_mark(w["p"], Color(0.8, 0.7, 0.6))
			Sfx.play("thunk", -6.0, 1.6)
			shot.show_miss()
			_hold = 0.35
		else:
			shot.break_bottle(int(hits[0]), dir, int(b["streak"]))
			_hold = 0.55
		shot._scale = 1.0
		_bullet = {}


func _tick_casings(d: float) -> void:
	var i := 0
	while i < _casings.size():
		var c: Dictionary = _casings[i]
		c["t"] = float(c["t"]) + d
		var n: Node3D = c["node"]
		c["vel"] = (c["vel"] as Vector3) + Vector3(0, -9.8, 0) * d
		n.global_position += (c["vel"] as Vector3) * d
		n.rotation += (c["spin"] as Vector3) * d
		if float(c["t"]) > 1.2:
			n.queue_free()
			_casings.remove_at(i)
			continue
		i += 1
	if not _old_mag.is_empty():
		var m: Node3D = _old_mag["node"]
		_old_mag["vel"] = (_old_mag["vel"] as Vector3) + Vector3(0, -9.8, 0) * d
		m.global_position += (_old_mag["vel"] as Vector3) * d
		m.rotation.x += d * 3.0
		_old_mag["t"] = float(_old_mag["t"]) + d
		if float(_old_mag["t"]) > 1.0:
			m.queue_free()
			_old_mag = {}


## The reload as a pose: (pitch, yaw, roll, lower) offsets, 0 outside a reload.
func _reload_pose() -> Vector4:
	if _reload_t < 0.0:
		return Vector4.ZERO
	var k := _reload_t / float(wcfg.get("reload_s", 1.15))
	var w := smoothstep(0.0, 0.18, k) * (1.0 - smoothstep(0.85, 1.0, k))
	return Vector4(deg_to_rad(-12.0) * w, deg_to_rad(10.0) * w, deg_to_rad(28.0) * w, w)


func _tick_reload(delta: float) -> void:
	var total := float(wcfg.get("reload_s", 1.15))
	var k0 := _reload_t / total
	_reload_t += delta
	var k := _reload_t / total
	var g: Node3D = _gun.get_node("Gun")
	if k0 < 0.2 and k >= 0.2:
		# The empty magazine drops out.
		var drop := WeaponModels.magazine()
		drop.top_level = true
		add_child(drop)
		drop.global_transform = _mag.global_transform
		_old_mag = {"node": drop, "vel": -g.global_transform.basis.y * 0.8, "t": 0.0}
		_mag.visible = false
		Sfx.play("clink", -2.0, 0.7)
	if k0 < 0.35 and k >= 0.35:
		_new_mag = WeaponModels.magazine()
		g.add_child(_new_mag)
		_new_mag.rotation = _mag.rotation
	if _new_mag:
		var f := smoothstep(0.35, 0.65, k)
		_new_mag.position = _mag.position + Vector3(0, -0.28, 0.04) * (1.0 - f)
	if k0 < 0.65 and k >= 0.65:
		if _new_mag:
			_new_mag.queue_free()
			_new_mag = null
		_mag.visible = true
		Sfx.play("tick", 0.0, 0.8)
	if k0 < 0.8 and k >= 0.8:
		# Rack the slide: it was locked back, it slams forward.
		_locked = false
		_slide_t = 0.5
		Sfx.play("clink", -1.0, 1.4)
	if k >= 1.0:
		_reload_t = -1.0
		logic.reload()
		shot.hud.refresh(shot._shown_bottles)
		shot._state = "aim"
		if _auto:
			_auto = false


func finish() -> void:
	visible = false
	if is_instance_valid(shot.hud):
		shot.hud.hide_reticle()
	for c in _casings:
		(c["node"] as Node3D).queue_free()
	_casings.clear()

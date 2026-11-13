class_name WeaponSniper
extends FinaleWeapon
## Sniper rifle (district 5, rooftop to rooftop). The bottles stand on a neon lounge on a roof
## ~100 m down the street: tiny by eye. Touch to raise the scope, drag to aim, release to fire.
## The scope drifts with breathing (a slow figure of eight) and a slow hand tremor, both
## functions of the time held (never of frames, so 30 and 60 fps drift alike). Through the
## steady window (steady_s) the drift is steady_k of sway_deg; past it it grows gently (over
## worse_s) to worse_k, at most the full sway_deg; an arc on the scope's lower rim drains through the
## steady window and turns amber after it, so the change is seen, not felt as a glitch. The
## bullet takes time and drops (zeroed at `zero` m). A hit is filmed in slow motion from just
## behind and above the round (the bullet cam, FinaleWeapon), ending on the shatter; then the
## bolt is cycled (cycle_s) before the next round. Rounds are limited (BottleLogic shots).

const RIFLE_AT := Vector3(0.13, -0.13, -0.12)   # rifle origin in camera space (unscoped)
const SCOPE_IN := 0.18                          # seconds to raise the scope

var _rifle: Node3D
var _bolt: Node3D
var _ui: CanvasLayer
var _overlay: ScopeOverlay
var _scoped := false
var _scope_k := 0.0               # 0 = eye, 1 = through the scope
var _scope_s := 0.0               # seconds scoped in (steadiness)
var _sway := Vector2.ZERO
var _sway_t := 0.0                # real seconds since the scope went up (the sway's clock)
var _phase := "ready"             # ready | bullet | look (the film's hold) | wait | cycle
var _flight: Dictionary = {}
var _cycle_t := 0.0
var _wait_t := 0.0               # phase wait: real s left on the scope before the bolt
var _bullet: Node3D
var _casings: Array = []
var _look_at := Vector3.ZERO
var _noise := FastNoiseLite.new()


## Black scope mask with a duplex crosshair and range dots.
class ScopeOverlay extends Control:
	var alpha := 0.0
	var steady := 1.0     # share of the steady window left (the arc on the lower rim)
	var tired := 0.0      # 0..1 past the steady window: the arc turns amber

	func _draw() -> void:
		if alpha <= 0.01:
			return
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.47
		var ink := Color(0, 0, 0, alpha)
		# Mask: everything outside the circle (four rects + a ring of thick arcs).
		draw_rect(Rect2(0, 0, size.x, c.y - r), ink)
		draw_rect(Rect2(0, c.y + r, size.x, size.y - c.y - r), ink)
		draw_rect(Rect2(0, c.y - r - 1, c.x - r, 2 * r + 2), ink)
		draw_rect(Rect2(c.x + r, c.y - r - 1, size.x - c.x - r, 2 * r + 2), ink)
		# The four corners between the circle and its square.
		for q in 4:
			var a0 := q * PI * 0.5
			var corner := c + Vector2(cos(a0 + PI * 0.25), sin(a0 + PI * 0.25)) * (r + 2.0) * sqrt(2.0)
			var pts := PackedVector2Array([corner])
			for k in 25:
				var a := a0 + PI * 0.5 * k / 24.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, ink)
		draw_arc(c, r, 0, TAU, 96, Color(0, 0, 0, alpha * 0.6), 10.0, true)
		draw_arc(c, r - 14.0, 0, TAU, 96, Color(0, 0, 0, alpha * 0.25), 18.0, true)
		# Duplex crosshair: thick outer posts, thin centre.
		var thin := Color(0.05, 0.05, 0.05, alpha)
		draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.32, 0), thin, 7.0)
		draw_line(c + Vector2(r * 0.32, 0), c + Vector2(r, 0), thin, 7.0)
		draw_line(c + Vector2(0, r * 0.32), c + Vector2(0, r), thin, 7.0)
		draw_line(c + Vector2(0, -r), c + Vector2(0, -r * 0.32), thin, 7.0)
		draw_line(c + Vector2(-r * 0.32, 0), c + Vector2(r * 0.32, 0), thin, 1.6)
		draw_line(c + Vector2(0, -r * 0.32), c + Vector2(0, r * 0.32), thin, 1.6)
		for k in range(1, 5):
			var d := r * 0.075 * k
			draw_circle(c + Vector2(0, d), 2.6, thin)
			draw_circle(c + Vector2(d, 0), 2.6, thin)
			draw_circle(c + Vector2(-d, 0), 2.6, thin)
		draw_circle(c, 2.2, Color(0.9, 0.1, 0.1, alpha))
		# Breath arc on the lower rim: full and pale green while the hold is steady, draining
		# through the steady window, then a dim amber arc as the drift slowly comes back.
		var half := deg_to_rad(38.0)
		var rr := r - 30.0
		draw_arc(c, rr, PI * 0.5 - half, PI * 0.5 + half, 48, Color(1, 1, 1, alpha * 0.18), 7.0, true)
		if steady > 0.002:
			draw_arc(c, rr, PI * 0.5 - half * steady, PI * 0.5 + half * steady, 48,
				Color(0.55, 1.0, 0.6, alpha * 0.85), 7.0, true)
		elif tired > 0.0:
			draw_arc(c, rr, PI * 0.5 - half, PI * 0.5 + half, 48, Color(1.0, 0.68, 0.2, alpha * (0.35 + 0.5 * tired)), 7.0, true)


func _ready() -> void:
	_noise.seed = logic.level
	_noise.frequency = 3.0
	_rifle = WeaponModels.rifle()
	add_child(_rifle)
	add_fill()
	_bolt = _rifle.get_node("Bolt")
	_ui = CanvasLayer.new()
	_ui.layer = 1
	add_child(_ui)
	_overlay = ScopeOverlay.new()
	UiKit.full_rect(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_overlay)


func speed() -> float:
	return float(wcfg.get("speed", 300.0))


func zero() -> float:
	return logic.zero_angle(speed(), float(wcfg.get("zero", 100.0)))


func handle_input(event: InputEvent) -> void:
	if _phase != "ready":
		return
	var t := touch(event)
	if t.is_empty():
		return
	match String(t["kind"]):
		"down":
			_scope(true)
		"drag":
			# Finer through the scope.
			var sens := float(wcfg.get("sens", 0.012)) * (1.0 if _scoped else 4.0)
			drag_aim(t["rel"], sens)
		"up":
			if _scoped and _scope_k > 0.7 and logic.can_fire():
				# Fired exactly where the crosshair shows (the view carries the sway x _scope_k).
				_fire(velocity(aim_dir(_sway.x * _scope_k, _sway.y * _scope_k), speed(), zero()))
			else:
				_scope(false)
		"cancel":
			_scope(false)


func _scope(on: bool) -> void:
	if on and not _scoped:
		_scope_s = 0.0
		_sway_t = 0.0
		Sfx.play("tick", -8.0, 0.6)
	_scoped = on


## Autoplay: raise the scope, settle on the next bottle for a moment, then fire (no sway).
func auto_fire() -> void:
	if _phase != "ready" or _auto:
		return
	if logic.next_target() < 0:
		return
	_auto = true
	_scope(true)


func _auto_tick() -> void:
	var i := logic.next_target()
	if i < 0:
		_auto = false
		return
	var v := logic.solve(eye_h(), i, speed(), shot._ft)
	look_along(v, zero())
	_sway = Vector2.ZERO
	if _scope_k >= 1.0 and _scope_s >= 0.45:
		_auto = false
		_fire(v)


func _fire(v: Vector3) -> void:
	var o := eye_h()
	var s0 := logic.streak
	var res := logic.fire(o, v, shot._ft)
	var end := wall_point(o, v, shot._ft, 0.0)
	var hits: Array = res["hits"]
	_flight = {"o": o, "v": v, "t0": shot._ft, "res": res, "end": end, "streak": s0 + 1 if not hits.is_empty() else 0}
	shot._state = "flying"
	kick += deg_to_rad(1.6)
	Sfx.play("shot_sniper", 3.0)
	Game.vibrate(45)
	shot.hud.refresh(shot._shown_bottles)
	if not hits.is_empty():
		# Bullet cam: slow motion from just behind and above the round, which stays in frame.
		# The scope stays up underneath, so a skipped film shows the shatter through it.
		_phase = "bullet"
		_bullet = WeaponModels.bullet(float(wcfg.get("cam_bullet", 5.0)))
		_bullet.top_level = true
		add_child(_bullet)
		var glint := OmniLight3D.new()
		glint.light_color = Color("ffd9a0")
		glint.light_energy = 2.0
		glint.omni_range = 0.6
		glint.position = Vector3(0.15, 0.2, 0.3)
		_bullet.add_child(glint)
		var trail := FinaleWeapon.streak_mesh(Color(1.0, 0.88, 0.6, 0.8), 0.014)
		add_child(trail)
		_flight["trail"] = trail
		film_begin(float(res["t"]) - shot._ft)
	else:
		_phase = "bullet"
		shot._scale = 1.0


func tick(delta: float, d: float) -> void:
	follow_aim(delta, float(wcfg.get("sens", 0.012)) * (1.0 if _scoped else 4.0))
	_scope_k = move_toward(_scope_k, 1.0 if _scoped else 0.0, delta / SCOPE_IN)
	if _scoped:
		_scope_s += delta
	kick = move_toward(kick, 0.0, deg_to_rad(1.6) / 0.5 * delta)
	_update_sway(delta)
	if _auto and _phase == "ready":
		_auto_tick()
	_tick_casings(d)
	var cam := Transform3D(view_basis(_sway.x * _scope_k, _sway.y * _scope_k), eye())
	var fov := float(wcfg.get("fov", 46.0))
	var sfov := float(wcfg.get("scope_fov", 2.8))
	# Zoom in log space so the scope snaps in like an optic, not a slow dolly.
	shot._fov = exp(lerpf(log(fov), log(sfov), smoothstep(0.0, 1.0, _scope_k)))
	place_fill(cam)
	shot._cam = cam
	shot._focus = -1.0
	shot._roll = 0.0
	_overlay.alpha = smoothstep(0.5, 1.0, _scope_k)
	_overlay.steady = steady_left(_scope_s, wcfg) if _scoped else 1.0
	_overlay.tired = tiredness(_scope_s, wcfg) if _scoped else 0.0
	_overlay.queue_redraw()
	_rifle.visible = _scope_k < 0.6
	_rifle.global_transform = cam * Transform3D(Basis(), RIFLE_AT + Vector3(0, 0.03 * _scope_k, 0.05 * _scope_k))
	match _phase:
		"bullet":
			_tick_bullet(delta)
		"look":
			# The bullet cam holds on the shatter, then the scope comes down and the bolt works.
			_overlay.alpha = 0.0
			_rifle.visible = false
			if film_hold(delta, _look_at):
				_scoped = false
				_scope_k = 0.0
				_start_cycle()
		"wait":
			_wait_t -= delta
			if _wait_t <= 0.0:
				_scoped = false
				_start_cycle()
		"cycle":
			_tick_cycle(delta)


## How much of the full sway (sway_deg) shows `s` seconds after the scope went up: steady_k
## through the steady window (steady_s), then it rises smoothly over worse_s to worse_k (capped
## at 1) and stays there. Never a step: the old profile jumped to 2.4x past 1.6 s.
static func hold_k(s: float, w: Dictionary) -> float:
	var steady_k := float(w.get("steady_k", 0.15))
	var worse_k := clampf(float(w.get("worse_k", 0.5)), steady_k, 1.0)
	return lerpf(steady_k, worse_k, tiredness(s, w))


## Share of the steady window left (the scope's breath arc): 1 when the scope goes up, 0 at steady_s.
static func steady_left(s: float, w: Dictionary) -> float:
	return clampf(1.0 - s / maxf(float(w.get("steady_s", 2.5)), 0.1), 0.0, 1.0)


## 0 inside the steady window, rising to 1 as the drift comes back (worse_s after it).
static func tiredness(s: float, w: Dictionary) -> float:
	var steady := maxf(float(w.get("steady_s", 2.5)), 0.1)
	return smoothstep(0.0, maxf(float(w.get("worse_s", 4.0)), 0.1), s - steady)


## The scope's drift (yaw, pitch radians) `t` seconds after it went up, at hold factor `k`:
## a slow breathing figure of eight (0.14 / 0.29 Hz) plus a slow tremor (about 1.3 Hz), both
## starting from zero as the scope comes up. Smooth in `t`, so it never jumps between frames.
static func sway_at(t: float, k: float, w: Dictionary, noise: FastNoiseLite) -> Vector2:
	var sway := deg_to_rad(float(w.get("sway_deg", 0.2)))
	var trem := deg_to_rad(float(w.get("tremor_deg", 0.02)))
	var breath := Vector2(sin(t * 0.9), sin(t * 1.8) * 0.6) * sway
	var n0 := noise.get_noise_1d(0.0)
	var n1 := noise.get_noise_1d(50.0)
	var shake := Vector2(noise.get_noise_1d(t * 0.45) - n0, noise.get_noise_1d(t * 0.45 + 50.0) - n1) * trem
	return (breath + shake) * k * smoothstep(0.0, 0.25, t)


func _update_sway(delta: float) -> void:
	if not _scoped:
		_sway *= exp(-delta / 0.08)
		return
	_sway_t += delta
	_sway = sway_at(_sway_t, hold_k(_scope_s, wcfg), wcfg, _noise)


func _tick_bullet(delta: float) -> void:
	var f := _flight
	var res: Dictionary = f["res"]
	var hits: Array = res["hits"]
	var t := shot._ft - float(f["t0"])
	var o: Vector3 = f["o"]
	var v: Vector3 = f["v"]
	if hits.is_empty():
		var end: Dictionary = f["end"]
		if t >= float(end["t"]) - float(f["t0"]):
			# A miss: a puff where it lands, seen through the scope.
			impact_mark(end["p"], Color(0.75, 0.7, 0.8), 0.12)
			Sfx.play("thunk", -14.0, 1.3)
			shot.show_miss()
			_flight = {}
			_phase = "wait"
			_start_hold_then_cycle()
		return
	var arrive := float(res["t"]) - float(f["t0"])
	var tt := minf(t, arrive)
	var p := shot.to_world(logic.trajectory(o, v, tt))
	var dir := (v + Vector3(0, -logic.gravity(), 0) * tt).normalized()
	_bullet.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p)
	if f.has("trail"):
		# A short hot streak just behind the round (the air it parts), thin beside the lens.
		FinaleWeapon.place_streak(f["trail"], p - dir * 0.8, p, 0.5)
	var i := int(hits[0])
	if filming() and not film_holding():
		# The camera rides just behind and above the round (it was 0.32 m to the side looking
		# 2.5 m ahead through a 32 degree lens: the round sat outside the frame), and stops
		# cam_stop short of the bottle so the round flies on into it in front of the lens.
		var ta := FinaleWeapon.film_anchor_t(tt, arrive, float(wcfg.get("cam_stop", 2.5)) / speed())
		var ad := (v + Vector3(0, -logic.gravity(), 0) * ta).normalized()
		film_fly(delta, shot.to_world(logic.trajectory(o, v, ta)), ad, p, dir,
			0.034 * float(wcfg.get("cam_bullet", 5.0)), shot._bottle_center(i, shot._ft))
		_overlay.alpha = 0.0
		_rifle.visible = false
	if t >= arrive:
		shot.break_bottle(i, dir, int(f["streak"]))
		_look_at = shot._bottle_center(i, shot._ft)
		_bullet.queue_free()
		if f.has("trail"):
			(f["trail"] as Node3D).queue_free()
		_flight = {}
		if filming():
			film_hit()
			_phase = "look"
		else:
			# The film was skipped: the shatter is seen through the scope, then the bolt.
			shot._scale = 1.0
			_phase = "wait"
			_start_hold_then_cycle()


## The rifle (or the scope) is up and a shot can go.
func aim_ui_visible() -> bool:
	return _phase == "ready" and is_visible_in_tree() and (_rifle.visible or _overlay.alpha > 0.5)


func _start_hold_then_cycle() -> void:
	# Stay on the scope a moment so the miss reads, then lower it and work the bolt (timed in
	# tick: a tween ran on its own clock, outside the finale's).
	_phase = "wait"
	_wait_t = 0.6


func _start_cycle() -> void:
	if logic.shots_left <= 0 or logic.remaining() == 0:
		_phase = "ready"
		shot.shot_over()
		return
	_phase = "cycle"
	_cycle_t = 0.0
	Sfx.play("clink", -3.0, 0.8)


## Bolt action: lift, pull back (the case flies out), push forward, lock down.
func _tick_cycle(delta: float) -> void:
	var total := float(wcfg.get("cycle_s", 0.95))
	var k0 := _cycle_t / total
	_cycle_t += delta
	var k := minf(_cycle_t / total, 1.0)
	var lift := smoothstep(0.0, 0.2, k) * (1.0 - smoothstep(0.8, 1.0, k))
	var back := smoothstep(0.2, 0.45, k) * (1.0 - smoothstep(0.55, 0.8, k))
	_bolt.rotation.z = deg_to_rad(70.0) * lift
	_bolt.position.z = -0.1 + 0.09 * back
	# The rifle rolls a little towards the hand working the bolt.
	_rifle.rotate_object_local(Vector3.FORWARD, deg_to_rad(10.0) * sin(k * PI))
	if k0 < 0.42 and k >= 0.42:
		var c := WeaponModels.casing(true)
		c.top_level = true
		add_child(c)
		c.global_position = _bolt.global_position + _rifle.global_transform.basis.y * 0.02
		var b := _rifle.global_transform.basis
		_casings.append({"node": c, "vel": b.x * 1.6 + b.y * 1.4, "spin": Vector3(12, 20, 5), "t": 0.0})
		shot._later.append({"t": 0.55, "id": "clink", "vol": -12.0})
	if k0 < 0.8 and k >= 0.8:
		Sfx.play("tick", -2.0, 0.9)
	if k >= 1.0:
		_phase = "ready"
		shot._state = "flying"
		shot.shot_over()


func _tick_casings(d: float) -> void:
	var i := 0
	while i < _casings.size():
		var c: Dictionary = _casings[i]
		c["t"] = float(c["t"]) + d
		c["vel"] = (c["vel"] as Vector3) + Vector3(0, -9.8, 0) * d
		var n: Node3D = c["node"]
		n.global_position += (c["vel"] as Vector3) * d
		n.rotation += (c["spin"] as Vector3) * d
		if float(c["t"]) > 1.2:
			n.queue_free()
			_casings.remove_at(i)
			continue
		i += 1


func warm_parts() -> Array:
	var b := WeaponModels.bullet(float(wcfg.get("cam_bullet", 5.0)))
	var glint := OmniLight3D.new()
	glint.light_color = Color("ffd9a0")
	glint.light_energy = 2.0
	glint.omni_range = 0.6
	b.add_child(glint)
	return [b, WeaponModels.casing(true), World._box(Vector3(0.12, 0.12, 0.01), Color(0.06, 0.05, 0.04)),
		FinaleWeapon.streak_mesh(Color(1.0, 0.88, 0.6, 0.8), 0.014)]


func finish() -> void:
	film_end()
	visible = false
	_ui.queue_free()

class_name FinaleWeapon
extends Node3D
## Base for the Bottle Shot weapons other than knives. BottleShot owns the stash, the bottles,
## the clock (_ft, slowed by _scale), the HUD and the shatter; a weapon owns input, the
## camera (it writes shot._cam / _fov / _focus / _blur), its model and its projectiles.
## Rules come from BottleLogic.fire (hero space: hero at the origin, floor at y = 0, -Z ahead).
## When a shot's film is over the weapon calls shot.shot_over().
##
## Aim (owner play-test 2026-11-13: "holding fluctuates... after 2-3 s it moves so aggressively"):
## only the finger that pressed first steers (a thumb resting on the glass used to make the aim
## leap between the two fingers), the view eases onto the finger with a frame-rate independent
## time constant (AIM_TAU, so uneven touch-event timing at a low or variable frame rate never
## steps the aim), and any sway is slow, small and a function of time held, never of frames.
##
## Bullet cam: a pistol, bow or sniper shot that will break a bottle is filmed in slow motion
## from beside and a little behind the round or arrow (chase_view), which stays in frame and
## lit; the camera stops short of the bottle so the shot ends on the shatter, holds a beat, and
## gives the aim back with the clock at exactly 1. A tap skips it (film_skip).

const AIM_TAU := 0.025         # s: the aim covers 63 % of the way to a moving finger in this time
const AIM_TAU_STILL := 0.09    # s: ... to a resting finger (its tremble is smoothed away)
const AIM_FAST_PX := 400.0     # finger px/s from which the aim follows at AIM_TAU
const CHASE_BACK := 0.25       # bullet cam (default rig): metres behind the projectile's tail
const CHASE_SIDE := 0.06       # ... beside its line
const CHASE_UP := 0.2          # ... and above it: on a tall screen the round flies up the
                               # picture towards the bottles, its profile seen from above
const CHASE_LEAD := 0.25       # it looks this far ahead of the projectile's middle
const CHASE_FOV := 46.0
const CHASE_EASE := 0.08       # real s to ease into the slow motion

var shot: BottleShot
var logic: BottleLogic
var world: World
var wcfg: Dictionary
var yaw := 0.0                 # view direction (radians); 0/0 = straight down the range
var pitch := 0.0
var kick := 0.0                # recoil pitch on top of the aim (radians), recovers
var _touch := false
var _last := Vector2.ZERO
var _auto := false             # autoplay asked for a shot
var input_while_busy := false  # true: also gets touches while a shot is out (to keep a held finger)
var _fill: OmniLight3D
var goal := Vector2.ZERO       # (yaw, pitch) the finger has set; yaw/pitch ease onto it (follow_aim)
var _goal_prev := Vector2.ZERO
var _finger_speed := 0.0       # px/s, smoothed
var _finger := -1              # index of the finger that steers (-1 = none down)
var film: Dictionary = {}      # the bullet cam while it runs (film_begin), else empty
var _film_n := 0


func setup(s: BottleShot) -> FinaleWeapon:
	shot = s
	logic = s.logic
	world = s.world
	wcfg = logic.wcfg
	# Start aimed at the middle of the bottle set.
	var r := rest_aim(logic)
	yaw = r.x
	pitch = r.y
	goal = r
	_goal_prev = r
	return self


## (yaw, pitch) from the eye to the middle of the bottle set: where every weapon starts aimed.
static func rest_aim(l: BottleLogic) -> Vector2:
	var lo := INF
	var hi := -INF
	for b in l.layout["bottles"]:
		lo = minf(lo, float(b["y"]))
		hi = maxf(hi, float(b["y"]))
	var d := Vector3(0, (lo + hi) * 0.5, -l.distance) - eye_point(l.wcfg)
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


## The eye in hero space for a weapon config.
static func eye_point(w: Dictionary) -> Vector3:
	return Vector3(0.0, float(w.get("eye_y", 1.6)), -0.35)


## The eye in hero space (a little ahead of the hero's face, so his head never fills the lens).
func eye_h() -> Vector3:
	return eye_point(wcfg)


func eye() -> Vector3:
	return shot.to_world(eye_h())


func view_basis(extra_yaw := 0.0, extra_pitch := 0.0) -> Basis:
	return Basis.from_euler(Vector3(pitch + kick + extra_pitch, yaw + extra_yaw, 0.0))


## Forward direction of the current aim (with recoil).
func aim_dir(extra_yaw := 0.0, extra_pitch := 0.0) -> Vector3:
	return -view_basis(extra_yaw, extra_pitch).z


## Velocity with forward speed `speed` along the range, leaving along `dir` tilted up by `zero`
## radians (sights zeroed at a distance).
func velocity(dir: Vector3, speed: float, zero := 0.0) -> Vector3:
	var b := Basis.from_euler(Vector3(asin(clampf(dir.y, -1.0, 1.0)) + zero, atan2(-dir.x, -dir.z), 0.0))
	var v := -b.z
	return v * (speed / maxf(-v.z, 0.05))


## Points the view along `v` (autoplay), removing the sight's zero tilt.
func look_along(v: Vector3, zero := 0.0) -> void:
	var d := v.normalized()
	yaw = atan2(-d.x, -d.z)
	pitch = asin(clampf(d.y, -1.0, 1.0)) - zero
	goal = Vector2(yaw, pitch)
	_goal_prev = goal
	kick = 0.0


func rest_view() -> Transform3D:
	return Transform3D(view_basis(), eye())


## Puts the HUD reticle on the screen point of the current aim, seen from `cam` (world).
func show_reticle(cam: Transform3D, kind: String, extra_yaw := 0.0, extra_pitch := 0.0) -> void:
	var vp := shot.hud.get_viewport().get_visible_rect().size
	var p := eye() + aim_dir(extra_yaw, extra_pitch) * 20.0
	shot.hud.set_reticle(project_cam(cam.affine_inverse() * p, shot._fov, vp), kind)


func rest_fov() -> float:
	return float(wcfg.get("fov", 34.0))


## Drag deltas in pixels -> aim goal (degrees per pixel = sens); follow_aim eases the view onto it.
func drag_aim(rel: Vector2, sens: float) -> void:
	goal.x -= deg_to_rad(rel.x * sens)
	goal.y = clampf(goal.y - deg_to_rad(rel.y * sens), deg_to_rad(-30.0), deg_to_rad(30.0))


## The view eases onto the finger's goal: the same path at 30 or 60 fps, and drag events that
## arrive two in one frame and none in the next no longer step the aim. A finger moving on
## purpose is followed closely (AIM_TAU); a resting one more softly (AIM_TAU_STILL), so the
## pixel or two a fingertip trembles is smoothed away (the scope magnifies it 4x). `sens` =
## the current degrees per finger pixel.
func follow_aim(delta: float, sens: float) -> void:
	if delta <= 0.0:
		return
	var px := (goal - _goal_prev).length() / maxf(deg_to_rad(sens), 0.000001)
	_goal_prev = goal
	_finger_speed = lerpf(_finger_speed, px / delta, ease_k(delta, 0.06))
	var tau := lerpf(AIM_TAU_STILL, AIM_TAU, clampf(_finger_speed / AIM_FAST_PX, 0.0, 1.0))
	var k := ease_k(delta, tau)
	yaw = lerpf(yaw, goal.x, k)
	pitch = lerpf(pitch, goal.y, k)


## Share of the way to cover this frame for an exponential ease with time constant `tau`.
static func ease_k(delta: float, tau: float) -> float:
	if delta <= 0.0:
		return 0.0
	return 1.0 - exp(-delta / maxf(tau, 0.0001))


## Shared touch parsing: returns {kind: down|drag|up|cancel, pos, rel} or {}. Only the first
## finger counts: a second one (a thumb resting on the glass) neither steers nor fires.
func touch(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if _touch and e.index != _finger:
				return {}
			_touch = true
			_finger = e.index
			_last = e.position
			return {"kind": "down", "pos": e.position, "rel": Vector2.ZERO}
		if _touch and e.index == _finger:
			_touch = false
			_finger = -1
			return {"kind": "cancel" if e.canceled else "up", "pos": e.position, "rel": e.position - _last}
	elif event is InputEventScreenDrag and _touch:
		var e := event as InputEventScreenDrag
		if e.index != _finger:
			return {}
		var rel := e.position - _last
		_last = e.position
		return {"kind": "drag", "pos": e.position, "rel": rel}
	return {}


## A finger lifted while BottleShot was not passing touches on: forget it, so a stale finger
## never blocks the next one.
func forget_finger(index: int) -> void:
	if _touch and index == _finger:
		_touch = false
		_finger = -1


# ---------------------------------------------------------------- overridables

func begin() -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass


func tick(_delta: float, _d: float) -> void:
	pass


func auto_fire() -> void:
	pass


func finish() -> void:
	film_end()
	visible = false


## Level-load prewarm (BottleShot dormant): `on` shows the weapon's parts that only appear
## mid-shot (a muzzle flash...) so they draw out of sight while the level loads; off hides them.
func warm(_on: bool) -> void:
	pass


## Level-load prewarm: one of each thing this weapon makes during play (tracers, casings,
## projectiles...), built the same way, for BottleShot to draw out of sight while loading.
func warm_parts() -> Array:
	return []


# ---------------------------------------------------------------- bullet cam

## Starts the slow-motion film of a shot that will break a bottle: `flight` = game seconds until
## it reaches the bottle. The clock slows so the flight lasts about cam_s real seconds.
func film_begin(flight: float) -> void:
	var cam_s := maxf(float(wcfg.get("cam_s", 0.85)), 0.1)
	var slow := clampf(flight / cam_s, float(wcfg.get("cam_min_scale", 0.05)), 1.0)
	_film_n += 1
	film = {"real": 0.0, "slow": slow, "from": shot._scale, "side": 1.0 if _film_n % 2 == 1 else -1.0,
		"hold": -1.0, "cam": shot._cam}


## True while the bullet cam owns the camera.
func filming() -> bool:
	return not film.is_empty()


## True once the projectile has reached its bottle (the hold on the shatter).
func film_holding() -> bool:
	return not film.is_empty() and float(film["hold"]) >= 0.0


## One frame of the film while the projectile flies: `a`/`ad` = the point on the flight path
## the camera rides (it stops short of the bottle) and its direction, `p`/`d` = the projectile's
## tip and direction now, `length` its length, `target` the bottle (all world). Sets the camera,
## lens and clock.
func film_fly(delta: float, a: Vector3, ad: Vector3, p: Vector3, d: Vector3, length: float, target: Vector3) -> void:
	if film.is_empty():
		return
	film["real"] = float(film["real"]) + delta
	shot._scale = lerpf(float(film["from"]), float(film["slow"]), smoothstep(0.0, CHASE_EASE, float(film["real"])))
	var cam := chase_view(a, ad, p, d, length, float(film["side"]), chase_rig())
	film["cam"] = cam
	film["p"] = p - d * (length * 0.5)   # the projectile's middle (tests check it stays in frame)
	_film_lens(cam, target)
	# The fill rides beside the projectile so a dark stash never hides it.
	if _fill:
		_fill.global_position = p - d * (length * 0.5) + cam.basis.x * 0.2 + cam.basis.y * 0.15 + cam.basis.z * 0.1


## The projectile has reached the bottle: hold on the shatter (cam_hold real seconds) while the
## clock comes back up from cam_hold_scale to 1.
func film_hit() -> void:
	if film.is_empty() or float(film["hold"]) >= 0.0:
		return
	film["hold"] = 0.0
	shot._scale = float(wcfg.get("cam_hold_scale", 0.35))


## The hold after the hit, one frame. Returns true when the film is over (clock back at 1).
func film_hold(delta: float, target: Vector3) -> bool:
	if film.is_empty():
		return true
	var h := float(film["hold"]) + delta
	film["hold"] = h
	var total := maxf(float(wcfg.get("cam_hold", 0.6)), 0.05)
	var k := clampf(h / total, 0.0, 1.0)
	shot._scale = lerpf(float(wcfg.get("cam_hold_scale", 0.35)), 1.0, smoothstep(0.3, 1.0, k))
	# A slow pull back along the view so the flying glass stays in frame.
	var cam: Transform3D = film["cam"]
	var view := Transform3D(cam.basis, cam.origin + cam.basis.z * 0.35 * (1.0 - pow(1.0 - k, 2.0)))
	_film_lens(view, target)
	if h >= total:
		film_end()
		return true
	return false


## Over (or skipped, or the finale ends): the clock is exactly 1 again and the weapon's own
## view takes the camera back on its next frame.
func film_end() -> void:
	if film.is_empty():
		return
	film = {}
	if shot != null and is_instance_valid(shot):
		shot._scale = 1.0


## A tap while filming skips the film: the shot plays on at full speed from the weapon's view.
func film_skip() -> bool:
	if film.is_empty():
		return false
	film_end()
	return true


func _film_lens(cam: Transform3D, target: Vector3) -> void:
	shot._cam = cam
	shot._fov = CHASE_FOV
	shot._focus = cam.origin.distance_to(target) + 0.8
	shot._blur = 0.04
	shot._roll = 0.0
	if shot.hud:
		shot.hud.hide_reticle()


## This weapon's bullet cam rig: (back, side, up, lead) in metres (finale.json cam_rig).
func chase_rig() -> Vector4:
	var r: Array = wcfg.get("cam_rig", [])
	if r.size() == 4:
		return Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return Vector4(CHASE_BACK, CHASE_SIDE, CHASE_UP, CHASE_LEAD)


## The bullet cam's view: behind (rig.x), beside (rig.y) and above (rig.z) the point `a` on the
## flight path (direction `ad`), looking rig.w ahead of the projectile's middle (tip `p`,
## direction `d`, `length` long), so the projectile sits just off centre, the bottles beyond it.
static func chase_view(a: Vector3, ad: Vector3, p: Vector3, d: Vector3, length: float, side_sign: float,
		rig := Vector4(CHASE_BACK, CHASE_SIDE, CHASE_UP, CHASE_LEAD)) -> Transform3D:
	var side := ad.cross(Vector3.UP)
	side = (side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT) * side_sign
	var eye := a - ad * (length + rig.x) + side * rig.y + Vector3.UP * rig.z
	var look := p - d * (length * 0.5) + d * rig.w
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


## Game time (since the shot) of the point the bullet cam rides: the projectile's own time until
## it is `stop` game seconds short of `arrive`, then it eases to a halt there, so the shot flies
## on into the bottle in front of the lens. Continuous, at the projectile's speed at the join.
static func film_anchor_t(t: float, arrive: float, stop: float) -> float:
	var e := maxf(stop * 0.5, 0.0001)
	var knee := maxf(arrive - stop - e, 0.0)
	if t <= knee:
		return t
	return knee + e * (1.0 - exp(-(t - knee) / e))


# ---------------------------------------------------------------- screen checks

## Pixel position of camera-space point `q` for the game camera (KEEP_WIDTH: `fov_h` is the
## horizontal field of view in degrees) on a viewport of `vp` pixels. Points at or behind the
## lens are pushed onto a near plane so a part crossing it still gets a (huge) rect.
static func project_cam(q: Vector3, fov_h: float, vp: Vector2) -> Vector2:
	var f := vp.x * 0.5 / tan(deg_to_rad(fov_h) * 0.5)
	var z := maxf(-q.z, 0.02)
	return Vector2(vp.x * 0.5 + f * q.x / z, vp.y * 0.5 - f * q.y / z)


## Screen rects of the bottles still standing at finale time `t`, seen from `cam` (hero space,
## like BottleLogic), each a little larger than the glass itself.
static func bottle_rects(l: BottleLogic, cam: Transform3D, fov_h: float, vp: Vector2, t: float) -> Array:
	var out: Array = []
	var inv := cam.affine_inverse()
	var hw := 0.16 * l.size
	for i in l.count():
		if l.broken[i]:
			continue
		var p := l.position(i, t)
		var r := Rect2()
		var first := true
		for c in [Vector3(-hw, -0.42 * l.size, 0), Vector3(hw, -0.42 * l.size, 0), Vector3(-hw, 0.44 * l.size, 0), Vector3(hw, 0.44 * l.size, 0)]:
			var s := project_cam(inv * (Vector3(p.x, p.y, -l.distance) + c), fov_h, vp)
			if first:
				r = Rect2(s, Vector2.ZERO)
				first = false
			else:
				r = r.expand(s)
		out.append(r)
	return out


# ---------------------------------------------------------------- helpers

## A soft light riding with the camera so the weapon in hand never goes black in a dark stash.
func add_fill() -> void:
	var l := OmniLight3D.new()
	l.name = "Fill"
	l.light_color = Color("fff1dc")
	l.light_energy = 1.3
	l.omni_range = 1.6
	l.shadow_enabled = false
	l.top_level = true
	add_child(l)
	_fill = l


func place_fill(cam: Transform3D) -> void:
	if _fill:
		_fill.global_position = cam * Vector3(0.25, 0.22, 0.05)


## Leaves a tracer streak: a thin glowing box from `a` to `b`.
static func streak_mesh(color: Color, width: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, 1.0)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	return mi


static func place_streak(mi: MeshInstance3D, a: Vector3, b: Vector3, width := 1.0) -> void:
	var l := maxf(a.distance_to(b), 0.001)
	var z := (a - b) / l
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	mi.global_transform = Transform3D(Basis(x, z.cross(x), z) * Basis.from_scale(Vector3(width, width, l)), (a + b) * 0.5)


## A dark hole and a puff of wall dust where a shot struck the back wall (world point).
func impact_mark(p: Vector3, dust: Color, size := 0.05) -> void:
	var hole := World._box(Vector3(size, size, 0.01), Color(0.06, 0.05, 0.04))
	hole.position = Vector3(p.x, p.y, shot._wall_front + 0.006)
	shot.add_child(hole)
	shot.fx.burst(Vector3(p.x, p.y, shot._wall_front + 0.05), dust, 8, 1.4, 0.02, 0.4)


## Where a projectile from `o` with `v` (hero space) meets the back wall (world point) and when.
func wall_point(o: Vector3, v: Vector3, t0: float, wind_x: float) -> Dictionary:
	var wall_hz := shot._wall_front - shot.hero_pos.z
	var dt := (o.z - wall_hz) / maxf(-v.z, 0.01)
	var p := logic.trajectory(o, v, dt, wind_x)
	if p.y < 0.02:
		# It drops into the floor first: solve for y = 0 on the way.
		var g := logic.gravity()
		var a := -0.5 * g
		var disc := v.y * v.y - 4.0 * a * o.y
		if g > 0.0 and disc >= 0.0:
			var tf := (-v.y - sqrt(disc)) / (2.0 * a)
			if tf > 0.0 and tf < dt:
				dt = tf
				p = logic.trajectory(o, v, dt, wind_x)
				return {"p": shot.to_world(p), "t": t0 + dt, "floor": true}
	return {"p": shot.to_world(p), "t": t0 + dt, "floor": false}

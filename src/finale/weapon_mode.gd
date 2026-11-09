class_name FinaleWeapon
extends Node3D
## Base for the Bottle Shot weapons other than knives. BottleShot owns the stash, the bottles,
## the clock (_ft, slowed by _scale), the HUD and the shatter; a weapon owns input, the
## camera (it writes shot._cam / _fov / _focus / _blur), its model and its projectiles.
## Rules come from BottleLogic.fire (hero space: hero at the origin, floor at y = 0, -Z ahead).
## When a shot's film is over the weapon calls shot.shot_over().

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


func setup(s: BottleShot) -> FinaleWeapon:
	shot = s
	logic = s.logic
	world = s.world
	wcfg = logic.wcfg
	# Start aimed at the middle of the bottle set.
	var mid := Vector3(0, _mid_y(), -logic.distance)
	var d := mid - eye_h()
	yaw = atan2(-d.x, -d.z)
	pitch = atan2(d.y, Vector2(d.x, d.z).length())
	return self


func _mid_y() -> float:
	var lo := INF
	var hi := -INF
	for b in logic.layout["bottles"]:
		lo = minf(lo, float(b["y"]))
		hi = maxf(hi, float(b["y"]))
	return (lo + hi) * 0.5


## The eye in hero space (a little ahead of the hero's face, so his head never fills the lens).
func eye_h() -> Vector3:
	return Vector3(0.0, float(wcfg.get("eye_y", 1.6)), -0.35)


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
	kick = 0.0


func rest_view() -> Transform3D:
	return Transform3D(view_basis(), eye())


func rest_fov() -> float:
	return float(wcfg.get("fov", 34.0))


## Drag deltas in pixels -> aim (degrees per pixel = sens).
func drag_aim(rel: Vector2, sens: float) -> void:
	yaw -= deg_to_rad(rel.x * sens)
	pitch = clampf(pitch - deg_to_rad(rel.y * sens), deg_to_rad(-30.0), deg_to_rad(30.0))


## Shared touch parsing: returns {kind: down|drag|up, pos, rel} or {}.
func touch(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_touch = true
			_last = e.position
			return {"kind": "down", "pos": e.position, "rel": Vector2.ZERO}
		if _touch:
			_touch = false
			return {"kind": "up", "pos": e.position, "rel": e.position - _last}
	elif event is InputEventScreenDrag and _touch:
		var e := event as InputEventScreenDrag
		var rel := e.position - _last
		_last = e.position
		return {"kind": "drag", "pos": e.position, "rel": rel}
	return {}


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
	visible = false


# ---------------------------------------------------------------- helpers

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


static func place_streak(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var l := maxf(a.distance_to(b), 0.001)
	var z := (a - b) / l
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	mi.global_transform = Transform3D(Basis(x, z.cross(x), z).scaled(Vector3(1, 1, l)), (a + b) * 0.5)


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

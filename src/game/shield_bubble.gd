class_name ShieldBubble
extends MeshInstance3D
## The squad's shield in the street: a clear bubble over the formation the player sees.
## A fresnel rim with a clear centre (troops keep their true colours), a slow hex shimmer and
## a gentle pulse (shield_bubble.gdshader). It pops in when the sim's shield goes up, ripples
## where blocked fire, firebombs and charging gangs hit it, blinks in its last second (the
## sim's own timer: honest), and bursts away the moment the shield ends.
## Sized to the formation's real figures every frame (feet and heads inside), so it grows
## with the squad. One unit sphere scaled to the bubble's radii and sitting on the road (the
## road hides the rest): one draw, no screen reads.
## LevelView keeps a small hook: update() each frame, hit() for blocked shots.
## Numbers: config/world_look.json "shield_bubble".

const SHADER := preload("res://src/game/shield_bubble.gdshader")
const HITS := 4

static var _look: Dictionary = {}

var centre := Vector3.ZERO      # the bubble's base centre on the road
var radii := Vector3.ONE        # its half width (x), height (y) and half depth (z)
var _cfg: Dictionary = {}
var _fx: Node = null
var _mat: ShaderMaterial
var _t := 0.0                   # the street's clock, for the shimmer
var _state := "off"             # off, on, burst
var _age := 0.0                 # seconds in the current state
var _prev_shield := 0.0
var _hits := PackedVector4Array()
var _sized := false
var _last_hit_t := -INF


## config/world_look.json "shield_bubble", loaded once.
static func look() -> Dictionary:
	if _look.is_empty():
		var data: Variant = Config.load_json(World.LOOK_PATH)
		if data is Dictionary:
			_look = (data as Dictionary).get("shield_bubble", {})
	return _look


## The smallest bubble that holds every figure, head to toe. `points` are figures as
## Vector3(x, top, z) on the road. A bubble sitting on the road: an ellipsoid whose centre is
## cfg.lift of the tallest top up (its widest girth around the figures' bodies, so a tall
## figure near the edge still fits), reaching cfg.head above the tallest top. Its girth ellipse
## holds every figure's feet (padded by cfg.pad), then widens until each figure's feet and top
## are inside too. A lone hero gets cfg.min_r. The road cuts off what is below it.
## Returns {"centre": Vector3(x, lift height, z), "radii": Vector3(half width, half height,
## half depth)}.
static func fit(points: Array, cfg: Dictionary) -> Dictionary:
	var pad := float(cfg.get("pad", 0.3))
	var min_r := float(cfg.get("min_r", 1.0))
	var head := float(cfg.get("head", 0.45))
	var lift := float(cfg.get("lift", 0.5))
	if points.is_empty():
		return {"centre": Vector3.ZERO, "radii": Vector3(min_r, min_r + head, min_r)}
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	var top := 0.0
	for p in points:
		lo = Vector3(minf(lo.x, p.x), 0.0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0.0, maxf(hi.z, p.z))
		top = maxf(top, p.y)
	var cy := top * lift
	var c := Vector3((lo.x + hi.x) * 0.5, cy, (lo.z + hi.z) * 0.5)
	var hx := maxf((hi.x - lo.x) * 0.5, 0.001)
	var hz := maxf((hi.z - lo.z) * 0.5, 0.001)
	# The ground ellipse with the box's proportions that holds every centre, then the pad.
	var s := 0.0
	for p in points:
		s = maxf(s, Vector2((p.x - c.x) / hx, (p.z - c.z) / hz).length())
	var a := hx * s + pad
	var b := hz * s + pad
	var ry := top - cy + head
	# Widen until each figure is inside at its feet and its top: (q/u)^2 + (dy/ry)^2 <= 1 for a
	# figure at girth radius q whose feet are cy below the centre and its top p.y - cy above it.
	var u := 1.0
	for p in points:
		# A figure is `pad` wide either side: its outermost side in the girth ellipse.
		var dx := absf(p.x - c.x)
		var dz := absf(p.z - c.z)
		var q := maxf(Vector2((dx + pad) / a, dz / b).length(), Vector2(dx / a, (dz + pad) / b).length())
		var dy := maxf(cy, absf(p.y - cy))
		var room := sqrt(maxf(1.0 - pow(dy / ry, 2.0), 0.0001))
		u = maxf(u, q / room)
	var rx := maxf(a * u, min_r)
	var rz := maxf(b * u, min_r)
	# A bubble, not a capsule: neither half axis below `round` of the other (only ever grows).
	var k := float(cfg.get("round", 0.0))
	return {"centre": c, "radii": Vector3(maxf(rx, rz * k), ry, maxf(rz, rx * k))}


## Where the line from `from` to `to` enters the dome (centre c, radii r), as a fraction of
## the way (0..1), or -1 if it never does.
static func ray_entry(c: Vector3, r: Vector3, from: Vector3, to: Vector3) -> float:
	var o := (from - c) / r
	var dv := (to - from) / r
	var qa := dv.dot(dv)
	if qa <= 0.0:
		return -1.0
	var qb := 2.0 * o.dot(dv)
	var qc := o.dot(o) - 1.0
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return -1.0
	var t0 := (-qb - sqrt(disc)) / (2.0 * qa)
	return t0 if t0 >= 0.0 and t0 <= 1.0 else -1.0


## Honest last second: full strength until blink_s is left, then a steady on/off blink.
static func blink(shield_t: float, cfg: Dictionary) -> float:
	if shield_t >= float(cfg.get("blink_s", 1.0)):
		return 1.0
	var phase := fposmod(shield_t * float(cfg.get("blink_hz", 5.0)), 1.0)
	return 1.0 if phase >= 0.5 else float(cfg.get("blink_low", 0.25))


## Size at u (0..1) of the pop-in: from pop_from up past full size and back (ease-out-back).
static func pop_scale(u: float, cfg: Dictionary) -> float:
	var x := clampf(u, 0.0, 1.0) - 1.0
	var c1 := float(cfg.get("pop_back", 1.70158))
	var e := 1.0 + (c1 + 1.0) * x * x * x + c1 * x * x
	return lerpf(float(cfg.get("pop_from", 0.55)), 1.0, e)


static func _col(v: Variant, fallback: Color) -> Color:
	return Color(String(v)) if v is String else fallback


func setup(fx_node: Node = null) -> ShieldBubble:
	_cfg = look()
	_fx = fx_node
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = int(_cfg.get("segments", 40))
	sm.rings = int(_cfg.get("rings", 12))
	mesh = sm
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("rim_color", _col(_cfg.get("rim"), Color(0.5, 0.95, 1.0)))
	_mat.set_shader_parameter("edge_color", _col(_cfg.get("edge"), Color.WHITE))
	for k in ["rim_power", "rim_alpha", "rim_top", "base_alpha", "contact", "contact_m", "hex_cells", "hex_alpha", "scan_speed", "pulse_hz",
			"pulse", "hit_reach", "hit_width", "back_wall"]:
		if _cfg.has(k):
			_mat.set_shader_parameter(k, float(_cfg[k]))
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_hits.resize(HITS)
	for i in HITS:
		_hits[i] = Vector4(0, 1, 0, 1)
	_push_hits()
	visible = false
	return self


## Pre-warm (LevelView._prewarm): a copy drawn once out of sight so the shader compiles while
## the level loads, not on the first press.
func show_warm(at: Vector3) -> void:
	position = at
	scale = Vector3(2.0, 2.4, 2.0)
	visible = true


## True while the shield is up: blocked shots stop on the bubble.
func is_up() -> bool:
	return _state == "on"


## True when world point `p` is within `margin` m of the bubble as drawn (or inside it).
func touches(p: Vector3, margin: float) -> bool:
	var r := radii * scale_now() + Vector3.ONE * margin
	var q := (p - centre) / r
	return is_up() and q.length_squared() <= 1.0


func active_hits() -> int:
	var n := 0
	for h in _hits:
		if h.w < 1.0:
			n += 1
	return n


## A blocked shot from `from` aimed at `to` (world): it stops where it enters the bubble,
## which ripples there. Returns the point the shot ends at (`to` when no bubble is up).
func hit(from: Vector3, to: Vector3) -> Vector3:
	if not is_up():
		return to
	var p := entry(from, to)
	_add_hit(p, radii * scale_now())
	return p


## A shot still in the air (incoming tracers take about 1 s) lands on the bubble at world
## point `p`, which ripples there (where it is now: the bubble moved with the squad).
func ripple_at(p: Vector3) -> void:
	if is_up():
		_add_hit(p, radii * scale_now())


## Where a shot from `from` aimed at `to` would stop on the bubble as it is now, without a
## ripple (`to` when no bubble is up).
func entry(from: Vector3, to: Vector3) -> Vector3:
	if not is_up():
		return to
	var r := radii * scale_now()
	var u := ray_entry(centre, r, from, to)
	var p: Vector3
	if u < 0.0:
		# Aimed past it: end on the surface towards the shooter.
		var dir := from - centre
		var k := 1.0 / maxf(Vector3(dir.x / r.x, dir.y / r.y, dir.z / r.z).length(), 0.0001)
		p = centre + dir * k
	else:
		p = from.lerp(to, u)
	p.y = maxf(p.y, 0.15)
	return p


func _add_hit(p: Vector3, r: Vector3) -> void:
	# A gang firing every frame would recycle the ripples before they spread: at most HITS
	# new ripples per ripple life, so each one runs its whole course.
	var hit_s := maxf(float(_cfg.get("hit_s", 0.45)), 0.01)
	if _t - _last_hit_t < hit_s / HITS:
		return
	_last_hit_t = _t
	var local := ((p - centre) / r).normalized()
	var oldest := 0
	for i in HITS:
		if _hits[i].w > _hits[oldest].w:
			oldest = i
	_hits[oldest] = Vector4(local.x, local.y, local.z, 0.0)
	_push_hits()
	if _fx != null and _fx.has_method("burst"):
		_fx.burst(p, Color(String(_cfg.get("rim", "8ff4ff"))), 5, 3.5, 0.12, 0.25, 1.0, 4.0)


func _push_hits() -> void:
	if _mat != null:
		_mat.set_shader_parameter("hits", _hits)


## The size factor right now (pop-in, the gentle breathing, the burst).
func scale_now() -> float:
	match _state:
		"on":
			var pop := pop_scale(_age / maxf(float(_cfg.get("pop_s", 0.28)), 0.01), _cfg)
			return pop * (1.0 + float(_cfg.get("breathe", 0.015)) * sin(_t * float(_cfg.get("pulse_hz", 1.2)) * TAU))
		"burst":
			var u := clampf(_age / maxf(float(_cfg.get("burst_s", 0.3)), 0.01), 0.0, 1.0)
			return lerpf(1.0, float(_cfg.get("burst_grow", 1.22)), 1.0 - pow(1.0 - u, 2.0))
	return 1.0


## Each frame: `shield_t` = the sim's shield seconds left (0 when none, or when the level is
## no longer running), `allies` = LevelView's figures ({kind, pos}), their heights.
func update(d: float, shield_t: float, allies: Array, hero_h: float, troop_h: float) -> void:
	_t += d
	_age += d
	if shield_t > 0.0 and (_state != "on" or shield_t > _prev_shield + 0.05):
		if _state != "on":
			_sized = false
		_state = "on"
		_age = 0.0
	elif shield_t <= 0.0 and _state == "on":
		_state = "burst"
		_age = 0.0
		if _fx != null and _fx.has_method("burst"):
			_fx.burst(centre, Color(String(_cfg.get("rim", "8ff4ff"))), 26, 7.0, 0.16, 0.4, 2.0, 6.0)
	elif _state == "burst" and _age >= float(_cfg.get("burst_s", 0.3)):
		_state = "off"
	_prev_shield = shield_t
	visible = _state != "off"
	if not visible:
		return
	# Follow the formation the player sees: centre at once, size eased. A figure's top is its
	# raised hand or gun (the hero throws overhead).
	var top_hero := hero_h * float(_cfg.get("hero_top", 1.0))
	var top_troop := troop_h * float(_cfg.get("troop_top", 1.0))
	var pts: Array = []
	for a in allies:
		var p: Vector3 = a["pos"]
		pts.append(Vector3(p.x, top_hero if a["kind"] == "hero" else top_troop, p.z))
	var f := fit(pts, _cfg)
	var want: Vector3 = f["radii"]
	if not _sized:
		radii = want
		centre = f["centre"]
		_sized = true
		if _fx != null and _fx.has_method("ring"):
			_fx.ring(Vector3(centre.x, 0.2, centre.z), Color(String(_cfg.get("rim", "8ff4ff"))), 32, 6.0, 0.16)
	else:
		# Grows at once (a figure never pokes out), shrinks gently as the squad thins; an eased
		# centre that lags behind the fit grows the bubble by the lag, so it still holds them.
		var k := 1.0 - exp(-d * float(_cfg.get("ease", 6.0)))
		var fc: Vector3 = f["centre"]
		centre = Vector3(fc.x, lerpf(centre.y, fc.y, k), lerpf(centre.z, fc.z, k))
		radii = radii.lerp(want, k).max(want + Vector3(0.0, absf(centre.y - fc.y), absf(centre.z - fc.z)))
	position = centre
	scale = radii * scale_now()
	# Ripples age; the look fades in, blinks in the last second, flashes on pop and burst.
	var hit_s := maxf(float(_cfg.get("hit_s", 0.45)), 0.01)
	var aged := false
	for i in HITS:
		if _hits[i].w < 1.0:
			var h := _hits[i]
			h.w = minf(h.w + d / hit_s, 1.0)
			_hits[i] = h
			aged = true
	if aged:
		_push_hits()
	var fade := 1.0
	var flash := 0.0
	if _state == "on":
		var pop_u := clampf(_age / maxf(float(_cfg.get("pop_s", 0.28)), 0.01), 0.0, 1.0)
		fade = minf(pop_u * 2.0, 1.0) * blink(shield_t, _cfg)
		flash = 1.0 - pop_u
	else:
		var bu := clampf(_age / maxf(float(_cfg.get("burst_s", 0.3)), 0.01), 0.0, 1.0)
		fade = pow(1.0 - bu, 2.0)
		flash = 1.0 - bu
	_mat.set_shader_parameter("t", _t)
	_mat.set_shader_parameter("fade", fade)
	_mat.set_shader_parameter("flash", flash)

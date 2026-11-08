class_name BottleShot
extends Node3D
## End-of-level Bottle Shot. The hero gets one knife per bottle; drag to aim at the bottle
## wall, release to throw. Each throw is a little film:
##   1. a side-on tracking shot right beside the spinning knife, in slow motion, with the
##      bottles growing behind it;
##   2. ~0.15 s before contact, a cut to a front three-quarter close-up of the target;
##   3. on contact time snaps back to full speed and the bottle bursts into glass shards and
##      a short spray of the drink (streaks only, no droplet balls); the knife buries itself
##      in the planks behind. A miss thunks into the wood and the camera holds on it.
## Rules (hits, multiplier, coins) live in BottleLogic and are decided at the throw.

signal done(result: Dictionary)

const SLOW := 0.2               # time scale while a knife flies
const SLOW_IN := 0.12           # real seconds to ease into the slow motion
const CUT_LEAD := 0.15          # real seconds before contact: cut to the close-up
const HIT_STOP := 0.045         # real seconds the frame freezes on contact
const HOLD_HIT := 0.85          # real seconds on the close-up after a bottle breaks
const HOLD_MISS := 0.3          # real seconds on the stuck knife after a miss
const ARC := 0.25               # metres the knife rises mid-flight
const SPIN_PER_S := 4.2         # knife turns per second of (game) flight
const NORMAL_VIEW := Vector3(0.35, 1.85, 1.5)  # just over the hero's shoulder
const AIM_FOV := 34.0           # telephoto: the bottle wall fills the screen
const TRACK_FOV := 52.0
const CLOSE_FOV := 40.0
const NEAR := 0.04              # close-ups need a near clip plane right by the lens
const TRACK_SIDE := 0.3        # tracking camera: metres beside the flight line
const TRACK_BACK := 0.45        # ... and behind the knife
const TRACK_LEAD := 0.3        # it looks this far ahead of the knife
const CLOSE_DIST := 1.3         # close-up distance from the bottle
const CLOSE_DOLLY := 0.5       # extra pull-back while the glass flies
const BOTTLE_SCALE := 1.3
const STAGE_KNIFE_IN := 0.04    # metres a stuck knife's tip sinks into the planks

var logic: BottleLogic
var world: World
var fx: Fx
var font: Font
var troops := 0
var station_bonus := 0.0
var hero_pos := Vector3.ZERO
var on_throw: Callable        # LevelView plays the hero's throw animation

var _wall_z := -7.5
var _wall_front := -7.475
var _ft := 0.0                # finale clock (game time; slows down in slow motion)
var _scale := 1.0             # current time scale
var _bottles: Array = []      # Node3D per bottle
var _glows: Array = []        # caustic blob (and halo) per bottle
var _rack: Node3D
var _reticle: MeshInstance3D
var _aim := Vector2(0, 1.8)
var _aiming := false
var _knife: Node3D = null
var _knife_from := Vector3.ZERO
var _knife_to := Vector3.ZERO   # aimed point (BottleLogic's line)
var _knife_end := Vector3.ZERO  # where the knife's balance point stops (tip in the wood)
var _knife_dir := Vector3.FORWARD
var _knife_t0 := 0.0
var _knife_t1 := 0.0
var _knife_hit := -1
var _t_contact := 0.0
var _k_contact := 1.0
var _contacted := false
var _turns := 2.0
var _real := 0.0              # real seconds since the throw
var _hitstop := 0.0
var _cam := Transform3D()
var _cam_mode := "aim"        # aim | track | close
var _close_target := Vector3.ZERO
var _close_t := 0.0           # real seconds since the cut
var _side := 1.0              # which side the close-up camera sits on
var _roll := 0.0
var _track_h := 0.05
var _fov := AIM_FOV
var _aim_fov := AIM_FOV
var _aim_focus := 6.0
var _focus := 6.0
var _blur := 0.1
var _state := "aim"           # aim | flying | impact | tally | finished
var _wait := 0.0
var _throw_n := 0
var _shatters: Array = []
var _stuck: Array = []
var _quiver: Array = []       # {node, tip, basis, t, amp}
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_mat: StandardMaterial3D
var _trail_pts: Array = []    # {p, t}
var _trail_color := Color(0.85, 0.95, 1.0)
var _blade_color := Color("e6eaf0")
var _cord_color := Color(0.55, 0.1, 0.12)
var _later: Array = []        # {t, id, vol}: sounds scheduled in real time
var _dust_mat: ShaderMaterial
var _ui: CanvasLayer
var _knife_icons: Array = []
var _mult_root: Control
var _mult_label: Label
var _rays: Rays
var _flash: ColorRect
var _mult_shown := 1.0
var _mult_from := 1.0
var _mult_to := 1.0
var _mult_t := 1.0
var _punch := 0.0
var _punch_gold := false


## Sunburst behind the multiplier when it jumps.
class Rays extends Control:
	var color := Color(1.0, 0.85, 0.3, 0.0)
	var spin := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := maxf(size.x, size.y) * 0.5
		for i in 14:
			var a := spin + TAU * i / 14.0
			var w := 0.09 if i % 2 == 0 else 0.05
			var pts := PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * r, c + Vector2(cos(a + w), sin(a + w)) * r])
			draw_colored_polygon(pts, color)


func setup(w: World, f: Fx, fnt: Font, level_id: int, troop_count: int, hero: Vector3, bonus: float) -> BottleShot:
	world = w
	fx = f
	font = fnt
	troops = troop_count
	hero_pos = hero
	station_bonus = bonus
	var cfg: Dictionary = Config.load_json("res://config/finale.json")
	logic = BottleLogic.new(cfg, level_id)
	_wall_z = hero.z + float(cfg["wall_z"])
	_wall_front = _wall_z + 0.025
	return self


func _ready() -> void:
	var ks: Dictionary = Game.knife_skin()
	_blade_color = Color(String(ks.get("blade", "e6eaf0")))
	if String(ks.get("trail", "")) != "":
		_trail_color = Color(String(ks["trail"]))
		_cord_color = _trail_color.darkened(0.35)
	_build_wall()
	_build_trail()
	_build_ui()
	_aim_lens()
	_fov = _aim_fov
	_focus = _aim_focus
	_cam = _aim_view()
	_apply_camera()
	Sfx.play("swoosh")


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _state != "aim":
		return
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
		pressed = true
	else:
		return
	if pressed:
		_aiming = true
		_aim = _screen_to_wall(pos)
	elif released and _aiming:
		_aiming = false
		_aim = _screen_to_wall(pos)
		throw_at(_aim)


func _screen_to_wall(p: Vector2) -> Vector2:
	var cam := world.camera
	var from := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	if absf(dir.z) < 0.001:
		return _aim
	var t := (_wall_z - from.z) / dir.z
	var hit := from + dir * t
	return Vector2(clampf(hit.x - hero_pos.x, -2.4, 2.4), clampf(hit.y, 0.6, 3.6))


## Throws a knife at a wall point (x relative to the hero, y = height). Also used by autoplay.
func throw_at(aim: Vector2) -> void:
	if _state != "aim" or logic.knives_left <= 0:
		return
	_knife_from = hero_pos + Vector3(0.25, 1.45, -0.4)
	_knife_to = Vector3(hero_pos.x + aim.x, aim.y, _wall_z + 0.12)
	var flight := logic.flight_time(_knife_from.distance_to(_knife_to))
	_knife_t0 = _ft
	_knife_t1 = _ft + flight
	_knife_hit = logic.throw(aim, _knife_t1)
	_knife_dir = (_knife_to - _knife_from).normalized()
	# The tip ends buried in the planks on the same line; the balance point sits TIP behind.
	var tip := _knife_from + _knife_dir * ((_wall_front - STAGE_KNIFE_IN - _knife_from.z) / _knife_dir.z)
	_knife_end = tip - _knife_dir * FinaleKnife.TIP
	_turns = maxf(1.0, round(flight * SPIN_PER_S))
	_t_contact = _knife_t1
	_k_contact = 1.0
	if _knife_hit >= 0:
		# Contact = the tip reaching the front of the bottle (it carries on into the wall).
		var front_z := _wall_z + 0.25 + _bottle_radius(_knife_hit)
		var centre_z := front_z - _knife_dir.z * FinaleKnife.TIP
		var k := clampf((_knife_from.z - centre_z) / maxf(_knife_from.z - _knife_end.z, 0.01), 0.0, 1.0)
		_t_contact = _knife_t0 + k * flight
		_k_contact = maxf(k, 0.05)
	_contacted = false
	_knife = FinaleKnife.make(_blade_color, _cord_color)
	add_child(_knife)
	_knife.position = _knife_from
	_knife.basis = Basis.looking_at(_knife_dir, Vector3.UP)
	_trail_pts.clear()
	_throw_n += 1
	_side = 1.0 if _throw_n % 2 == 1 else -1.0
	_roll = 0.09 * _side
	_track_h = 0.06 if _throw_n % 2 == 1 else -0.04
	_state = "flying"
	_cam_mode = "track"
	_real = 0.0
	_scale = 1.0
	_reticle.visible = false
	_cam = _track_view(_knife_from)
	_fov = TRACK_FOV
	_blur = 0.05
	_update_icons()
	Sfx.play("knife", 2.0)
	Sfx.play("swoosh", -4.0, 0.55)
	if on_throw.is_valid():
		on_throw.call()


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if _state == "finished":
		return
	_tick_sounds(delta)
	_tick_ui(delta)
	var d := delta * _scale
	if _hitstop > 0.0:
		_hitstop -= delta
		d = 0.0
	_ft += d
	_move_bottles()
	var cam_pos := world.camera.global_position
	for s in _shatters:
		(s as Shatter).tick(d, cam_pos)
	_tick_quiver(delta)
	if _dust_mat:
		_dust_mat.set_shader_parameter("t", _ft)
	match _state:
		"aim":
			_reticle.visible = true
			_reticle.position = Vector3(hero_pos.x + _aim.x, _aim.y, _wall_z + 0.3)
			_reticle.rotation.z += delta * 2.0
			var k := minf(delta * 6.0, 1.0)
			_cam = _cam.interpolate_with(_aim_view(), k)
			_fov = lerpf(_fov, _aim_fov, k)
			_focus = lerpf(_focus, _aim_focus, k)
			_blur = lerpf(_blur, 0.1, k)
			_roll = 0.0
		"flying":
			_fly(delta)
		"impact":
			_wait -= delta
			_close_t += delta
			_cam = _close_view()
			if _wait <= 0.0:
				if logic.knives_left > 0 and logic.broken_count() + logic.broken_count(true) < logic.count():
					_state = "aim"
					_cam_mode = "aim"
					_aim_lens()
				else:
					_state = "tally"
					_cam_mode = "aim"
					_wait = 1.0
					Sfx.play("win")
		"tally":
			_wait -= delta
			var k := minf(delta * 3.0, 1.0)
			_cam = _cam.interpolate_with(_aim_view(), k)
			_fov = lerpf(_fov, _aim_fov, k)
			_focus = lerpf(_focus, _aim_focus, k)
			if _wait <= 0.0:
				_state = "finished"
				world.set_camera_override(null)
				world.set_lens(-1.0)
				_ui.queue_free()
				done.emit({"broken": logic.broken_count(), "gold": logic.broken_count(true),
					"mult": logic.multiplier(), "coins": logic.coins(troops, station_bonus)})
				return  # the camera is handed back; don't take it again below
	_apply_camera()


func _fly(delta: float) -> void:
	_real += delta
	if not _contacted:
		_scale = lerpf(1.0, SLOW, smoothstep(0.0, SLOW_IN, _real))
	var k := clampf((_ft - _knife_t0) / maxf(_knife_t1 - _knife_t0, 0.001), 0.0, 1.0)
	var p := _knife_from.lerp(_knife_end, k) + Vector3.UP * sin(k * PI) * ARC
	_knife.position = p
	# End over end, tip first again exactly when it reaches the bottle (or the wall).
	var spin := (1.0 - minf(k / _k_contact, 1.0)) * _turns * TAU
	_knife.basis = Basis.looking_at(_knife_dir, Vector3.UP) * Basis(Vector3.RIGHT, spin)
	_push_trail(p)
	if not _contacted:
		var left_real := (_t_contact - _ft) / maxf(_scale, 0.05)
		if _cam_mode == "track" and left_real <= CUT_LEAD:
			_cut_to_close()
		if _ft >= _t_contact:
			_contact()
	match _cam_mode:
		"track":
			_cam = _track_view(p)
			_focus = (_cam.origin.distance_to(p)) + 1.2
		"close":
			_close_t += delta
			_cam = _close_view()
	if k >= 1.0:
		_stick()


func _cut_to_close() -> void:
	_cam_mode = "close"
	_close_t = 0.0
	if _knife_hit >= 0:
		_close_target = _bottle_center(_knife_hit, _t_contact)
	else:
		_close_target = _knife_end + _knife_dir * FinaleKnife.TIP + Vector3(0, 0, 0.03)
	_fov = CLOSE_FOV
	_blur = 0.06
	_roll = 0.0
	_cam = _close_view()
	_focus = CLOSE_DIST + 0.6


func _contact() -> void:
	_contacted = true
	_scale = 1.0
	if _knife_hit < 0:
		return
	var i := _knife_hit
	var b: Node3D = _bottles[i]
	_close_target = _bottle_center(i, _ft)
	var gold := logic.is_gold(i)
	var motion := String(logic.layout.get("motion", "static"))
	var shelf := {}
	if motion == "static":
		shelf = {"y": b.global_position.y, "x0": hero_pos.x - 2.0, "x1": hero_pos.x + 2.0,
			"z0": _wall_z - 0.03, "z1": _wall_z + 0.47}
	var neck: Node3D
	if motion == "swing":
		# Hanging bottles keep their neck on the string; it swings on alone.
		neck = BottleMesh.break_apart(b, false, true)
		b.add_child(neck)
		neck.position.y = float(neck.get_meta("pivot", 0.4))
		neck = null
	else:
		neck = BottleMesh.break_apart(b, true, true)
	for g in _glows[i]:
		(g as Node3D).visible = false
	var shape := int(b.get_meta("shape", 0))
	var sh := Shatter.new().setup(b.global_position, BOTTLE_SCALE, _knife_dir, BottleMesh.glass_color(b),
		BottleMesh.drink_color(b), gold, _wall_front, shelf, neck, BottleMesh.height(shape))
	add_child(sh)
	_shatters.append(sh)
	_hitstop = HIT_STOP
	_flash.color.a = 0.32 if gold else 0.22
	world.shake(0.22)
	Sfx.play("glass_break", 2.0)
	_later.append({"t": 0.3, "id": "glass_tinkle", "vol": -3.0})
	Sfx.play("coin", -4.0, 1.2)
	Game.vibrate(60)
	if gold:
		fx.confetti(_close_target, 46)
		Game.vibrate(120)
	_set_multiplier(logic.multiplier(), gold)


func _stick() -> void:
	_knife.position = _knife_end
	var base := Basis.looking_at(_knife_dir, Vector3.UP)
	var tilt := 0.0 if _knife_hit >= 0 else randf_range(-0.12, 0.12)
	base = base * Basis(Vector3.UP, tilt)
	_knife.basis = base
	var tip := _knife_end + _knife_dir * FinaleKnife.TIP
	_quiver.append({"node": _knife, "tip": tip, "basis": base, "t": 0.0, "amp": 0.16 if _knife_hit < 0 else 0.09})
	_stuck.append(_knife)
	if _knife_hit >= 0:
		Sfx.play("thunk", -8.0)
		fx.burst(tip + Vector3(0, 0, 0.02), Color(0.55, 0.38, 0.22), 4, 1.6, 0.012, 0.3)
	else:
		Sfx.play("thunk", 2.0)
		fx.burst(tip + Vector3(0, 0, 0.02), Color(0.55, 0.38, 0.22), 9, 2.0, 0.015, 0.35)
		world.shake(0.12)
		if _cam_mode != "close":
			_cut_to_close()
	_knife = null
	_trail_pts.clear()
	_draw_trail()
	_scale = 1.0
	_state = "impact"
	_wait = HOLD_HIT if _knife_hit >= 0 else HOLD_MISS


## Stuck knives quiver for a moment, pivoting on the buried tip.
func _tick_quiver(delta: float) -> void:
	var i := 0
	while i < _quiver.size():
		var q: Dictionary = _quiver[i]
		q["t"] = float(q["t"]) + delta
		var t := float(q["t"])
		var node: Node3D = q["node"]
		if t > 0.6 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.basis = q["basis"]
				node.position = (q["tip"] as Vector3) - node.basis * Vector3(0, 0, -FinaleKnife.TIP)
			_quiver.remove_at(i)
			continue
		var a := float(q["amp"]) * exp(-t * 9.0) * sin(t * 62.0)
		node.basis = (q["basis"] as Basis) * Basis(Vector3.RIGHT, a)
		node.position = (q["tip"] as Vector3) - node.basis * Vector3(0, 0, -FinaleKnife.TIP)
		i += 1


func _tick_sounds(delta: float) -> void:
	var i := 0
	while i < _later.size():
		var s: Dictionary = _later[i]
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) <= 0.0:
			Sfx.play(String(s["id"]), float(s["vol"]))
			_later.remove_at(i)
			continue
		i += 1


# ---------------------------------------------------------------- cameras

func _apply_camera() -> void:
	var xf := _cam
	if _roll != 0.0:
		xf.basis = xf.basis * Basis(Vector3(0, 0, 1), _roll)
	world.set_camera_override(xf)
	world.set_lens(_fov, _focus, NEAR, _blur)


## Telephoto lens framing this level's bottles (plus their motion) edge to edge.
func _aim_lens() -> void:
	var extent := 0.0
	for b in logic.layout["bottles"]:
		extent = maxf(extent, absf(float(b["x"])))
	extent += float(logic.layout.get("amp", 0.0)) + 0.55
	var d := _aim_view().origin.distance_to(Vector3(hero_pos.x, 1.8, _wall_z))
	_aim_fov = clampf(rad_to_deg(2.0 * atan(extent / d)), 22.0, AIM_FOV)
	_aim_focus = d + 0.4


func _aim_view() -> Transform3D:
	var eye := hero_pos + NORMAL_VIEW
	var look := Vector3(hero_pos.x, 1.75, _wall_z)
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


## Beside and a little behind the knife, looking ahead of it so the knife sits big in the
## foreground and the bottle wall fills the background.
func _track_view(p: Vector3) -> Transform3D:
	var side := _knife_dir.cross(Vector3.UP).normalized()
	var eye := p + side * TRACK_SIDE - _knife_dir * TRACK_BACK + Vector3.UP * _track_h
	var look := p + _knife_dir * TRACK_LEAD
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


## Front three-quarter close-up of the target (bottle or wall spot); pulls back slowly
## after contact so the flying glass stays in frame.
func _close_view() -> Transform3D:
	var dolly := 0.0
	if _contacted and _knife_hit >= 0:
		dolly = CLOSE_DOLLY * (1.0 - pow(1.0 - clampf(_close_t / HOLD_HIT, 0.0, 1.0), 2.0))
	var dist := (CLOSE_DIST if _knife_hit >= 0 else 0.85) + dolly
	# A miss is filmed more from the side, so the knife sticking out of the planks reads.
	var off := (Vector3(-_side * 0.55, 0.14, 0.85) if _knife_hit >= 0 else Vector3(-_side * 0.8, 0.12, 0.6)).normalized() * dist
	var target := _close_target
	if _knife_hit >= 0 and not _contacted:
		target = _bottle_center(_knife_hit, _ft)
	var eye := target + off
	return Transform3D(Basis.looking_at(target + Vector3(0, 0.06, 0) - eye, Vector3.UP), eye)


# ---------------------------------------------------------------- bottles

func _bottle_world(i: int, t: float) -> Vector3:
	var p := logic.position(i, t)
	return Vector3(hero_pos.x + p.x, p.y - 0.4, _wall_z + 0.25)


func _bottle_center(i: int, t: float) -> Vector3:
	var b: Node3D = _bottles[i]
	var h := BottleMesh.height(int(b.get_meta("shape", 0))) * BOTTLE_SCALE
	return _bottle_world(i, t) + Vector3(0, h * 0.5, 0)


func _bottle_radius(i: int) -> float:
	var b: Node3D = _bottles[i]
	var r := 0.0
	for p in BottleMesh.SHAPES[int(b.get_meta("shape", 0))]["profile"]:
		r = maxf(r, (p as Vector2).x)
	return r * BOTTLE_SCALE


func _move_bottles() -> void:
	var motion := String(logic.layout.get("motion", "static"))
	for i in _bottles.size():
		var b: Node3D = _bottles[i]
		b.position = _bottle_world(i, _ft)
		if motion == "swing":
			var p := logic.position(i, _ft)
			var base: Dictionary = logic.layout["bottles"][i]
			b.rotation.z = (p.x - float(base["x"])) * -0.5
	if motion == "slide" or motion == "drive":
		_rack.position.x = hero_pos.x + logic.position(0, _ft).x - float(logic.layout["bottles"][0]["x"])


# ---------------------------------------------------------------- build

func _build_wall() -> void:
	var motion := String(logic.layout.get("motion", "static"))
	# Gallery: a warm plank wall with a frame, lit by two spotlights so every bottle throws
	# a shadow on it, a string of glowing bulbs across the top, faint beams with dust.
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(6.4, 4.4, 0.25)
	wall.mesh = wm
	var pm := ShaderMaterial.new()
	pm.shader = load("res://src/finale/planks.gdshader")
	wall.material_override = pm
	wall.position = Vector3(hero_pos.x, 2.0, _wall_z - 0.1)
	add_child(wall)
	for side in [-1, 1]:
		var post := World._box(Vector3(0.3, 4.6, 0.4), Color("3b2414"))
		post.position = Vector3(hero_pos.x + side * 3.25, 2.1, _wall_z)
		add_child(post)
	var beam := World._box(Vector3(6.9, 0.32, 0.45), Color("3b2414"))
	beam.position = Vector3(hero_pos.x, 4.3, _wall_z)
	add_child(beam)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color("ffd98a")
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color("ffc65a")
	bulb_mat.emission_energy_multiplier = 4.0
	for i in 13:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		bulb.mesh = sm
		bulb.material_override = bulb_mat
		var x := -3.0 + i * 0.5
		bulb.position = Vector3(hero_pos.x + x, 4.05 - 0.12 * sin(fposmod(x, 1.0) * PI), _wall_z + 0.3)
		add_child(bulb)
	var spots: Array = []
	for side in [-1, 1]:
		var spot := SpotLight3D.new()
		spot.light_color = Color("ffe2b0")
		spot.light_energy = 3.2
		spot.spot_range = 14.0
		spot.spot_angle = 32.0
		spot.shadow_enabled = true
		spot.position = Vector3(hero_pos.x + side * 2.4, 4.6, _wall_z + 4.0)
		add_child(spot)
		var target := Vector3(hero_pos.x + side * 0.4, 1.8, _wall_z)
		spot.look_at(target, Vector3.UP)
		spots.append({"pos": spot.position, "dir": (target - spot.position).normalized()})
		_add_beam(spot.position, target, 32.0)
	_add_dust(spots, 32.0)
	_rack = Node3D.new()
	add_child(_rack)
	_rack.position = Vector3(hero_pos.x, 0, 0)
	var heights := {}
	for b in logic.layout["bottles"]:
		heights[snappedf(float(b["y"]) - 0.4, 0.01)] = true  # shelf top = the bottle base
	if motion == "swing":
		var bar := World._box(Vector3(4.2, 0.12, 0.12), Color("2b2b2b"))
		bar.position = Vector3(hero_pos.x, 3.2, _wall_z + 0.25)
		add_child(bar)
	else:
		for h in heights:
			var shelf := World._box(Vector3(4.0 if motion == "static" else 2.8, 0.08, 0.5), Color("8a5a32"))
			shelf.position = Vector3(0, float(h) - 0.04, _wall_z + 0.22)
			_rack.add_child(shelf)
	var level_seed := int(logic.layout.get("seed", 0))
	for i in logic.count():
		var gold := logic.is_gold(i)
		var hue := fmod(0.31 + i * 0.17, 1.0)
		var bottle := BottleMesh.make(gold, hue, (i * 3 + level_seed + logic.count()) % 4)
		bottle.scale = Vector3.ONE * BOTTLE_SCALE
		add_child(bottle)
		_bottles.append(bottle)
		var glows: Array = []
		# Caustic: light through the drink pools as a coloured glow on the planks behind.
		var drink := BottleMesh.drink_color(bottle)
		var c := _glow_quad(Vector2(0.34, 0.5), drink.lerp(Color.WHITE, 0.3), 0.28, 0.0)
		c.position = Vector3(0.0, 0.2, -0.17)
		bottle.add_child(c)
		glows.append(c)
		if gold:
			var halo := _glow_quad(Vector2(0.95, 1.1), Color(1.0, 0.78, 0.3), 0.55, 0.35)
			halo.position = Vector3(0.0, 0.32, -0.18)
			bottle.add_child(halo)
			glows.append(halo)
		_glows.append(glows)
		if motion == "swing":
			var string := World._box(Vector3(0.012, 1.0, 0.012), Color("dddddd"))
			string.position = Vector3(0, 0.62 + 0.5, 0)
			bottle.add_child(string)
	_move_bottles()
	_reticle = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.13
	tm.outer_radius = 0.17
	_reticle.mesh = tm
	_reticle.rotation.x = PI * 0.5
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("ff3b3b")
	rm.no_depth_test = true
	_reticle.material_override = rm
	add_child(_reticle)


func _glow_quad(size: Vector2, color: Color, strength: float, pulse: float) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = load("res://src/finale/glow.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("pulse", pulse)
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q


## A faint visible beam from a spotlight to (just short of) the wall.
func _add_beam(from: Vector3, to: Vector3, angle_deg: float) -> void:
	var length := from.distance_to(to) - 0.15
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = tan(deg_to_rad(angle_deg)) * length * 0.85
	cm.height = length
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = load("res://src/finale/light_cone.gdshader")
	m.set_shader_parameter("strength", 0.07)
	m.set_shader_parameter("height", length)
	cone.material_override = m
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	var dir := (to - from).normalized()
	# The cylinder runs along +Y: point its -Y end at the wall.
	var y := -dir
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	cone.global_transform = Transform3D(Basis(x, y, z), from + dir * length * 0.5)


## Dust motes drifting through the two beams (only the ones inside a beam show).
func _add_dust(spots: Array, angle_deg: float) -> void:
	var n := 180
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mm.mesh = qm
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var p := Vector3(hero_pos.x + rng.randf_range(-2.7, 2.7), rng.randf_range(0.7, 4.3), _wall_z + rng.randf_range(0.3, 3.6))
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(hero_pos.x - 3.5, 0.0, _wall_z - 0.5), Vector3(7.0, 5.0, 5.0))
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = load("res://src/finale/dust.gdshader")
	_dust_mat.set_shader_parameter("spot_a", spots[0]["pos"])
	_dust_mat.set_shader_parameter("dir_a", spots[0]["dir"])
	_dust_mat.set_shader_parameter("spot_b", spots[1]["pos"])
	_dust_mat.set_shader_parameter("dir_b", spots[1]["dir"])
	_dust_mat.set_shader_parameter("cos_angle", cos(deg_to_rad(angle_deg * 0.85)))
	mi.material_override = _dust_mat
	add_child(mi)


func _build_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_trail)


## Air streak behind the flying knife: the last few positions (in finale time).
func _push_trail(p: Vector3) -> void:
	_trail_pts.append({"p": p, "t": _ft})
	while _trail_pts.size() > 2 and _ft - float(_trail_pts[0]["t"]) > 0.045:
		_trail_pts.pop_front()
	_draw_trail()


func _draw_trail() -> void:
	_trail_mesh.clear_surfaces()
	var n := _trail_pts.size()
	if n < 2:
		return
	var cam_pos := world.camera.global_position
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
	for i in n:
		var p: Vector3 = _trail_pts[i]["p"]
		var a: Vector3 = _trail_pts[maxi(i - 1, 0)]["p"]
		var b: Vector3 = _trail_pts[mini(i + 1, n - 1)]["p"]
		var tangent := (b - a).normalized()
		var side := tangent.cross((cam_pos - p).normalized())
		if side.length_squared() < 0.000001:
			continue
		var f := float(i) / float(n - 1)
		side = side.normalized() * 0.018 * f
		var c := Color(_trail_color, 0.4 * f * f)
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(p - side)
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(p + side)
	_trail_mesh.surface_end()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(_flash)
	_ui.add_child(_flash)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_top = -170
	row.offset_bottom = -70
	row.offset_left = -180
	row.offset_right = 180
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(row)
	for i in logic.knives_left:
		var icon := UiKit.icon("knife", 84)
		row.add_child(icon)
		_knife_icons.append(icon)
	_mult_root = Control.new()
	_mult_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_mult_root.offset_top = 120
	_mult_root.offset_bottom = 300
	_mult_root.offset_left = -220
	_mult_root.offset_right = 220
	_mult_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_mult_root)
	_rays = Rays.new()
	UiKit.full_rect(_rays)
	_rays.offset_left = 40
	_rays.offset_right = -40
	_rays.offset_top = -60
	_rays.offset_bottom = 60
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mult_root.add_child(_rays)
	_mult_label = UiKit.label("×1", 96, UiKit.GOLD, 18)
	UiKit.full_rect(_mult_label)
	_mult_label.modulate.a = 0.85
	_mult_root.add_child(_mult_label)


func _update_icons() -> void:
	for i in _knife_icons.size():
		(_knife_icons[i] as Control).modulate.a = 1.0 if i < logic.knives_left else 0.2


## The multiplier jumps: it counts up from the old value with a punch, a flash and rays.
func _set_multiplier(m: float, gold: bool) -> void:
	_mult_from = _mult_shown
	_mult_to = m
	_mult_t = 0.0
	_punch = 1.0
	_punch_gold = gold
	_rays.color = Color(1.0, 0.62, 0.15, 0.0) if gold else Color(1.0, 0.9, 0.45, 0.0)
	_mult_label.modulate.a = 1.0


func _tick_ui(delta: float) -> void:
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - delta * 3.0, 0.0)
	if _mult_t < 1.0:
		_mult_t = minf(_mult_t + delta / 0.35, 1.0)
		_mult_shown = lerpf(_mult_from, _mult_to, 1.0 - pow(1.0 - _mult_t, 3.0))
		_mult_label.text = "×%s" % (_fmt(_mult_to) if _mult_t >= 1.0 else "%.1f" % _mult_shown)
	if _punch > 0.0:
		_punch = maxf(_punch - delta / (0.6 if _punch_gold else 0.45), 0.0)
		var big := 1.25 if _punch_gold else 0.9
		var s := 1.0 + big * _punch * _punch + 0.12 * sin(_punch * PI * 4.0) * _punch
		_mult_label.pivot_offset = _mult_label.size * 0.5
		_mult_label.scale = Vector2.ONE * s
		_mult_label.rotation = sin(_punch * 22.0) * 0.1 * _punch
		var ls := _mult_label.label_settings
		ls.font_color = UiKit.GOLD.lerp(Color.WHITE, clampf(_punch * 1.6 - 0.6, 0.0, 1.0))
		_rays.spin += delta * 1.6
		_rays.color.a = 0.75 * _punch
		_rays.pivot_offset = _rays.size * 0.5
		_rays.scale = Vector2.ONE * (0.7 + (1.0 - _punch) * 0.7)
		_rays.queue_redraw()
		if _punch <= 0.0:
			_mult_label.scale = Vector2.ONE
			_mult_label.rotation = 0.0
			ls.font_color = UiKit.GOLD
			_rays.color.a = 0.0
			_rays.queue_redraw()


static func _fmt(m: float) -> String:
	return str(int(m)) if is_equal_approx(m, round(m)) else "%.1f" % m

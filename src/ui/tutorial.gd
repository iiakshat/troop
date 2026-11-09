class_name Tutorial
extends CanvasLayer
## First-run freeze-frame tutorials (spec v1.1 item 11). No words: a ghost hand, a spotlight
## and rings. Each shows once ever (Game seen_hints). In a level the street holds still
## (LevelView.hold) until the player does the thing being taught:
##   swipe     drag to steer (held until the player drags)
##   gate_pick the first gate choice: the best lane is lit (held until the squad is in it)
##   red_gate  the squad lines up with a red gate: bullets fly into it, it ticks up (tap)
##   shield / bomb  the first gang arrives while a charge is ready: the button is lit (tap)
## In Bottle Shot a ghost hand loops each weapon's gesture (once per weapon, the first time
## its district's finale opens) until the first touch; the first shot waits for the player.
## The pistol also gets a one-time swipe-down reload demo. main.gd never creates this under
## autoplay; `tutor=auto` (debug) acts out each step after AUTO_S for screenshots.

const OWNS := ["swipe", "red_gate", "shield", "bomb"]  # level-data hints this replaces (Hud skips them)
const AUTO_S := 1.6
const HAND := 130.0
const TIP := Vector2(0.92, 0.80)    # fingertip in the hand icon (share of its size)
const GATE_Z := -22.0               # a gate row this close (m) opens the gate tutorials
const RED_Z := -48.0                # ... and a red gate this close (just before fire range) opens its own
const GANG_Z := -44.0               # a gang this close (in fire range) opens the power tutorial
const SPOT_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(720.0, 1280.0);
uniform vec2 center = vec2(-9999.0, -9999.0);
uniform vec2 radius = vec2(1.0, 1.0);
uniform float dim = 0.0;
void fragment() {
	vec2 p = UV * rect_size;
	float d = length((p - center) / radius);
	COLOR = vec4(0.02, 0.03, 0.08, dim * smoothstep(0.75, 1.05, d));
}
"""

var view: LevelView
var hud: Hud
var auto := false

var _step := ""
var _t := 0.0
var _played := 0.0
var _lane := -1           # the lane this step wants (gate, red)
var _row_id := -1         # the gate row the gate tutorial used (the red one waits for another)
var _power := ""
var _charges_at := 0
var _touched := false
var _drag_px := 0.0
var _lane_at := 1
var _weapon := ""
var _gesture := ""        # sweep | drag | tap | hold_drag | swipe
var _a := Vector2.ZERO    # gesture start (fingertip)
var _b := Vector2.ZERO    # gesture end
var _ring := Vector2(-1, -1)
var _ring_r := 0.0
var _spot := Vector2(-9999, -9999)
var _spot_r := Vector2.ONE
var _dim := 0.0
var _dim_to := 0.0
var _dots := false        # ghost bullets from _a to _ring (red gate)
var _tip := Vector2.ZERO
var _pressed := false
var _release_t := -1.0    # gesture phase of the last release (burst ring)

var _root: Control
var _shade: ColorRect
var _mat: ShaderMaterial
var _canvas: Control
var _hand: TextureRect
var _icon: TextureRect


func setup(v: LevelView, h: Hud, auto_act := false) -> Tutorial:
	view = v
	hud = h
	auto = auto_act
	return self


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SPOT_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_shade.material = _mat
	_root.add_child(_shade)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_fx)
	_root.add_child(_canvas)
	_icon = UiKit.icon("aim", 96)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	_root.add_child(_icon)
	_hand = TextureRect.new()
	_hand.texture = UiKit.icon_texture("hand")
	_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hand.size = Vector2(HAND, HAND)
	_hand.pivot_offset = TIP * HAND
	_hand.rotation = PI   # the finger points up and left; the hand trails below
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.visible = false
	_root.add_child(_hand)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_touched = true
	elif event is InputEventScreenDrag:
		_drag_px += absf((event as InputEventScreenDrag).relative.x)
	elif event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if k in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]:
			_drag_px += 100.0


# ---------------------------------------------------------------- steps

func _process(delta: float) -> void:
	if view == null or not is_instance_valid(view):
		return
	_dim = move_toward(_dim, _dim_to, delta * 2.5)
	if view.paused:
		_paint()
		return
	_t += delta
	if _step == "":
		_touched = false
		_drag_px = 0.0
		_look()
	else:
		_run_step()
	_paint()


func _seen(id: String) -> bool:
	return Game.hint_seen(id)


## Opens the next tutorial that is due right now, if any.
func _look() -> void:
	if view.finale != null and is_instance_valid(view.finale):
		_look_finale()
		return
	if view.sim == null or view.sim.state != "run" or view._state != "play":
		return
	_played += get_process_delta_time()
	var sim := view.sim
	if not _seen("swipe"):
		if _played > 0.6:
			_begin("swipe", true)
			_lane_at = sim.lane
		return
	var row := _next_row()
	if not row.is_empty() and float(row["z"]) > GATE_Z:
		if not _seen("gate_pick") and _offer_count(row) >= 2:
			_row_id = int(row["id"])
			_lane = _best_lane(row)
			_begin("gate_pick", _lane != sim.lane)
			return
	if _seen("gate_pick") and not _seen("red_gate"):
		# The squad lines up with a red gate in fire range (it starts shooting it up now).
		for r in sim.rows:
			var z := float(r["z"])
			if int(r["id"]) != _row_id and z > RED_Z and z < -6.0 and not _red_in_lane(r, sim.lane).is_empty() and _gang_clear_before(z):
				_row_id = int(r["id"])
				_lane = sim.lane
				_begin("red_gate", true)
				return
	for id in ["shield", "bomb"]:
		if int(sim.charges.get(id, 0)) > 0 and not _seen(id) and _gang_near():
			_power = id
			_charges_at = int(sim.charges[id])
			_begin(id, true)
			return


func _look_finale() -> void:
	var f := view.finale
	if f._state != "aim":
		return
	var w := String(f.logic.weapon)
	if not _seen("bottle_" + w):
		_weapon = w
		_begin("bottle_" + w, false)
		return
	if w == "pistol" and f.logic.needs_reload() and not _seen("bottle_reload"):
		_weapon = w
		_begin("bottle_reload", false)


func _begin(id: String, hold: bool) -> void:
	if auto:
		print("TUT %d %s" % [Engine.get_process_frames(), id])
	Game.mark_hint(id)
	_step = id
	_t = 0.0
	_touched = false
	_drag_px = 0.0
	_dots = false
	_ring = Vector2(-1, -1)
	_spot = Vector2(-9999, -9999)
	_icon.visible = false
	_hand.visible = true
	view.hold = hold
	_dim_to = 0.5 if hold else 0.0
	if hold:
		Sfx.play("tick", -4.0, 1.3)


func _end() -> void:
	if auto:
		print("TUT %d end %s lane=%d charges=%s" % [Engine.get_process_frames(), _step, view.sim.lane, view.sim.charges])
	_step = ""
	view.hold = false
	_dim_to = 0.0
	_hand.visible = false
	_icon.visible = false
	_ring = Vector2(-1, -1)
	_spot = Vector2(-9999, -9999)
	_dots = false
	_touched = false
	_drag_px = 0.0


func _run_step() -> void:
	var sim := view.sim
	var acting := auto and _t > AUTO_S
	match _step:
		"swipe":
			var sq := _squad_screen()
			_gesture = "sweep"
			_a = sq + Vector2(-170, 40)
			_b = sq + Vector2(170, 40)
			_spot = sq + Vector2(0, -40)
			_spot_r = Vector2(300, 220)
			if acting:
				view._move(-1 if sim.lane > 0 else 1)
			if _t > 0.3 and (_drag_px > 30.0 or sim.lane != _lane_at):
				_end()
		"gate_pick":
			var row := _row_by_id(_row_id)
			if row.is_empty():
				_end()
				return
			var gp := _gate_screen(float(row["z"]), _lane)
			_ring = gp
			_ring_r = _gate_r(float(row["z"]), _lane)
			_spot = gp + Vector2(0, _ring_r * 0.2)
			_spot_r = Vector2(1.6, 2.0) * _ring_r
			_gesture = "drag"
			_a = _squad_screen() + Vector2(0, 40)
			_b = _lane_screen(_lane) + Vector2(0, 40)
			if sim.lane == _lane:
				if not view.hold:
					# Already in the best lane: the light stays a moment, nothing waits.
					_gesture = "tap"
					_a = gp + Vector2(0, 60)
					if _t > 1.4:
						_end()
				else:
					_end()
			elif acting:
				view._move(signi(_lane - sim.lane))
		"red_gate":
			var row := _row_by_id(_row_id)
			if row.is_empty():
				_end()
				return
			var gp := _gate_screen(float(row["z"]), _lane)
			_ring = gp
			_ring_r = _gate_r(float(row["z"]), _lane)
			_spot = gp + Vector2(0, _ring_r * 0.2)
			_spot_r = Vector2(1.6, 2.0) * _ring_r
			_icon.visible = true
			_icon.position = gp + Vector2(-48, -_ring_r - 110.0 + sin(_t * 5.0) * 8.0)
			_dots = true
			_a = _squad_screen()
			_gesture = ""
			_hand.visible = false
			if (_t > 0.8 and (_touched or _drag_px > 30.0)) or acting:
				_end()
		"shield", "bomb":
			var b: Control = hud._power_buttons.get(_power, null)
			if b == null or not b.visible:
				_end()
				return
			var c := b.global_position + b.size * 0.5
			_ring = c
			_ring_r = b.size.x * 0.62
			_spot = c
			_spot_r = Vector2(b.size.x, b.size.x) * 0.9
			_gesture = "tap"
			_a = c + Vector2(10, 20)
			if acting:
				view.use_power(_power)
			if int(sim.charges.get(_power, 0)) < _charges_at or (_t > 0.6 and _touched):
				_end()
		_:
			_run_bottle()


func _run_bottle() -> void:
	var f := view.finale
	if f == null or not is_instance_valid(f) or f._state != "aim":
		if f == null or not is_instance_valid(f) or f._state in ["tally", "finished"]:
			_end()
		return
	var vp := _root.size
	var c := Vector2(vp.x * 0.5, vp.y * 0.5)
	var target := _bottle_screen()
	_ring = target
	_ring_r = 70.0
	if _step == "bottle_reload":
		_ring = Vector2(-1, -1)
		_gesture = "swipe"
		_a = c + Vector2(80, -60)
		_b = c + Vector2(80, 260)
	else:
		match _weapon:
			"stars":
				_gesture = "swipe"
				_a = Vector2(c.x + 40, vp.y * 0.86)
				_b = target if target.x >= 0.0 else c
			"bow", "sniper":
				_gesture = "hold_drag"
				_a = Vector2(c.x + 60, vp.y * 0.74)
				_b = _a + Vector2(-50, -70)
			"pistol":
				_gesture = "drag"
				_a = Vector2(c.x + 60, vp.y * 0.76)
				_b = _a + Vector2(-60, -90)
			_:
				_gesture = "drag"
				var aim := target if target.x >= 0.0 else c
				_a = aim + Vector2(110, 170)
				_b = aim
	if _touched or (auto and _t > AUTO_S):
		_end()


# ---------------------------------------------------------------- level queries

## The nearest gate row still ahead of the squad.
func _next_row() -> Dictionary:
	var best: Dictionary = {}
	for r in view.sim.rows:
		var z := float(r["z"])
		if z < -0.5 and (best.is_empty() or z > float(best["z"])):
			best = r
	return best


func _row_by_id(id: int) -> Dictionary:
	for r in view.sim.rows:
		if int(r["id"]) == id:
			return r
	return {}


func _offer_count(row: Dictionary) -> int:
	var n := 0
	for g in row["gates"]:
		if not _is_red(g):
			n += 1
	return n


static func _is_red(g: Dictionary) -> bool:
	return float(g.get("step", 0.0)) > 0.0 and int(g.get("v", 0)) < 0


func _red_in_lane(row: Dictionary, lane: int) -> Dictionary:
	for g in row["gates"]:
		if int(g["lane"]) == lane and _is_red(g) and not g.get("blocked", false):
			return g
	return {}


## The lane whose gate leaves the biggest squad (a red gate counts at its current value).
func _best_lane(row: Dictionary) -> int:
	return best_lane(row, float(view.sim.squad.total()), view.sim.lane)


## Pure: the best lane of `row` for a squad of `n` in `lane` (ties keep the current lane).
static func best_lane(row: Dictionary, n: float, lane: int) -> int:
	var best := lane
	var best_v := -INF
	for g in row["gates"]:
		var v := gate_value(g, n)
		var l := int(g["lane"])
		if v > best_v or (v == best_v and l == lane):
			best_v = v
			best = l
	return best


## Rough squad size after a gate (only to pick the lane to light; the sim stays exact).
static func gate_value(g: Dictionary, n: float) -> float:
	match String(g.get("op", "")):
		"num":
			return n + float(g.get("v", 0))
		"mul":
			return n * float(g.get("k", 1))
		"div":
			return n / maxf(float(g.get("k", 1)), 1.0)
		"pct":
			return n * (1.0 + float(g.get("v", 0)) / 100.0)
		"recruit":
			return n + 3.0 * float(g.get("n", 1))
		"weapon", "power", "foe_div", "foe_strip", "turncoat":
			return n + 2.0
	return n


func _gang_near() -> bool:
	for h in view.sim.hordes:
		if int(h.get("count", 0)) > 0 and float(h["z"]) > GANG_Z:
			return true
	return false


func _gang_clear_before(z: float) -> bool:
	for h in view.sim.hordes:
		if int(h.get("count", 0)) > 0 and float(h["z"]) > z:
			return false
	return true


# ---------------------------------------------------------------- screen positions

func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()


func _project(p: Vector3) -> Vector2:
	var cam := _cam()
	if cam == null or cam.is_position_behind(p):
		return Vector2(-1, -1)
	return cam.unproject_position(p)


func _squad_screen() -> Vector2:
	return _project(Vector3(view._squad_x, 1.0, 0.5))


func _lane_screen(lane: int) -> Vector2:
	return _project(Vector3(LevelView.LANE_X[lane], 1.0, 0.5))


func _gate_screen(z: float, lane: int) -> Vector2:
	return _project(Vector3(LevelView.LANE_X[lane], 1.6, z))


## Ring radius around a gate: about half a lane wide on screen at that distance.
func _gate_r(z: float, lane: int) -> float:
	var x := float(LevelView.LANE_X[lane])
	var a := _project(Vector3(x - 1.4, 1.6, z))
	var b := _project(Vector3(x + 1.4, 1.6, z))
	return clampf(a.distance_to(b) * 0.6, 44.0, 110.0)


func _bottle_screen() -> Vector2:
	var f := view.finale
	var i := f.logic.next_target()
	if i < 0:
		return Vector2(-1, -1)
	var p := _project(f._bottle_center(i, f._ft))
	if p.x < 0.0 or p.y < 0.0 or p.x > _root.size.x or p.y > _root.size.y:
		return Vector2(-1, -1)
	return p


# ---------------------------------------------------------------- drawing

func _paint() -> void:
	_mat.set_shader_parameter("rect_size", _root.size)
	_mat.set_shader_parameter("center", _spot)
	_mat.set_shader_parameter("radius", _spot_r)
	_mat.set_shader_parameter("dim", _dim)
	_shade.visible = _dim > 0.01
	if _step != "" and _hand.visible:
		_animate_hand()
	_canvas.queue_redraw()


## The ghost hand acts out `_gesture` on a loop: where the fingertip is and whether it presses.
func _animate_hand() -> void:
	var period := 1.9
	var k := fmod(_t, period) / period
	var p := _a
	var pressed := false
	var fade := 1.0
	match _gesture:
		"sweep":
			p = _a.lerp(_b, 0.5 + 0.5 * sin(_t * 2.8))
			pressed = true
		"tap":
			p = _a
			pressed = fmod(_t, 0.9) < 0.25
		"drag":
			if k < 0.15:
				fade = k / 0.15
			elif k < 0.25:
				pressed = true
			elif k < 0.7:
				pressed = true
				p = _a.lerp(_b, smoothstep(0.25, 0.7, k))
			else:
				p = _b
				fade = 1.0 - smoothstep(0.85, 1.0, k)
			if k >= 0.7 and _release_t < 0.0:
				_release_t = _t
		"hold_drag":
			if k < 0.1:
				fade = k / 0.1
			elif k < 0.45:
				pressed = true
			elif k < 0.75:
				pressed = true
				p = _a.lerp(_b, smoothstep(0.45, 0.75, k))
			else:
				p = _b
				fade = 1.0 - smoothstep(0.88, 1.0, k)
			if k >= 0.75 and _release_t < 0.0:
				_release_t = _t
		"swipe":
			if k < 0.2:
				fade = k / 0.2
			elif k < 0.3:
				pressed = true
			elif k < 0.42:
				pressed = true
				p = _a.lerp(_b, (k - 0.3) / 0.12)
			else:
				p = _b
				fade = 1.0 - smoothstep(0.5, 0.7, k)
			if k >= 0.42 and _release_t < 0.0:
				_release_t = _t
	if k < 0.1:
		_release_t = -1.0
	_tip = p
	_pressed = pressed
	_hand.position = p - _hand.pivot_offset
	_hand.scale = Vector2.ONE * (0.86 if pressed else 1.0)
	_hand.modulate = Color(1, 1, 1, fade)


func _draw_fx() -> void:
	if _step == "":
		return
	var t := _t
	if _ring.x >= 0.0:
		var pulse := 0.5 + 0.5 * sin(t * 6.0)
		_canvas.draw_arc(_ring, _ring_r * (1.0 + 0.08 * pulse), 0, TAU, 48, Color(1.0, 0.85, 0.2, 0.9), 8.0)
		_canvas.draw_arc(_ring, _ring_r * (1.15 + 0.25 * fmod(t, 1.0)), 0, TAU, 48, Color(1.0, 0.85, 0.2, 0.6 * (1.0 - fmod(t, 1.0))), 5.0)
	if _dots and _ring.x >= 0.0 and _a.x >= 0.0:
		# Ghost bullets fly into the red gate; an up chevron says its number climbs.
		for i in 5:
			var k := fmod(t * 1.6 + i * 0.2, 1.0)
			var p := _a.lerp(_ring, k)
			_canvas.draw_circle(p, 9.0, Color(1.0, 0.92, 0.4, 1.0 - k * 0.5))
		var up := _ring + Vector2(_ring_r + 34.0, -10 - fmod(t, 1.0) * 30.0)
		var a := 1.0 - fmod(t, 1.0)
		_canvas.draw_polyline(PackedVector2Array([up + Vector2(-26, 16), up + Vector2(0, -10), up + Vector2(26, 16)]), Color(0.3, 1.0, 0.4, a), 10.0)
	if _step != "" and _hand.visible and _gesture != "":
		if _pressed and _gesture != "tap" and _gesture != "sweep":
			# Dotted trail from where the finger went down.
			var n := int(_a.distance_to(_tip) / 26.0)
			for i in n:
				_canvas.draw_circle(_a.lerp(_tip, float(i) / maxf(float(n), 1.0)), 5.0, Color(1, 1, 1, 0.55))
		if _gesture == "sweep":
			_canvas.draw_line(_a, _b, Color(1, 1, 1, 0.35), 6.0)
			for e: Vector2 in [_a, _b]:
				var dir: Vector2 = (e - (_a + _b) * 0.5).normalized()
				_canvas.draw_polyline(PackedVector2Array([e - dir * 26 + dir.orthogonal() * 22, e, e - dir * 26 - dir.orthogonal() * 22]), Color(1, 1, 1, 0.7), 7.0)
		if _pressed:
			_canvas.draw_circle(_tip, 30.0, Color(1, 1, 1, 0.3))
			_canvas.draw_arc(_tip, 30.0, 0, TAU, 32, Color(1, 1, 1, 0.8), 4.0)
		if _release_t >= 0.0 and t - _release_t < 0.4:
			var k := (t - _release_t) / 0.4
			_canvas.draw_arc(_b, 30.0 + 60.0 * k, 0, TAU, 32, Color(1, 1, 1, 0.8 * (1.0 - k)), 5.0)

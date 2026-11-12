class_name Tutorial
extends CanvasLayer
## First-run tutorials in one visual language (spec v2 §11). Each shows once ever (Game
## seen_hints). No words.
## Gesture lessons: the glossy hand (PointerHand) acts the gesture out where it should be done,
## with the screen dimmed around it; the street holds still (LevelView.hold) until the player
## does it. The hand is used for these only:
##   tap       tap the lower half to fire faster (first, before anything else; 3 taps)
##   swipe     drag to steer (held until the player drags)
##   barrel    the first explosive barrel: steer into its lane (held), then tap to shoot it
##   bottle_*  each Bottle Shot weapon's gesture, and the pistol reload
## Everything else has its own look and never a hand:
##   gate_pick the first gate choice: green chevrons painted on the road into the best lane and
##             the exact result above its gate (squad 16 ▸ 48); held until the squad is in it
##   red_gate  the squad lines up with a red gate in fire range: slow motion while ghost
##             bullets fly into it and it ticks up (ends just after it turns green)
##   shield / bomb  the first gang arrives while a charge is ready: the "new" card and a gold
##             outline on the button (NewItemCard), no freeze
## main.gd never creates this under autoplay; `tutor=auto` (debug) acts out each step after
## AUTO_S for screenshots.

const OWNS := ["swipe", "red_gate", "shield", "bomb", "barrel"]  # level-data hints this teaches itself
const AUTO_S := 1.6
const HAND := 130.0
const TAPS := 3                     # taps that end the tap lesson
const TAP_PX := 24.0                # a lesson tap moves less than this (viewport px) ...
const TAP_S := 0.35                 # ... and lifts within this many seconds
const TAP_ZONE := 0.5               # the tap zone starts this far down the screen (units.json input.zone_top wins)
const GATE_Z := -22.0               # a gate row this close (m) opens the gate tutorials
const GATE_HOLD_S := 6.0            # the gate lesson never holds longer than this
const RED_EARLY := 3.0              # ... and a red gate this far before fire range opens its own: the squad
                                    # shoots any red gate up to 0 within ~2.5 s of reaching it, so the lesson
                                    # must start just before the first shots land (in slow motion, so the
                                    # ticks read while it comes closer)
const RED_MAX_S := 6.0              # ... or after this many seconds of slow motion
const BARREL_MAX_S := 4.0           # the barrel's shooting part ends after this long
const POWER_S := 3.0                # the power card's step lasts this long (or until used)
const GANG_Z := -44.0               # a gang this close (in fire range) opens the power tutorial
const CHEVRON_GAP := 2.4            # metres between road chevrons
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
var screen := Vector2.ZERO  # tests: the screen size when not in the tree

var _step := ""
var _t := 0.0
var _played := 0.0
var _lane := -1           # the lane this step wants (gate, red, barrel)
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
var _dots := false        # ghost bullets from _a to _ring (red gate, barrel)
var _red_green_t := 0.0   # seconds since the lesson's red gate turned green
var _tip := Vector2.ZERO
var _pressed := false
var _release_t := -1.0    # gesture phase of the last release (burst ring)
var _taps := 0            # tap lesson: taps so far
var _press: Dictionary = {}   # touch index -> {pos, t} while a finger is down in the tap zone
var _chevrons := false    # gate lesson: road chevrons into _lane
var _preview: Array = []  # gate lesson: [squad now, squad after the best gate] (exact)
var _preview_n := -1
var _barrel: Dictionary = {}
var _shooting := false    # barrel lesson: in its lane, shooting it

var _root: Control
var _shade: ColorRect
var _mat: ShaderMaterial
var _canvas: Control
var _hand: PointerHand
var _icon: TextureRect
var _pill: PanelContainer
var _pill_now: Label
var _pill_after: Label


func setup(v: LevelView, h: Hud, auto_act := false) -> Tutorial:
	view = v
	hud = h
	auto = auto_act
	return self


## True for the lessons that teach a gesture: the only ones that show the hand.
static func uses_hand(id: String) -> bool:
	return id in ["tap", "swipe", "barrel"] or id.begins_with("bottle_")


func _ready() -> void:
	build()


func build() -> void:
	if _root != null:
		return
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
	# Gate lesson result preview: squad now ▸ after the best gate.
	_pill = RetentionPanel.card_box(Color(0.1, 0.45, 0.16, 0.94), 8, 20, 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(row)
	row.add_child(RetentionPanel.icon_safe("person", 46))
	_pill_now = UiKit.label("", 46, Color.WHITE, 8)
	row.add_child(_pill_now)
	row.add_child(RetentionPanel.icon_safe("play", 30, UiKit.YELLOW))
	_pill_after = UiKit.label("", 52, UiKit.YELLOW, 10)
	row.add_child(_pill_after)
	_pill.visible = false
	_root.add_child(_pill)
	_hand = PointerHand.make(HAND)
	_hand.visible = false
	_root.add_child(_hand)
	if view != null:
		var card := view.new_item_card()
		card.skip = OWNS
		if hud != null:
			card.buttons = hud._power_buttons


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_touched = true
			if e.position.y >= _screen().y * _zone_top():
				_press[e.index] = {"pos": e.position, "t": _t}
		elif _press.has(e.index):
			var p: Dictionary = _press[e.index]
			_press.erase(e.index)
			if e.position.distance_to(p["pos"]) < TAP_PX and _t - float(p["t"]) <= TAP_S:
				_taps += 1
	elif event is InputEventScreenDrag:
		_drag_px += absf((event as InputEventScreenDrag).relative.x)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]:
			_drag_px += 100.0
		elif k == KEY_SPACE:
			_taps += 1


func _zone_top() -> float:
	return float(Game.units.get("input", {}).get("zone_top", TAP_ZONE))


func _screen() -> Vector2:
	if screen != Vector2.ZERO:
		return screen
	return _root.size if _root != null and _root.size != Vector2.ZERO else Vector2(720, 1280)


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
		_taps = 0
		_look(delta)
	else:
		_run_step(delta)
	_paint()


func _seen(id: String) -> bool:
	return Game.hint_seen(id)


## Opens the next tutorial that is due right now, if any.
func _look(delta: float) -> void:
	if view.finale != null and is_instance_valid(view.finale):
		_look_finale()
		return
	if view.sim == null or view.sim.state != "run" or view._state != "play":
		return
	_played += delta
	var sim := view.sim
	if not _seen("tap"):
		if _played > 0.6:
			_begin("tap", true)
		return
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
			if int(r["id"]) != _row_id and z > -sim.fire_range - RED_EARLY and z < -6.0 and not _red_in_lane(r, sim.lane).is_empty() and _gang_clear_before(z):
				_row_id = int(r["id"])
				_lane = sim.lane
				_red_green_t = 0.0
				_begin("red_gate", false)
				view.slow = true
				_dim_to = 0.35
				return
	if not _seen("barrel"):
		for ob in sim.obstacles:
			var z := float(ob["z"])
			if String(ob.get("kind", "")) == "barrel" and not ob.get("armed", false) and z > -sim.fire_range - RED_EARLY and z < -8.0 and _gang_clear_before(z):
				_barrel = ob
				_lane = int(ob["lane"])
				_shooting = false
				_begin("barrel", sim.lane != _lane)
				return
	for id in ["shield", "bomb"]:
		if int(sim.charges.get(id, 0)) > 0 and not _seen(id) and _gang_near():
			_power = id
			_charges_at = int(sim.charges[id])
			_begin(id, false)
			var b: Control = hud._power_buttons.get(id, null) if hud != null else null
			view.new_item_card().show_item({"id": id}, b, true)
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
	_taps = 0
	_press.clear()
	_dots = false
	_chevrons = false
	_preview = []
	_preview_n = -1
	_ring = Vector2(-1, -1)
	_spot = Vector2(-9999, -9999)
	_icon.visible = false
	_hand.visible = uses_hand(id)
	view.hold = hold
	_dim_to = 0.5 if hold else 0.0
	if hold:
		Sfx.play("tick", -4.0, 1.3)
	_run_step(0.0)   # the first frame already shows the gesture where it belongs


func _end() -> void:
	if auto:
		print("TUT %d end %s lane=%d charges=%s" % [Engine.get_process_frames(), _step, view.sim.lane, view.sim.charges])
	if _step == "barrel":
		view.new_item_card().show_item({"id": "barrel"}, null, true)
	_step = ""
	view.hold = false
	view.slow = false
	_dim_to = 0.0
	_hand.visible = false
	_icon.visible = false
	_pill.visible = false
	_ring = Vector2(-1, -1)
	_spot = Vector2(-9999, -9999)
	_dots = false
	_chevrons = false
	_preview = []
	_touched = false
	_drag_px = 0.0
	_taps = 0


func _run_step(delta: float) -> void:
	var sim := view.sim
	var acting := auto and _t > AUTO_S
	match _step:
		"tap":
			# Tap the lower half: the hand taps there, a pip fills per tap, 3 taps go on.
			var sc := _screen()
			var top := sc.y * _zone_top()
			_gesture = "tap"
			_a = Vector2(sc.x * 0.5, lerpf(top, sc.y, 0.55))
			_spot = Vector2(sc.x * 0.5, lerpf(top, sc.y, 0.6))
			_spot_r = Vector2(sc.x * 0.62, (sc.y - top) * 0.62)
			if acting and fmod(_t, 0.3) < delta:
				_taps += 1
				if sim.has_method("tap"):
					sim.call("tap")
			if _taps >= TAPS:
				_end()
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
			# Green chevrons on the road into the best lane and the exact result above its
			# gate. No hand.
			var row := _row_by_id(_row_id)
			if row.is_empty():
				_end()
				return
			_chevrons = true
			_gesture = ""
			_update_preview(row)
			var gp := _gate_screen(float(row["z"]), _lane)
			_ring_r = _gate_r(float(row["z"]), _lane)
			_spot = gp + Vector2(0, _ring_r * 0.6)
			_spot_r = Vector2(1.7, 2.6) * _ring_r
			if sim.lane == _lane:
				if not view.hold:
					# Already in the best lane: the chevrons stay a moment, nothing waits.
					if _t > 1.4:
						_end()
				else:
					_end()
			elif acting:
				view._move(signi(_lane - sim.lane))
			elif view.hold and _t > GATE_HOLD_S:
				view.hold = false   # never stuck: the street runs on, the chevrons stay
				_dim_to = 0.0
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
			# Ends a moment after the gate has turned green (or time ran out).
			if _red_in_lane(row, _lane).is_empty():
				_red_green_t += delta
			if _red_green_t > 0.9 or _t > RED_MAX_S or float(row["z"]) > -6.0:
				_end()
		"barrel":
			_run_barrel(acting)
		"shield", "bomb":
			if acting:
				view.use_power(_power)
			if int(sim.charges.get(_power, 0)) < _charges_at:
				# The lesson's charge comes back: no 5 h recharge starts on the first level, and
				# the player can still throw the bomb (or raise the shield) any time after.
				view.refund_power(_power)
				_end()
			elif _t > POWER_S:
				_end()
		_:
			_run_bottle()


## The barrel lesson: held while the hand drags the squad into the barrel's lane, then the
## street runs while the hand taps (fire faster) and ghost bullets fly into it, until the
## barrel is armed. At the end the "new" card shows what it does (aim ▸ fuse ▸ blast N).
func _run_barrel(acting: bool) -> void:
	var sim := view.sim
	if _barrel.is_empty() or not sim.obstacles.has(_barrel) or _barrel.get("armed", false) or float(_barrel["z"]) > -4.0:
		_end()
		return
	var bp := _project(Vector3(LevelView.LANE_X[_lane], 0.7, float(_barrel["z"])))
	_ring = bp
	_ring_r = _gate_r(float(_barrel["z"]), _lane) * 0.7
	if not _shooting:
		_gesture = "drag"
		_a = _squad_screen() + Vector2(0, 40)
		_b = _lane_screen(_lane) + Vector2(0, 40)
		_spot = (bp + _a) * 0.5
		_spot_r = Vector2(320, 300)
		if sim.lane == _lane or _t > GATE_HOLD_S:
			_shooting = true
			_t = 0.0
			view.hold = false
			_dim_to = 0.0
		elif acting:
			view._move(signi(_lane - sim.lane))
		return
	var sc := _screen()
	_gesture = "tap"
	_a = Vector2(sc.x * 0.62, lerpf(sc.y * _zone_top(), sc.y, 0.6))
	_dots = true
	if _t > BARREL_MAX_S:
		_end()


## The exact squad after the lesson's gate (a copy of the sim takes it), refreshed when the
## squad changes. Only gates that change the squad get a preview.
func _update_preview(row: Dictionary) -> void:
	var n := view.sim.squad.total()
	if n == _preview_n:
		return
	_preview_n = n
	_preview = []
	for g in row["gates"]:
		if int(g["lane"]) == _lane and String(g["op"]) in ["num", "mul", "div", "pct", "recruit"]:
			var c := view.sim.clone()
			c._apply_gate(g)
			_preview = [n, c.squad.total()]
	_pill.visible = not _preview.is_empty()
	if _pill.visible:
		_pill_now.text = str(_preview[0])
		_pill_after.text = str(_preview[1])


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
	if not is_inside_tree():
		return null
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
			# Down onto the spot, press, lift off a little towards the lower right.
			var q := fmod(_t, 0.9) / 0.9
			pressed = q < 0.28
			p = _a + Vector2(18, 18) * (0.0 if pressed else sin((q - 0.28) / 0.72 * PI))
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
	_hand.set_tip(p)
	_hand.pressed = pressed
	_hand.modulate = Color(1, 1, 1, fade)


func _draw_fx() -> void:
	if _step == "":
		return
	var t := _t
	if _chevrons:
		_draw_chevrons()
	if _step == "tap":
		# One pip per tap needed, filled as the player taps (above the hand).
		for i in TAPS:
			var c := _a + Vector2((i - (TAPS - 1) * 0.5) * 56.0, -150.0)
			_canvas.draw_circle(c, 20.0, UiKit.INK)
			_canvas.draw_circle(c, 15.0, UiKit.GOLD if i < _taps else Color(1, 1, 1, 0.25))
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
		if _gesture == "tap":
			# Tap ripple spreading from the fingertip after each press.
			var q := fmod(t, 0.9) / 0.9
			_canvas.draw_arc(_a, 26.0 + 70.0 * q, 0, TAU, 40, Color(1, 1, 1, 0.85 * (1.0 - q)), 5.0)


## Gate lesson: green chevrons painted on the road from the squad into the best lane, flowing
## towards the gate, perspective-correct (each one is projected from the road), and the
## result pill above that gate.
func _draw_chevrons() -> void:
	var row := _row_by_id(_row_id)
	if row.is_empty() or _cam() == null:
		return
	var z1 := float(row["z"]) + 1.5
	var z0 := -1.5
	if z1 >= z0:
		return
	var x0 := view._squad_x
	var x1 := float(LevelView.LANE_X[_lane])
	var span := z0 - z1
	var shift := fmod(_t * 3.0, CHEVRON_GAP)
	var s := shift
	while s < span:
		var k := s / span
		var z := z0 - s
		var x := lerpf(x0, x1, smoothstep(0.0, 0.7, k))
		var xn := lerpf(x0, x1, smoothstep(0.0, 0.7, minf(k + 0.05, 1.0)))
		var fwd := Vector3(xn - x, 0, -span * 0.05).normalized()
		var side := Vector3(-fwd.z, 0, fwd.x)
		var tip := Vector3(x, 0.06, z) + fwd * 0.45
		var l := Vector3(x, 0.06, z) - fwd * 0.35 + side * 0.85
		var r := Vector3(x, 0.06, z) - fwd * 0.35 - side * 0.85
		var pts := PackedVector2Array([_project(l), _project(tip), _project(r)])
		if pts[0].x >= 0.0 and pts[1].x >= 0.0 and pts[2].x >= 0.0:
			var w := clampf(pts[0].distance_to(pts[2]) * 0.2, 4.0, 22.0)
			var a := smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.85, 1.0, k))
			_canvas.draw_polyline(pts, Color(UiKit.INK, 0.55 * a), w + 6.0)
			_canvas.draw_polyline(pts, Color(0.35, 1.0, 0.45, 0.95 * a), w)
		s += CHEVRON_GAP
	if _pill.visible:
		var gp := _gate_screen(float(row["z"]), _lane)
		if gp.x >= 0.0:
			_pill.position = gp - Vector2(_pill.size.x * 0.5, _gate_r(float(row["z"]), _lane) + _pill.size.y + 40.0)

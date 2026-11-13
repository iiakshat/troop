class_name NewItemCard
extends CanvasLayer
## "This is new" (spec v2 §11 as amended by v2.1 §6). The first time ever a new enemy,
## obstacle, rank or power shows up (a level `hint` event, or Tutorial for the powers and the
## barrel):
##   - a card slides in at the top edge: the tone chip, the object's icon, then ▸ its effect
##     as icons and numbers (barrel: aim ▸ fuse ▸ thug -40), framed and coloured by the item's
##     tone (gain / threat / use, config/hints.json)
##   - a marker on the one object that triggered the hint, in the same tone: a ring and the
##     tone chip on a gang (following its survivors), a small tag over an obstacle, a sparkle
##     on every matching gate sign of that row (no lane singled out), a pulse on a HUD button
## The card and the marker share one clock (show_s). The marker is bound once, when the card
## opens: to the event's `horde` id (LevelSim._enemy_hints_due), else to the nearest matching
## object ahead. When that object is dead, passed or removed it fades out in fade_s and never
## moves to another one. No hand and no freeze. LevelView creates one on its first hint event
## (`item_card`); Tutorial fills `skip` with the ids it teaches itself and `buttons` with the
## HUD power buttons.

const PATH := "res://config/hints.json"
const CARD_Y := 168.0        # under the HUD's top bar
const SLIDE_S := 0.25
const CARD_BG := Color(0.07, 0.11, 0.27, 0.94)

static var _table: Dictionary = {}

var view: LevelView
var buttons: Dictionary = {}   # power id -> Control
var skip: Array = []           # ids a running Tutorial teaches itself

var _id := ""
var _icon_name := ""
var _tone := "use"
var _t := 0.0                  # seconds left on the shared clock (card and marker)
var _age := 0.0
var _find: Dictionary = {}
var _kind := ""                # what the marker is bound to: horde | obstacle | row | button | ""
var _bind_id := -1             # ... and its sim id (-1: none)
var _obj: Dictionary = {}      # the bound sim object (a row's first matching gate), for numbers
var _target: Control = null    # a HUD control (kind "button")
var _gone := false             # the bound object is dead, passed or removed: fade, never re-bind
var _gone_t := 0.0
var _pos := Vector2(-1, -1)    # marker centre on screen (-1: not on screen this frame)
var _rad := Vector2.ZERO       # ring radii (gang, button)
var _stem := Vector2(-1, -1)   # an obstacle tag's stem end, on the object
var _sparks: Array = []        # a gate row: one screen point per matching sign
var _alpha := 0.0              # the marker's opacity this frame (0 = not drawn)
var project := Callable()      # tests: a stand-in camera (Vector3 -> screen, x < 0 = not on it)

var _warm := 0                # prewarm(): frames left to draw nearly transparent
var _root: Control = null
var _card: PanelContainer
var _row: HBoxContainer
var _canvas: Control


static func table() -> Dictionary:
	if _table.is_empty():
		var d = Config.load_json(PATH)
		_table = d if d is Dictionary else {"items": {}}
	return _table


static func item(id: String) -> Dictionary:
	return table().get("items", {}).get(id, {})


## "gain" | "threat" | "use" for a hints.json item; default_tone for anything else (a Tutorial
## ring with no item, the Bottle Shot aims).
static func tone(id: String) -> String:
	return String(item(id).get("tone", table().get("default_tone", "use")))


static func tone_color(t: String) -> Color:
	return Color(String(table().get("tones", {}).get(t, {}).get("color", "ffd23f")))


## plus (gain), warn (threat) or reticle (use): the chip's silhouette.
static func tone_shape(t: String) -> String:
	return String(table().get("tones", {}).get(t, {}).get("shape", "reticle"))


func setup(v: LevelView) -> NewItemCard:
	view = v
	layer = 6
	build()
	return self


func build() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.name = "ItemRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_marker)
	_root.add_child(_canvas)
	_card = RetentionPanel.card_box(CARD_BG, 12, 26, 5)
	_card.name = "NewCard"
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.visible = false
	_root.add_child(_card)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_row)


## Opens the card and the marker for hint `ev` ({"id", "horde"?, "enemy"?, ...}). `target` =
## a HUD control to mark instead of a street object. False when it is unknown, or a Tutorial
## teaches it (unless `by_tutor`: the Tutorial itself opens it). Once ever per id ("card_<id>"
## in seen_hints, so a Tutorial lesson that marked `id` can still end on its card).
func show_item(ev: Dictionary, target: Control = null, by_tutor := false) -> bool:
	var id := String(ev.get("id", ""))
	var it := item(id)
	if id == "" or it.is_empty() or (skip.has(id) and not by_tutor) or Game.hint_seen("card_" + id):
		return false
	build()
	Game.mark_hint(id)
	Game.mark_hint("card_" + id)
	_warm = 0                # a real card ends the load-time prewarm at once (one clock from now)
	_card.modulate.a = 1.0
	_id = id
	_icon_name = String(it.get("icon", id))
	_tone = tone(id)
	_find = it.get("find", {})
	_target = target if target != null else buttons.get(String(_find.get("button", "")), null)
	_age = 0.0
	_t = float(table().get("show_s", 2.6))
	_bind(ev)
	_locate()
	_update_alpha()
	_card.add_theme_stylebox_override("panel", RetentionPanel.box(CARD_BG, 26, 6, tone_color(_tone), 12))
	_fill(effects(id, _obj, view.sim.stats if view != null and view.sim != null else {}))
	_card.visible = true
	Sfx.play("banner", -6.0, 1.3)
	var sim_t := float(view.sim.time) if view != null and view.sim != null else 0.0
	Analytics.hint_shown(id, view.level_id if view != null else 0, sim_t)
	if OS.get_cmdline_user_args().has("tutor=auto"):
		print("CARD %d %s" % [Engine.get_process_frames(), id])  # screenshot timing, like Tutorial's TUT
	return true


## Level load (LevelView._prewarm): the card (with the icons and numbers of every hint in
## `ids`), the ring, the three tone chips and a sparkle draw for `frames` frames, nearly
## transparent, so their canvas pipelines, textures and glyphs are ready before the first new
## item shows up (that was a 99 ms frame at L13's first SWAT; spec v2 §3).
func prewarm(ids: Array = [], frames := 4) -> void:
	build()
	_warm = frames
	var fx: Array = [{"icon": "thug", "text": "-40"}]
	for id in ids:
		var it := item(String(id))
		if not it.is_empty():
			fx.append({"icon": String(it.get("icon", id)), "text": ""})
			fx.append_array(effects(String(id), {}, view.sim.stats if view != null and view.sim != null else {}))
	_icon_name = "thug"
	_fill(fx)
	_card.modulate.a = 0.02
	_card.visible = true
	_canvas.queue_redraw()


func showing() -> bool:
	return _t > 0.0


## True while the card or the marker still has time (they share one clock).
func active() -> bool:
	return _t > 0.0


func card_icon() -> String:
	return _icon_name if showing() else ""


## What the marker is bound to: {"kind": horde | obstacle | row | button | "", "id": sim id}.
func bound() -> Dictionary:
	return {"kind": _kind, "id": _bind_id}


func marker_alpha() -> float:
	return _alpha


func marker_pos() -> Vector2:
	return _pos


func marker_color() -> Color:
	return tone_color(_tone)


## ring (gang), tag (obstacle), sparkle (gate signs), pulse (HUD button), "" (nothing).
func marker_shape() -> String:
	return {"horde": "ring", "obstacle": "tag", "row": "sparkle", "button": "pulse"}.get(_kind, "")


## The gate signs sparkling this frame (screen points).
func sparkles() -> Array:
	return _sparks.duplicate() if _alpha > 0.0 else []


func frame_color() -> Color:
	var sb := _card.get_theme_stylebox("panel") as StyleBoxFlat
	return sb.border_color if sb != null else Color.TRANSPARENT


func _fill(fx: Array) -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	var col := tone_color(_tone)
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(56, 92)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tn := _tone
	chip.draw.connect(func(): NewItemCard.draw_chip(chip, chip.size * 0.5, 24.0, tn))
	_row.add_child(chip)
	_row.add_child(RetentionPanel.icon_safe(_icon_name, 92))
	_row.add_child(RetentionPanel.icon_safe("play", 40, col))
	for i in fx.size():
		var e: Dictionary = fx[i]
		if i > 0:
			_row.add_child(RetentionPanel.icon_safe("play", 26, Color(1, 1, 1, 0.6)))
		_row.add_child(RetentionPanel.icon_safe(String(e["icon"]), 64))
		if String(e["text"]) != "":
			_row.add_child(UiKit.label(String(e["text"]), 50, col, 10))


## The effect row for `id`: [{icon, text}], numbers read from the bound object `obj`, then
## config/units.json, then the Codex value with `stats` (the level's upgraded stats): "value.<rank>"
## = worth N constables, "dps.<rank>" = one troop's lightning firepower (the Codex headline).
static func effects(id: String, obj: Dictionary, stats: Dictionary) -> Array:
	var out: Array = []
	for e in item(id).get("effects", []):
		var d: Dictionary = e
		var text := String(d.get("text", ""))
		var src := String(d.get("from", ""))
		if src != "":
			text = ""
			var parts := src.split(".")
			var v = null
			var fmt := String(d.get("fmt", "%s"))
			match parts[0]:
				"obj":
					var key := parts[1]
					if d.has("fmt_pct") and obj.has(key + "_pct"):
						v = obj[key + "_pct"]
						fmt = String(d["fmt_pct"])
					elif obj.has(key):
						v = obj[key]
					else:
						v = _units_default(id, key)
				"units":
					v = _path(Game.units, parts.slice(1))
				"value":
					var s: Dictionary = stats if stats.has(parts[1]) else Game.units.get("allies", {})
					v = CodexPanel.number(CodexPanel.value_of(s, parts[1]))
				"dps":
					var s2: Dictionary = stats if stats.has(parts[1]) else Game.upgraded_allies()
					v = Economy.fmt_power(CodexPanel.troop_dps(s2, parts[1]))
			if v != null:
				if fmt.contains("%d"):
					v = int(round(float(v)))
				text = fmt % v
		out.append({"icon": String(d.get("icon", "")), "text": text})
	return out


static func _path(d: Variant, keys: Array) -> Variant:
	var cur: Variant = d
	for k in keys:
		if cur is Dictionary and (cur as Dictionary).has(k):
			cur = cur[k]
		else:
			return null
	return cur


## The object's value before it is on the street: its units.json default.
static func _units_default(id: String, key: String) -> Variant:
	var f: Dictionary = item(id).get("find", {})
	if f.has("obstacle"):
		return _path(Game.units, ["obstacles", String(f["obstacle"]), key])
	if f.has("horde"):
		var en := String(f["horde"])
		return _path(Game.units, ["enemies", en, "hp" if key == "max_hp" else key])
	return null


# ---------------------------------------------------------------- binding (once per card)

## Binds the marker to one object, once: the event's own object id when it names one (a gang
## from LevelSim._enemy_hints_due), else the nearest matching object ahead now. Nothing found:
## no marker (the card still shows).
func _bind(ev: Dictionary) -> void:
	_kind = ""
	_bind_id = -1
	_obj = {}
	_gone = false
	_gone_t = 0.0
	_pos = Vector2(-1, -1)
	_stem = Vector2(-1, -1)
	_sparks = []
	_alpha = 0.0
	if _target != null or _find.has("button"):
		_kind = "button"
		_gone = _target == null
		return
	var sim: LevelSim = view.sim if view != null else null
	if sim == null:
		return
	if _find.has("obstacle"):
		_kind = "obstacle"
		var ob: Dictionary = _by_id(sim.obstacles, int(ev["obstacle"])) if ev.has("obstacle") else _nearest(sim.obstacles.filter(
			func(o): return String(o.get("kind", "")) == String(_find["obstacle"])))
		_bind_id = int(ob.get("id", -1))
		_obj = ob
	elif _find.has("cage"):
		# Review v2.1: a hostage cage gets an obstacle-style tag over it (the nearest one ahead).
		_kind = "cage"
		var cg: Dictionary = _nearest(sim.cages.filter(func(c): return not bool(c.get("open", false))))
		_bind_id = int(cg.get("id", -1))
		_obj = cg
	elif _find.has("gate") or _find.has("red_gate"):
		_kind = "row"
		var r: Dictionary = _by_id(sim.rows, int(ev["row"])) if ev.has("row") else _first_row(sim)
		_bind_id = int(r.get("id", -1))
		for g in r.get("gates", []):
			if _gate_matches(g):
				_obj = g
				break
	elif _find.has("horde") or ev.has("horde"):
		_kind = "horde"
		if ev.has("horde"):
			_bind_id = int(ev["horde"])
		else:
			var en := String(ev.get("enemy", _find.get("horde", "")))
			var near: Dictionary = {}
			for h in sim.hordes:
				if int(h.get("count", 0)) > 0 and (en == "" or String(h.get("enemy", "")) == en) \
						and (near.is_empty() or LevelSim.front_z(h) > LevelSim.front_z(near)):
					near = h
			_bind_id = int(near.get("id", -1))
		_obj = _by_id(sim.hordes, _bind_id)
	if _bind_id < 0:
		_gone = true


## The first row ahead holding a matching gate.
func _first_row(sim: LevelSim) -> Dictionary:
	var best: Dictionary = {}
	for r in sim.rows:
		var z := float(r["z"])
		if z >= -0.5 or (not best.is_empty() and z <= float(best["z"])):
			continue
		for g in r["gates"]:
			if _gate_matches(g):
				best = r
				break
	return best


func _gate_matches(g: Dictionary) -> bool:
	if _find.has("red_gate"):
		return Tutorial._is_red(g)
	if String(g.get("op", "")) != String(_find.get("gate", "")):
		return false
	for k in ["unit", "id"]:
		if _find.has(k) and String(g.get(k, "")) != String(_find[k]):
			return false
	return true


static func _by_id(list: Array, id: int) -> Dictionary:
	if id < 0:
		return {}
	for o in list:
		if int(o.get("id", -1)) == id:
			return o
	return {}


static func _nearest(list: Array) -> Dictionary:
	var best: Dictionary = {}
	for o in list:
		var z := float(o["z"])
		if z < -0.5 and (best.is_empty() or z > float(best["z"])):
			best = o
	return best


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _warm > 0:
		_warm -= 1
		_canvas.queue_redraw()
		if _warm == 0:
			_card.modulate.a = 1.0
			_card.visible = _t > 0.0
		return
	if _t <= 0.0:
		if _alpha > 0.0 or _card.visible:
			_alpha = 0.0
			_card.visible = false
			_canvas.queue_redraw()
		return
	_age += delta
	_t = maxf(_t - delta, 0.0)
	_locate()
	if _gone:
		_gone_t += delta
	_update_alpha()
	# Slide in from the top edge, out again at the end.
	var k := minf(_age / SLIDE_S, 1.0)
	if _t < SLIDE_S:
		k = _t / SLIDE_S
	_card.visible = _t > 0.0
	_card.position = Vector2((_root.size.x - _card.size.x) * 0.5, lerpf(-_card.size.y - 20.0, CARD_Y, ease(k, 0.4)))
	_canvas.queue_redraw()


## The marker fades in the last fade_s of the shared clock, and over fade_s once its object is
## gone; it is not drawn while its object is off screen (or was never on it).
func _update_alpha() -> void:
	var fade := maxf(float(table().get("fade_s", 0.2)), 0.01)
	var a := minf(_t / fade, 1.0)
	if _gone:
		a *= clampf(1.0 - _gone_t / fade, 0.0, 1.0)
	if (_kind == "row" and _sparks.is_empty()) or (_kind != "row" and _pos.x < 0.0) or _kind == "":
		a = 0.0
	_alpha = a


## Follows the bound object on screen. Once it is dead, passed or removed the marker keeps its
## last place while it fades (`_gone`), and nothing is searched again.
func _locate() -> void:
	if _gone:
		return
	if _kind == "button":
		_pos = Vector2(-1, -1)
		if is_instance_valid(_target) and _target.is_visible_in_tree():
			_pos = _target.global_position + _target.size * 0.5
			_rad = _target.size * 0.62
		return
	if view == null or view.sim == null:
		return
	var sim := view.sim
	match _kind:
		"horde":
			var h := _by_id(sim.hordes, _bind_id)
			if h.is_empty() or int(h.get("count", 0)) <= 0:
				_gone = true
				return
			_obj = h
			_place_horde(h)
		"obstacle":
			var ob := _by_id(sim.obstacles, _bind_id)
			if ob.is_empty() or float(ob["z"]) >= -0.5:
				_gone = true
				return
			var base := Vector3(LevelView.LANE_X[int(ob["lane"])], 0.0, float(ob["z"]))
			_pos = _project(base + Vector3(0, float(table().get("tag_y", 2.1)), 0))
			_stem = _project(base + Vector3(0, 0.6, 0))
		"cage":
			var cg := _by_id(sim.cages, _bind_id)
			if cg.is_empty() or bool(cg.get("open", false)) or float(cg["z"]) >= -0.5:
				_gone = true
				return
			var cb := Vector3(LevelView.LANE_X[int(cg["lane"])], 0.0, float(cg["z"]))
			_pos = _project(cb + Vector3(0, CageView.TAG_Y + 1.0, 0))
			_stem = _project(cb + Vector3(0, CageView.H, 0))
		"row":
			var r := _by_id(sim.rows, _bind_id)
			var lanes: Array = []
			for g in r.get("gates", []):
				if _gate_matches(g):
					lanes.append(int(g["lane"]))
			if r.is_empty() or float(r["z"]) >= -0.5 or lanes.is_empty():
				_gone = true
				return
			var sp: Dictionary = table().get("sparkle", {})
			_sparks = []
			for lane in lanes:
				var q := _project(Vector3(LevelView.LANE_X[lane] + float(sp.get("dx", 0.95)), float(sp.get("y", 2.35)), float(r["z"])))
				if q.x >= 0.0:
					_sparks.append(q)
			_pos = _sparks[0] if not _sparks.is_empty() else Vector2(-1, -1)


## A gang's ring: the screen centre and spread of its live figures (feet to heads), so it
## follows the survivors as the gang thins, not the street's middle.
func _place_horde(h: Dictionary) -> void:
	_pos = Vector2(-1, -1)
	var boss := bool(h.get("boss", false))
	var feet: Array = []
	var hv: Dictionary = view._hordes.get(h["id"], {})
	if not hv.is_empty() and not (hv["offs"] as Array).is_empty():
		for o in hv["offs"]:
			feet.append(view._fig_pos(hv, o))
	else:
		feet.append(Vector3(0.0, 0.0, LevelSim.front_z(h)))
	var tall := LevelView.CHAR_H * (LevelView.BOSS_SCALE * LevelView.boss_grow(float(h["z"])) if boss else 1.0)
	var box := Rect2()
	var sum := Vector2.ZERO
	var n := 0
	for f: Vector3 in feet:
		var c := _project(f + Vector3(0, tall * 0.5, 0))
		var lo := _project(f)
		var hi := _project(f + Vector3(0, tall, 0))
		if c.x < 0.0 or lo.x < 0.0 or hi.x < 0.0:
			continue
		if n == 0:
			box = Rect2(lo, Vector2.ZERO)
		box = box.expand(lo).expand(hi)
		sum += c
		n += 1
	if n == 0:
		return
	_pos = sum / n
	_rad = Vector2(clampf(box.size.x * 0.5 + 16.0, 34.0, 260.0), clampf(box.size.y * 0.5 + 12.0, 28.0, 220.0))


## A street point on screen; (-1, -1) when behind the camera or there is none.
func _project(p: Vector3) -> Vector2:
	if project.is_valid():
		return project.call(p)
	if view == null or not view.is_inside_tree():
		return Vector2(-1, -1)
	var cam := view.get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(p):
		return Vector2(-1, -1)
	return cam.unproject_position(p)


# ---------------------------------------------------------------- drawing

func _draw_marker() -> void:
	var t := _age
	var pulse := 0.5 + 0.5 * sin(t * 7.0)
	if _warm > 0 and _t <= 0.0:
		var c := _root.size * 0.5
		_ring(c, Vector2(60, 40), tone_color("threat"), 0.02)
		var i := 0
		for tn in ["gain", "threat", "use"]:
			draw_chip(_canvas, c + Vector2(-80 + 80 * i, 0), 22.0, tn, 0.02)
			i += 1
		_sparkle(c + Vector2(0, 60), 20.0, "gain", 0.02, t)
		return
	if _alpha <= 0.0:
		return
	var a := _alpha
	var col := tone_color(_tone)
	match _kind:
		"button":
			_ring(_pos, _rad * (1.0 + 0.08 * pulse), col, a)
		"horde":
			_ring(_pos, _rad * (1.0 + 0.04 * pulse), col, a)
			if bool(_obj.get("boss", false)):
				# Review v2.1: beside a boss's or lieutenant's ring, never on his health bar or
				# his escort's count above it.
				draw_chip(_canvas, _pos + Vector2(-_rad.x - 30.0 - 4.0 * pulse, 0), 24.0, _tone, a)
			else:
				draw_chip(_canvas, _pos + Vector2(0, -_rad.y - 30.0 - 4.0 * pulse), 24.0, _tone, a)
		"obstacle", "cage":
			if _stem.x >= 0.0:
				_canvas.draw_line(_pos + Vector2(0, 18), _stem, Color(UiKit.INK, 0.8 * a), 7.0)
				_canvas.draw_line(_pos + Vector2(0, 18), _stem, Color(col, a), 3.0)
			draw_chip(_canvas, _pos + Vector2(0, -3.0 * pulse), 22.0, _tone, a)
		"row":
			var px := float(table().get("sparkle", {}).get("px", 20))
			for p: Vector2 in _sparks:
				_sparkle(p, px, _tone, a, t)


func _ring(c: Vector2, r: Vector2, col: Color, a: float) -> void:
	_ellipse(c, r * 1.07, Color(col, 0.22 * a), 14.0)
	_ellipse(c, r, Color(UiKit.INK, 0.75 * a), 9.0)
	_ellipse(c, r, Color(col, a), 4.5)


## A gate sign's sparkle: four twinkling rays round the tone chip.
func _sparkle(c: Vector2, s: float, tn: String, a: float, t: float) -> void:
	var col := tone_color(tn)
	var tw := 0.75 + 0.25 * sin(t * 9.0)
	for i in 4:
		var ang := PI / 4.0 + TAU * i / 4.0 + t * 0.8
		var dir := Vector2(cos(ang), sin(ang))
		var tip := c + dir * s * 1.9 * tw
		var side := dir.orthogonal() * s * 0.22
		var base := c + dir * s * 0.7
		_canvas.draw_colored_polygon(PackedVector2Array([base + side * 1.6, tip + dir * 3.0, base - side * 1.6]), Color(UiKit.INK, 0.7 * a))
		_canvas.draw_colored_polygon(PackedVector2Array([base + side, tip, base - side]), Color(col.lightened(0.35), a))
	draw_chip(_canvas, c, s * 0.62, tn, a)


## The tone chip at `c`, about 2·s across: a green disc with a white + (gain), a red triangle
## with "!" (threat), an orange aim reticle (use). Shapes differ as well as colours.
static func draw_chip(ci: CanvasItem, c: Vector2, s: float, tn: String, a := 1.0) -> void:
	var col := Color(tone_color(tn), a)
	var ink := Color(UiKit.INK, a)
	var white := Color(1, 1, 1, a)
	match tone_shape(tn):
		"warn":
			var tri := PackedVector2Array([c + Vector2(0, -1.12 * s), c + Vector2(1.08 * s, 0.82 * s), c + Vector2(-1.08 * s, 0.82 * s)])
			var mid := (tri[0] + tri[1] + tri[2]) / 3.0
			var out := PackedVector2Array()
			for p in tri:
				out.append(mid + (p - mid) * 1.28)
			ci.draw_colored_polygon(out, ink)
			ci.draw_colored_polygon(tri, col)
			ci.draw_rect(Rect2(c.x - 0.12 * s, c.y - 0.5 * s, 0.24 * s, 0.68 * s), white)
			ci.draw_circle(c + Vector2(0, 0.44 * s), 0.14 * s, white)
		"reticle":
			ci.draw_arc(c, 0.74 * s, 0, TAU, 32, ink, 0.46 * s)
			for i in 4:
				var d := Vector2.RIGHT.rotated(TAU * i / 4.0)
				ci.draw_line(c + d * 0.3 * s, c + d * 1.18 * s, ink, 0.4 * s)
			ci.draw_arc(c, 0.74 * s, 0, TAU, 32, col, 0.24 * s)
			for i in 4:
				var d := Vector2.RIGHT.rotated(TAU * i / 4.0)
				ci.draw_line(c + d * 0.36 * s, c + d * 1.1 * s, col, 0.2 * s)
			ci.draw_circle(c, 0.14 * s, col)
		_:
			ci.draw_circle(c, 1.08 * s, ink)
			ci.draw_circle(c, 0.9 * s, col)
			ci.draw_rect(Rect2(c.x - 0.52 * s, c.y - 0.13 * s, 1.04 * s, 0.26 * s), white)
			ci.draw_rect(Rect2(c.x - 0.13 * s, c.y - 0.52 * s, 0.26 * s, 1.04 * s), white)


## Crosshair ticks on a ring of radius r (Tutorial's rings in the use tone).
static func draw_ticks(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	for i in 4:
		var d := Vector2.RIGHT.rotated(TAU * i / 4.0 + PI / 4.0)
		ci.draw_line(c + d * (r - w * 2.2), c + d * (r + w * 2.2), col, w)


func _ellipse(c: Vector2, r: Vector2, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	_canvas.draw_polyline(pts, col, w, true)

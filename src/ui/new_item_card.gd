class_name NewItemCard
extends CanvasLayer
## "This is new" (spec v2 §11). The first time ever a new enemy, obstacle, rank or power shows
## up (a level `hint` event, or Tutorial for the powers and the barrel):
##   - a card slides in at the top edge: the object's icon, then ▸ its effect as icons and
##     numbers (barrel: aim ▸ fuse ▸ thug -40); it hides by itself after card_s
##   - the object itself gets a pulsing gold outline and a "!" burst that follow it on screen
## No hand and no freeze. What each id shows and which object it outlines: config/hints.json.
## LevelView creates one on its first hint event (`item_card`); Tutorial fills `skip` with
## the ids it teaches itself and `buttons` with the HUD power buttons.

const PATH := "res://config/hints.json"
const CARD_Y := 168.0        # under the HUD's top bar
const SLIDE_S := 0.25
const GOLD := Color(1.0, 0.82, 0.18)

static var _table: Dictionary = {}

var view: LevelView
var buttons: Dictionary = {}   # power id -> Control
var skip: Array = []           # ids a running Tutorial teaches itself

var _id := ""
var _icon_name := ""
var _card_t := 0.0             # seconds the card stays up
var _out_t := 0.0              # seconds the outline stays up
var _age := 0.0
var _find: Dictionary = {}
var _obj: Dictionary = {}      # the outlined sim object, once found
var _target: Control = null    # ... or a HUD control
var _pos := Vector2(-1, -1)    # outline centre on screen
var _rad := Vector2.ZERO       # outline radii

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
	_canvas.draw.connect(_draw_outline)
	_root.add_child(_canvas)
	_card = RetentionPanel.card_box(Color(0.07, 0.11, 0.27, 0.94), 12, 26, 5)
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


## Opens the card and the outline for hint `ev` ({"id", ...}). `target` = a HUD control to
## outline instead of a street object. False when it is unknown, or a Tutorial teaches it
## (unless `by_tutor`: the Tutorial itself opens it). Once ever per id ("card_<id>" in
## seen_hints, so a Tutorial lesson that marked `id` can still end on its card).
func show_item(ev: Dictionary, target: Control = null, by_tutor := false) -> bool:
	var id := String(ev.get("id", ""))
	var it := item(id)
	if id == "" or it.is_empty() or (skip.has(id) and not by_tutor) or Game.hint_seen("card_" + id):
		return false
	build()
	Game.mark_hint(id)
	Game.mark_hint("card_" + id)
	_id = id
	_icon_name = String(it.get("icon", id))
	_find = it.get("find", {})
	_target = target if target != null else buttons.get(String(_find.get("button", "")), null)
	_obj = {}
	_pos = Vector2(-1, -1)
	_age = 0.0
	_card_t = float(table().get("card_s", 2.2))
	_out_t = float(table().get("outline_s", 3.0))
	_locate()
	_fill(effects(id, _obj, view.sim.stats if view != null and view.sim != null else {}))
	_card.visible = true
	Sfx.play("banner", -6.0, 1.3)
	return true


func showing() -> bool:
	return _card_t > 0.0


func card_icon() -> String:
	return _icon_name if showing() else ""


func _fill(fx: Array) -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	var badge := RetentionPanel.icon_safe(_icon_name, 92)
	_row.add_child(badge)
	_row.add_child(RetentionPanel.icon_safe("play", 40, UiKit.YELLOW))
	for i in fx.size():
		var e: Dictionary = fx[i]
		if i > 0:
			_row.add_child(RetentionPanel.icon_safe("play", 26, Color(1, 1, 1, 0.6)))
		_row.add_child(RetentionPanel.icon_safe(String(e["icon"]), 64))
		if String(e["text"]) != "":
			_row.add_child(UiKit.label(String(e["text"]), 50, UiKit.YELLOW, 10))


## The effect row for `id`: [{icon, text}], numbers read from the found object `obj`, then
## config/units.json, then the Codex value with `stats` (the level's upgraded stats).
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


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _card_t <= 0.0 and _out_t <= 0.0:
		return
	_age += delta
	_card_t = maxf(_card_t - delta, 0.0)
	if _pos.x >= 0.0 or _target != null:
		_out_t = maxf(_out_t - delta, 0.0)   # the outline's clock starts once its object shows
	elif _age > 8.0:
		_out_t = 0.0
	_locate()
	# Slide in from the top edge, out again at the end.
	var k := minf(_age / SLIDE_S, 1.0)
	if _card_t < SLIDE_S:
		k = _card_t / SLIDE_S
	_card.visible = _card_t > 0.0
	_card.position = Vector2((_root.size.x - _card.size.x) * 0.5, lerpf(-_card.size.y - 20.0, CARD_Y, ease(k, 0.4)))
	_canvas.queue_redraw()


## Finds the outlined object on screen (it follows it); keeps the one found first.
func _locate() -> void:
	_pos = Vector2(-1, -1)
	if _target != null:
		if is_instance_valid(_target) and _target.is_visible_in_tree():
			_pos = _target.global_position + _target.size * 0.5
			_rad = _target.size * 0.62
		return
	if view == null or view.sim == null:
		return
	var sim := view.sim
	var p3 := Vector3.ZERO
	var half := 1.4
	if _find.has("obstacle"):
		if _obj.is_empty() or not sim.obstacles.has(_obj):
			_obj = _nearest(sim.obstacles.filter(func(o): return String(o.get("kind", "")) == String(_find["obstacle"])))
		if _obj.is_empty():
			return
		p3 = Vector3(LevelView.LANE_X[int(_obj["lane"])], 0.7, float(_obj["z"]))
		half = float(_obj.get("width", 2.4)) * 0.5 + 0.3
	elif _find.has("horde"):
		if _obj.is_empty() or not sim.hordes.has(_obj) or int(_obj.get("count", 0)) <= 0:
			var hs := sim.hordes.filter(func(h): return String(h.get("enemy", "")) == String(_find["horde"]) and int(h.get("count", 0)) > 0)
			_obj = {} if hs.is_empty() else hs[0]
		if _obj.is_empty():
			return
		var boss := bool(_obj.get("boss", false))
		var hv: Dictionary = view._hordes.get(_obj["id"], {})
		var front := view._horde_front(hv) if not hv.is_empty() else Vector3(0, 0, LevelSim.front_z(_obj))
		p3 = Vector3(front.x if boss else 0.0, 2.4 if boss else 1.0, front.z - (0.0 if boss else 1.2))
		half = 1.6 if boss else 3.4
	else:
		# A gate: the first row ahead holding a matching one.
		var g := _find_gate(sim)
		if g.is_empty():
			return
		p3 = Vector3(LevelView.LANE_X[int(g["lane"])], 1.6, float(g["_z"]))
		half = 1.4
	var cam := _cam()
	if cam == null or cam.is_position_behind(p3):
		return
	var c := cam.unproject_position(p3)
	var a := cam.unproject_position(p3 - Vector3(half, 0, 0))
	var b := cam.unproject_position(p3 + Vector3(half, 0, 0))
	var rx := clampf(a.distance_to(b) * 0.55, 36.0, 260.0)
	_pos = c
	_rad = Vector2(rx, rx * 0.8)


func _find_gate(sim: LevelSim) -> Dictionary:
	var best: Dictionary = {}
	for r in sim.rows:
		var z := float(r["z"])
		if z >= -0.5 or (not best.is_empty() and z <= float(best["_z"])):
			continue
		for g in r["gates"]:
			if _gate_matches(g):
				best = (g as Dictionary).duplicate()
				best["_z"] = z
				if _obj.is_empty():
					_obj = g
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


static func _nearest(list: Array) -> Dictionary:
	var best: Dictionary = {}
	for o in list:
		var z := float(o["z"])
		if z < -0.5 and (best.is_empty() or z > float(best["z"])):
			best = o
	return best


func _cam() -> Camera3D:
	if view == null or not view.is_inside_tree():
		return null
	return view.get_viewport().get_camera_3d()


# ---------------------------------------------------------------- drawing

func _draw_outline() -> void:
	if _out_t <= 0.0 or _pos.x < 0.0:
		return
	var t := _age
	var fade := minf(_out_t / 0.4, 1.0)
	var pulse := 0.5 + 0.5 * sin(t * 7.0)
	var r := _rad * (1.0 + 0.06 * pulse)
	_ellipse(_pos, r * 1.08, Color(GOLD, 0.25 * fade), 18.0)
	_ellipse(_pos, r, Color(UiKit.INK, 0.8 * fade), 11.0)
	_ellipse(_pos, r, Color(GOLD, fade), 6.0)
	# The "new" burst: a gold star badge with "!" that pops in, then breathes.
	var bp := _pos + Vector2(r.x * 0.78, -r.y * 0.92)
	var s := 30.0 * (1.0 + 0.1 * pulse) * minf(_age / 0.2, 1.0)
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0 - PI / 2.0
		pts.append(bp + Vector2(cos(a), sin(a)) * (s if i % 2 == 0 else s * 0.7))
	_canvas.draw_colored_polygon(pts, Color(UiKit.INK, fade))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(bp + (p - bp) * 0.84)
	_canvas.draw_colored_polygon(inner, Color(GOLD, fade))
	_canvas.draw_string(UiKit.FONT, bp + Vector2(-8, 13), "!", HORIZONTAL_ALIGNMENT_CENTER, 16, 36, Color(UiKit.INK, fade))
	for i in 4:   # sparkles circling the badge
		var a := t * 2.5 + TAU * i / 4.0
		_canvas.draw_circle(bp + Vector2(cos(a), sin(a)) * s * 1.5, 3.5, Color(1, 1, 0.8, 0.9 * fade))


func _ellipse(c: Vector2, r: Vector2, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	_canvas.draw_polyline(pts, col, w, true)

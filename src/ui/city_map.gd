class_name CityMap
extends Control
## The lobby's body: a tall scrolling map of the city, 5 districts x 10 levels, Downtown at the
## bottom and Uptown at the top (assets/city/map.png + map_layout.json, painted by ART).
## - Level nodes follow the road: green = beaten (0-3 stars under it), yellow = the current
##   level (pulses, with a ripple), blue = open, grey + lock = locked. Boss levels are bigger,
##   red, with a crown. The hero pin stands on the selected level.
## - Each district has a banner: district number, crown / boss crown / lock, levels beaten
##   "7/10" and stars "21/30". Districts not reached yet are greyed out with a big lock.
## - The 25 buildings stand on their plots, ruined or rebuilt (art changes with the save).
##   A coin bubble floats over earning buildings (tap: the city storage is collected and coins
##   fly to the counter), a price tag sits on ruins you can rebuild (a hammer bobs over it when
##   you can afford it), and a hammer + timer shows while one is being built.
## Drag to scroll with inertia (mouse wheel on PC). All taps are hit-tested here, so a drag
## that starts on a node never presses it. Tapping the selected node again asks to play it.

signal level_selected(level: int)              ## an open level was tapped; it is now `selected`
signal play_requested(level: int)              ## the selected level was tapped again
signal building_pressed(id: String)
signal collected(coins: int, from: Vector2)    ## a bubble was tapped: these coins are collected right after; from = bubble (global)

const LAYOUT_PATH := "res://assets/city/map_layout.json"
const BASE_W := 720.0          ## the map is laid out at this width, then scaled to the screen
const NODE := 92.0             ## level node diameter (base px)
const BOSS_NODE := 116.0
const PAD_TOP := 170.0         ## scroll room past the map's ends (its edge rows, stretched)
const PAD_BOTTOM := 200.0
const DRAG_START := 14.0       ## px a press must travel before it becomes a drag
const FRICTION := 4.5          ## inertia decay per second
const FOCUS := 0.6             ## a focused level sits at this fraction of the view height
const GRAY_SHADER := """shader_type canvas_item;
uniform float dark = 0.52;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(g) * dark, vec3(0.10, 0.12, 0.22), 0.18), c.a);
}
"""

const COLOR_LIBERATED := Color("43a047")
const COLOR_OCCUPIED := Color("e5463b")
const COLOR_LOCKED := Color("5b6170")

var selected := 1
var layout: Dictionary = {}
var map_h := 0.0                ## map height at BASE_W

var _k := 1.0                   # screen px per base px
var _content: Control
var _layers := {}
var _hand: TextureRect = null   # first-build pointer, then the best-next-purchase pointer
var _hand_at := ""
var _hand_tw: Tween = null
var _bands: Array = []          # [{d, rect, pads: [], lock}]
var _banners := {}              # district -> {box, num, icon, label, stars}
var _nodes := {}                # level -> {btn, c, r, stars, lock, crown}
var _bld := {}                  # id -> {...}
var _bld_order: Array = []      # back to front
var _bw := 316.8                # building sprite size (base px)
var _marker: Control
var _ripple: Panel
var _pulse_tw: Tween
var _scroll_tw: Tween
var _scroll := 0.0
var _vel := 0.0
var _press := false
var _drag := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _last_ms := 0
var _tick := 0.0
var _focus_pending := true
var _focus_level := 1
var _gray: ShaderMaterial


# ---------------------------------------------------------------- pure helpers (tested)

## The map layout, or a plain zig-zag one if the file is missing, so the lobby never crashes
## without its art.
static func load_layout() -> Dictionary:
	if FileAccess.file_exists(LAYOUT_PATH):
		var data: Variant = Config.load_json(LAYOUT_PATH)
		if data is Dictionary and (data as Dictionary).has("districts"):
			return data
	return fallback_layout()


static func fallback_layout(districts := 5, per := 10) -> Dictionary:
	var out := []
	var band_h := 1.0 / districts
	for d in range(1, districts + 1):
		var top := 1.0 - d * band_h
		var bottom := top + band_h
		var levels := []
		for i in per:
			var y := bottom - (i + 0.5) * band_h / per
			levels.append({"level": (d - 1) * per + i + 1, "pos": [0.25 if i % 2 == 0 else 0.62, y]})
		var blds := []
		var ids := City.buildings_in(d)
		for i in ids.size():
			blds.append({"id": ids[i], "pos": [0.78 if i % 2 == 0 else 0.4, bottom - (i + 0.7) * band_h / (ids.size() + 1)]})
		out.append({"id": d, "band": [top, bottom], "tile": "", "tint": "#ffffff", "buildings": blds, "levels": levels})
	return {"size": [720, 9600], "image": "", "building_pivot": [0.5, 0.808], "building_width": 0.36, "districts": out}


## The level the map focuses on and Play starts: the first level not beaten yet (the highest
## unlocked one when everything is beaten).
static func current_level(save: Dictionary, count: int) -> int:
	var top := clampi(int(save.get("unlocked", 1)), 1, maxi(count, 1))
	for n in range(1, top + 1):
		if not City.level_beaten(save, n):
			return n
	return top


## beaten | current | open | locked
static func node_state(save: Dictionary, n: int, count: int) -> String:
	if n < 1 or n > count or n > int(save.get("unlocked", 1)):
		return "locked"
	if City.level_beaten(save, n):
		return "beaten"
	return "current" if n == current_level(save, count) else "open"


## {beaten, total, stars, max_stars} for a district's banner.
static func district_progress(save: Dictionary, d: int, economy: Dictionary = {}) -> Dictionary:
	var per := Economy.district_levels(economy)
	var beaten := 0
	var stars := 0
	for n in range((d - 1) * per + 1, d * per + 1):
		if City.level_beaten(save, n):
			beaten += 1
		stars += clampi(int(save.get("stars", {}).get(str(n), 0)), 0, 3)
	return {"beaten": beaten, "total": per, "stars": stars, "max_stars": per * 3}


## Scroll offset kept inside the content (0 = top).
static func clamp_scroll(v: float, content_h: float, view_h: float) -> float:
	return clampf(v, 0.0, maxf(content_h - view_h, 0.0))


## Coin icons to fly for a collection (more coins, more icons, within reason).
static func fly_count(coins: int) -> int:
	return clampi(int(ceil(coins / 10.0)), 3, 12)


# ---------------------------------------------------------------- build

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	layout = load_layout()
	var sz: Array = layout.get("size", [604, 8192])
	map_h = BASE_W * float(sz[1]) / maxf(float(sz[0]), 1.0)
	_bw = float(layout.get("building_width", 0.44)) * BASE_W
	selected = current_level(Game.save, Config.LEVEL_COUNT)
	_focus_level = selected
	_gray = ShaderMaterial.new()
	_gray.shader = Shader.new()
	_gray.shader.code = GRAY_SHADER

	var bg := ColorRect.new()
	bg.color = Color("1d2740")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(bg)
	add_child(bg)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.size = Vector2(BASE_W, PAD_TOP + map_h + PAD_BOTTOM)
	add_child(_content)
	for n in ["map", "buildings", "locks", "nodes", "overlay", "pills", "banners", "marker"]:
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(c)
		_layers[n] = c
	_build_map()
	_build_buildings()
	_build_nodes()
	_build_marker()
	refresh()
	resized.connect(_relayout)
	Game.city_changed.connect(refresh_buildings)
	Game.coins_changed.connect(_on_coins)
	Game.stars_changed.connect(_on_stars)
	Game.build_finished.connect(_on_build_finished)
	_relayout()


func to_base(pos: Variant) -> Vector2:
	var p: Array = pos if pos is Array else [0.5, 0.5]
	return Vector2(float(p[0]) * BASE_W, PAD_TOP + float(p[1]) * map_h)


func _map_texture() -> Texture2D:
	var path := "res://assets/city/" + String(layout.get("image", ""))
	if String(layout.get("image", "")) == "" or not ResourceLoader.exists(path):
		return null
	# One 8192 px tall texture needs a GPU that takes it; otherwise use the five tiles.
	var rd := RenderingServer.get_rendering_device()
	var need := int((layout.get("size", [0, 8192]) as Array)[1])
	if rd == null or rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D) < need:
		return null
	return load(path) as Texture2D


func _band_texture(d: Dictionary, full: Texture2D) -> Texture2D:
	var band: Array = d.get("band", [0.0, 1.0])
	if full != null:
		var at := AtlasTexture.new()
		at.atlas = full
		var h := float(full.get_height())
		at.region = Rect2(0, float(band[0]) * h, full.get_width(), (float(band[1]) - float(band[0])) * h)
		return at
	var path := "res://assets/city/" + String(d.get("tile", ""))
	if String(d.get("tile", "")) != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## A few rows at the top or bottom edge of a band texture (stretched into the scroll pads).
static func _edge_strip(t: Texture2D, top: bool) -> Texture2D:
	var base: Texture2D = t
	var reg := Rect2(Vector2.ZERO, t.get_size())
	if t is AtlasTexture:
		base = (t as AtlasTexture).atlas
		reg = (t as AtlasTexture).region
	var at := AtlasTexture.new()
	at.atlas = base
	at.region = Rect2(reg.position.x, reg.position.y if top else reg.end.y - 3.0, reg.size.x, 3.0)
	return at


func _band_rect(tex: Texture2D, pos: Vector2, sz: Vector2, fill: Color) -> Control:
	var c: Control
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		c = r
	else:
		var cr := ColorRect.new()
		cr.color = fill
		c = cr
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = pos
	c.size = sz
	_layers["map"].add_child(c)
	return c


func _build_map() -> void:
	var full := _map_texture()
	var districts: Array = layout["districts"]
	for i in districts.size():
		var d: Dictionary = districts[i]
		var band: Array = d.get("band", [0.0, 1.0])
		var y0 := PAD_TOP + float(band[0]) * map_h
		var h := (float(band[1]) - float(band[0])) * map_h
		var tex := _band_texture(d, full)
		var fill := Color("5d9b45").darkened(0.12 * i)
		var rect := _band_rect(tex, Vector2(0, y0), Vector2(BASE_W, h + 1.0), fill)
		var pads := []
		if float(band[1]) >= 0.999:
			pads.append(_band_rect(_edge_strip(tex, false) if tex else null, Vector2(0, y0 + h), Vector2(BASE_W, PAD_BOTTOM), fill))
		if float(band[0]) <= 0.001:
			pads.append(_band_rect(_edge_strip(tex, true) if tex else null, Vector2(0, 0), Vector2(BASE_W, PAD_TOP + 1.0), fill))
		var lock := UiKit.icon("district_lock", 200)
		lock.size = Vector2(200, 200)
		lock.position = Vector2(BASE_W * 0.5 - 100, y0 + h * 0.5 - 100)
		lock.modulate.a = 0.92
		_layers["locks"].add_child(lock)
		_bands.append({"d": int(d.get("id", i + 1)), "rect": rect, "pads": pads, "lock": lock})
		_build_banner(d, districts)


## Banner near the top of a district, on the side away from the road.
func _build_banner(d: Dictionary, districts: Array) -> void:
	var id := int(d.get("id", 1))
	var band: Array = d.get("band", [0.0, 1.0])
	var road_x := 0.5
	var lv: Array = d.get("levels", [])
	if not lv.is_empty():
		road_x = float(lv[lv.size() - 1]["pos"][0])
		for other in districts:
			if int(other.get("id", 0)) == id + 1 and not (other.get("levels", []) as Array).is_empty():
				road_x = (road_x + float(other["levels"][0]["pos"][0])) * 0.5
	var w := 410.0
	var h := 84.0
	var cx := BASE_W * (0.29 if road_x > 0.5 else 0.71)
	var cy := maxf(PAD_TOP + float(band[0]) * map_h + 72.0, PAD_TOP + 210.0)
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = Vector2(w, h)
	box.position = Vector2(cx - w * 0.5, cy - h * 0.5)
	_layers["banners"].add_child(box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(row)
	row.offset_top = 2
	row.offset_bottom = -6
	box.add_child(row)
	var num := Panel.new()
	num.custom_minimum_size = Vector2(56, 56)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	num.add_theme_stylebox_override("panel", UiKit.flat_box(Color(0, 0, 0, 0.35), 28, 4))
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UiKit.label(str(id), 36, Color.WHITE, 8)
	UiKit.full_rect(nl)
	nl.offset_top = 3
	num.add_child(nl)
	row.add_child(num)
	var ic := UiKit.icon("crown", 58)
	row.add_child(ic)
	var lab := UiKit.label("0/10", 38, Color.WHITE, 10)
	row.add_child(lab)
	row.add_child(UiKit.icon("star_icon", 40))
	var st := UiKit.label("0/30", 30, UiKit.YELLOW, 9)
	row.add_child(st)
	_banners[id] = {"box": box, "icon": ic, "label": lab, "stars": st}


func _build_buildings() -> void:
	var piv: Array = layout.get("building_pivot", [0.5, 0.808])
	var list := []
	for d in layout["districts"]:
		var tint := Color.WHITE
		if String(d.get("tint", "")).is_valid_html_color():
			tint = Color(String(d["tint"]))
		for b in d.get("buildings", []):
			list.append({"id": String(b["id"]), "pos": to_base(b["pos"]), "d": int(d.get("id", 1)), "tint": tint})
	list.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
	for e in list:
		var id: String = e["id"]
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = e["pos"]
		_layers["buildings"].add_child(holder)
		var spr := TextureRect.new()
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spr.size = Vector2(_bw, _bw)
		spr.position = Vector2(-float(piv[0]) * _bw, -float(piv[1]) * _bw)
		spr.modulate = e["tint"]
		holder.add_child(spr)

		var over := Control.new()
		over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		over.position = e["pos"]
		_layers["overlay"].add_child(over)
		var badge := _badge("1", 46)
		badge.position = Vector2(_bw * 0.2, -40)
		over.add_child(badge)
		var tag := _pill_box(Vector2(150, 58), Color(0.05, 0.1, 0.25, 0.78), "coin", 40, 32)
		tag.position = Vector2(-75, -_bw * 0.34)
		over.add_child(tag)
		var hammer := UiKit.icon("hammer", 64)
		hammer.size = Vector2(64, 64)
		hammer.pivot_offset = Vector2(32, 52)
		hammer.position = Vector2(-32, tag.position.y - 66)
		over.add_child(hammer)
		_swing(hammer, 18.0, 0.42)
		var work := _pill_box(Vector2(176, 62), Color(0.1, 0.18, 0.42, 0.88), "hammer", 50, 32)
		work.position = Vector2(-88, -_bw * 0.5)
		over.add_child(work)
		var wic: Control = (work.get_meta("icon") as Control)
		wic.pivot_offset = Vector2(25, 40)
		_swing(wic, 26.0, 0.3)
		var bubble := _bubble()
		bubble.position = Vector2(-78, -_bw * 0.7)
		over.add_child(bubble)
		_bob(bubble, 7.0, 0.7)
		_bld[id] = {
			"pos": e["pos"], "d": e["d"], "tint": e["tint"], "holder": holder, "spr": spr,
			"over": over, "badge": badge, "tag": tag, "hammer": hammer, "work": work,
			"bubble": bubble, "status": "", "tex": "",
		}
		_bld_order.append(id)
	# First-build pointer (one time, no words): a hand tapping the cheapest ruin the new
	# player can afford, until the first building is started. After that the same hand bobs
	# over the best next purchase (Game.best_purchase) when it is a building.
	_hand = UiKit.icon("hand", 120)
	_hand.size = Vector2(120, 120)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.z_index = 0
	_hand.visible = false
	_layers["overlay"].add_child(_hand)


func _point_hand(cheapest: String) -> void:
	if _hand == null:
		return
	var show := cheapest != ""
	if show and _hand_at != cheapest:
		_hand_at = cheapest
		var tag: Control = _bld[cheapest]["tag"]
		# Fingertip (the icon's lower right) on the price tag.
		var tip: Vector2 = _bld[cheapest]["pos"] + tag.position + tag.size * 0.5
		_hand.position = tip - Vector2(108, 108)
		if _hand_tw:
			_hand_tw.kill()
		_hand_tw = _hand.create_tween().set_loops()
		var p := _hand.position
		_hand_tw.tween_property(_hand, "position", p - Vector2(22, 22), 0.35).set_trans(Tween.TRANS_SINE)
		_hand_tw.tween_property(_hand, "position", p, 0.35).set_trans(Tween.TRANS_SINE)
	_hand.visible = show
	if not show:
		_hand_at = ""
		if _hand_tw:
			_hand_tw.kill()
			_hand_tw = null


func _build_nodes() -> void:
	_ripple = Panel.new()
	_ripple.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ripple.add_theme_stylebox_override("panel", UiKit.flat_box(Color(1, 0.85, 0.25, 0.0), 80, 7, UiKit.YELLOW))
	_layers["nodes"].add_child(_ripple)
	for d in layout["districts"]:
		for l in d.get("levels", []):
			var n := int(l["level"])
			var c := to_base(l["pos"])
			var boss := Economy.is_boss(n, Game.economy)
			var dia := BOSS_NODE if boss else NODE
			var b := UiKit.button(str(n), "blue", 52 if boss else 44, Vector2(dia, dia), "round")
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.size = Vector2(dia, dia)
			b.position = c - b.size * 0.5
			b.pivot_offset = b.size * 0.5
			_layers["nodes"].add_child(b)
			var lock := UiKit.icon("lock", 42)
			lock.size = Vector2(42, 42)
			lock.position = Vector2(dia - 36, dia - 46)
			b.add_child(lock)
			var stars := []
			for i in 3:
				var s := UiKit.icon("star_icon", 38)
				s.size = Vector2(38, 38)
				s.position = c + Vector2(-19 + (i - 1) * 34, dia * 0.5 - (22 if i == 1 else 28))
				_layers["nodes"].add_child(s)
				stars.append(s)
			var crown: Control = null
			if boss:
				crown = UiKit.icon("boss_crown", 72)
				crown.size = Vector2(72, 72)
				crown.position = c + Vector2(-36, -dia * 0.5 - 58)
				_layers["nodes"].add_child(crown)
			# Recommended Squad Power (v1.1): a small pill under the nodes ahead of the player;
			# red with a warning tint on the node when the squad is weaker than that.
			var pw := _pill_box(Vector2(124, 46), Color(0.05, 0.1, 0.25, 0.8), "power", 36, 28)
			pw.position = c + Vector2(-62, dia * 0.5 - 8)
			pw.visible = false
			_layers["pills"].add_child(pw)  # above the building price tags
			_nodes[n] = {"btn": b, "c": c, "r": dia * 0.5, "stars": stars, "lock": lock, "crown": crown, "power": pw}


func _build_marker() -> void:
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers["marker"].add_child(_marker)
	var pin := UiKit.icon("map_pin", 92)
	pin.size = Vector2(92, 92)
	pin.position = Vector2(-46, -NODE * 0.5 - 92)
	_marker.add_child(pin)
	_bob(pin, 10.0, 0.45)


func _badge(text: String, dia: float) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = Vector2(dia, dia)
	p.add_theme_stylebox_override("panel", UiKit.flat_box(UiKit.BLUE, int(dia * 0.5), 4))
	var l := UiKit.label(text, int(dia * 0.62), Color.WHITE, 8)
	UiKit.full_rect(l)
	l.offset_top = 2
	p.add_child(l)
	p.set_meta("label", l)
	return p


## Fixed-size rounded box with an icon and a number, centred.
func _pill_box(sz: Vector2, color: Color, icon_name: String, icon_px: int, font_px: int) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = sz
	p.add_theme_stylebox_override("panel", UiKit.flat_box(color, int(sz.y * 0.5), 4))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(row)
	p.add_child(row)
	var ic := UiKit.icon(icon_name, icon_px)
	row.add_child(ic)
	var l := UiKit.label("0", font_px, Color.WHITE, 8)
	row.add_child(l)
	p.set_meta("icon", ic)
	p.set_meta("label", l)
	return p


## Cream coin bubble with a little tail.
func _bubble() -> Control:
	var b := _pill_box(Vector2(156, 70), UiKit.CREAM, "coin", 48, 34)
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(66, 66), Vector2(90, 66), Vector2(78, 86)])
	tail.color = UiKit.CREAM
	b.add_child(tail)
	b.move_child(tail, 0)
	var sb: StyleBoxFlat = b.get_theme_stylebox("panel")
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	return b


func _bob(c: Control, amount: float, half: float) -> void:
	var y := c.position.y
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "position:y", y - amount, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c, "position:y", y, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _swing(c: Control, degrees: float, half: float) -> void:
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "rotation_degrees", -degrees, half).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "rotation_degrees", degrees * 0.4, half).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- state

func refresh() -> void:
	refresh_levels()
	refresh_buildings()


func refresh_levels() -> void:
	var save: Dictionary = Game.save
	var count := Config.LEVEL_COUNT
	var cur := current_level(save, count)
	if node_state(save, selected, count) == "locked":
		selected = cur
	var power := Game.squad_power()
	var quiet := Game.first_build_pending()
	for n in _nodes:
		var e: Dictionary = _nodes[n]
		var st := node_state(save, n, count)
		var boss: bool = e["crown"] != null
		var color: String = {"beaten": "green", "current": "yellow", "open": "blue", "locked": "grey"}[st]
		if boss and (st == "current" or st == "open"):
			color = "red"
		var b: Button = e["btn"]
		var box := _node_box(color)
		for s in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(s, box)
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.62) if st == "locked" else Color.WHITE)
		(e["lock"] as Control).visible = st == "locked"
		var got := clampi(int(save.get("stars", {}).get(str(n), 0)), 0, 3)
		for i in 3:
			var s: Control = e["stars"][i]
			s.visible = st == "beaten"
			s.modulate = Color.WHITE if i < got else Color(0.18, 0.13, 0.1, 0.75)
		if e["crown"] != null:
			(e["crown"] as Control).modulate = Color(0.45, 0.45, 0.5, 0.85) if st == "locked" else Color.WHITE
		var pw: Panel = e["power"]
		var rec := Game.recommended_power(n)
		var info := power_hint(st, n, cur, rec, power, quiet)
		pw.visible = bool(info["show"])
		b.modulate = WARN_TINT if bool(info["warn"]) else Color.WHITE
		if pw.visible:
			(pw.get_meta("label") as Label).text = Economy.fmt_power(rec)
			var psb: StyleBoxFlat = pw.get_theme_stylebox("panel")
			psb.bg_color = Color(0.85, 0.2, 0.15, 0.92) if bool(info["warn"]) else Color(0.05, 0.1, 0.25, 0.8)
	_set_current(cur)
	_place_marker(false)
	for band in _bands:
		var reached := City.district_reached(save, int(band["d"]), Game.economy)
		(band["rect"] as CanvasItem).material = null if reached else _gray
		for p in band["pads"]:
			(p as CanvasItem).material = null if reached else _gray
		(band["lock"] as Control).visible = not reached
	for d in _banners:
		var e: Dictionary = _banners[d]
		var p := district_progress(save, d, Game.economy)
		(e["label"] as Label).text = "%d/%d" % [p["beaten"], p["total"]]
		(e["stars"] as Label).text = "%d/%d" % [p["stars"], p["max_stars"]]
		var col := COLOR_LOCKED
		var icon_name := "district_lock"
		if City.district_liberated(save, d, Game.economy):
			col = COLOR_LIBERATED
			icon_name = "crown"
		elif City.district_reached(save, d, Game.economy):
			col = COLOR_OCCUPIED
			icon_name = "boss_crown"
		var sb := UiKit.flat_box(col, 22, 5)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 6)
		(e["box"] as Panel).add_theme_stylebox_override("panel", sb)
		(e["icon"] as TextureRect).texture = UiKit.icon_texture(icon_name)


const WARN_TINT := Color(1.0, 0.62, 0.55)
const TOP_BAR_Y := 120.0          ## screen y (px) of the lobby top bar's lower edge
const POWER_AHEAD := 4            ## the power pill shows on the current level and this many after it


const WARN_GAP := 1.15             ## warn only when the recommendation is this far above the power
const WARN_AHEAD := 1              ## only the current node and this many after it can warn


## Whether a level node shows its recommended power, and whether it warns (pure, tested):
## not on beaten levels, only from the current level to POWER_AHEAD levels past it. Every level
## is winnable without upgrades, so it warns only on the current or next node, only when the
## recommendation is more than WARN_GAP above the player's Squad Power, and never while the
## first-build pointer is up (`quiet`), so the map never says "too weak" and "build this" at once.
static func power_hint(state: String, n: int, current: int, rec: float, power: float, quiet := false) -> Dictionary:
	var show := state != "beaten" and rec > 0 and n >= current and n <= current + POWER_AHEAD
	var warn := show and not quiet and n <= current + WARN_AHEAD and float(rec) > float(power) * WARN_GAP
	return {"show": show, "warn": warn}


## The whole round button texture scaled to the node (no 9-slice, so it stays a circle).
static var _node_boxes := {}


static func _node_box(color: String) -> StyleBoxTexture:
	if not _node_boxes.has(color):
		var sb := StyleBoxTexture.new()
		var path := String(UiKit.BUTTON_TEX.get(color, UiKit.BUTTON_TEX["blue"])) % "round"
		sb.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
		sb.content_margin_top = 2
		sb.content_margin_bottom = 12
		_node_boxes[color] = sb
	return _node_boxes[color]


## Pulse + ripple on the current level node.
func _set_current(n: int) -> void:
	if _pulse_tw:
		_pulse_tw.kill()
	for k in _nodes:
		(_nodes[k]["btn"] as Control).scale = Vector2.ONE
	if not _nodes.has(n) or node_state(Game.save, n, Config.LEVEL_COUNT) != "current":
		_ripple.visible = false
		return
	var e: Dictionary = _nodes[n]
	var b: Button = e["btn"]
	_pulse_tw = b.create_tween().set_loops()
	_pulse_tw.tween_property(b, "scale", Vector2.ONE * 1.1, 0.5).set_trans(Tween.TRANS_SINE)
	_pulse_tw.tween_property(b, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	_ripple.visible = true
	_ripple.size = b.size
	_ripple.pivot_offset = b.size * 0.5
	_ripple.position = e["c"] - b.size * 0.5
	if not _ripple.has_meta("tw"):
		var tw := _ripple.create_tween().set_loops()
		tw.tween_property(_ripple, "scale", Vector2.ONE * 1.75, 1.1).from(Vector2.ONE)
		tw.parallel().tween_property(_ripple, "modulate:a", 0.0, 1.1).from(1.0)
		_ripple.set_meta("tw", tw)


func _place_marker(animate: bool) -> void:
	if not _nodes.has(selected):
		_marker.visible = false
		return
	_marker.visible = true
	var e: Dictionary = _nodes[selected]
	var at: Vector2 = e["c"] - Vector2(0, (float(e["r"]) - NODE * 0.5) + (62.0 if e["crown"] != null else 0.0))
	if animate:
		var tw := _marker.create_tween()
		tw.tween_property(_marker, "position", at, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_marker.position = at


func refresh_buildings() -> void:
	if _bld.is_empty():
		return
	var cheapest := ""
	var cheapest_cost := 1 << 30
	var pointing := Game.first_build_pending()
	var best: Dictionary = {} if pointing else Game.best_purchase()
	var save: Dictionary = Game.save
	var eco: Dictionary = Game.economy
	var t: int = Game.now()
	var pend := City.pending_by_building(save, t, eco)
	var coins := int(save.get("coins", 0))
	for id in _bld:
		var e: Dictionary = _bld[id]
		var st := City.status(save, id, t, eco)
		var earning := City.level(save, id, t)
		var tex_name := "%s" % id if earning >= 1 else "%s_ruin" % id
		if e["tex"] != tex_name:
			e["tex"] = tex_name
			var path := "res://assets/city/%s.png" % tex_name
			(e["spr"] as TextureRect).texture = load(path) as Texture2D if ResourceLoader.exists(path) else UiKit.icon_texture("city_hall")
		(e["spr"] as CanvasItem).material = _gray if st == "locked" else null
		var badge: Panel = e["badge"]
		badge.visible = earning >= 2
		(badge.get_meta("label") as Label).text = str(earning)
		var work: Panel = e["work"]
		work.visible = st == "building"
		if work.visible:
			(work.get_meta("label") as Label).text = UiKit.fmt_time(City.remaining(save, id, t))
		var tag: Panel = e["tag"]
		var cost := City.next_cost(save, id, eco)
		var can := (st == "ruin" or st == "built") and cost >= 0 and coins >= cost and City.can_start(save, id, t, eco) == ""
		# Ruins always show their price; built ones only when the upgrade is affordable now.
		tag.visible = st == "ruin" or can
		if tag.visible:
			(tag.get_meta("label") as Label).text = UiKit.fmt_coins(cost)
			if pointing and can and cost < cheapest_cost:
				cheapest = id
				cheapest_cost = cost
			tag.modulate = Color.WHITE if can else Color(1, 1, 1, 0.8)
			var sb: StyleBoxFlat = tag.get_theme_stylebox("panel")
			sb.bg_color = Color(0.12, 0.55, 0.2, 0.92) if can else Color(0.05, 0.1, 0.25, 0.78)
		(e["hammer"] as Control).visible = can
		var bubble: Panel = e["bubble"]
		var amount := int(pend.get(id, 0))
		bubble.visible = amount >= 1
		if bubble.visible:
			(bubble.get_meta("label") as Label).text = UiKit.fmt_coins(amount)
		e["status"] = st
	if not pointing and String(best.get("kind", "")) == "building" and _bld.has(String(best["id"])):
		cheapest = String(best["id"])
	_point_hand(cheapest)


# ---------------------------------------------------------------- scrolling and input

func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_k = size.x / BASE_W
	_content.scale = Vector2(_k, _k)
	if _focus_pending:
		_focus_pending = false
		focus_level(_focus_level, false)
	else:
		_set_scroll(_scroll)


func _set_scroll(v: float) -> void:
	_scroll = clamp_scroll(v, _content.size.y * _k, size.y)
	_content.position = Vector2(0, -_scroll)


## Scrolls so level n sits a bit below the middle of the view.
func focus_level(n: int, animate := true) -> void:
	if not _nodes.has(n):
		return
	if size.y <= 0.0:
		_focus_pending = true
		_focus_level = n
		return
	var target := clamp_scroll((_nodes[n]["c"] as Vector2).y * _k - size.y * FOCUS, _content.size.y * _k, size.y)
	_vel = 0.0
	if _scroll_tw:
		_scroll_tw.kill()
	if animate:
		_scroll_tw = create_tween()
		_scroll_tw.tween_method(_set_scroll, _scroll, target, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_set_scroll(target)


## After a win: the map opens on the level just beaten, then the pin hops to the new current
## level and the map glides there (call right after the lobby is shown).
func advance_from(prev: int) -> void:
	if not _nodes.has(prev) or prev == selected:
		return
	var target := selected
	selected = prev
	_place_marker(false)
	selected = target
	focus_level(prev, false)
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(_hop_to_selected)


func _hop_to_selected() -> void:
	focus_level(selected, true)
	_place_marker(true)
	Sfx.play("unlock")


func select(n: int) -> void:
	if node_state(Game.save, n, Config.LEVEL_COUNT) == "locked":
		return
	selected = n
	_place_marker(true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				if _scroll_tw:
					_scroll_tw.kill()
				_vel = 0.0
				_set_scroll(_scroll + (-110.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 110.0))
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press = true
			_drag = false
			_press_pos = mb.position
			_last_pos = mb.position
			_last_ms = Time.get_ticks_msec()
			_vel = 0.0
			if _scroll_tw:
				_scroll_tw.kill()
		elif _press:
			_press = false
			if not _drag:
				_tap(mb.position)
			elif Time.get_ticks_msec() - _last_ms > 90:
				_vel = 0.0  # the finger stopped before lifting: no fling
		accept_event()
	elif event is InputEventMouseMotion and _press:
		var mm := event as InputEventMouseMotion
		if not _drag and mm.position.distance_to(_press_pos) > DRAG_START:
			_drag = true
		if _drag:
			var dy := mm.position.y - _last_pos.y
			_set_scroll(_scroll - dy)
			var ms := Time.get_ticks_msec()
			var dt := maxf((ms - _last_ms) / 1000.0, 0.004)
			_vel = lerpf(_vel, -dy / dt, 0.4)
			_last_ms = ms
		_last_pos = mm.position
		accept_event()


func _process(delta: float) -> void:
	if not _press and _vel != 0.0:
		var before := _scroll
		_set_scroll(_scroll + _vel * delta)
		_vel *= exp(-FRICTION * delta)
		if absf(_vel) < 15.0 or is_equal_approx(before, _scroll):
			_vel = 0.0
	_tick += delta
	if _tick >= 0.5:
		_tick = 0.0
		refresh_buildings()
	# Recommended-power pills fade out under the lobby's top bar, so they never sit next to
	# (and read as part of) the player's own power number.
	for n in _nodes:
		var pw: Control = _nodes[n]["power"]
		if pw.visible:
			pw.modulate.a = clampf((pw.global_position.y - TOP_BAR_Y) / 40.0, 0.0, 1.0)


## Content point (base px) under a point of this control.
func to_content(p: Vector2) -> Vector2:
	return (p - _content.position) / _k


func _tap(p: Vector2) -> void:
	var q := to_content(p)
	for id in _bld:
		var e: Dictionary = _bld[id]
		var bub: Control = e["bubble"]
		if bub.visible and Rect2((e["over"] as Control).position + bub.position, bub.size).grow(16).has_point(q):
			_collect(bub)
			return
	var best := -1
	var best_d := INF
	for n in _nodes:
		var dist := q.distance_to(_nodes[n]["c"])
		if dist < float(_nodes[n]["r"]) + 16.0 and dist < best_d:
			best = n
			best_d = dist
	if best > 0:
		_tap_node(best)
		return
	for i in range(_bld_order.size() - 1, -1, -1):
		var id: String = _bld_order[i]
		var pos: Vector2 = _bld[id]["pos"]
		if Rect2(pos.x - _bw * 0.3, pos.y - _bw * 0.62, _bw * 0.6, _bw * 0.74).has_point(q):
			Sfx.play("tap")
			UiKit.bump(_bld[id]["spr"], 1.06)
			building_pressed.emit(id)
			return


func _tap_node(n: int) -> void:
	var b: Button = _nodes[n]["btn"]
	if node_state(Game.save, n, Config.LEVEL_COUNT) == "locked":
		Sfx.play("error")
		UiKit.shake(b)
		return
	Sfx.play("tap")
	if n == selected:
		play_requested.emit(n)
		return
	select(n)
	level_selected.emit(n)


## Collects through the first visible coin bubble (debug args, tests). False if none shows.
func collect_any() -> bool:
	for id in _bld_order:
		var bub: Control = _bld[id]["bubble"]
		if bub.visible:
			_collect(bub)
			return true
	return false


func _collect(bubble: Control) -> void:
	var from := bubble.get_global_rect().get_center()
	var amount: int = Game.city_pending()
	if amount <= 0:
		return
	Sfx.play("collect")
	collected.emit(amount, from)  # first, so the counter can hold its number while coins fly
	Game.city_collect(1)


func _on_coins(_c: int) -> void:
	refresh_buildings()


func _on_stars(_total: int) -> void:
	refresh_levels()


func _on_build_finished(id: String) -> void:
	refresh_buildings()
	if _bld.has(id):
		Sfx.play("build_done")
		UiKit.pop(_bld[id]["holder"], 0.7)

class_name FinaleHud
extends CanvasLayer
## Bottle Shot HUD, icons and numbers only:
##   top left   bottles still standing (bottle icon + number)
##   top        the reward multiplier (×N, jumps with a sunburst)
##   right      the combo (flame + hits in a row), big while a streak runs, cracks and fades on a miss
##   bottom     ammo: one icon per shot (knife, bullet, arrow, star) + the number left;
##              a pistol shows its magazine as rounds and the spare rounds as +N
##   top left (under the bottles)  wind (bow): an arrow showing its direction and strength + m/s
##   reload     a pulsing magazine with a swipe-down arrow when the pistol is empty
##   reticle    where the shot goes: a green pin (bow) or a crosshair (pistol); the weapon
##              moves it every frame while aiming

const AMMO_ICONS := {"knife": "knife", "pistol": "bullet", "sniper": "bullet", "bow": "arrow", "stars": "star"}

var logic: BottleLogic
var _flash: ColorRect
var _bottle_n: Label
var _ammo_row: HBoxContainer
var _ammo_icons: Array = []
var _ammo_n: Label
var _mult_root: Control
var _mult_label: Label
var _rays: Rays
var _combo_root: Control
var _combo_label: Label
var _flame: Glyph
var _wind_root: Control
var _wind_glyph: Glyph
var _wind_label: Label
var _reload: Control
var _reticle: Glyph
var _wind_max := 1.5
var _reload_t := 0.0
var _mult_shown := 1.0
var _mult_from := 1.0
var _mult_to := 1.0
var _mult_t := 1.0
var _punch := 0.0
var _punch_gold := false
var _combo_shown := 0
var _combo_punch := 0.0
var _combo_break := 0.0
var ghosted := false            # a see-through copy drawn while the level loads (_ghost_all)
const GHOST_ALPHA := 0.01       # still drawn (its pipelines compile), far too faint to see


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


## Small drawn icons the icon set lacks: bullet, arrow, star, flame, wind arrow, magazine.
class Glyph extends Control:
	var kind := "bullet"
	var color := Color.WHITE
	var angle := 0.0

	func _init(k: String, px: int, c := Color.WHITE) -> void:
		kind = k
		color = c
		custom_minimum_size = Vector2(px, px)
		size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var ink := UiKit.INK
		match kind:
			"bullet":
				# Upright cartridge: brass case, copper ogive.
				var w := s * 0.26
				var case_r := Rect2(c.x - w * 0.5, c.y - s * 0.05, w, s * 0.45)
				draw_rect(case_r.grow(3), ink)
				var tip := PackedVector2Array()
				for k in 9:
					var a := PI * k / 8.0
					tip.append(Vector2(c.x - cos(a) * w * 0.5, c.y - s * 0.05 - sin(a) * s * 0.4))
				draw_colored_polygon(_grow(tip, c, 3.0), ink)
				draw_rect(case_r, Color("d6a84a") * color)
				draw_colored_polygon(tip, Color("c46a3a") * color)
				draw_rect(Rect2(case_r.position.x, case_r.end.y - s * 0.07, w, s * 0.07), Color("a8822f") * color)
			"arrow":
				var a := c + Vector2(-s * 0.36, s * 0.36)
				var b := c + Vector2(s * 0.36, -s * 0.36)
				draw_line(a, b, ink, s * 0.14)
				draw_line(a, b, Color("caa36a") * color, s * 0.07)
				var d := (b - a).normalized()
				var n := Vector2(-d.y, d.x)
				var head := PackedVector2Array([b + d * s * 0.08, b - d * s * 0.2 + n * s * 0.12, b - d * s * 0.2 - n * s * 0.12])
				draw_colored_polygon(_grow(head, b, 3.0), ink)
				draw_colored_polygon(head, Color("dfe4ea") * color)
				for k in 2:
					var f := a + d * s * (0.06 + k * 0.1)
					draw_line(f, f - d * s * 0.1 + n * s * 0.13, Color("e0484f") * color, s * 0.06)
					draw_line(f, f - d * s * 0.1 - n * s * 0.13, Color("e0484f") * color, s * 0.06)
			"star":
				var pts := PackedVector2Array()
				for k in 8:
					var r := s * (0.46 if k % 2 == 0 else 0.16)
					var a := angle + TAU * k / 8.0
					pts.append(c + Vector2(cos(a), sin(a)) * r)
				draw_colored_polygon(_grow(pts, c, 3.0), ink)
				draw_colored_polygon(pts, Color("c9d1da") * color)
				draw_circle(c, s * 0.07, ink)
			"flame":
				var pts := PackedVector2Array()
				for k in 25:
					var t := TAU * k / 24.0
					# A teardrop with a flicked tip.
					var r := s * 0.3
					var p := Vector2(sin(t) * r, -cos(t) * r)
					if p.y < 0.0:
						p.x *= 1.0 + p.y / (s * 0.3) * 0.75
						p.y *= 1.65
					pts.append(c + Vector2(0, s * 0.12) + p)
				draw_colored_polygon(_grow(pts, c, 4.0), ink)
				draw_colored_polygon(pts, Color("ff7a1a") * color)
				var inner := PackedVector2Array()
				for p in pts:
					inner.append(c + Vector2(0, s * 0.2) + (p - c - Vector2(0, s * 0.12)) * 0.55)
				draw_colored_polygon(inner, Color("ffd23f") * color)
			"wind":
				var d := Vector2(cos(angle), sin(angle))
				var n := Vector2(-d.y, d.x)
				var a := c - d * s * 0.38
				var b := c + d * s * 0.3
				draw_line(a, b, ink, s * 0.16)
				draw_line(a, b, Color("bfe6ff") * color, s * 0.08)
				var head := PackedVector2Array([c + d * s * 0.46, b - d * s * 0.04 + n * s * 0.2, b - d * s * 0.04 - n * s * 0.2])
				draw_colored_polygon(_grow(head, b, 3.0), ink)
				draw_colored_polygon(head, Color("bfe6ff") * color)
			"pin":
				# Bow pin sight: a ring with a glowing green bead and a short post under it.
				draw_arc(c, s * 0.34, 0.0, TAU, 40, ink, s * 0.1)
				draw_arc(c, s * 0.34, 0.0, TAU, 40, Color("e9f7ff") * color, s * 0.05)
				draw_line(c + Vector2(0, s * 0.1), c + Vector2(0, s * 0.3), ink, s * 0.08)
				draw_line(c + Vector2(0, s * 0.1), c + Vector2(0, s * 0.3), Color("e9f7ff") * color, s * 0.035)
				draw_circle(c, s * 0.1, ink)
				draw_circle(c, s * 0.075, Color("6dff7a") * color)
				draw_circle(c - Vector2(s * 0.025, s * 0.025), s * 0.025, Color(1, 1, 1, 0.85))
			"cross":
				# Pistol crosshair: four ticks around a small gap and a red centre dot.
				for k in 4:
					var d := Vector2.from_angle(PI * 0.5 * k)
					draw_line(c + d * s * 0.14, c + d * s * 0.42, ink, s * 0.1)
					draw_line(c + d * s * 0.14, c + d * s * 0.42, Color.WHITE * color, s * 0.045)
				draw_circle(c, s * 0.065, ink)
				draw_circle(c, s * 0.045, Color("ff4a3d") * color)
			"mag":
				var r := Rect2(c.x - s * 0.16, c.y - s * 0.34, s * 0.32, s * 0.6)
				draw_rect(r.grow(3), ink)
				draw_rect(r, Color("3a3f46") * color)
				draw_rect(Rect2(c.x - s * 0.1, r.position.y - s * 0.09, s * 0.2, s * 0.09), Color("d6a84a") * color)
				# Swipe-down chevrons under it.
				for k in 2:
					var y := r.end.y + s * (0.08 + k * 0.1)
					draw_polyline(PackedVector2Array([Vector2(c.x - s * 0.16, y), Vector2(c.x, y + s * 0.08), Vector2(c.x + s * 0.16, y)]), Color.WHITE * color, s * 0.05)

	static func _grow(pts: PackedVector2Array, c: Vector2, px: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(p + (p - c).normalized() * px)
		return out


func setup(l: BottleLogic) -> FinaleHud:
	logic = l
	return self


func _ready() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(_flash)
	add_child(_flash)
	# Bottles left.
	var tl := HBoxContainer.new()
	tl.position = Vector2(24, 34)
	tl.add_theme_constant_override("separation", 8)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tl)
	tl.add_child(UiKit.icon("bottle", 64))
	_bottle_n = UiKit.label("0", 56, Color.WHITE, 12)
	tl.add_child(_bottle_n)
	# Ammo row.
	_ammo_row = HBoxContainer.new()
	_ammo_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_ammo_row.offset_top = -150
	_ammo_row.offset_bottom = -60
	_ammo_row.offset_left = -260
	_ammo_row.offset_right = 260
	_ammo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ammo_row.add_theme_constant_override("separation", 10)
	_ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ammo_row)
	var per := logic.mag_size if logic.mag_size > 0 else logic.shots_left
	var px := 72 if per <= 5 else 58 if per <= 7 else 46
	for i in mini(per, 10):
		var icon: Control
		var kind := String(AMMO_ICONS.get(logic.weapon, "knife"))
		if kind == "knife":
			icon = UiKit.icon("knife", px)
		else:
			icon = Glyph.new(kind, px)
		_ammo_row.add_child(icon)
		_ammo_icons.append(icon)
	_ammo_n = UiKit.label("", 48, Color.WHITE, 10)
	_ammo_row.add_child(_ammo_n)
	# Multiplier.
	_mult_root = Control.new()
	_mult_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_mult_root.offset_top = 110
	_mult_root.offset_bottom = 260
	_mult_root.offset_left = -200
	_mult_root.offset_right = 200
	_mult_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mult_root)
	_rays = Rays.new()
	UiKit.full_rect(_rays)
	_rays.offset_left = 40
	_rays.offset_right = -40
	_rays.offset_top = -60
	_rays.offset_bottom = 60
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mult_root.add_child(_rays)
	# The reward multiplier is the smaller number, behind a coin (what it multiplies); the combo
	# (flame) is the big one, so the two "×" never read as the same thing.
	var mrow := HBoxContainer.new()
	UiKit.full_rect(mrow)
	mrow.alignment = BoxContainer.ALIGNMENT_CENTER
	mrow.add_theme_constant_override("separation", 6)
	mrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mult_root.add_child(mrow)
	var coin := UiKit.icon("coin", 52)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(coin)
	_mult_label = UiKit.label("×1", 58, UiKit.GOLD, 14)
	_mult_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mult_label.modulate.a = 0.85
	mrow.add_child(_mult_label)
	# Combo: flame + ×N, right side.
	_combo_root = Control.new()
	# Top right, above the target area (mid-screen it covered the top shelf).
	_combo_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_combo_root.offset_left = -330
	_combo_root.offset_right = -22
	_combo_root.offset_top = 8
	_combo_root.offset_bottom = 148
	_combo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_root.modulate.a = 0.0
	add_child(_combo_root)
	_flame = Glyph.new("flame", 110)
	_flame.position = Vector2(0, 10)
	_flame.size = Vector2(110, 110)
	_combo_root.add_child(_flame)
	_combo_label = UiKit.label("2", 88, Color("ffb13a"), 18)
	# Anchored to the right edge and growing leftwards: a wide "×2.5" never runs off screen.
	_combo_label.anchor_left = 1.0
	_combo_label.anchor_right = 1.0
	_combo_label.offset_left = -208
	_combo_label.offset_right = 0
	_combo_label.offset_top = 10
	_combo_label.offset_bottom = 126
	_combo_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_root.add_child(_combo_label)
	# Wind (bow).
	_wind_root = Control.new()
	_wind_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)  # under the bottle count
	_wind_root.offset_left = 10
	_wind_root.offset_right = 164
	_wind_root.offset_top = 110
	_wind_root.offset_bottom = 230
	_wind_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wind_root.visible = false
	add_child(_wind_root)
	_wind_glyph = Glyph.new("wind", 76)
	_wind_glyph.position = Vector2(40, 0)
	_wind_glyph.size = Vector2(76, 76)
	_wind_root.add_child(_wind_glyph)
	_wind_label = UiKit.label("0", 36, Color.WHITE, 8)
	_wind_label.position = Vector2(0, 70)
	_wind_label.size = Vector2(154, 50)
	_wind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wind_root.add_child(_wind_label)
	# Reload prompt (pistol).
	_reload = Glyph.new("mag", 120)
	_reload.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_reload.offset_left = 120
	_reload.offset_right = 240
	_reload.offset_top = -330
	_reload.offset_bottom = -210
	_reload.visible = false
	add_child(_reload)
	# Reticle (bow pin / pistol crosshair), placed by the weapon each frame.
	_reticle = Glyph.new("pin", 64)
	_reticle.visible = false
	add_child(_reticle)
	_wind_max = wind_max(logic)
	refresh()
	if ghosted:
		_ghost_all()


## Level-load prewarm (BottleShot dormant): every part at once, nearly see-through, with every
## character the finale writes at each size, so the canvas pipelines and the font's glyphs are
## ready before the burst into the stash and the first bottle (this copy is freed after).
func _ghost_all() -> void:
	for c in get_children():
		(c as CanvasItem).visible = true
		(c as CanvasItem).modulate.a = GHOST_ALPHA
	_flash.color.a = 0.5   # full screen: keep it far below what an eye could catch
	_rays.color.a = 1.0
	_reticle.position = Vector2(300, 600)
	_reload.offset_top = -330
	for l in [_bottle_n, _ammo_n, _mult_label, _combo_label, _wind_label]:
		(l as Label).text = "×+.0123456789"


## Re-reads counts from the logic (call after a shot is visually resolved or a reload).
func refresh(show_spent := -1) -> void:
	_bottle_n.text = str(logic.remaining()) if show_spent < 0 else str(show_spent)
	var mag := logic.mag_size > 0
	var have := logic.mag_left if mag else logic.shots_left
	for i in _ammo_icons.size():
		(_ammo_icons[i] as Control).modulate.a = 1.0 if i < have else 0.18
	if mag:
		var spare := logic.shots_left - logic.mag_left
		_ammo_n.text = "+%d" % spare if spare > 0 else ""
	else:
		_ammo_n.text = str(logic.shots_left) if _ammo_icons.size() < logic.shots_left or logic.shots_left > 5 else ""


func set_bottles(n: int) -> void:
	_bottle_n.text = str(n)


## Wind arrow: hidden when calm (anything that would read "0.0"); otherwise it points the way
## the wind blows, its length and opacity grow with the strength, and the number says how strong.
func set_wind(w: float) -> void:
	var v := wind_view(w, _wind_max)
	_wind_root.visible = bool(v["visible"])
	_wind_glyph.angle = float(v["angle"])
	var k := float(v["length"])
	_wind_glyph.pivot_offset = _wind_glyph.size * 0.5
	_wind_glyph.scale = Vector2(k, 1.0)
	_wind_glyph.modulate.a = 0.5 + 0.5 * k
	_wind_glyph.queue_redraw()
	_wind_label.text = String(v["text"])


## Pure: how the wind indicator shows wind `w` (m/s^2, + = to the right) when the strongest wind
## in the game is `w_max`: {visible, angle (0 right, PI left), length 0.35..1, text}.
static func wind_view(w: float, w_max: float) -> Dictionary:
	var text := "%.1f" % absf(w)
	var k := clampf(absf(w) / maxf(w_max, 0.01), 0.0, 1.0)
	return {"visible": text != "0.0", "angle": 0.0 if w >= 0.0 else PI,
		"length": 0.35 + 0.65 * k, "text": text}


## The strongest wind any level can roll (the top of the difficulty row times the bow's wind).
static func wind_max(l: BottleLogic) -> float:
	var top := 0.0
	for x in ((l.cfg.get("difficulty", {}) as Dictionary).get("wind", []) as Array):
		top = maxf(top, float(x))
	return maxf(top * float(l.wcfg.get("wind", 1.0)), 0.1)


## The part of a `vp` screen (canvas pixels, 720 wide) the HUD leaves clear for the bottles:
## below the top band (bottle count, wind, multiplier, combo) and above the ammo row.
static func safe_rect(vp: Vector2) -> Rect2:
	return Rect2(0.0, SAFE_TOP, vp.x, vp.y - SAFE_TOP - SAFE_BOTTOM)


const SAFE_TOP := 225.0
const SAFE_BOTTOM := 150.0


## Shows the reticle (`kind` "pin" or "cross") centred on screen point `p`.
func set_reticle(p: Vector2, kind: String) -> void:
	if _reticle == null:
		return
	if _reticle.kind != kind:
		_reticle.kind = kind
		_reticle.queue_redraw()
	_reticle.position = p - _reticle.size * 0.5
	_reticle.visible = true


func hide_reticle() -> void:
	if _reticle:
		_reticle.visible = false


func show_reload(on: bool) -> void:
	_reload.visible = on
	_reload_t = 0.0


func flash(a: float, c := Color.WHITE) -> void:
	_flash.color = Color(c, maxf(_flash.color.a, a))


## The multiplier jumps: it counts up from the old value with a punch, a flash and rays.
func set_multiplier(m: float, gold: bool) -> void:
	_mult_from = _mult_shown
	_mult_to = m
	_mult_t = 0.0
	_punch = 1.0
	_punch_gold = gold
	_rays.color = Color(1.0, 0.62, 0.15, 0.0) if gold else Color(1.0, 0.9, 0.45, 0.0)
	_mult_label.modulate.a = 1.0


## Shows the combo for a streak of `n` hits in a row (from 2 up); 0 breaks it. Spec v2.1 §3.1:
## the streak no longer multiplies coins (the coin × does, Economy.level_coins), so the flame
## shows the streak's length, never a "×" that would promise a payout (`factor` is unused).
func set_combo(n: int, factor: float) -> void:
	if n >= 2:
		_combo_label.text = str(n)
		# The flame sits just left of the number, whatever its width.
		_flame.position.x = maxf(_combo_root.size.x - _combo_label.get_minimum_size().x - 104.0, 0.0)
		_combo_punch = 1.0
		_combo_break = 0.0
		_combo_root.modulate = Color(1, 1, 1, 1)
		_combo_root.rotation = 0.0
	elif _combo_shown >= 2:
		_combo_break = 1.0
	_combo_shown = n


func _process(delta: float) -> void:
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - delta * 3.0, 0.0)
	if _mult_t < 1.0:
		_mult_t = minf(_mult_t + delta / 0.35, 1.0)
		_mult_shown = lerpf(_mult_from, _mult_to, 1.0 - pow(1.0 - _mult_t, 3.0))
		_mult_label.text = "×%s" % fmt(_mult_to if _mult_t >= 1.0 else snappedf(_mult_shown, 0.5))
	if _punch > 0.0:
		_punch = maxf(_punch - delta / (0.6 if _punch_gold else 0.45), 0.0)
		var big := 0.7 if _punch_gold else 0.5
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
	# Combo: punches in, the flame flickers while the streak runs; a miss shakes it red and fades it.
	# Pivot on the right edge: the punch grows into the screen, never past its edge.
	_combo_root.pivot_offset = Vector2(_combo_root.size.x, _combo_root.size.y * 0.5)
	if _combo_punch > 0.0:
		_combo_punch = maxf(_combo_punch - delta / 0.45, 0.0)
		_combo_root.scale = Vector2.ONE * (1.0 + 0.6 * _combo_punch * _combo_punch)
	if _combo_shown >= 2 and _combo_break <= 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		_flame.scale = Vector2(1.0 + 0.05 * sin(t * 17.0), 1.0 + 0.08 * sin(t * 23.0 + 1.0))
		_flame.pivot_offset = Vector2(55, 90)
	if _combo_break > 0.0:
		_combo_break = maxf(_combo_break - delta / 0.6, 0.0)
		_combo_root.modulate = Color(1.0, 0.45 + 0.55 * (1.0 - _combo_break), 0.45 + 0.55 * (1.0 - _combo_break), _combo_break)
		_combo_root.rotation = sin(_combo_break * 60.0) * 0.08 * _combo_break
	if _reload.visible:
		_reload_t += delta
		var k := 1.0 + 0.12 * sin(_reload_t * 8.0)
		_reload.pivot_offset = _reload.size * 0.5
		_reload.scale = Vector2.ONE * k
		_reload.offset_top = -330 + 10.0 * sin(_reload_t * 4.0)
		_reload.offset_bottom = _reload.offset_top + 120


static func fmt(m: float) -> String:
	return str(int(m)) if is_equal_approx(m, round(m)) else "%.1f" % m

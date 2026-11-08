class_name UiKit
extends RefCounted
## Bright-cartoon UI kit: chunky glossy buttons (Kenney UI Pack, 9-sliced), white
## game-icons on coloured buttons, cream panels with thick dark outlines, Luckiest Guy.
## Owner rule: icons over words; text only for numbers and the odd title.

const FONT := preload("res://assets/fonts/LuckiestGuy-Regular.ttf")
const FONT_SMALL := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const INK := Color("2b1a07")
const CREAM := Color("fff4dc")
const YELLOW := Color("ffd23f")
const GREEN := Color("5fd35b")
const BLUE := Color("3fa9ff")
const RED := Color("ff5b4f")
const GOLD := Color("ffd23f")
const SKY := Color("1c4fb8")

const BUTTON_TEX := {
	"yellow": "res://assets/ui/yellow_%s.png", "green": "res://assets/ui/green_%s.png",
	"blue": "res://assets/ui/blue_%s.png", "red": "res://assets/ui/red_%s.png", "grey": "res://assets/ui/grey_%s.png",
}

static var _icons: Dictionary = {}


## Glossy full-colour icon (assets/icons/gloss, AI-painted) when there is one, else the
## white game-icons.net SVG (UI glyphs like pause, close, retry).
static func icon_texture(name: String) -> Texture2D:
	if not _icons.has(name):
		var gloss := "res://assets/icons/gloss/%s.png" % name
		_icons[name] = load(gloss) if ResourceLoader.exists(gloss) else load("res://assets/icons/%s.svg" % name)
	return _icons[name]


static func is_gloss(name: String) -> bool:
	return ResourceLoader.exists("res://assets/icons/gloss/%s.png" % name)


## Icon at `size` px. White SVG glyphs take `tint`; glossy icons keep their colours
## (only the tint's alpha applies, for fading).
static func icon(name: String, size := 64, tint := Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_texture(name)
	if is_gloss(name):
		tint = Color(1, 1, 1, tint.a)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func label(text: String, size: int, color := Color.WHITE, outline := 12, small := false) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = FONT_SMALL if small else FONT
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = INK
	ls.shadow_size = 0
	ls.shadow_color = Color(INK, 0.9)
	ls.shadow_offset = Vector2(0, maxf(3.0, size * 0.07))
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _tex_box(color: String, shape: String, pressed := false) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(BUTTON_TEX[color] % shape)
	var m := 26 if shape != "round" else 40
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m + 6
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10 + (6 if pressed else 0)
	sb.content_margin_bottom = 18 - (6 if pressed else 0)
	if pressed:
		sb.modulate_color = Color(0.88, 0.88, 0.88)
	return sb


## Glossy button. `text` may be empty when an icon is added. color: yellow|green|blue|red|grey.
static func button(text: String, color := "yellow", size := 46, min_size := Vector2(0, 110), shape := "rectangle") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 10)
	b.add_theme_stylebox_override("normal", _tex_box(color, shape))
	b.add_theme_stylebox_override("hover", _tex_box(color, shape))
	b.add_theme_stylebox_override("pressed", _tex_box(color, shape, true))
	b.add_theme_stylebox_override("disabled", _tex_box("grey", shape))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Sfx.play("tap"))
	b.button_down.connect(func(): _squash(b))
	return b


## Square/round button showing an icon, with an optional small number badge.
static func icon_button(icon_name: String, color := "blue", size := 120, shape := "square") -> Button:
	var b := button("", color, 10, Vector2(size, size), shape)
	var ic := icon(icon_name, int(size * 0.55))
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_top = size * 0.12
	ic.offset_bottom = -size * 0.2
	ic.offset_left = size * 0.18
	ic.offset_right = -size * 0.18
	b.add_child(ic)
	b.set_meta("icon", ic)
	return b


static func set_badge(b: Button, n: int) -> void:
	var badge: Label = b.get_meta("badge") if b.has_meta("badge") else null
	if badge == null:
		badge = label("", 30, Color.WHITE, 8)
		var bg := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = RED
		sb.set_corner_radius_all(22)
		sb.set_border_width_all(4)
		sb.border_color = INK
		bg.add_theme_stylebox_override("panel", sb)
		bg.size = Vector2(44, 44)
		bg.position = Vector2(b.custom_minimum_size.x - 34, -10)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bg)
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.add_child(badge)
		b.set_meta("badge", badge)
		b.set_meta("badge_bg", bg)
	badge.text = str(n)
	(b.get_meta("badge_bg") as Control).visible = n > 0


## Red "!" badge that bobs: something to do here (e.g. an upgrade you can afford).
static func set_alert(b: Button, on: bool) -> void:
	set_badge(b, 1 if on else 0)
	(b.get_meta("badge") as Label).text = "!"
	var bg: Control = b.get_meta("badge_bg")
	if on and not bg.has_meta("tween"):
		var tw := bg.create_tween().set_loops()
		tw.tween_property(bg, "position:y", -18.0, 0.35).set_trans(Tween.TRANS_SINE)
		tw.tween_property(bg, "position:y", -10.0, 0.35).set_trans(Tween.TRANS_SINE)
		bg.set_meta("tween", tw)


static func panel(color := CREAM) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(30)
	sb.set_border_width_all(6)
	sb.border_color = INK
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 34
	sb.content_margin_bottom = 28
	p.add_theme_stylebox_override("panel", sb)
	return p


## Rounded dark pill with an icon and a number (coins, troops).
static func pill(icon_name: String, text: String, tint := YELLOW) -> HBoxContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.12, 0.3, 0.6)
	sb.set_corner_radius_all(40)
	sb.set_border_width_all(4)
	sb.border_color = INK
	sb.content_margin_left = 8
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	row.add_child(icon(icon_name, 46, tint))
	var l := label(text, 40, Color.WHITE, 10)
	row.add_child(l)
	var wrap := HBoxContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(box)
	wrap.set_meta("label", l)
	return wrap


static func pill_set(p: HBoxContainer, text: String) -> void:
	(p.get_meta("label") as Label).text = text


## Red ribbon header with an icon (and optional text).
static func ribbon(icon_name: String, text := "") -> PanelContainer:
	var r := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = RED
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(6)
	sb.border_color = INK
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 6
	sb.content_margin_bottom = 10
	r.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	r.add_child(row)
	if icon_name != "":
		row.add_child(icon(icon_name, 64))
	if text != "":
		row.add_child(label(text, 54))
	return r


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## Full rect minus the phone's notch / camera cut-out / gesture bar, so nothing important
## hides under them. Call after the control is in the tree.
static func safe_rect(c: Control) -> Control:
	full_rect(c)
	var ins := safe_insets(c)
	c.offset_top = ins.x
	c.offset_bottom = -ins.y
	return c


## (top, bottom) unsafe margins in UI units. Desktop: none.
static func safe_insets(c: Control) -> Vector2:
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.y <= 0.0 or safe.size.y <= 0.0:
		return Vector2(48, 24)
	var k := c.get_viewport().get_visible_rect().size.y / win.y
	var top := maxf(safe.position.y, 0.0) * k
	var bottom := maxf(win.y - safe.end.y, 0.0) * k
	return Vector2(maxf(top, 24.0), maxf(bottom, 12.0))


static func pop(c: Control, from := 0.6) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * from
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _squash(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(1.06, 0.92), 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

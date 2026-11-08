class_name UiKit
extends RefCounted
## Small helpers for building chunky, readable mobile UI in code.

const FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const INK := Color("1b1e27")
const GREEN := Color("2fb36b")
const BLUE := Color("3b82f6")
const GOLD := Color("f2c14e")
const RED := Color("e0484f")


static func label(text: String, size: int, color := Color.WHITE, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(color: Color, radius := 22, border := 0, border_color := INK) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 5)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func button(text: String, color: Color, size := 46, min_size := Vector2(0, 96)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_stylebox_override("normal", box(color, 26, 4))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.08), 26, 4))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.15), 26, 4))
	b.add_theme_stylebox_override("disabled", box(color.darkened(0.45), 26, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Sfx.play("tap"))
	return b


static func panel(color := Color(0.1, 0.11, 0.15, 0.92)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(color, 30, 4)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	p.add_theme_stylebox_override("panel", sb)
	return p


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## Simple pop-in tween.
static func pop(c: Control, from := 0.6) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * from
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

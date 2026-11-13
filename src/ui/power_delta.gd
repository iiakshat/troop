class_name PowerDelta
extends Label
## Owner play-test: whenever a power number changes, a small "+N" in green (or "-N" in red)
## shows right under it for HOLD s, then fades. Changes that come within that time add up and
## restart it, so a burst of gains reads as one number and never flickers; a sum that rounds to
## 0 hides it. The number uses the power's own format (Economy.fmt_power). The label is
## top_level and follows `target` every frame, so a popping or scaling pill does not move it.
## Used by the HUD's firepower, the lobby's Squad Power and the Armory's power pill.

const HOLD := 2.5
const FADE := 0.5
const UP := Color("7dff6b")
const DOWN := Color("ff4b45")

var target: Control
var gap := 0.0          ## px between the target's bottom and the label
var _sum := 0.0
var _left := 0.0        # seconds until it is gone


static func make(under: Control, font_px := 30, below := 0.0) -> PowerDelta:
	var d := PowerDelta.new()
	d.target = under
	d.gap = below
	d.top_level = true
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_theme_font_override("font", UiKit.FONT)
	d.add_theme_font_size_override("font_size", font_px)
	d.add_theme_color_override("font_outline_color", UiKit.INK)
	d.add_theme_constant_override("outline_size", maxi(font_px / 4, 6))
	d.visible = false
	return d


## A change of `d` power units (after - before).
func add(d: float) -> void:
	if _left <= 0.0:
		_sum = 0.0
	_sum += d
	_left = HOLD + FADE
	var n := Economy.fmt_power(absf(_sum))
	if n == "0":
		_left = 0.0
		visible = false
		return
	text = ("+" if _sum > 0.0 else "-") + n
	add_theme_color_override("font_color", UP if _sum > 0.0 else DOWN)
	modulate.a = 1.0
	visible = true
	_follow()


## The sum on show ("" when hidden; tests).
func shown() -> String:
	return text if visible else ""


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		visible = false
		_sum = 0.0
		return
	modulate.a = clampf(_left / FADE, 0.0, 1.0)
	_follow()


func _follow() -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	visible = target.is_visible_in_tree()
	var r := target.get_global_rect()
	size = get_minimum_size()
	global_position = Vector2(r.position.x + (r.size.x - size.x) * 0.5, r.end.y + gap)

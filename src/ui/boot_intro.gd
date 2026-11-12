class_name BootIntro
extends Control
## The axnex studio intro (spec v2 §1), about 2 s on the boot backdrop:
##   0.00-0.35  the wordmark fades and settles in
##   0.35-1.05  a white light sweep crosses it
##   0.95-1.65  siren flashes, blue left / red right, with the siren_whoop
##   1.75-2.10  it fades out
## Time is driven by advance() (BootSequence calls it), so tests need no frames.
## The first launch plays it in full; later launches skip it with a tap (`skippable`).

const DURATION := 2.1
const TEX := preload("res://assets/brand/axnex.svg")
const BLUE := Color("3fa9ff")
const RED := Color("ff4a4a")
const FLASHES := [0.95, 1.07, 1.19, 1.31, 1.43, 1.55]  # blue, red, blue, red...

const SWEEP_SHADER := """
shader_type canvas_item;
uniform float sweep = -1.0;  // centre of the light band along the wordmark (UV x)
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = abs(UV.x + (UV.y - 0.5) * 0.45 - sweep);
	float band = smoothstep(0.14, 0.0, d);
	c.rgb = mix(c.rgb, vec3(1.0), band * 0.9);
	COLOR = c;
}
"""

var skippable := false
var t := 0.0
var _mark: TextureRect
var _mat: ShaderMaterial
var _whooped := false

static var _glow_tex: Texture2D


func _init(can_skip := false) -> void:
	skippable = can_skip
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_mark = TextureRect.new()
	_mark.texture = TEX
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SWEEP_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mark.material = _mat
	add_child(_mark)
	resized.connect(_apply)
	_apply()


func is_done() -> bool:
	return t >= DURATION


func advance(dt: float) -> void:
	t += dt
	if not _whooped and t >= FLASHES[0]:
		_whooped = true
		if is_inside_tree():
			Sfx.play("siren_whoop")
	_apply()


func _apply() -> void:
	var w := minf(size.x * 0.64, 470.0) if size.x > 0 else 460.0
	var h := w * float(TEX.get_height()) / float(TEX.get_width())
	var settle := _ease_out(clampf(t / 0.4, 0.0, 1.0))
	var s := 0.88 + 0.12 * settle
	_mark.size = Vector2(w, h)
	_mark.pivot_offset = _mark.size / 2.0
	_mark.position = size / 2.0 - _mark.size / 2.0
	_mark.scale = Vector2(s, s)
	var a := clampf(t / 0.3, 0.0, 1.0) * clampf((DURATION - t) / 0.35, 0.0, 1.0)
	_mark.modulate = Color(1, 1, 1, a)
	_mat.set_shader_parameter("sweep", lerpf(-0.35, 1.35, clampf((t - 0.35) / 0.7, 0.0, 1.0)))
	queue_redraw()


func _draw() -> void:
	if _glow_tex == null:
		_glow_tex = radial_glow()
	var c := size / 2.0
	var r := maxf(size.x, 420.0) * 0.55
	var fade := clampf((DURATION - t) / 0.35, 0.0, 1.0)
	for i in FLASHES.size():
		var age := t - float(FLASHES[i])
		if age < 0.0 or age > 0.45:
			continue
		var k := exp(-age * 7.0) * fade
		var left := i % 2 == 0
		var col := (BLUE if left else RED)
		col.a = k * 0.85
		var at := c + Vector2((-0.28 if left else 0.28) * size.x, 0.0)
		draw_texture_rect(_glow_tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


## A soft white radial dot (centre opaque, edge clear) for glows; tint it when drawing.
static func radial_glow() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex

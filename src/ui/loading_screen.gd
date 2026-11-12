class_name LoadingScreen
extends Control
## The loading screen (spec v2 §1): the Siren Squad logo, a siren light-bar loading bar
## (blue and red stripes strobing, the light-bar riding its front edge) and one icon-only
## tip card (pictures and arrows, no words). When the bar is full (`is_done`) BootSequence
## builds the game under it, then fades it away. Driven by advance().

const DURATION := 1.4
const BAR := preload("res://assets/brand/lightbar.png")
## Icon-only tips: icon names, ">" draws an arrow. Each one is a real rule of the game.
const TIPS := [
	["hand", ">", "speed"],          # tap: the hero throws faster
	["coin", ">", "knife_power"],    # coins buy weapon power
	["shield", "bomb"],              # two powers, ready between levels
	["barrel", ">", "fire"],         # shoot a barrel: it blasts the gang
	["star_icon", ">", "star_chest"],# stars fill the star chest
	["hammer", ">", "city_hall"],    # rebuild the city
]

var t := 0.0
var tip := 0


func _init(tip_index := -1) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	tip = tip_index if tip_index >= 0 else int(Time.get_unix_time_from_system()) % TIPS.size()


func progress() -> float:
	var x := clampf(t / DURATION, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 1.6)


func is_done() -> bool:
	return t >= DURATION


func advance(dt: float) -> void:
	t += dt
	queue_redraw()


func _draw() -> void:
	var view := size if size.x > 0 else Vector2(720, 1280)
	TitleLogo.draw_logo(self, TitleLogo.loading_rect(view), t + TitleLogo.DURATION, 0.8)
	_draw_tip(view)
	_draw_bar(view)


func _draw_tip(view: Vector2) -> void:
	var items: Array = TIPS[tip % TIPS.size()]
	var icon := minf(view.x * 0.17, 120.0)
	var arrow := icon * 0.42
	var gap := icon * 0.16
	var w := 0.0
	for it in items:
		w += (arrow if it == ">" else icon) + gap
	w -= gap
	var card := Rect2(Vector2(view.x / 2.0 - w / 2.0 - icon * 0.35, view.y * 0.52 - icon * 0.85),
		Vector2(w + icon * 0.7, icon * 1.7))
	var a := clampf(t / 0.25, 0.0, 1.0)
	draw_style_box(UiKit.flat_box(Color(1, 1, 1, 0.07 * a), 28, 4, Color(1, 1, 1, 0.16 * a)), card)
	var x := view.x / 2.0 - w / 2.0
	var cy := view.y * 0.52
	for it in items:
		if it == ">":
			var p := Vector2(x + arrow * 0.25, cy)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -arrow * 0.42),
				p + Vector2(arrow * 0.62, 0), p + Vector2(0, arrow * 0.42)]), Color(1, 0.82, 0.25, a))
			x += arrow + gap
			continue
		var tex := UiKit.icon_texture(String(it))
		if tex:
			var bob := sin(t * 5.0 + x * 0.02) * 4.0
			draw_texture_rect(tex, Rect2(Vector2(x, cy - icon / 2.0 + bob), Vector2(icon, icon)), false, Color(1, 1, 1, a))
		x += icon + gap


func _draw_bar(view: Vector2) -> void:
	var w := minf(view.x * 0.74, 540.0)
	var h := 40.0
	var r := Rect2(Vector2(view.x / 2.0 - w / 2.0, view.y * 0.72), Vector2(w, h))
	draw_style_box(UiKit.flat_box(Color("0a1230"), 20, 5, Color("1e2d66")), r.grow(6))
	var fill := (w) * progress()
	if fill > 2.0:
		# stripes alternate police blue and siren red; their brightness strobes
		var blue_on := fmod(t, 0.3) < 0.15
		var stripe := 26.0
		var x := 0.0
		var i := 0
		while x < fill:
			var sw := minf(stripe, fill - x)
			var is_blue := i % 2 == 0
			var col := BootIntro.BLUE if is_blue else BootIntro.RED
			col = col.lightened(0.25) if is_blue == blue_on else col.darkened(0.3)
			draw_rect(Rect2(r.position + Vector2(x, 0), Vector2(sw, h)), col)
			x += stripe
			i += 1
		draw_rect(Rect2(r.position + Vector2(0, 4), Vector2(fill, h * 0.22)), Color(1, 1, 1, 0.28))
		# the light-bar rides the front edge
		var bh := h * 1.55
		var bw := bh * float(BAR.get_width()) / float(BAR.get_height())
		var front := Vector2(r.position.x + fill, r.get_center().y)
		draw_texture_rect(BAR, Rect2(front - Vector2(bw / 2.0, bh / 2.0), Vector2(bw, bh)), false)

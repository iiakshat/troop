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
	["hand", ">", "power"],          # tap: the hero throws faster, firepower (lightning) rises
	["coin", ">", "knife_power"],    # coins buy weapon power
	["clock", ">", "shield", "bomb"],# time refills the free shield and bomb
	["barrel", ">", "fire"],         # shoot a barrel: it blasts the gang
	["star_icon", ">", "star_chest"],# stars fill the star chest
	["hammer", ">", "city_hall"],    # rebuild the city
]

## Icons drawn as a tap gesture: rings ripple out from the fingertip, so the hand reads as
## "tap the screen", never as a pointer at nothing (spec v2 §12.3).
const TAP_ICONS := ["hand"]
const TAP_PERIOD := 0.7

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
			if TAP_ICONS.has(it):
				_draw_tap(tex, Rect2(Vector2(x, cy - icon / 2.0), Vector2(icon, icon)), a)
			else:
				var bob := sin(t * 5.0 + x * 0.02) * 4.0
				draw_texture_rect(tex, Rect2(Vector2(x, cy - icon / 2.0 + bob), Vector2(icon, icon)), false, Color(1, 1, 1, a))
		x += icon + gap


## A tapping hand: it presses in (moves along its finger and shrinks a little), and on each
## press a ring ripples out from the fingertip (Tutorial.TIP, the same spot the tutorials use).
func _draw_tap(tex: Texture2D, r: Rect2, a: float) -> void:
	var ph := fmod(t, TAP_PERIOD) / TAP_PERIOD
	var press := sin(clampf(ph / 0.35, 0.0, 1.0) * PI)  # 0 -> 1 -> 0 over the first 35%
	var tip_at := r.position + r.size * Tutorial.TIP
	for k in 2:
		var age := fmod(t + k * TAP_PERIOD * 0.5, TAP_PERIOD) / TAP_PERIOD
		var rr := r.size.x * (0.08 + 0.32 * age)
		draw_arc(tip_at, rr, 0.0, TAU, 32, Color(1, 1, 1, (1.0 - age) * 0.7 * a), maxf(2.0, r.size.x * 0.035), true)
	var s := 1.0 - 0.08 * press
	var hr := Rect2(tip_at - r.size * Tutorial.TIP * s, r.size * s)
	hr.position += Vector2(1, 1) * press * r.size.x * 0.06
	draw_texture_rect(tex, hr, false, Color(1, 1, 1, a))


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
		# the light-bar rides the front edge (kept inside the track, so a full bar ends flush)
		var bh := h * 1.55
		var bw := bh * float(BAR.get_width()) / float(BAR.get_height())
		var fx := clampf(r.position.x + fill - bw * 0.35, r.position.x + bw * 0.5, r.end.x - bw * 0.5)
		var front := Vector2(fx, r.get_center().y)
		draw_texture_rect(BAR, Rect2(front - Vector2(bw / 2.0, bh / 2.0), Vector2(bw, bh)), false)

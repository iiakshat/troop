class_name TitleLogo
extends Control
## The Siren Squad logo sting (spec v2 §1): the logo pops in with a bounce, its light-bar
## flashes police blue and red with a siren_chirp, beacon light washes the backdrop, then the
## logo glides up into its place on the loading screen (LoadingScreen draws it there too,
## so the hand-over is seamless). Driven by advance(); after the first launch a tap hurries it.

const DURATION := 1.7
const TEX := preload("res://assets/brand/siren_squad_logo.png")
## The light-bar lenses on the logo image (fractions of its width / height).
const LENS_BLUE := Vector2(0.29, 0.12)
const LENS_RED := Vector2(0.71, 0.12)
const GLIDE := 0.32  # last seconds: the move into the loading-screen spot

var skippable := false
var t := 0.0
var _chirped := false


func _init(can_skip := false) -> void:
	skippable = can_skip
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func is_done() -> bool:
	return t >= DURATION


func advance(dt: float) -> void:
	t += dt
	if not _chirped and t >= 0.22:
		_chirped = true
		if is_inside_tree():
			Sfx.play("siren_chirp")
	queue_redraw()


## Where the big logo sits during the sting.
static func hero_rect(view: Vector2) -> Rect2:
	var w := minf(view.x * 0.86, 620.0)
	var h := w * float(TEX.get_height()) / float(TEX.get_width())
	return Rect2(Vector2(view.x / 2.0 - w / 2.0, view.y * 0.42 - h / 2.0), Vector2(w, h))


## Where the logo sits on the loading screen.
static func loading_rect(view: Vector2) -> Rect2:
	var w := minf(view.x * 0.66, 470.0)
	var h := w * float(TEX.get_height()) / float(TEX.get_width())
	return Rect2(Vector2(view.x / 2.0 - w / 2.0, view.y * 0.27 - h / 2.0), Vector2(w, h))


## Draws the logo into `r` on `ci`, with its two lenses flashing at time `time`
## (`strength` 0..1 scales the flash).
static func draw_logo(ci: CanvasItem, r: Rect2, time: float, strength := 1.0, alpha := 1.0) -> void:
	ci.draw_texture_rect(TEX, r, false, Color(1, 1, 1, alpha))
	var glow := _glow()
	var blue_on := fmod(time, 0.36) < 0.18
	var gr := r.size.x * 0.22
	for i in 2:
		var lens: Vector2 = LENS_BLUE if i == 0 else LENS_RED
		var on := blue_on if i == 0 else not blue_on
		var col := BootIntro.BLUE if i == 0 else BootIntro.RED
		col.a = (0.75 if on else 0.12) * strength * alpha
		var at := r.position + r.size * lens
		ci.draw_texture_rect(glow, Rect2(at - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, col)


static var _glow_tex: Texture2D


static func _glow() -> Texture2D:
	if _glow_tex == null:
		_glow_tex = BootIntro.radial_glow()
	return _glow_tex


func _draw() -> void:
	var view := size if size.x > 0 else Vector2(720, 1280)
	# beacon light washing the backdrop from the sides
	var wash := clampf(t / 0.3, 0.0, 1.0)
	var blue_on := fmod(t, 0.36) < 0.18
	var big := view.x * 0.95
	for i in 2:
		var col := BootIntro.BLUE if i == 0 else BootIntro.RED
		var on := blue_on if i == 0 else not blue_on
		col.a = (0.34 if on else 0.08) * wash
		var at := Vector2(0.0 if i == 0 else view.x, view.y * 0.36)
		draw_texture_rect(_glow(), Rect2(at - Vector2(big, big), Vector2(big, big) * 2.0), false, col)
	# pop in (back-ease overshoot), hold, then glide into the loading-screen spot
	var hero := hero_rect(view)
	var pop := clampf(t / 0.45, 0.0, 1.0)
	var s := _back_out(pop) * 0.6 + 0.4 if t < 0.45 else 1.0
	var r := Rect2(hero.get_center() - hero.size * s / 2.0, hero.size * s)
	var g := clampf((t - (DURATION - GLIDE)) / GLIDE, 0.0, 1.0)
	if g > 0.0:
		var to := loading_rect(view)
		var e := g * g * (3.0 - 2.0 * g)
		r = Rect2(r.position.lerp(to.position, e), r.size.lerp(to.size, e))
	draw_logo(self, r, t, clampf((t - 0.2) / 0.2, 0.0, 1.0), clampf(t / 0.12, 0.0, 1.0))


func _back_out(x: float) -> float:
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

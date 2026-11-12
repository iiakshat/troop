class_name LoadingScreen
extends Control
## The loading screen (owner 2026-11-12: no wordmark, a cinematic shot instead). One
## full-screen key-art shot, the charge or the standoff, alternating per launch (`pick_shot`,
## a tiny user:// file, never the save). It covers any screen with its focal point kept,
## pushes in slowly (PUSH over PUSH_TIME) and a soft red and blue siren light sweeps across
## it. Over a bottom scrim: one icon-only tip card (pictures and arrows, no words) and the
## siren light-bar loading bar.
##
## The bar follows real loading. The first screen's heavy resources load on threads (`warm`
## paths) and fill WARM_SHARE of it; BootSequence then builds the first screen under the
## opaque screen (`mark_built`) and the rest fills. The bar moves toward that real value at
## most 1/FILL_TIME per second and never runs ahead of it. Driven by advance().

const SHOTS := [
	{"path": "res://assets/brand/keyart_charge.jpg", "focus": Vector2(0.5, 0.45)},
	{"path": "res://assets/brand/keyart_standoff.jpg", "focus": Vector2(0.45, 0.47)},
]
const SHOT_FILE := "user://boot_art.cfg"
const SHOT_FILE_DEBUG := "user://boot_art_debug.cfg"  # debug-save runs keep the player's turn
const PUSH := 0.04          # the push-in: the shot grows this much over PUSH_TIME
const PUSH_TIME := 3.0
const WARM_SHARE := 0.85    # of the bar: the threaded loads (the rest is the build)
const FILL_TIME := 0.9      # seconds the bar takes at least from empty to full
const SWEEP_PERIOD := 2.8   # one pass of the siren lights
const SWEEP_ALPHA := 0.2
const SCRIM_TOP := 0.6      # the bottom scrim starts at this share of the height
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
var shot := 0
## () -> float 0..1, the share of the warm paths loaded. Default: the threaded loads.
var warm_progress: Callable

var _shown := 0.0
var _warm := 0.0
var _built := false
var _chirped := false
var _art: Texture2D
var _paths := PackedStringArray()
var _done := {}       # path -> true once loaded, failed or missing
var _held: Array = [] # loaded resources, kept until the first screen holds its own
var _art_layer: Control
var _sweep: Control
var _ui: Control

static var _glow_tex: Texture2D


func _init(tip_index := -1, shot_index := 0, warm := PackedStringArray()) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	tip = tip_index if tip_index >= 0 else int(Time.get_unix_time_from_system()) % TIPS.size()
	shot = clampi(shot_index, 0, SHOTS.size() - 1)
	_art = art_texture(shot)
	for p in warm:
		_paths.append(p)
		if not ResourceLoader.exists(p) or ResourceLoader.load_threaded_request(p) != OK:
			_done[p] = true
	# Three layers: the shot, the additive siren sweep over it, then the scrim, tip and bar.
	_art_layer = _layer()
	_art_layer.draw.connect(func(): _draw_art(_art_layer))
	_sweep = _layer()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sweep.material = add
	_sweep.draw.connect(func(): _draw_sweep(_sweep))
	_ui = _layer()
	_ui.draw.connect(func(): _draw_ui(_ui))
	_warm = _poll_warm()


func _layer() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	return c


## The shot's texture: taken from the threaded request BootSequence started during the intro
## when there is one, else loaded now.
static func art_texture(i: int) -> Texture2D:
	var path := String(SHOTS[i]["path"])
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var r := ResourceLoader.load_threaded_get(path) as Texture2D
		if r:
			return r
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## This launch's shot: the one after the last launch's (charge first), remembered in a tiny
## ConfigFile of its own so the save is never touched for it.
static func pick_shot(path := "") -> int:
	if path == "":
		var tree := Engine.get_main_loop() as SceneTree
		var game: Node = tree.root.get_node_or_null("Game") if tree else null
		path = SHOT_FILE_DEBUG if game != null and game.has_meta("debug_save") else SHOT_FILE
	var cfg := ConfigFile.new()
	var last := -1
	if cfg.load(path) == OK:
		last = int(cfg.get_value("boot", "last_shot", -1))
	var next := (last + 1) % SHOTS.size()
	cfg.set_value("boot", "last_shot", next)
	cfg.save(path)
	return next


## Where a tex_size image is drawn to cover view: scaled to cover, then by zoom about the
## focal point (shares of the image), placed so the focal point sits as near the middle as
## the image's edges allow.
static func cover_rect(tex_size: Vector2, view: Vector2, focus: Vector2, zoom := 1.0) -> Rect2:
	var k := maxf(view.x / tex_size.x, view.y / tex_size.y) * zoom
	var s := tex_size * k
	var pos := view / 2.0 - focus * s
	pos.x = clampf(pos.x, view.x - s.x, 0.0)
	pos.y = clampf(pos.y, view.y - s.y, 0.0)
	return Rect2(pos, s)


func progress() -> float:
	return _shown


func real_progress() -> float:
	return WARM_SHARE * _warm + (1.0 - WARM_SHARE) * (1.0 if _built else 0.0)


## True once every warm path has loaded (or failed): the first screen can be built.
func loaded() -> bool:
	return _warm >= 1.0


## BootSequence built the first screen: the last part of the bar may fill.
func mark_built() -> void:
	_built = true


func is_done() -> bool:
	return _built and _shown >= 1.0


func held_count() -> int:
	return _held.size()


func advance(dt: float) -> void:
	t += dt
	_warm = _poll_warm()
	_shown = minf(real_progress(), _shown + dt / FILL_TIME)
	if not _chirped and t >= 0.2:
		_chirped = true
		if is_inside_tree():
			Sfx.play("siren_chirp")
	for c in [_art_layer, _sweep, _ui]:
		(c as Control).queue_redraw()


func _poll_warm() -> float:
	if warm_progress.is_valid():
		return clampf(float(warm_progress.call()), 0.0, 1.0)
	if _paths.is_empty():
		return 1.0
	var sum := 0.0
	for p in _paths:
		if not _done.has(p):
			var pr := []
			var st := ResourceLoader.load_threaded_get_status(p, pr)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				var r := ResourceLoader.load_threaded_get(p)
				if r:
					_held.append(r)
				_done[p] = true
			elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				sum += float(pr[0]) if pr.size() > 0 else 0.0
				continue
			else:  # failed: never hold the boot on it (the screen loads it again itself)
				_done[p] = true
		sum += 1.0
	return sum / float(_paths.size())


func _view() -> Vector2:
	return size if size.x > 0 else Vector2(720, 1280)


func _draw_art(ci: CanvasItem) -> void:
	var view := _view()
	ci.draw_rect(Rect2(Vector2.ZERO, view), BootSequence.BG)
	if _art == null:
		return
	var x := clampf(t / PUSH_TIME, 0.0, 1.0)
	var zoom := 1.0 + PUSH * (1.0 - pow(1.0 - x, 2.0))  # eases out: the push settles
	ci.draw_texture_rect(_art, cover_rect(_art.get_size(), view, SHOTS[shot]["focus"], zoom), false)


## Two soft beacon glows, red and blue, crossing the shot in opposite directions (additive,
## so they light the art instead of tinting it flat).
func _draw_sweep(ci: CanvasItem) -> void:
	var view := _view()
	var fade := clampf(t / 0.4, 0.0, 1.0)
	var r := view.x * 0.85
	for i in 2:
		var ph := fmod(t / SWEEP_PERIOD + i * 0.5, 1.0)
		var x := view.x * (-0.35 + 1.7 * ph)
		if i == 1:
			x = view.x - x
		var col := BootIntro.RED if i == 0 else BootIntro.BLUE
		col.a = SWEEP_ALPHA * fade * sin(ph * PI)  # brightest mid-screen, gone at the edges
		var at := Vector2(x, view.y * (0.3 + 0.08 * i))
		ci.draw_texture_rect(_glow(), Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


static func _glow() -> Texture2D:
	if _glow_tex == null:
		_glow_tex = BootIntro.radial_glow()
	return _glow_tex


func _draw_ui(ci: CanvasItem) -> void:
	var view := _view()
	_draw_scrim(ci, view)
	_draw_tip(ci, view)
	_draw_bar(ci, view)


## The bottom scrim: the boot navy rising from clear to nearly solid, so the tip and the bar
## read on any shot.
func _draw_scrim(ci: CanvasItem, view: Vector2) -> void:
	var c0 := BootSequence.BG
	var stops := [[SCRIM_TOP, 0.0], [0.78, 0.55], [1.0, 0.9]]
	for i in stops.size() - 1:
		var y0: float = view.y * float(stops[i][0])
		var y1: float = view.y * float(stops[i + 1][0])
		var a0 := Color(c0, float(stops[i][1]))
		var a1 := Color(c0, float(stops[i + 1][1]))
		ci.draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(view.x, y0), Vector2(view.x, y1), Vector2(0, y1)]),
			PackedColorArray([a0, a0, a1, a1]))


func _draw_tip(ci: CanvasItem, view: Vector2) -> void:
	var items: Array = TIPS[tip % TIPS.size()]
	var icon := minf(view.x * 0.13, 96.0)
	var arrow := icon * 0.42
	var gap := icon * 0.16
	var w := 0.0
	for it in items:
		w += (arrow if it == ">" else icon) + gap
	w -= gap
	var cy := view.y * 0.805
	var card := Rect2(Vector2(view.x / 2.0 - w / 2.0 - icon * 0.35, cy - icon * 0.8),
		Vector2(w + icon * 0.7, icon * 1.6))
	var a := clampf(t / 0.25, 0.0, 1.0)
	ci.draw_style_box(UiKit.flat_box(Color(0.02, 0.05, 0.14, 0.55 * a), 28, 4, Color(1, 1, 1, 0.18 * a)), card)
	var x := view.x / 2.0 - w / 2.0
	for it in items:
		if it == ">":
			var p := Vector2(x + arrow * 0.25, cy)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -arrow * 0.42),
				p + Vector2(arrow * 0.62, 0), p + Vector2(0, arrow * 0.42)]), Color(1, 0.82, 0.25, a))
			x += arrow + gap
			continue
		var tex := UiKit.icon_texture(String(it))
		if tex:
			if TAP_ICONS.has(it):
				_draw_tap(ci, Rect2(Vector2(x, cy - icon / 2.0), Vector2(icon, icon)), a)
			else:
				var bob := sin(t * 5.0 + x * 0.02) * 4.0
				ci.draw_texture_rect(tex, Rect2(Vector2(x, cy - icon / 2.0 + bob), Vector2(icon, icon)), false, Color(1, 1, 1, a))
		x += icon + gap


## A tapping hand: it presses in (moves along its finger and shrinks a little), and on each
## press a ring ripples out from the fingertip (PointerHand's art and fingertip, the same hand
## the tutorials and menus use).
func _draw_tap(ci: CanvasItem, r: Rect2, a: float) -> void:
	var tex := PointerHand.texture()
	var tip_share := PointerHand.tip_share()
	var ph := fmod(t, TAP_PERIOD) / TAP_PERIOD
	var press := sin(clampf(ph / 0.35, 0.0, 1.0) * PI)  # 0 -> 1 -> 0 over the first 35%
	var tip_at := r.position + r.size * tip_share
	for k in 2:
		var age := fmod(t + k * TAP_PERIOD * 0.5, TAP_PERIOD) / TAP_PERIOD
		var rr := r.size.x * (0.08 + 0.32 * age)
		ci.draw_arc(tip_at, rr, 0.0, TAU, 32, Color(1, 1, 1, (1.0 - age) * 0.7 * a), maxf(2.0, r.size.x * 0.035), true)
	var s := 1.0 - 0.08 * press
	var hr := Rect2(tip_at - r.size * tip_share * s, r.size * s)
	hr.position += (tip_share - Vector2(0.5, 0.5)).normalized() * press * r.size.x * 0.06  # along the finger
	ci.draw_texture_rect(tex, hr, false, Color(1, 1, 1, a))


func _draw_bar(ci: CanvasItem, view: Vector2) -> void:
	var w := minf(view.x * 0.74, 540.0)
	var h := 40.0
	var r := Rect2(Vector2(view.x / 2.0 - w / 2.0, view.y * 0.905 - h / 2.0), Vector2(w, h))
	ci.draw_style_box(UiKit.flat_box(Color("0a1230"), 20, 5, Color("1e2d66")), r.grow(6))
	var fill := w * progress()
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
			ci.draw_rect(Rect2(r.position + Vector2(x, 0), Vector2(sw, h)), col)
			x += stripe
			i += 1
		ci.draw_rect(Rect2(r.position + Vector2(0, 4), Vector2(fill, h * 0.22)), Color(1, 1, 1, 0.28))
		# the light-bar rides the front edge (kept inside the track, so a full bar ends flush)
		var bh := h * 1.55
		var bw := bh * float(BAR.get_width()) / float(BAR.get_height())
		var fx := clampf(r.position.x + fill - bw * 0.35, r.position.x + bw * 0.5, r.end.x - bw * 0.5)
		var front := Vector2(fx, r.get_center().y)
		ci.draw_texture_rect(BAR, Rect2(front - Vector2(bw / 2.0, bh / 2.0), Vector2(bw, bh)), false)

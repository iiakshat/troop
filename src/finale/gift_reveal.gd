class_name GiftReveal
extends CanvasLayer
## Spec v2.1 §4.3: a guest Bottle Shot weapon (finale.json level_weapon) is handed over as a gift
## at the burst into the stash, before aiming, on every attempt. No words:
##   drop    a gift box falls in and lands with a squash
##   wiggle  it shakes harder and harder, sparks leaking from under the lid
##   open    the lid pops off in a flash, a ring and a sparkle burst
##   spin    the weapon (the art of the player's Armory tier for it) spins up out of the box, light
##           rays behind it; a locked Armory track shows a lock, a map pin and its unlock level
##   fly     the weapon flies into the hero's hand (BottleShot keeps `hand` on the weapon's screen
##           point) and the real weapon appears there (`handed`), then aiming starts (`finished`)
## Phase lengths come from finale.json "gift" and are squeezed into at most 1.5 s; any tap or key
## skips straight to the hand-off, and that tap's release is swallowed so it never fires a shot.
## The timeline is pure (play / advance / skip / take_input), so tests drive it without a tree;
## drawing happens only inside the tree. Never covers the bottles once aiming starts: the whole
## layer is gone by then.

signal handed     # the weapon reached the hand: show the real one
signal finished   # over: aiming starts

const PHASES := ["drop_s", "wiggle_s", "open_s", "spin_s", "fly_s"]
const DEFAULTS := {"drop_s": 0.26, "wiggle_s": 0.3, "open_s": 0.1, "spin_s": 0.44, "fly_s": 0.3}
const MAX_S := 1.5            # spec cap; finale.json gift.max_s can only lower it
const ARRIVE := 0.8           # share of the fly phase at which the weapon reaches the hand
const LID_CUT := 0.525        # the gift icon's lid / body seam (share of its height)
const BOX_ART := "res://assets/icons/gloss/gift.png"
const SPARK_COLORS := [Color("ffd23f"), Color("fff4dc"), Color("ff8fd8"), Color("8fefff"), Color("ffb347")]

static var _tex_cache: Dictionary = {}

var cfg: Dictionary
var weapon := "pistol"
var tier := 1
var lock_level := 0           # > 0: the weapon's Armory track opens at this level
var hand := Vector2(-1, -1)   # the hand's screen point (BottleShot keeps it current); < 0 = default
var t := 0.0
var playing := false
var done := false
var _handed := false
var _swallow := false         # a skipping touch is still down: take its drags and its release
var _release_frame := -1      # its release's frame: an emulated twin release then is taken too
var _d: Dictionary = {}       # phase lengths after the squeeze
var _ends: Array = []         # phase end times
var _sparks: Array = []       # {p, v, age, life, size, color, spin, rot}
var _rng := RandomNumberGenerator.new()
var _cues: Dictionary = {}    # sound cues already played
var _view: Control
var _font: Font
var _art_tex: Texture2D


# ---------------------------------------------------------------- pure

## Phase lengths ({drop_s, wiggle_s, open_s, spin_s, fly_s}), squeezed into the cap.
static func durations(gift: Dictionary) -> Dictionary:
	var d := {}
	var sum := 0.0
	for k in PHASES:
		d[k] = maxf(float(gift.get(k, DEFAULTS[k])), 0.0)
		sum += float(d[k])
	var cap := minf(float(gift.get("max_s", MAX_S)), MAX_S)
	if sum > cap and sum > 0.0:
		for k in PHASES:
			d[k] = float(d[k]) * cap / sum
	return d


## The whole reveal in seconds (at most 1.5).
static func total(gift: Dictionary) -> float:
	var d := durations(gift)
	var s := 0.0
	for k in PHASES:
		s += float(d[k])
	return s


## What the reveal shows for `w` from a save, read only: {track, tier, lock, art}. tier = the
## player's Armory tier for the weapon (1 when nothing is owned), lock = the level its Armory
## track opens at while it is still locked (else 0), art = that tier's picture.
static func info(save: Dictionary, w: String, armory_cfg: Dictionary = {}) -> Dictionary:
	var id := Armory.track_of("finale_" + w, armory_cfg)
	if id == "":
		return {"track": "", "tier": 1, "lock": 0, "art": ""}
	var owned := Armory.level(save, id, armory_cfg).x
	var lock := 0
	if Armory.is_locked(id, int(save.get("unlocked", 1)), armory_cfg):
		lock = Armory.unlock_level(id, armory_cfg)
	return {"track": id, "tier": owned, "lock": lock, "art": art_path(id, owned, armory_cfg)}


static func art_path(track_id: String, tier_n: int, armory_cfg: Dictionary = {}) -> String:
	var a := String(Armory.tier_info(track_id, tier_n, armory_cfg).get("art", ""))
	return ArmoryPanel.ART_DIR + a.trim_prefix("armory/") + ".png" if a != "" else ""


## Loads the reveal's pictures for `w` at its current tier, so the burst into the stash does
## not load them (BottleShot's level-load prewarm calls this).
static func warm(w: String, save: Dictionary) -> void:
	_texture(BOX_ART)
	_texture(String(info(save, w)["art"]))
	_texture("res://assets/icons/gloss/lock.png")
	_texture("res://assets/icons/gloss/map_pin.png")


static func _texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func setup(gift: Dictionary, w: String, tier_: int, lock_: int) -> GiftReveal:
	cfg = gift
	weapon = w
	tier = maxi(tier_, 1)
	lock_level = maxi(lock_, 0)
	_d = durations(gift)
	_ends.clear()
	var acc := 0.0
	for k in PHASES:
		acc += float(_d[k])
		_ends.append(acc)
	_rng.seed = hash(w) ^ 0x5eed
	layer = 5   # above the finale HUD (2), below the first-run lessons (6)
	return self


func play() -> void:
	if playing or done:
		return
	playing = true
	t = 0.0
	_cue("drop", "swoosh", -2.0, 1.25)


## Moves the timeline on by `dt` real seconds.
func advance(dt: float) -> void:
	if not playing or done:
		return
	t += dt
	_tick_sparks(dt)
	var open_at := float(_ends[1])
	if t >= float(_ends[0]):
		_cue("land", "punch", -10.0, 1.6)
	if t >= open_at:
		if not _cues.has("open"):
			_burst(_box_center(), int(cfg.get("sparks", 30)), 1.0)
		_cue("open", "chest_open", 0.0, 1.0)
	if t >= _arrive_t() and not _handed:
		_hand_over()
	if t >= float(_ends[4]):
		_finish()


## A tap: straight to the hand-off.
func skip() -> void:
	if not playing or done:
		return
	t = float(_ends[4])
	if not _handed:
		_hand_over()
	_finish()


## Input while the reveal runs or its skipping tap is still down. True = taken (the weapon never
## sees it). A press skips; everything else while playing is swallowed.
func take_input(event: InputEvent) -> bool:
	var pointer := event is InputEventScreenTouch or event is InputEventMouseButton
	var moving := event is InputEventScreenDrag or event is InputEventMouseMotion
	var pressed := false
	if pointer:
		pressed = event.is_pressed()
	elif event is InputEventKey:
		pressed = event.is_pressed() and not (event as InputEventKey).echo
	elif not moving:
		return false
	if playing and not done:
		if pressed:
			skip()
			_swallow = pointer
		return true
	if not (pointer or moving):
		return false
	if _swallow:
		if pointer and not pressed:
			_swallow = false
			_release_frame = Engine.get_process_frames()
		return true
	# The same release once more in that frame (a touch's emulated mouse twin) is taken too.
	return pointer and not pressed and Engine.get_process_frames() == _release_frame


func _arrive_t() -> float:
	return float(_ends[3]) + float(_d["fly_s"]) * ARRIVE


func _hand_over() -> void:
	_handed = true
	_burst(_hand_point(), 10, 0.45)
	_cue("hand", "unlock", -2.0, 1.15)
	handed.emit()


func _finish() -> void:
	if done:
		return
	done = true
	playing = false
	finished.emit()
	if _view:
		_view.queue_redraw()


func _cue(id: String, sound: String, vol: float, pitch: float) -> void:
	if _cues.has(id):
		return
	_cues[id] = true
	if is_inside_tree():
		Sfx.play(sound, vol, pitch)


# ---------------------------------------------------------------- sparks

func _burst(at: Vector2, n: int, power: float) -> void:
	var w := _screen().x
	for i in n:
		var a := TAU * (i + _rng.randf_range(-0.35, 0.35)) / maxf(n, 1)
		var sp := _rng.randf_range(0.45, 1.25) * w * 1.15 * power
		_sparks.append({"p": at, "v": Vector2(cos(a), sin(a)) * sp + Vector2(0, -w * 0.25 * power),
			"age": 0.0, "life": _rng.randf_range(0.35, 0.7), "size": _rng.randf_range(0.018, 0.04) * w * (0.6 + 0.4 * power),
			"color": SPARK_COLORS[_rng.randi() % SPARK_COLORS.size()], "spin": _rng.randf_range(-9.0, 9.0), "rot": _rng.randf() * TAU})


func _tick_sparks(dt: float) -> void:
	var g := _screen().x * 2.2
	# Wiggle: a few sparks leak from under the lid.
	if t > float(_ends[0]) and t < float(_ends[1]) and _rng.randf() < dt * 22.0:
		var bc := _box_center()
		var bs := _box_size()
		var p := bc + Vector2(_rng.randf_range(-0.4, 0.4) * bs, -0.05 * bs)
		_sparks.append({"p": p, "v": Vector2(_rng.randf_range(-0.3, 0.3), -_rng.randf_range(0.5, 1.0)) * _screen().x * 0.5,
			"age": 0.0, "life": 0.35, "size": _screen().x * 0.016, "color": SPARK_COLORS[_rng.randi() % 2], "spin": 6.0, "rot": 0.0})
	for s in _sparks:
		s["age"] = float(s["age"]) + dt
		s["v"] = (s["v"] as Vector2) * (1.0 - minf(dt * 2.5, 0.5)) + Vector2(0, g * dt)
		s["p"] = (s["p"] as Vector2) + (s["v"] as Vector2) * dt
		s["rot"] = float(s["rot"]) + float(s["spin"]) * dt
	_sparks = _sparks.filter(func(s): return float(s["age"]) < float(s["life"]))


# ---------------------------------------------------------------- layout

func _screen() -> Vector2:
	if _view and _view.is_inside_tree():
		return _view.get_viewport_rect().size
	return Vector2(540, 960)


func _box_size() -> float:
	return _screen().x * float(cfg.get("box", 0.36))


func _weapon_size() -> float:
	return _screen().x * float(cfg.get("weapon", 0.58))


func _box_center() -> Vector2:
	var s := _screen()
	return Vector2(s.x * 0.5, s.y * 0.47)


func _weapon_rest() -> Vector2:
	var s := _screen()
	return Vector2(s.x * 0.5, s.y * 0.38)


func _hand_point() -> Vector2:
	var s := _screen()
	if hand.x < 0.0 or hand.y < 0.0:
		return Vector2(s.x * 0.72, s.y * 0.86)
	return Vector2(clampf(hand.x, 0.0, s.x), clampf(hand.y, 0.0, s.y))


# ---------------------------------------------------------------- drawing

func _ready() -> void:
	_font = UiKit.FONT
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_paint)
	add_child(_view)


func _process(delta: float) -> void:
	if playing and not done:
		advance(delta)
	if _view:
		_view.queue_redraw()
	if done and not _swallow and Engine.get_process_frames() > _release_frame + 1:
		set_process(false)


func _input(event: InputEvent) -> void:
	if take_input(event):
		get_viewport().set_input_as_handled()


static func _ease_out_back(x: float, k := 1.7) -> float:
	x = clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + x * x * ((k + 1.0) * x + k)


func _u(i: int) -> float:
	var a := 0.0 if i == 0 else float(_ends[i - 1])
	var b := float(_ends[i])
	return clampf((t - a) / maxf(b - a, 0.0001), 0.0, 1.0)


func _paint() -> void:
	if not playing or done:
		return
	var s := _screen()
	var dim := float(cfg.get("dim", 0.55))
	var fade_in := clampf(t / 0.12, 0.0, 1.0)
	var fly := _u(4)
	var out := 1.0 - smoothstep(0.35, 1.0, fly) if t >= float(_ends[3]) else 1.0
	_view.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.01, 0.06, dim * fade_in * out))
	var bc := _box_center()
	var bs := _box_size()
	var opened := t >= float(_ends[1])
	# A warm glow behind the box, brighter once it opens.
	var glow := (0.5 + 0.5 * _u(1)) * fade_in * out
	if opened:
		glow = (1.0 + 0.4 * (1.0 - _u(2))) * out
	var gc := bc.lerp(_weapon_rest(), _u(3)) if opened else bc
	for i in 6:
		var k := 1.0 - i / 6.0
		_view.draw_circle(gc, bs * (0.55 + 0.75 * k), Color(1.0, 0.82, 0.35, 0.05 * glow))
	if opened:
		_paint_rays(gc, bs, out)
	_paint_box(bc, bs)
	if opened:
		_paint_ring(bc, bs)
	_paint_sparks()
	if t >= float(_ends[2]) - float(_d["open_s"]) * 0.5:
		_paint_weapon()
	if lock_level > 0 and t >= float(_ends[2]) + float(_d["spin_s"]) * 0.3:
		_paint_lock(out)
	if _handed:
		var k := clampf((t - _arrive_t()) / maxf(float(_d["fly_s"]) * (1.0 - ARRIVE), 0.01), 0.0, 1.0)
		var hp := _hand_point()
		_view.draw_circle(hp, bs * (0.25 + 0.45 * k), Color(1.0, 0.95, 0.7, 0.7 * (1.0 - k)))


func _paint_rays(c: Vector2, bs: float, out: float) -> void:
	var n := 12
	var spin := t * 1.6
	var ray_len := bs * 1.9 * _ease_out_back(clampf(_u(2) * 0.6 + _u(3) * 0.6, 0.0, 1.0), 1.2)
	var a := 0.32 * out
	for i in n:
		var ang := spin + TAU * i / n
		var half := 0.11
		var pts := PackedVector2Array([c, c + Vector2(cos(ang - half), sin(ang - half)) * ray_len,
			c + Vector2(cos(ang + half), sin(ang + half)) * ray_len])
		var col := Color(1.0, 0.9, 0.5, a) if i % 2 == 0 else Color(1.0, 0.7, 0.9, a * 0.7)
		_view.draw_colored_polygon(pts, col)


func _paint_box(bc: Vector2, bs: float) -> void:
	var tex := _texture(BOX_ART)
	if tex == null:
		return
	var tsz := tex.get_size()
	var cut := tsz.y * LID_CUT
	if t < float(_ends[1]):
		# Drop (gravity in, squash on landing), then the wiggle.
		var pos := bc
		var sc := Vector2.ONE
		var rot := 0.0
		if t < float(_ends[0]):
			var k := _u(0)
			pos.y = lerpf(-bs, bc.y, k * k)
			sc = Vector2(0.92, 1.1)
		else:
			var w := _u(1)
			var land := clampf((t - float(_ends[0])) / 0.14, 0.0, 1.0)
			var squash := sin(land * PI) * (1.0 - land) * 0.9
			sc = Vector2(1.0 + 0.22 * squash, 1.0 - 0.22 * squash) * (1.0 + 0.08 * w)
			rot = sin(w * TAU * 3.5) * deg_to_rad(4.0 + 10.0 * w)
		_view.draw_set_transform(pos + Vector2(0, bs * 0.5), rot, sc)   # pivot at the box's foot
		_view.draw_texture_rect(tex, Rect2(Vector2(-bs * 0.5, -bs), Vector2(bs, bs)), false)
		_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# Open: the lid flies up and away, the body bounces and drops out of sight.
	var u := clampf((t - float(_ends[1])) / maxf(float(_d["open_s"]) + float(_d["spin_s"]) * 0.7, 0.01), 0.0, 1.0)
	var lid_h := bs * LID_CUT
	var lid_pos := bc + Vector2(bs * 0.35 * u, -bs * (0.5 - LID_CUT * 0.5) - bs * 1.6 * u + bs * 1.2 * u * u)
	var lid_a := 1.0 - smoothstep(0.55, 1.0, u)
	if lid_a > 0.0:
		_view.draw_set_transform(lid_pos, u * 1.6, Vector2.ONE * (1.0 + 0.15 * u))
		_view.draw_texture_rect_region(tex, Rect2(Vector2(-bs * 0.5, -lid_h * 0.5), Vector2(bs, lid_h)),
			Rect2(0, 0, tsz.x, cut), Color(1, 1, 1, lid_a))
	var body_h := bs - lid_h
	var drop := bs * 0.9 * u * u
	var bsq := 1.0 + 0.18 * sin(minf(u * 3.0, 1.0) * PI)
	var body_a := 1.0 - smoothstep(0.35, 0.85, u)
	if body_a > 0.0:
		_view.draw_set_transform(bc + Vector2(0, bs * 0.5 + drop), 0.0, Vector2(bsq, 2.0 - bsq))
		_view.draw_texture_rect_region(tex, Rect2(Vector2(-bs * 0.5, -body_h), Vector2(bs, body_h)),
			Rect2(0, cut, tsz.x, tsz.y - cut), Color(1, 1, 1, body_a))
	_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_ring(bc: Vector2, bs: float) -> void:
	var k := clampf((t - float(_ends[1])) / 0.32, 0.0, 1.0)
	if k >= 1.0:
		return
	_view.draw_arc(bc, bs * (0.3 + 1.5 * k), 0.0, TAU, 48, Color(1.0, 0.95, 0.75, 0.85 * (1.0 - k)), bs * 0.09 * (1.0 - k) + 2.0, true)
	var f := clampf((t - float(_ends[1])) / 0.14, 0.0, 1.0)
	if f < 1.0:
		_view.draw_circle(bc, bs * (0.5 + 0.4 * f), Color(1, 1, 1, 0.85 * (1.0 - f)))


func _paint_sparks() -> void:
	for s in _sparks:
		var k := float(s["age"]) / float(s["life"])
		var r := float(s["size"]) * (1.0 - 0.6 * k)
		var col: Color = s["color"]
		col.a = 1.0 - k * k
		var pts := PackedVector2Array()
		for i in 8:
			var a := float(s["rot"]) + TAU * i / 8.0
			var rr := r if i % 2 == 0 else r * 0.32
			pts.append((s["p"] as Vector2) + Vector2(cos(a), sin(a)) * rr)
		_view.draw_colored_polygon(pts, col)


func _paint_weapon() -> void:
	var tex := _art()
	if tex == null:
		return
	var ws := _weapon_size()
	var from := _box_center()
	var rest := _weapon_rest()
	var spin_u := _u(3)
	var pos := from.lerp(rest, _ease_out_back(spin_u, 1.4))
	var sc := lerpf(0.25, 1.0, _ease_out_back(spin_u, 1.6))
	# Full turns about the vertical axis, slowing to face the player.
	var ang := TAU * float(cfg.get("turns", 1.5)) * (1.0 - pow(1.0 - spin_u, 3.0))
	var flip := cos(ang)
	var rot := 0.0
	var tint := Color(1, 1, 1, 1)
	if t >= float(_ends[3]):
		# Into the hand: an arc down to it, shrinking, tilting like a weapon being taken.
		var k := clampf(_u(4) / ARRIVE, 0.0, 1.0)
		if k >= 1.0:
			return
		var e := k * k * (3.0 - 2.0 * k)
		var hp := _hand_point()
		var ctrl := Vector2(lerpf(rest.x, hp.x, 0.5), minf(rest.y, hp.y) - ws * 0.25)
		pos = rest.lerp(ctrl, e).lerp(ctrl.lerp(hp, e), e)
		sc = lerpf(1.0, 0.32, e)
		rot = lerpf(0.0, deg_to_rad(-18.0), e)
		flip = 1.0
	# A little bob while it hangs there.
	pos.y += sin(t * 9.0) * ws * 0.012
	if flip < 0.0:
		tint = Color(0.72, 0.72, 0.8)   # the back of the turning picture reads darker
	var sx := absf(flip) * sc
	if absf(flip) < 0.08:
		sx = 0.08 * sc
	_view.draw_set_transform(pos, rot, Vector2(sx * signf(flip if flip != 0.0 else 1.0), sc))
	_view.draw_texture_rect(tex, Rect2(Vector2(-ws * 0.5, -ws * 0.5), Vector2(ws, ws)), false, tint)
	_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The weapon's picture at the shown tier (the Armory card's art; its icon if there is none).
func _art() -> Texture2D:
	if _art_tex == null:
		var id := Armory.track_of("finale_" + weapon)
		_art_tex = _texture(art_path(id, tier) if id != "" else "")
		if _art_tex == null:
			_art_tex = UiKit.icon_texture(String(ArmoryPanel.FALLBACK.get(id, "star_icon")))
	return _art_tex


## Under the weapon: a dark pill with a lock, a map pin and the level the Armory track opens at.
func _paint_lock(out: float) -> void:
	var ws := _weapon_size()
	var start := float(_ends[2]) + float(_d["spin_s"]) * 0.3
	var pop := _ease_out_back(clampf((t - start) / 0.16, 0.0, 1.0), 2.2)
	var a := out
	if t >= float(_ends[3]):
		a = 1.0 - smoothstep(0.0, 0.6, _u(4))
	if a <= 0.0 or pop <= 0.0:
		return
	var h := ws * 0.24
	var txt := str(lock_level)
	var fs := int(h * 0.62)
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := h * 0.95 * 2.0 + tw + h * 0.5
	var c := _weapon_rest() + Vector2(0, ws * 0.5 + h * 0.15)
	_view.draw_set_transform(c, 0.0, Vector2.ONE * pop)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.12, 0.88 * a)
	sb.border_color = Color(1.0, 0.82, 0.25, a)
	sb.set_border_width_all(maxi(int(h * 0.06), 2))
	sb.set_corner_radius_all(int(h * 0.5))
	_view.draw_style_box(sb, Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h)))
	var x := -w * 0.5 + h * 0.2
	var lock_tex := _texture("res://assets/icons/gloss/lock.png")
	if lock_tex:
		_view.draw_texture_rect(lock_tex, Rect2(Vector2(x, -h * 0.42), Vector2(h * 0.84, h * 0.84)), false, Color(1, 1, 1, a))
	x += h * 0.95
	var pin := _texture("res://assets/icons/gloss/map_pin.png")
	if pin:
		_view.draw_texture_rect(pin, Rect2(Vector2(x, -h * 0.4), Vector2(h * 0.8, h * 0.8)), false, Color(1, 1, 1, a))
	x += h * 0.9
	var base := Vector2(x, fs * 0.36)
	_view.draw_string_outline(_font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(int(fs * 0.22), 4), Color(UiKit.INK, a))
	_view.draw_string(_font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
	_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

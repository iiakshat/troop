class_name PointerHand
extends Control
## The one pointing hand (spec v2 §11): glossy cartoon art (assets/ui/hand.png, soft shadow
## baked in) whose fingertip sits exactly on a spot. It is used for two things only:
##   - a first-run gesture lesson (Tutorial moves it with set_tip / pressed)
##   - "buy this" in menus: PointerHand.on(button, at) taps on the button and follows its
##     layout, always next to the item's icon and its before ▸ after number (tag()).
## The node's own position is its top-left; the fingertip is `tip_offset()` inside it.

const TEX := "res://assets/ui/hand.png"
const TAP_S := 0.7           # one tap: down, press, lift

static var _tex: Texture2D = null
static var _tip := Vector2(-1, -1)

var hand_size := 110.0
var pressed := false: set = _set_pressed
var _art: TextureRect
var _anchor: Control = null   # menu use: the control the hand taps on
var _at := Vector2(0.5, 0.5)  # ... and where on it (share of its size)
var _tw: Tween = null


static func texture() -> Texture2D:
	if _tex == null:
		_tex = load(TEX) as Texture2D if ResourceLoader.exists(TEX) else UiKit.icon_texture("hand")
	return _tex


## The fingertip as a share of the art's size (config/hints.json "hand.tip").
static func tip_share() -> Vector2:
	if _tip.x < 0.0:
		var t: Array = NewItemCard.table().get("hand", {}).get("tip", [0.08, 0.07])
		_tip = Vector2(float(t[0]), float(t[1]))
	return _tip


static func make(size_px := 110.0) -> PointerHand:
	var h := PointerHand.new()
	h.hand_size = size_px
	h.name = "PointerHand"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.size = Vector2(size_px, size_px)
	h.pivot_offset = h.tip_offset()
	h._art = TextureRect.new()
	h._art.name = "HandArt"
	h._art.texture = texture()
	h._art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h._art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h._art.size = h.size
	h._art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(h._art)
	return h


func tip_offset() -> Vector2:
	return tip_share() * hand_size


## Puts the fingertip on `p` (parent coordinates).
func set_tip(p: Vector2) -> void:
	position = p - tip_offset()


func _set_pressed(v: bool) -> void:
	pressed = v
	scale = Vector2.ONE * (0.88 if v else 1.0)   # pivot = fingertip: the finger stays put


## Menu pointer: a hand tapping on `b` at `at` (share of its size), freed with it and
## following its real layout. A tap ripple marks the press.
static func on(b: Control, at := Vector2(0.5, 0.5), size_px := 100.0) -> PointerHand:
	var h := make(size_px)
	h.z_index = 5
	h._anchor = b
	h._at = at
	b.add_child(h)
	b.resized.connect(h.place)
	h.place()
	h.tap_loop()
	return h


func place() -> void:
	if _anchor != null and is_instance_valid(_anchor):
		set_tip(_anchor.size * _at)


## Taps forever: the hand comes down onto the spot, presses (ripple), lifts off.
func tap_loop() -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween().set_loops()
	_tw.tween_property(_art, "position", Vector2(14, 14), TAP_S * 0.45).set_trans(Tween.TRANS_SINE)
	_tw.tween_property(_art, "position", Vector2.ZERO, TAP_S * 0.2).set_trans(Tween.TRANS_QUAD)
	_tw.tween_callback(func(): pressed = true; queue_redraw())
	_tw.tween_interval(TAP_S * 0.15)
	_tw.tween_callback(func(): pressed = false)
	_tw.tween_interval(TAP_S * 0.2)


func _draw() -> void:
	if pressed:
		var c := tip_offset()
		draw_circle(c, hand_size * 0.2, Color(1, 1, 1, 0.35))
		draw_arc(c, hand_size * 0.24, 0, TAU, 32, Color(1, 1, 1, 0.9), 4.0)


## The "buy this" tag beside the hand: the item's icon, then its number before ▸ after.
static func tag(icon_name: String, before: String, after: String, px := 40) -> PanelContainer:
	var card := RetentionPanel.card_box(Color(0.06, 0.1, 0.25, 0.92), 6, 18, 4)
	card.name = "BuyTag"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	h.add_child(RetentionPanel.icon_safe(icon_name, int(px * 1.3)))
	if before != "":
		h.add_child(UiKit.label(before, px, Color.WHITE, 8))
	h.add_child(RetentionPanel.icon_safe("play", int(px * 0.7), UiKit.YELLOW))
	h.add_child(UiKit.label(after, px, UiKit.YELLOW, 8))
	return card

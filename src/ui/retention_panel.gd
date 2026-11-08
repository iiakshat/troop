class_name RetentionPanel
extends Control
## Shared frame for the retention panels (daily, missions, spin, boosters, revive, codex,
## chests, welcome back): a dimmed full screen, a card with a ribbon icon and a close X that is
## always visible and always works, an optional coin pill that rewards fly into, and helpers for
## reward rows, rewarded-ad buttons, pops, bursts and timers. No words: icons and numbers.
## Every panel frees itself on close and emits `closed` exactly once (Android back closes too).

signal closed

const CARD_W := 664.0
const OVERLAY_SIZE := Vector2(720, 1280)

var _card: PanelContainer
var _safe: Control
var _close_btn: Button
var _coin_pill: HBoxContainer
var _coins_shown := 0
var _coin_tween: Tween
var _closing := false
var _busy := false                 # an ad is showing for this panel: ignore repeat taps
var hold_coins := false            # true: the pill waits for count_coins() (chests)


## Builds the frame and returns the card's column. Call from _ready (needs the tree).
func _frame(icon_name: String, height: float, title := "", with_coins := true, color := UiKit.CREAM) -> VBoxContainer:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	UiKit.full_rect(dim)
	add_child(dim)
	_safe = Control.new()
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)
	UiKit.safe_rect(_safe)
	_card = UiKit.panel(color)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.offset_left = -CARD_W * 0.5
	_card.offset_right = CARD_W * 0.5
	_card.offset_top = -height * 0.5
	_card.offset_bottom = height * 0.5
	_safe.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var rib := UiKit.ribbon(icon_name, title)
	rib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(rib)
	_close_btn = UiKit.icon_button("close", "red", 96)
	_close_btn.pressed.connect(close)
	head.add_child(_close_btn)
	if with_coins:
		_coins_shown = int(Game.save.get("coins", 0))
		_coin_pill = UiKit.pill("coin", str(_coins_shown))
		_coin_pill.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(_coin_pill)
		Game.coins_changed.connect(_on_coins_changed)
	UiKit.pop(_card, 0.7)
	return col


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not _closing and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# ---------------------------------------------------------------- icons and labels

## Icon that never errors: glossy PNG, else white SVG glyph, else the star.
static func icon_safe(name: String, size := 64, tint := Color.WHITE) -> TextureRect:
	return UiKit.icon(name if has_icon(name) else "star_icon", size, tint)


static func has_icon(name: String) -> bool:
	return name != "" and (ResourceLoader.exists("res://assets/icons/gloss/%s.png" % name)
		or ResourceLoader.exists("res://assets/icons/%s.svg" % name))


## First icon name that exists in `names` (else star_icon).
static func first_icon(names: Array) -> String:
	for n in names:
		if has_icon(String(n)):
			return String(n)
	return "star_icon"


## Plays the first sound id the Sfx autoload has (AUDIO may not have added new ids yet).
static func sfx(ids: Array, volume_db := 0.0, pitch := 1.0) -> void:
	var s: Node = Engine.get_main_loop().root.get_node_or_null("Sfx") if Engine.get_main_loop() is SceneTree else null
	if s == null:
		return
	var streams: Variant = s.get("_streams")
	var variants: Variant = s.get("_variants")
	for id in ids:
		var known := (streams is Dictionary and (streams as Dictionary).has(id)) or (variants is Dictionary and (variants as Dictionary).has(id))
		if known or (streams == null and variants == null):
			s.play(String(id), volume_db, pitch)
			return


## Analytics event, if the autoload is there.
static func log_event(event_name: String, params := {}) -> void:
	var a: Node = Engine.get_main_loop().root.get_node_or_null("Analytics") if Engine.get_main_loop() is SceneTree else null
	if a:
		a.event(event_name, params)


## "hh:mm:ss" (or "mm:ss" under an hour).
static func clock_text(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	var s := seconds % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]


## Seconds until local midnight (when daily things reset). Real time, never faked.
static func seconds_to_midnight() -> int:
	var t := Time.get_time_dict_from_system()
	return 86400 - (int(t["hour"]) * 3600 + int(t["minute"]) * 60 + int(t["second"]))


## Short number: 1234 -> "1234", 12345 -> "12.3K", 1234567 -> "1.23M".
static func num(n: int) -> String:
	if absi(n) >= 1_000_000:
		return "%.2fM" % (n / 1_000_000.0)
	if absi(n) >= 10_000:
		return "%.1fK" % (n / 1000.0)
	return str(n)


# ---------------------------------------------------------------- rewards

## Icon name for a cosmetic id (outfit = shirt, knife skin = knife).
static func cosmetic_icon(reward: Dictionary) -> String:
	return "knife" if String(reward.get("cosmetic_kind", "")) == "knives" else "shirt"


## Ordered [[icon, text]] items for a reward dict: coins, boosters, cosmetic, unrolled chest.
static func reward_items(reward: Dictionary) -> Array:
	var out := []
	if int(reward.get("coins", 0)) > 0:
		out.append(["coin", num(int(reward["coins"]))])
	for b in ["headstart", "shield", "bomb"]:
		if int(reward.get(b, 0)) > 0:
			out.append([b, "×%d" % int(reward[b])])
	if String(reward.get("cosmetic", "")) != "":
		out.append([cosmetic_icon(reward), ""])
	if out.is_empty() and String(reward.get("chest", "")) != "":
		var cid := String(reward["chest"])
		out.append([String(Game.economy.get("chests", {}).get(cid, {}).get("icon", "chest")), ""])
	return out


## Row of reward icons with their numbers.
static func reward_row(reward: Dictionary, size := 64, font := 44, sep := 14) -> HBoxContainer:
	return items_row(reward_items(reward), size, font, sep)


## Row of [icon, text] items.
static func items_row(items: Array, size := 64, font := 44, sep := 14) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", sep)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in items:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon_safe(String(it[0]), size))
		if String(it[1]) != "":
			cell.add_child(UiKit.label(String(it[1]), font, Color.WHITE, maxi(font / 5, 6)))
		row.add_child(cell)
	return row


# ---------------------------------------------------------------- ads

## Green button with the ad icon and an optional number ("x2", "+1"). Logs the offer.
func ad_button(placement: String, text := "", size := Vector2(240, 110), extra_icon := "") -> Button:
	var b := UiKit.button("", "green", 10, size)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -8
	b.add_child(row)
	var ic := minf(size.y * 0.58, 72.0)
	row.add_child(icon_safe(first_icon(["ad_play", "play"]), int(ic)))
	if extra_icon != "":
		row.add_child(icon_safe(extra_icon, int(ic)))
	if text != "":
		row.add_child(UiKit.label(text, int(minf(size.y * 0.42, 54.0)), Color.WHITE, 10))
	b.set_meta("row", row)
	var ads := _ads()
	if ads:
		ads.note_offer(placement)
	return b


## Shows a rewarded ad (Ads stub opens the placeholder popup) and calls cb(ok). While it runs,
## repeat taps are ignored. Without the Ads autoload the reward is given at once.
func watch_ad(placement: String, cb: Callable) -> void:
	if _busy:
		return
	var ads := _ads()
	if ads == null:
		cb.call(true)
		return
	_busy = true
	ads.show_rewarded(placement, func(ok: bool):
		_busy = false
		if is_instance_valid(self) and not _closing:
			cb.call(ok))


func _ads() -> Node:
	return get_node_or_null("/root/Ads") if is_inside_tree() else null


# ---------------------------------------------------------------- juice

func _on_coins_changed(c: int) -> void:
	if not is_instance_valid(_coin_pill) or hold_coins:
		return
	_count_coins_to(c, 0.55)   # when the flying coins land


## Counts the pill up to the real balance (after flying coins land).
func count_coins(delay := 0.55) -> void:
	if is_instance_valid(_coin_pill):
		_count_coins_to(int(Game.save.get("coins", 0)), delay)


func set_coins_shown(c: int) -> void:
	_coins_shown = c
	if is_instance_valid(_coin_pill):
		UiKit.pill_set(_coin_pill, str(c))


func _count_coins_to(target: int, delay := 0.0) -> void:
	if _coin_tween and _coin_tween.is_valid():
		_coin_tween.kill()
	var from := _coins_shown
	_coin_tween = create_tween()
	_coin_tween.tween_method(func(v: float):
		_coins_shown = int(round(v))
		UiKit.pill_set(_coin_pill, str(_coins_shown)), float(from), float(target), 0.6).set_delay(delay)


## Global centre of a control.
static func centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## Flies `n` copies of an icon from `from` to `to` (global positions), then calls done().
func fly(icon_name: String, from: Vector2, to: Vector2, n := 8, done := Callable(), size := 64) -> void:
	var layer := Control.new()
	layer.top_level = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 50
	add_child(layer)
	var last: Tween = null
	for i in n:
		var ic := icon_safe(icon_name, size)
		ic.size = Vector2(size, size)
		ic.pivot_offset = ic.size * 0.5
		ic.position = from - ic.size * 0.5
		layer.add_child(ic)
		var spread := Vector2(randf_range(-110, 110), randf_range(-110, 40))
		var tw := ic.create_tween()
		tw.tween_property(ic, "position", from + spread - ic.size * 0.5, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(i * 0.035)
		tw.tween_property(ic, "position", to - ic.size * 0.5, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(ic, "scale", Vector2.ONE * 0.6, 0.42)
		tw.tween_callback(func():
			sfx(["coin"], -10.0, randf_range(0.95, 1.15))
			ic.queue_free())
		last = tw
	if last:
		last.finished.connect(func():
			layer.queue_free()
			if done.is_valid():
				done.call())
	else:
		layer.queue_free()


## Flies a reward's icons into the coin pill (coins) or to `to` (everything else).
func fly_reward(reward: Dictionary, from: Vector2, to := Vector2(-1, -1)) -> void:
	var pill_at := centre(_coin_pill) if is_instance_valid(_coin_pill) else from + Vector2(0, -300)
	var other_at := to if to.x >= 0.0 else pill_at
	for it in reward_items(reward):
		var ic := String(it[0])
		var target := pill_at if ic == "coin" else other_at
		fly(ic, from, target, 9 if ic == "coin" else 3)


## Little stars bursting out of a point (global), for claims and wins.
func burst(at: Vector2, n := 14, icon_name := "star_icon", size := 40) -> void:
	var layer := Control.new()
	layer.top_level = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 49
	add_child(layer)
	for i in n:
		var ic := icon_safe(icon_name, size)
		ic.size = Vector2(size, size)
		ic.pivot_offset = ic.size * 0.5
		ic.position = at - ic.size * 0.5
		layer.add_child(ic)
		var a := TAU * float(i) / float(n) + randf_range(-0.2, 0.2)
		var d := randf_range(120, 220)
		var tw := ic.create_tween().set_parallel()
		tw.tween_property(ic, "position", at + Vector2(cos(a), sin(a)) * d - ic.size * 0.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(ic, "rotation", randf_range(-3.0, 3.0), 0.55)
		tw.tween_property(ic, "modulate:a", 0.0, 0.55).set_delay(0.15)
	after(0.8, layer.queue_free)


## Calls cb after `seconds` (0 = next frame), on a tween bound to this node: nothing runs if
## the panel is gone by then. Works before the node is in a running tree.
func after(seconds: float, cb: Callable) -> void:
	var tw := create_tween()
	tw.tween_interval(maxf(seconds, 0.001))
	tw.tween_callback(cb)


## Endless gentle pulse (today's calendar cell, ready buttons).
static func pulse(c: Control, amount := 0.06, period := 0.9) -> Tween:
	var tw := c.create_tween().set_loops()
	tw.tween_callback(func(): c.pivot_offset = c.size * 0.5)
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), period * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, period * 0.5).set_trans(Tween.TRANS_SINE)
	return tw


## Rounded flat box style (cells, rows, bars).
static func box(color: Color, radius := 22, border := 5, border_color := UiKit.INK, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


static func card_box(color: Color, pad := 10, radius := 22, border := 5) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, border, UiKit.INK, pad))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Progress bar with an optional number on top ("12/15"). Returns the bar; set its value with
## bar_set(bar, have, need).
static func progress_bar(height := 46, fill := UiKit.GREEN, width := 0.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, height)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("background", box(Color(0.05, 0.1, 0.25, 0.75), height / 2, 4, UiKit.INK, 0))
	pb.add_theme_stylebox_override("fill", box(fill, height / 2, 4, UiKit.INK, 0))
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label("", int(height * 0.72), Color.WHITE, 8)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pb.add_child(l)
	pb.set_meta("label", l)
	return pb


static func bar_set(pb: ProgressBar, have: float, need: float, text := "") -> void:
	pb.max_value = maxf(need, 1.0)
	pb.value = clampf(have, 0.0, pb.max_value)
	(pb.get_meta("label") as Label).text = text if text != "" else "%d/%d" % [int(have), int(need)]


## A drawn check mark (no glyphs needed) for claimed cells.
static func check_mark(size := 56, color := UiKit.GREEN) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var s := c.size
		var pts := PackedVector2Array([Vector2(0.12, 0.52) * s, Vector2(0.4, 0.8) * s, Vector2(0.9, 0.2) * s])
		c.draw_polyline(pts, UiKit.INK, s.x * 0.26, true)
		c.draw_polyline(pts, color, s.x * 0.15, true))
	return c

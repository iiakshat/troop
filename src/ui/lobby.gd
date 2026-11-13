class_name Lobby
extends Control
## The lobby: the city map (CityMap) fills the screen; over it a top bar (settings, coins),
## side buttons (Daily = gift, Spin = wheel, Missions on the left; star chest with its
## progress on the right) and a bottom bar (Station, Armory, a big Play showing the selected
## level, Style; v2 moved Codex to the left column). Every button has a "!" alert when
## something is claimable or affordable. Icons and numbers only. v1.1: the top bar shows Squad
## Power (emblem + number, tap = Armory since v2; counts up after an upgrade) and a hand bobs
## over the Station or Armory button when the best next purchase (Game.best_purchase) is a
## room or a weapon step; the map points at buildings itself.
##
## Signals for INTEGRATE (RETENTION-UI panels open from main.gd, or via open_panel()):
##   play_pressed(level)  Play, or tapping the selected level node again
##   play(level)          same moment as play_pressed; kept so main.gd keeps working.
##                        Connect only one of the two.
##   daily_pressed  spin_pressed  missions_pressed  codex_pressed  star_chest_pressed
## Station, Armory, Style, Settings and BuildingPanel open here (one overlay at a time).
## close_overlay() -> bool closes the open panel (Android back: close it, else quit).
## After a win, lobby.map.advance_from(level_just_beaten) makes the pin hop to the next level.
## Debug args (after --): save=path (load that save, never write), building=<id> (open its
## panel), focus=N (scroll the map to level N), collect=1 (collect the city after 1 s),
## buy=<weapon id> (with panel=armory: buy one step after 1 s).

signal play(level: int)
signal play_pressed(level: int)
signal daily_pressed
signal spin_pressed
signal missions_pressed
signal codex_pressed
signal star_chest_pressed

var map: CityMap
var _chrome: Control
var _coins: HBoxContainer
var _coin_icon: Control
var _power: HBoxContainer
var _shown_power := -1.0
var _power_delta: PowerDelta
var _hand: Control = null  # best-purchase pointer on the Station or Armory: tag (before ▸ after) + tapping hand
var _hand_at := ""
var _play: Button
var _play_icon: TextureRect
var _play_label: Label
var _station: Button
var _armory: Button
var _codex: Button
var _style: Button
var _daily: Button
var _spin: Button
var _missions: Button
var _chest: Button
var _chest_label: Label
var _overlay: Control = null
var _level := 1
var _shown_coins := 0
var _flying := 0
var _away: Control = null   # the earned-while-away pill on show


func _ready() -> void:
	_debug_save()
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	map = CityMap.new()
	UiKit.full_rect(map)
	add_child(map)
	_level = map.selected
	map.level_selected.connect(_on_level_selected)
	map.play_requested.connect(_start)
	map.building_pressed.connect(_open_building)
	map.collected.connect(_on_collected)

	_chrome = Control.new()
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chrome)
	UiKit.safe_rect(_chrome)
	_build_top()
	_build_sides()
	_build_bottom()

	Game.coins_changed.connect(_on_coins)
	Game.alerts_changed.connect(refresh)
	Game.stars_changed.connect(_on_stars)
	Game.city_changed.connect(refresh)
	_shown_coins = int(Game.save["coins"])
	refresh()
	_debug_args()
	# After main.gd's boot popups have had their turn (the welcome-back one collects all).
	get_tree().create_timer(1.2).timeout.connect(_show_away)


func _build_top() -> void:
	# A dark fade behind the top bar, so map pills scrolling under it never mix with its numbers.
	var fade := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var gr := Gradient.new()
	gr.set_color(0, Color(0.02, 0.04, 0.1, 0.92))
	gr.set_color(1, Color(0.02, 0.04, 0.1, 0.0))
	gr.add_point(0.6, Color(0.02, 0.04, 0.1, 0.8))
	gt.gradient = gr
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	fade.offset_bottom = 150
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(fade)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 20
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 14)
	_chrome.add_child(top)
	var gear := UiKit.icon_button("settings", "yellow", 92)
	gear.pressed.connect(func(): _open(SettingsPanel.new()))
	top.add_child(gear)
	_power = UiKit.pill("power", "0", Color.WHITE)
	_power.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_power.mouse_filter = Control.MOUSE_FILTER_STOP
	_power.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_open(ArmoryPanel.new()))
	top.add_child(_power)
	_power_delta = PowerDelta.make(_power, 30, 2.0)
	_chrome.add_child(_power_delta)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	_coins = UiKit.pill("coin", "0", UiKit.YELLOW)
	_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_coins)
	_coin_icon = _coins.get_child(0).get_child(0).get_child(0) as Control


func _side_button(icon_name: String, sig: Signal, parent: Control) -> Button:
	var b := UiKit.icon_button(icon_name, "blue", 108)
	b.pressed.connect(func(): sig.emit())
	parent.add_child(b)
	return b


func _build_sides() -> void:
	var left := VBoxContainer.new()
	left.position = Vector2(20, 136)
	left.add_theme_constant_override("separation", 18)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(left)
	_daily = _side_button("gift", daily_pressed, left)
	_spin = _side_button("wheel", spin_pressed, left)
	_missions = _side_button("missions", missions_pressed, left)
	_codex = _side_button("badge", codex_pressed, left)

	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -128
	right.offset_right = -20
	right.offset_top = 136
	right.add_theme_constant_override("separation", 2)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(right)
	_chest = _side_button("star_chest", star_chest_pressed, right)
	_chest_label = UiKit.label("0/15", 30, Color.WHITE, 9)
	right.add_child(_chest_label)


func _build_bottom() -> void:
	var strip := Panel.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -176
	strip.offset_bottom = 400  # runs under the gesture bar / past the screen edge
	var sb := UiKit.flat_box(Color(0.04, 0.1, 0.26, 0.72), 34, 5)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	strip.add_theme_stylebox_override("panel", sb)
	_chrome.add_child(strip)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 18
	row.offset_right = -18
	row.offset_top = -160
	row.offset_bottom = -18
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(row)
	_station = UiKit.icon_button("station", "blue", 126)
	_station.size_flags_vertical = Control.SIZE_SHRINK_END
	_station.pressed.connect(func(): _open(StationPanel.new()))
	row.add_child(_station)
	_armory = UiKit.icon_button("pistol", "blue", 126)
	_armory.size_flags_vertical = Control.SIZE_SHRINK_END
	_armory.pressed.connect(func(): _open(ArmoryPanel.new()))
	row.add_child(_armory)

	_play = UiKit.button("", "green", 10, Vector2(0, 142))
	_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play.size_flags_vertical = Control.SIZE_SHRINK_END
	_play.pressed.connect(func(): _start(_level))
	row.add_child(_play)
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_theme_constant_override("separation", 6)
	prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(prow)
	prow.offset_top = 8
	prow.offset_bottom = -18
	_play.add_child(prow)
	_play_icon = UiKit.icon("play", 74)
	prow.add_child(_play_icon)
	_play_label = UiKit.label("1", 66, Color.WHITE, 12)
	prow.add_child(_play_label)

	_style = UiKit.icon_button("shirt", "blue", 126)
	_style.size_flags_vertical = Control.SIZE_SHRINK_END
	_style.pressed.connect(func(): _open(StylePanel.new()))
	row.add_child(_style)
	_play_breathe()
	# Best-next-purchase pointer for station rooms (no words): _point_station.


func _play_breathe() -> void:
	var tw := _play.create_tween().set_loops()
	tw.tween_interval(1.6)
	tw.tween_callback(func(): UiKit.bump(_play, 1.06))


## Opens a full-screen panel over the lobby (one at a time); the lobby refreshes when it closes.
func open_panel(p: Control) -> void:
	_open(p)


func _open(p: Control) -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = p
	p.tree_exited.connect(_on_panel_closed)
	add_child(p)
	_point_station()


## Closes the open panel (for Android back). True if there was one to close.
func close_overlay() -> bool:
	if not is_instance_valid(_overlay) or _overlay.is_queued_for_deletion():
		return false
	# Prefer close(): retention panels emit `closed` there, which the boot popup chain waits on.
	if _overlay.has_method("close"):
		_overlay.call("close")
	elif _overlay.has_method("_close"):
		_overlay.call("_close")
	else:
		_overlay.queue_free()
	_overlay = null
	return true


func _open_building(id: String) -> void:
	_open(BuildingPanel.new(id))


func _on_panel_closed() -> void:
	if is_inside_tree():
		refresh()
		map.refresh()
		get_tree().create_timer(0.6).timeout.connect(_show_away)


func _start(n: int) -> void:
	play_pressed.emit(n)
	play.emit(n)


func _on_level_selected(n: int) -> void:
	_level = n
	refresh()
	UiKit.bump(_play, 1.08)


func _on_coins(_c: int) -> void:
	refresh()


func _on_stars(_t: int) -> void:
	refresh()


## Storage collected on the map (the whole city at once): coins fly from every bubble (and the
## tapped spot) to the counter, a +N rises from the tapped spot, then the counter counts up.
func _on_collected(coins: int, from: Vector2) -> void:
	_flying += 1
	var before := _shown_coins
	var to := _coin_icon.get_global_rect().get_center()
	var points: Array = [from]
	for p in map.bubble_points():
		if (p as Vector2).distance_to(from) > 40.0:
			points.append(p)
	var per := maxi(int(ceil(CityMap.fly_count(coins) / float(points.size()))), 1)
	var left := [points.size()]
	var land := func():
		Sfx.play("coin")
		UiKit.bump(_coin_icon, 1.25)
	var done := func():
		left[0] -= 1
		if left[0] > 0:
			return
		_flying -= 1
		var now := int(Game.save["coins"])
		UiKit.pill_count(_coins, before, now)
		_shown_coins = now
	for p in points:
		UiKit.fly_coins(self, p, to, per if p == from else 1, land, done)
	_rise_gain(coins, from)


## "+N" with a coin rising from a collection spot and fading.
func _rise_gain(coins: int, at: Vector2) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.top_level = true
	row.z_index = 51
	row.add_theme_constant_override("separation", 4)
	row.add_child(UiKit.icon("coin", 44))
	row.add_child(UiKit.label("+" + UiKit.fmt_coins(coins), 46, UiKit.YELLOW, 12))
	add_child(row)
	row.size = row.get_combined_minimum_size()
	row.global_position = at - Vector2(row.size.x * 0.5, row.size.y)
	var tw := row.create_tween().set_parallel()
	tw.tween_property(row, "global_position:y", row.global_position.y - 110.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "modulate:a", 0.0, 0.4).set_delay(0.7)
	tw.chain().tween_callback(row.queue_free)


# ---------------------------------------------------------------- earned while away

## Owner play-test: each return to the map (from a level, or the app from the background)
## shows what the city stored meanwhile, a pill under the top bar: clock, coin, +N counting up
## and the storage's fill bar under it (full = the cap; it stops earning until collected).
## Tapping it collects the whole storage like a bubble. Waits while a panel is open (the
## welcome-back popup collects and so shows nothing more), and never shows +0.
func _show_away() -> void:
	if not is_inside_tree() or is_instance_valid(_overlay):
		return
	var g: Dictionary = Game.take_away_gain()
	var n := int(g.get("coins", 0))
	if n < 1:
		return
	if is_instance_valid(_away):
		_away.queue_free()
	var box := PanelContainer.new()
	var sb := UiKit.flat_box(Color(0.05, 0.12, 0.3, 0.88), 34, 4)
	sb.content_margin_left = 16
	sb.content_margin_right = 22
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	row.add_child(RetentionPanel.icon_safe("clock", 48))
	row.add_child(UiKit.icon("coin", 48))
	var num := UiKit.label("+0", 44, UiKit.YELLOW, 10)
	row.add_child(num)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = float(g.get("fill", 0.0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UiKit.flat_box(Color(0, 0, 0, 0.45), 6, 2))
	bar.add_theme_stylebox_override("fill", UiKit.flat_box(UiKit.RED if bar.value >= 0.999 else UiKit.YELLOW, 6, 2))
	col.add_child(bar)
	_chrome.add_child(box)
	_away = box
	box.set_meta("label", num)
	box.set_meta("coins", n)
	box.size = box.get_combined_minimum_size()
	box.position = Vector2((_chrome.size.x - box.size.x) * 0.5, 128.0)
	box.pivot_offset = box.size * 0.5
	box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			box.accept_event()
			var at := box.get_global_rect().get_center()
			box.queue_free()
			map.collect_from(at))
	Sfx.play("coin")
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_method(func(v: float): num.text = "+" + UiKit.fmt_coins(int(round(v))), 0.0, float(n), 0.8)
	tw.tween_callback(func(): UiKit.bump(box, 1.12))
	tw.tween_interval(2.6)
	tw.tween_property(box, "modulate:a", 0.0, 0.5)
	tw.tween_callback(box.queue_free)


## The earned-while-away pill on show: {coins, text}, or {} (tests).
func away_shown() -> Dictionary:
	if not is_instance_valid(_away) or _away.is_queued_for_deletion():
		return {}
	return {"coins": int(_away.get_meta("coins")), "text": (_away.get_meta("label") as Label).text}


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_show_away.call_deferred()  # after main.gd's welcome-back popup, which waits for it


func _exit_tree() -> void:
	Game.mark_away()  # off to a level (or the app closes): the away earnings count from here


func refresh() -> void:
	if not is_inside_tree():
		return
	if _flying <= 0:
		_shown_coins = int(Game.save["coins"])
		UiKit.pill_set(_coins, str(_shown_coins))
	var al: Dictionary = Game.alerts()
	UiKit.set_alert(_daily, bool(al.get("daily", false)))
	UiKit.set_alert(_spin, bool(al.get("spin", false)))
	UiKit.set_alert(_missions, bool(al.get("missions", false)))
	UiKit.set_alert(_station, bool(al.get("station", false)))
	UiKit.set_alert(_armory, bool(al.get("armory", false)))
	UiKit.set_alert(_chest, bool(al.get("star_chest", false)))
	var chest: Dictionary = Game.star_chest_progress()
	var span := maxi(int(chest.get("need", 0)) - int(chest.get("from", 0)), 1)
	var into := clampi(int(chest.get("have", 0)) - int(chest.get("from", 0)), 0, span)
	_chest_label.text = "%d/%d" % [into, span]
	if map:
		_level = map.selected   # Play always shows the map's pin (select() and advance_from() emit nothing)
	_play_label.text = str(_level)
	var boss := Economy.is_boss(_level, Game.economy)
	_play_icon.texture = UiKit.icon_texture("boss_crown" if boss else "play")
	_refresh_power()
	_point_station.call_deferred()


## Squad Power pill: counts up with a bump when it grew (an upgrade was just bought).
func _refresh_power() -> void:
	if _shown_power >= 0.0 and is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion():
		return  # the pill counts up (and shows its +N) once the panel closes
	var p := Game.squad_power()
	if _shown_power >= 0.0 and absf(p - _shown_power) >= 0.05:
		_power_delta.add(p - _shown_power)  # owner play-test: +N in green under the pill
	if _shown_power >= 0.0 and p >= _shown_power + 0.05:
		UiKit.pill_count(_power, _shown_power, p, 0.6, Economy.fmt_power)
		UiKit.bump(_power, 1.2)
	else:
		UiKit.pill_set(_power, Economy.fmt_power(p))
	_shown_power = p


## Spec v2 §11: when the best next purchase is a Station room (or an Armory step), the hand taps
## on the Station (or Armory) button under the item's icon and its in-game number before ▸ after.
func _point_station() -> void:
	if not is_inside_tree() or _station == null:
		return
	var best: Dictionary = {} if Game.first_build_pending() else Game.best_purchase()
	var kind := String(best.get("kind", ""))
	var target: Button = _station if kind == "room" else (_armory if kind == "weapon" else null)
	var show := target != null and not is_instance_valid(_overlay)
	var id := String(best.get("id", "")) if show else ""
	var lv := 0
	if show:
		lv = Armory.index(Game.save, id) if kind == "weapon" else Game.room_level(id)
	var key := "%s:%s:%d" % [kind, id, lv] if show else ""
	if key == _hand_at:
		return
	_hand_at = key
	if is_instance_valid(_hand):
		_hand.queue_free()
	_hand = null
	if not show:
		return
	var icon := String(ArmoryPanel.FALLBACK.get(id, "pistol")) if kind == "weapon" \
		else String(Game.economy["station"].get(id, {}).get("icon", "station"))
	# A holder at the fingertip spot carries the tag (above the button's left edge) and the
	# tapping hand, so the tag never scales with the hand's press.
	var sz := target.size if target.size.x > 1.0 else target.get_combined_minimum_size()
	var tip := sz * Vector2(0.55, 0.25)  # the whole hand stays above the screen edge
	_hand = Control.new()
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.z_index = 5
	_hand.position = tip
	target.add_child(_hand)
	var tag := PointerHand.tag(icon, StationPanel.value_text(id, lv), StationPanel.value_text(id, lv + 1), 32)
	tag.resized.connect(func(): tag.position = -tip - Vector2(0, tag.size.y + 12))
	_hand.add_child(tag)
	PointerHand.on(_hand, Vector2.ZERO, 104.0)


# ---------------------------------------------------------------- debug (screenshots)

func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		if kv[0] == key:
			return kv[1] if kv.size() > 1 else "1"
	return ""


## save=path: play on a copy of that save (JSON) and never write the real one.
func _debug_save() -> void:
	var path := _arg("save")
	if path == "" or not FileAccess.file_exists(path) or Game.has_meta("debug_save"):
		return  # main.gd already loaded it at boot (loading again would undo this session)
	Game.save_path = ""
	Game.boot(Config.load_json(path))


func _debug_args() -> void:
	var f := _arg("focus")
	if f != "":
		map.focus_level(int(f), false)
	var b := _arg("building")
	if b != "":
		_open_building(b)
	var adv := _arg("advance")
	if adv != "":
		map.advance_from(int(adv))
	if _arg("collect") != "":
		get_tree().create_timer(1.0).timeout.connect(map.collect_any)
	var buy := _arg("buy")
	if buy != "":
		# buy=<weapon id> with panel=armory: one step is bought after 1 s (screenshots).
		get_tree().create_timer(1.0).timeout.connect(func():
			if _overlay is ArmoryPanel:
				(_overlay as ArmoryPanel).buy(buy))

class_name Lobby
extends Control
## The lobby: the city map (CityMap) fills the screen; over it a top bar (settings, coins),
## side buttons (Daily = gift, Spin = wheel, Missions on the left; star chest with its
## progress on the right) and a bottom bar (Station, Codex, a big Play showing the selected
## level, Style). Every button has a "!" alert when something is claimable or affordable.
## Icons and numbers only. v1.1: the top bar shows Squad Power (emblem + number, tap = Station;
## counts up after an upgrade) and a hand bobs over the Station button when the best next
## purchase (Game.best_purchase) is a room; the map points at buildings itself.
##
## Signals for INTEGRATE (RETENTION-UI panels open from main.gd, or via open_panel()):
##   play_pressed(level)  Play, or tapping the selected level node again
##   play(level)          same moment as play_pressed; kept so main.gd keeps working.
##                        Connect only one of the two.
##   daily_pressed  spin_pressed  missions_pressed  codex_pressed  star_chest_pressed
## Station, Style, Settings and BuildingPanel open here (one overlay at a time).
## close_overlay() -> bool closes the open panel (Android back: close it, else quit).
## After a win, lobby.map.advance_from(level_just_beaten) makes the pin hop to the next level.
## Debug args (after --): save=path (load that save, never write), building=<id> (open its
## panel), focus=N (scroll the map to level N).

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
var _shown_power := -1
var _hand: TextureRect
var _hand_tw: Tween
var _play: Button
var _play_icon: TextureRect
var _play_label: Label
var _station: Button
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


func _build_top() -> void:
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
			_open(StationPanel.new()))
	top.add_child(_power)
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
	_codex = UiKit.icon_button("badge", "blue", 126)
	_codex.size_flags_vertical = Control.SIZE_SHRINK_END
	_codex.pressed.connect(func(): codex_pressed.emit())
	row.add_child(_codex)

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
	# Best-next-purchase pointer for station rooms (no words): a hand tapping the Station.
	_hand = UiKit.icon("hand", 104)
	_hand.size = Vector2(104, 104)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.visible = false
	_chrome.add_child(_hand)


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


## Storage collected on the map: coins fly from the bubble to the counter, which then counts up.
func _on_collected(coins: int, from: Vector2) -> void:
	_flying += 1
	var before := _shown_coins
	var to := _coin_icon.get_global_rect().get_center()
	var land := func():
		Sfx.play("coin")
		UiKit.bump(_coin_icon, 1.25)
	var done := func():
		_flying -= 1
		var now := int(Game.save["coins"])
		UiKit.pill_count(_coins, before, now)
		_shown_coins = now
	UiKit.fly_coins(self, from, to, CityMap.fly_count(coins), land, done)


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
	UiKit.set_alert(_chest, bool(al.get("star_chest", false)))
	var chest: Dictionary = Game.star_chest_progress()
	var span := maxi(int(chest.get("need", 0)) - int(chest.get("from", 0)), 1)
	var into := clampi(int(chest.get("have", 0)) - int(chest.get("from", 0)), 0, span)
	_chest_label.text = "%d/%d" % [into, span]
	if map and CityMap.node_state(Game.save, _level, Config.LEVEL_COUNT) == "locked":
		_level = map.selected
	_play_label.text = str(_level)
	var boss := Economy.is_boss(_level, Game.economy)
	_play_icon.texture = UiKit.icon_texture("boss_crown" if boss else "play")
	_refresh_power()
	_point_station.call_deferred()


## Squad Power pill: counts up with a bump when it grew (an upgrade was just bought).
func _refresh_power() -> void:
	var p := Game.squad_power()
	if _shown_power >= 0 and p > _shown_power:
		UiKit.pill_count(_power, _shown_power, p, 0.6)
		UiKit.bump(_power, 1.2)
	else:
		UiKit.pill_set(_power, str(p))
	_shown_power = p


func _point_station() -> void:
	if not is_inside_tree() or _hand == null:
		return
	var best: Dictionary = {} if Game.first_build_pending() else Game.best_purchase()
	var show := String(best.get("kind", "")) == "room" and not is_instance_valid(_overlay)
	if show == _hand.visible:
		return
	_hand.visible = show
	if _hand_tw:
		_hand_tw.kill()
		_hand_tw = null
	if show:
		# Fingertip (the icon's lower right) on the Station button's upper half.
		var r := _station.get_global_rect()
		var tip := r.position + Vector2(r.size.x * 0.62, r.size.y * 0.42)
		_hand.global_position = tip - Vector2(92, 92)
		var p := _hand.position
		_hand_tw = _hand.create_tween().set_loops()
		_hand_tw.tween_property(_hand, "position", p - Vector2(18, 18), 0.35).set_trans(Tween.TRANS_SINE)
		_hand_tw.tween_property(_hand, "position", p, 0.35).set_trans(Tween.TRANS_SINE)


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

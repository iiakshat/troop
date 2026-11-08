class_name Lobby
extends Control
## Title screen over the jogging squad: coins, settings, level picker, Station / Style and
## a big Play button. Icons over words.

signal play(level: int)

var _coins: HBoxContainer
var _level := 1
var _level_buttons: Array[Button] = []
var _play: Button
var _overlay: Control = null


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level = int(Game.save["unlocked"])

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 28
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var gear := UiKit.icon_button("settings", "yellow", 96)
	gear.pressed.connect(func(): _open(SettingsPanel.new()))
	top.add_child(gear)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	_coins = UiKit.pill("coin", "0", UiKit.YELLOW)
	_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_coins)

	var title := UiKit.label("TROOP", 170, UiKit.YELLOW, 30)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 140
	title.offset_bottom = 330
	title.rotation_degrees = -4.0
	add_child(title)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 34
	col.offset_right = -34
	col.offset_top = -470
	col.offset_bottom = -40
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var levels := HBoxContainer.new()
	levels.alignment = BoxContainer.ALIGNMENT_CENTER
	levels.add_theme_constant_override("separation", 14)
	levels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(levels)
	for n in range(1, Config.LEVEL_COUNT + 1):
		var b := UiKit.button(str(n), "blue", 48, Vector2(110, 110), "round")
		b.pressed.connect(_pick_level.bind(n))
		levels.add_child(b)
		_level_buttons.append(b)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var station := UiKit.icon_button("badge", "blue", 150)
	station.pressed.connect(func(): _open(StationPanel.new()))
	row.add_child(station)
	_play = UiKit.icon_button("play", "green", 150)
	_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play.pressed.connect(func(): play.emit(_level))
	row.add_child(_play)
	var style := UiKit.icon_button("shirt", "blue", 150)
	style.pressed.connect(func(): _open(StylePanel.new()))
	row.add_child(style)
	Game.coins_changed.connect(func(_c): refresh())
	refresh()


func _open(p: Control) -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = p
	p.tree_exited.connect(refresh)
	add_child(p)


func _pick_level(n: int) -> void:
	if n <= int(Game.save["unlocked"]):
		_level = n
		refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	UiKit.pill_set(_coins, str(int(Game.save["coins"])))
	for i in _level_buttons.size():
		var n := i + 1
		var b := _level_buttons[i]
		var locked := n > int(Game.save["unlocked"])
		b.disabled = locked
		b.text = "" if locked else str(n)
		if locked and not b.has_meta("lock"):
			var l := UiKit.icon("lock", 54)
			l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			l.offset_left = -27
			l.offset_right = 27
			l.offset_top = -34
			l.offset_bottom = 20
			b.add_child(l)
			b.set_meta("lock", l)
		if b.has_meta("lock"):
			(b.get_meta("lock") as Control).visible = locked
		var colr := "yellow" if n == _level else "blue"
		b.add_theme_stylebox_override("normal", UiKit._tex_box(colr, "round"))
		b.add_theme_stylebox_override("hover", UiKit._tex_box(colr, "round"))

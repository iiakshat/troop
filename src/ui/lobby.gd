class_name Lobby
extends Control
## Title screen over the jogging squad: coins, level picker, upgrades, PLAY.

signal play(level: int)

var _coins: Label
var _level := 1
var _level_buttons: Array[Button] = []
var _play: Button
var _upgrade_rows: Dictionary = {}


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
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	var coin_box := PanelContainer.new()
	coin_box.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.5), 30))
	coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(coin_box)
	_coins = UiKit.label("0", 42, UiKit.GOLD)
	coin_box.add_child(_coins)

	var title := UiKit.label("TROOP", 150, Color.WHITE, 26)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 120
	title.offset_bottom = 290
	add_child(title)
	var tag := UiKit.label("OUTSMART THE GANG", 40, UiKit.GOLD, 10)
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tag.offset_top = 280
	tag.offset_bottom = 330
	add_child(tag)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = 30
	col.offset_right = -30
	col.offset_top = -560
	col.offset_bottom = -40
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var up_row := HBoxContainer.new()
	up_row.add_theme_constant_override("separation", 12)
	col.add_child(up_row)
	for id in ["knife", "speed", "squad"]:
		up_row.add_child(_upgrade_card(id))

	var levels := HBoxContainer.new()
	levels.alignment = BoxContainer.ALIGNMENT_CENTER
	levels.add_theme_constant_override("separation", 16)
	col.add_child(levels)
	for n in range(1, Config.LEVEL_COUNT + 1):
		var b := UiKit.button(str(n), UiKit.BLUE, 44, Vector2(100, 90))
		b.pressed.connect(_pick_level.bind(n))
		levels.add_child(b)
		_level_buttons.append(b)

	_play = UiKit.button("PLAY", UiKit.GREEN, 72, Vector2(0, 150))
	_play.pressed.connect(func(): play.emit(_level))
	col.add_child(_play)
	refresh()


func _upgrade_card(id: String) -> Control:
	var up: Dictionary = Game.economy["upgrades"][id]
	var card := UiKit.panel(Color(0.08, 0.09, 0.13, 0.85))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	card.add_child(info)
	var name := UiKit.label(String(up["name"]).to_upper().replace(" ", "
"), 30)
	info.add_child(name)
	var desc := UiKit.label("", 24, Color("b8c2d6"), 6)
	info.add_child(desc)
	var buy := UiKit.button("", UiKit.GOLD, 32, Vector2(0, 76))
	info.add_child(buy)
	buy.pressed.connect(func():
		if Game.buy_upgrade(id):
			Sfx.play("coin")
			Sfx.play("recruit")
			UiKit.pop(buy, 0.8)
			refresh())
	_upgrade_rows[id] = {"desc": desc, "buy": buy}
	return card


func _pick_level(n: int) -> void:
	if n <= int(Game.save["unlocked"]):
		_level = n
		refresh()


func refresh() -> void:
	_coins.text = "%d COINS" % int(Game.save["coins"])
	for i in _level_buttons.size():
		var n := i + 1
		var b := _level_buttons[i]
		b.disabled = n > int(Game.save["unlocked"])
		b.text = str(n) if not b.disabled else "-"
		var col := UiKit.GREEN if n == _level else UiKit.BLUE
		b.add_theme_stylebox_override("normal", UiKit.box(col, 26, 4))
	_play.text = "PLAY  ·  LEVEL %d" % _level
	for id in _upgrade_rows:
		var up: Dictionary = Game.economy["upgrades"][id]
		var lv := int(Game.upgrades().get(id, 0))
		var r: Dictionary = _upgrade_rows[id]
		(r["desc"] as Label).text = "LV %d/%d" % [lv, int(up["max"])]
		var cost := Game.upgrade_cost(id)
		var buy: Button = r["buy"]
		if cost < 0:
			buy.text = "MAX"
			buy.disabled = true
		else:
			buy.text = "%d" % cost
			buy.disabled = int(Game.save["coins"]) < cost

class_name StationPanel
extends Control
## Police station: one card per room with its icon, level pips, the bonus it gives (a
## number) and a buy button (coin + price), a lock until the front desk opens it, or a
## tick when maxed.

var _cards: Dictionary = {}


func _ready() -> void:
	UiKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	UiKit.full_rect(dim)
	add_child(dim)
	var p := UiKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -330
	p.offset_right = 330
	p.offset_top = -560
	p.offset_bottom = 560
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	p.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var rib := UiKit.ribbon("badge")
	rib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(rib)
	var close := UiKit.icon_button("close", "red", 96)
	close.pressed.connect(queue_free)
	head.add_child(close)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)
	for room in Game.economy["station_order"]:
		grid.add_child(_card(String(room)))
	refresh()
	UiKit.pop(p, 0.7)


func _card(room: String) -> Control:
	var r: Dictionary = Game.economy["station"][room]
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("3b6fd1")
	sb.set_corner_radius_all(22)
	sb.set_border_width_all(5)
	sb.border_color = UiKit.INK
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(285, 0)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var ic := UiKit.icon(String(r["icon"]), 92)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var effect := UiKit.label("", 40, UiKit.YELLOW, 10)
	col.add_child(effect)
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 8)
	col.add_child(pips)
	for i in int(r["max"]):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(30, 30)
		pips.add_child(pip)
	var buy := UiKit.button("", "green", 40, Vector2(0, 96))
	buy.pressed.connect(func(): _buy(room))
	col.add_child(buy)
	var coin := UiKit.icon("coin", 44, UiKit.YELLOW)
	coin.position = Vector2(18, 18)
	buy.add_child(coin)
	_cards[room] = {"effect": effect, "pips": pips, "buy": buy, "coin": coin, "card": card}
	return card


func _buy(room: String) -> void:
	if Game.buy_room(room):
		Sfx.play("upgrade")
		var c: Dictionary = _cards[room]
		UiKit.pop(c["card"], 0.85)
		refresh()
	else:
		Sfx.play("error")


func refresh() -> void:
	for room in _cards:
		var r: Dictionary = Game.economy["station"][room]
		var c: Dictionary = _cards[room]
		var lv := Game.room_level(room)
		var cost := Game.room_cost(room)
		var unlocked := SaveData.room_unlocked(Game.economy, Game.save["station"], room)
		var per := float(r["per"])
		match String(r["effect"]):
			"coins":
				(c["effect"] as Label).text = "+%d%%" % int(round(maxi(lv, 1) * per * 100))
			"desk":
				(c["effect"] as Label).text = "%d" % (lv + 1)
			"charges":
				(c["effect"] as Label).text = "+%d" % maxi(lv, 1)
			_:
				(c["effect"] as Label).text = "+%d" % int(maxi(lv, 1) * per)
		var pips: HBoxContainer = c["pips"]
		for i in pips.get_child_count():
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiKit.YELLOW if i < lv else Color(0, 0, 0, 0.35)
			sb.set_corner_radius_all(15)
			sb.set_border_width_all(3)
			sb.border_color = UiKit.INK
			(pips.get_child(i) as Panel).add_theme_stylebox_override("panel", sb)
		var buy: Button = c["buy"]
		var coin: Control = c["coin"]
		if not unlocked:
			buy.text = ""
			buy.disabled = true
			coin.texture = UiKit.icon_texture("lock")
			coin.position = Vector2(110, 20)
		elif cost < 0:
			buy.text = "MAX"
			buy.disabled = true
			coin.visible = false
		else:
			buy.text = "   %d" % cost
			buy.disabled = int(Game.save["coins"]) < cost
			coin.texture = UiKit.icon_texture("coin")
			coin.position = Vector2(18, 18)
			coin.visible = true

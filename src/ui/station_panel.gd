class_name StationPanel
extends Control
## Police station upgrades. One row per room: its glossy icon, what you have now ▸ what the
## next level gives (real numbers from the game: knife damage, throws per second, starting
## squad, squad cap, coin bonus, powers at the start), level pips, and a coin price.

var _rows: Dictionary = {}
var _coins: HBoxContainer


func _ready() -> void:
	UiKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	UiKit.full_rect(dim)
	add_child(dim)
	var p := UiKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -340
	p.offset_right = 340
	p.offset_top = -520
	p.offset_bottom = 520
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	p.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var rib := UiKit.ribbon("station")
	rib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(rib)
	var close := UiKit.icon_button("close", "red", 96)
	close.pressed.connect(queue_free)
	head.add_child(close)
	_coins = UiKit.pill("coin", str(int(Game.save["coins"])))
	_coins.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_coins)
	for room in Game.economy["station_order"]:
		col.add_child(_row(String(room)))
	refresh()
	UiKit.pop(p, 0.7)


func _row(room: String) -> Control:
	var r: Dictionary = Game.economy["station"][room]
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("3b6fd1")
	sb.set_corner_radius_all(22)
	sb.set_border_width_all(5)
	sb.border_color = UiKit.INK
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	row.add_child(UiKit.icon(String(r["icon"]), 104))

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	row.add_child(mid)
	var values := HBoxContainer.new()
	values.alignment = BoxContainer.ALIGNMENT_CENTER
	values.add_theme_constant_override("separation", 10)
	mid.add_child(values)
	var now := UiKit.label("", 46, Color.WHITE, 10)
	values.add_child(now)
	var arrow := UiKit.icon("play", 34, UiKit.YELLOW)
	values.add_child(arrow)
	var next := UiKit.label("", 46, UiKit.YELLOW, 10)
	values.add_child(next)
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 8)
	mid.add_child(pips)
	for i in int(r["max"]):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(28, 16)
		pips.add_child(pip)

	var buy := UiKit.button("", "green", 40, Vector2(190, 100))
	buy.pressed.connect(func(): _buy(room))
	row.add_child(buy)
	var coin := UiKit.icon("coin", 46)
	coin.position = Vector2(14, 20)
	buy.add_child(coin)
	_rows[room] = {"now": now, "next": next, "arrow": arrow, "pips": pips, "buy": buy, "coin": coin, "card": card}
	return card


## The number a room shows at a given level, using the game's real base stats.
static func value_text(room: String, lv: int) -> String:
	var r: Dictionary = Game.economy["station"][room]
	var units: Dictionary = Config.units()
	var per := float(r["per"])
	match String(r["effect"]):
		"knife":
			return str(int(float(units["allies"]["hero"]["dmg"]) + lv * per))
		"speed":
			return BottleShot._fmt(float(units["allies"]["hero"]["rate"]) + 0.5 * lv * per)
		"squad":
			return str(1 + int(lv * per))
		"capacity":
			return str(int(units["world"].get("max_squad", 0)) + int(lv * per))
		"coins":
			return "+%d%%" % int(round(lv * per * 100))
		"charges":
			return ["0", "+1", "+2"][clampi(lv, 0, 2)]
	return str(lv)


func _buy(room: String) -> void:
	if Game.buy_room(room):
		Sfx.play("upgrade")
		UiKit.pop(_rows[room]["card"], 0.85)
		refresh()
	else:
		Sfx.play("error")


func refresh() -> void:
	UiKit.pill_set(_coins, str(int(Game.save["coins"])))
	for room in _rows:
		var c: Dictionary = _rows[room]
		var lv := Game.room_level(room)
		var cost := Game.room_cost(room)
		var maxed := cost < 0
		(c["now"] as Label).text = value_text(room, lv)
		(c["next"] as Label).text = "" if maxed else value_text(room, lv + 1)
		(c["arrow"] as Control).visible = not maxed
		var pips: HBoxContainer = c["pips"]
		for i in pips.get_child_count():
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiKit.YELLOW if i < lv else Color(0, 0, 0, 0.35)
			sb.set_corner_radius_all(8)
			sb.set_border_width_all(3)
			sb.border_color = UiKit.INK
			(pips.get_child(i) as Panel).add_theme_stylebox_override("panel", sb)
		var buy: Button = c["buy"]
		var coin: Control = c["coin"]
		if maxed:
			buy.text = ""
			buy.disabled = true
			coin.visible = true
			(coin as TextureRect).texture = UiKit.icon_texture("star_icon")
			coin.position = Vector2(70, 20)
		else:
			buy.text = "    %d" % cost
			buy.disabled = int(Game.save["coins"]) < cost
			(coin as TextureRect).texture = UiKit.icon_texture("coin")
			coin.position = Vector2(14, 20)


## True when the player can afford at least one upgrade (drives the "!" badges).
static func anything_affordable() -> bool:
	for room in Game.economy["station_order"]:
		var cost := Game.room_cost(String(room))
		if cost > 0 and int(Game.save["coins"]) >= cost:
			return true
	return false

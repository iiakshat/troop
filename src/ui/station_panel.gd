class_name StationPanel
extends Control
## Police station upgrades. One row per room: its glossy icon, what you have now ▸ what the
## next level gives (real numbers from the game: starting squad, squad cap, coin bonus), level
## pips (up to 10), and a coin price. v2: the knife and speed rooms moved to the Armory (a
## weapon card at the bottom opens it) and the garage's charges became the shield / bomb
## powers (5 h recharge).
## A level that needs a district liberated first shows district_lock + that district's number
## on the button instead of the price; one that needs a level reached first (v2.1: training
## from L4/6/8) shows the lock, the level pin and that level. Frees itself on close and emits
## `closed`.
## v1.1 (why upgrade): a Squad Power pill next to the coins, the in-game thing each room
## changes as a small icon before its numbers, the Squad Power the next level adds (+N), a
## one-second looping mini-preview on the room icon (a knife flying, a coin rising...), and a
## celebration on purchase (sparks, flash, power counting up, "+N" floating away).

signal closed

var _rows: Dictionary = {}
var _coins: HBoxContainer
var _power: HBoxContainer
var focus_room := ""          ## set before adding: that row flashes (the loss tip's room)

## The in-game thing each effect changes (shown before its numbers and in the mini-preview).
const EFFECT_ICONS := {
	"knife": ["knife_power", "knife"], "speed": ["fire_rate", "speed"], "squad": ["rank_constable", "badge"],
	"capacity": ["person", "badge"], "coins": ["coin"], "charges": ["shield", "police_car"],
}


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
	close.pressed.connect(_close)
	head.add_child(close)
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 18)
	col.add_child(pills)
	_power = UiKit.pill("power", Economy.fmt_power(Game.squad_power()), Color.WHITE)
	pills.add_child(_power)
	_coins = UiKit.pill("coin", str(int(Game.save["coins"])))
	pills.add_child(_coins)
	for room in Game.economy["station_order"]:
		col.add_child(_row(String(room)))
	col.add_child(_armory_link())
	refresh()
	UiKit.pop(p, 0.7)
	if _rows.has(focus_room):
		var card: Control = _rows[focus_room]["card"]
		var tw := card.create_tween().set_loops(4)
		tw.tween_property(card, "modulate", Color(1.5, 1.5, 0.8), 0.25)
		tw.tween_property(card, "modulate", Color.WHITE, 0.25)


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
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(104, 104)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var room_icon := UiKit.icon(String(r["icon"]), 104)
	room_icon.size = Vector2(104, 104)
	ic.add_child(room_icon)
	ic.add_child(preview(String(r["effect"]), 58, Vector2(52, 52)))
	row.add_child(ic)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	row.add_child(mid)
	var values := HBoxContainer.new()
	values.alignment = BoxContainer.ALIGNMENT_CENTER
	values.add_theme_constant_override("separation", 10)
	mid.add_child(values)
	values.add_child(RetentionPanel.icon_safe(effect_icon(String(r["effect"])), 44))
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
	var n := maxi(int(r["max"]), 1)
	var gap := 6 if n > 6 else 8
	pips.add_theme_constant_override("separation", gap)
	var pip_w := clampf(floorf((250.0 - (n - 1) * gap) / n), 14.0, 34.0)
	for i in n:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(pip_w, 16)
		pips.add_child(pip)

	var gain_row := HBoxContainer.new()
	gain_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gain_row.add_theme_constant_override("separation", 4)
	gain_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gain_row.add_child(RetentionPanel.icon_safe("power", 34))
	var gain := UiKit.label("", 30, UiKit.YELLOW, 8)
	gain_row.add_child(gain)
	mid.add_child(gain_row)

	var buy := UiKit.button("", "green", 40, Vector2(190, 100))
	buy.pressed.connect(func(): _buy(room))
	row.add_child(buy)
	_rows[room] = {"now": now, "next": next, "arrow": arrow, "pips": pips, "buy": buy, "card": card, "gain": gain, "gain_row": gain_row}
	return card


func _close() -> void:
	closed.emit()
	queue_free()


## v2: weapons are upgraded in the Armory; this card (weapon art + arrow) opens it in place.
func _armory_link() -> Control:
	var b := UiKit.button("", "yellow", 10, Vector2(0, 120))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(row)
	row.offset_bottom = -8
	b.add_child(row)
	for id in ["knives", "service_pistol", "shotgun"]:
		row.add_child(ArmoryPanel.art_icon(id, 92))
	row.add_child(RetentionPanel.icon_safe("play", 48, Color.WHITE))
	if ArmoryPanel.anything_affordable():
		UiKit.set_alert(b, true)
	b.pressed.connect(_open_armory)
	return b


func _open_armory() -> void:
	var parent := get_parent()
	if parent == null:
		return
	if parent.has_method("open_panel"):
		parent.call("open_panel", ArmoryPanel.new())   # the lobby swaps its overlay
	else:
		parent.add_child(ArmoryPanel.new())
		_close()


## The number a room shows at a given level, using the game's real base stats.
static func value_text(room: String, lv: int) -> String:
	if not Game.economy["station"].has(room):
		return ArmoryPanel.index_text(room, lv)   # a weapon track (improvement toasts)
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
			return "+%d%%" % int(lv * per)  # barracks: percent of the district's squad cap
		"coins":
			return "+%d%%" % int(round(lv * per * 100))
		"charges":
			return "+%d" % lv if lv > 0 else "0"
	return str(lv)


static func effect_icon(effect: String) -> String:
	return RetentionPanel.first_icon(EFFECT_ICONS.get(effect, ["star_icon"]))


## One-second looping mini-preview of what a room changes: the effect's icon doing it (a knife
## flying out, two knives in quick succession, a constable popping in, the squad growing, a
## coin rising, a shield pulsing). `at` = top-left inside its parent.
static func preview(effect: String, px := 58, at := Vector2.ZERO) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = at
	holder.size = Vector2(px, px)
	var ic := RetentionPanel.icon_safe(effect_icon(effect), px)
	ic.size = Vector2(px, px)
	ic.pivot_offset = Vector2(px, px) * 0.5
	holder.add_child(ic)
	var tw := ic.create_tween().set_loops()
	match effect:
		"knife", "speed":
			var throws := 2 if effect == "speed" else 1
			for i in throws:
				tw.tween_callback(func():
					ic.position = Vector2(-px * 0.3, 0)
					ic.modulate.a = 1.0)
				tw.tween_property(ic, "position:x", px * 0.5, 0.5 / throws).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.parallel().tween_property(ic, "modulate:a", 0.0, 0.25 / throws).set_delay(0.25 / throws)
			tw.tween_interval(0.5)
		"squad", "capacity":
			tw.tween_callback(func(): ic.scale = Vector2.ONE * 0.6)
			tw.tween_property(ic, "scale", Vector2.ONE * 1.15, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(ic, "scale", Vector2.ONE, 0.15)
			tw.tween_interval(0.6)
		"coins":
			tw.tween_callback(func():
				ic.position = Vector2(0, px * 0.2)
				ic.modulate.a = 1.0)
			tw.tween_property(ic, "position:y", -px * 0.4, 0.7).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(ic, "modulate:a", 0.0, 0.4).set_delay(0.3)
			tw.tween_interval(0.3)
		_:
			tw.tween_property(ic, "scale", Vector2.ONE * 1.2, 0.3).set_trans(Tween.TRANS_SINE)
			tw.tween_property(ic, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SINE)
			tw.tween_interval(0.4)
	return holder


func _buy(room: String) -> void:
	var before := Game.squad_power()
	if Game.buy_room(room):
		Sfx.play("upgrade")
		RetentionPanel.sfx(["rank_up", "coin"], -4.0, 1.2)
		Game.vibrate(40)
		refresh()
		_celebrate(room, before, Game.squad_power())
	else:
		Sfx.play("error")


## Purchase celebration: the card flashes and pops, sparks burst from the button, the power
## pill counts up and a "+N" with the power emblem floats up from the card.
func _celebrate(room: String, from: float, to: float) -> void:
	var c: Dictionary = _rows[room]
	var card: Control = c["card"]
	UiKit.pop(card, 0.85)
	card.modulate = Color(1.8, 1.8, 1.4)
	card.create_tween().tween_property(card, "modulate", Color.WHITE, 0.4)
	UiKit.pill_count(_power, from, to, 0.6, Economy.fmt_power)
	UiKit.bump(_power, 1.3)
	var btn: Control = c["buy"]
	var centre := btn.get_global_rect().get_center()
	for i in 12:
		var sp := RetentionPanel.icon_safe("star_icon", 34)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.size = Vector2(34, 34)
		sp.z_index = 30
		add_child(sp)
		sp.global_position = centre - Vector2(17, 17)
		var dir := Vector2.from_angle(TAU * i / 12.0 + randf() * 0.3)
		var tw := sp.create_tween().set_parallel()
		tw.tween_property(sp, "global_position", sp.global_position + dir * randf_range(90.0, 150.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "modulate:a", 0.0, 0.35).set_delay(0.15)
		tw.chain().tween_callback(sp.queue_free)
	if to >= from + 0.05:
		var float_row := HBoxContainer.new()
		float_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		float_row.z_index = 31
		float_row.add_child(RetentionPanel.icon_safe("power", 56))
		float_row.add_child(UiKit.label("+" + Economy.fmt_power(to - from), 54, UiKit.YELLOW, 12))
		add_child(float_row)
		var r := card.get_global_rect()
		float_row.global_position = r.position + Vector2(r.size.x * 0.4, 0)
		var tw2 := float_row.create_tween().set_parallel()
		tw2.tween_property(float_row, "global_position:y", r.position.y - 110.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(float_row, "modulate:a", 0.0, 0.4).set_delay(0.5)
		tw2.chain().tween_callback(float_row.queue_free)


func refresh() -> void:
	UiKit.pill_set(_coins, str(int(Game.save["coins"])))
	for room in _rows:
		var c: Dictionary = _rows[room]
		var state: Dictionary = Game.room_state(room)
		var lv := int(state["lv"])
		var cost := int(state["cost"])
		var maxed := bool(state["maxed"])
		var locked := int(state["locked"])
		(c["now"] as Label).text = value_text(room, lv)
		(c["next"] as Label).text = "" if maxed else value_text(room, lv + 1)
		(c["arrow"] as Control).visible = not maxed
		# Lightning gain = level-start firepower (spec v2 section 12.4): only training adds it.
		var g: float = 0.0 if maxed else Game.room_power_gain(room)
		(c["gain"] as Label).text = "+" + Economy.fmt_power(g)
		(c["gain_row"] as Control).modulate.a = 1.0 if g >= 0.05 else 0.0
		var pips: HBoxContainer = c["pips"]
		for i in pips.get_child_count():
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiKit.YELLOW if i < lv else Color(0, 0, 0, 0.35)
			sb.set_corner_radius_all(8)
			sb.set_border_width_all(3)
			sb.border_color = UiKit.INK
			(pips.get_child(i) as Panel).add_theme_stylebox_override("panel", sb)
		var buy: Button = c["buy"]
		if maxed:
			buy.disabled = true
			UiKit.button_row(buy, ["star_icon"], "", 40)
		elif locked > 0:
			buy.disabled = true
			# Boss crown + the boss level to beat (10/20/30...), as on the map's boss nodes.
			UiKit.button_row(buy, ["boss_crown"], str(locked * Economy.district_levels(Game.economy)), 40)
		elif int(state.get("level_lock", 0)) > 0:
			buy.disabled = true
			# Spec v2.1 section 3.3: training opens by level; the lock and the level pin + number,
			# as on a locked Armory card.
			UiKit.button_row(buy, ["lock", "map_pin"], str(int(state["level_lock"])), 40)
		else:
			buy.disabled = int(Game.save["coins"]) < cost
			UiKit.button_row(buy, ["coin"], UiKit.fmt_coins(cost), 40)


## A room's buy button as shown: {icons, text, disabled} (tests).
func buy_face(room: String) -> Dictionary:
	var b: Button = _rows[room]["buy"]
	var row: HBoxContainer = b.get_meta("row") if b.has_meta("row") else null
	if row == null:
		return {"icons": [], "text": b.text, "disabled": b.disabled}
	return {"icons": row.get_meta("names", []), "text": (row.get_meta("label") as Label).text, "disabled": b.disabled}


## True when the player can afford at least one upgrade (drives the "!" badges).
static func anything_affordable() -> bool:
	for room in Game.economy["station_order"]:
		if bool(Game.room_state(String(room))["can_buy"]):
			return true
	return false

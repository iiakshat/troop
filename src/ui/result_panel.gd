class_name ResultPanel
extends Control
## Level result.
## Win: trophy ribbon with the level, 1-3 stars popping in one after another (star1/2/3
## sounds), the bottles you broke and the finale multiplier, the coins counting up, a "x2"
## rewarded-ad button (ad icon; watching it pays the same coins again via Game.add_coins and
## the count goes on to double), the star-chest bar (tap the chest when it is full), then
## Home / Station (with its "!" alert) / Next.
## Loss ("so close"): the level, a road bar of how far you got with the percent, what beat
## you (icon + 1-3 word tip), the peak squad, and Home / Station / Retry. The revive offer
## is RevivePanel, shown by main.gd before this screen.
##   show_win(level, r, has_next)   r = {coins (paid, e.g. Game.win_level's coins), stars,
##                                       broken, gold, mult (finale multiplier)}
##   show_loss(level, cause, progress := -1.0 (0..1, hidden when < 0), peak := 0)

signal next_pressed
signal retry_pressed
signal lobby_pressed
signal station_pressed
signal doubled(extra_coins: int)   # the x2 ad was watched and the coins were paid again

const LOSS := {
	"thug": ["thug", "GROW BIGGER"], "knifer": ["knife", "GROW EARLIER"],
	"brute": ["brute", "BRING INSPECTORS"], "gunman": ["shield", "SHIELD UP"],
	"riot": ["riot", "BOMB OR PIERCE"], "biker": ["speed", "KILL THEM FAST"],
	"boss": ["boss", "BUILD UP FIRST"], "gate": ["aim", "SHOOT RED GATES"],
	"barricade": ["barricade", "SHOOT IT FIRST"], "car": ["police_car", "SHOOT IT FIRST"],
	"barrel": ["barrel", "SHOOT IT FIRST"], "pothole": ["pothole", "STEER AROUND"],
	"molotov": ["molotov", "SHIELD UP"], "sniper_foe": ["sniper_foe", "SHIELD UP"],
	"grenadier": ["grenadier", "SHIELD UP"],
}
const STAR_DELAY := 0.38

var _coin_label: Label
var _coins_shown := 0
var _coins := 0
var _x2: Button
var _ad_busy := false
var _doubled := false
var _station: Button


func _ready() -> void:
	UiKit.full_rect(self)
	visible = false


func show_win(level: int, r: Dictionary, has_next: bool) -> void:
	_clear()
	_doubled = false
	_ad_busy = false
	var col := _card(0)
	col.add_child(UiKit.ribbon(RetentionPanel.first_icon(["trophy_gold", "trophy"]), str(level)))
	# Stars: empty slots first, then they pop in one after another.
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", 6)
	stars_row.custom_minimum_size = Vector2(0, 150)
	col.add_child(stars_row)
	var won := clampi(int(r.get("stars", 1)), 0, 3)
	var star_nodes := []
	for i in 3:
		var holder := Control.new()
		var sz := 150.0 if i == 1 else 120.0
		holder.custom_minimum_size = Vector2(sz, sz)
		holder.size_flags_vertical = Control.SIZE_SHRINK_END if i != 1 else Control.SIZE_SHRINK_BEGIN
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stars_row.add_child(holder)
		var empty := RetentionPanel.icon_safe("star_icon", int(sz), Color(0.1, 0.12, 0.25, 0.7))
		UiKit.full_rect(empty)
		empty.modulate = Color(0.08, 0.1, 0.25, 0.75)
		holder.add_child(empty)
		var full := RetentionPanel.icon_safe("star_icon", int(sz))
		UiKit.full_rect(full)
		full.visible = false
		holder.add_child(full)
		star_nodes.append(full)
	# Bottles broken and the finale multiplier.
	var bottles := HBoxContainer.new()
	bottles.alignment = BoxContainer.ALIGNMENT_CENTER
	bottles.add_theme_constant_override("separation", 4)
	col.add_child(bottles)
	var total := int(r.get("broken", 0)) + int(r.get("gold", 0))
	for i in total:
		var gold := i >= int(r.get("broken", 0))
		bottles.add_child(UiKit.icon("broken_bottle", 56, UiKit.YELLOW if gold else Color("7dffb0")))
	if r.has("mult"):
		bottles.add_child(UiKit.label("×%s" % _fmt(float(r["mult"])), 56, UiKit.YELLOW, 14))
	# Coins counting up, and the x2 ad.
	var coins_row := HBoxContainer.new()
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coins_row.add_theme_constant_override("separation", 10)
	col.add_child(coins_row)
	coins_row.add_child(UiKit.icon("coin", 90, UiKit.YELLOW))
	_coin_label = UiKit.label("0", 96, Color.WHITE, 18)
	coins_row.add_child(_coin_label)
	_coins = int(r.get("coins", 0))
	_coins_shown = 0
	_x2 = _ad_button("x2_coins", "×2")
	_x2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_x2.pressed.connect(_on_x2)
	_x2.visible = _coins > 0
	_x2.disabled = true
	col.add_child(_x2)
	# Star chest progress (goal gradient).
	col.add_child(_chest_row())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	var home := UiKit.icon_button("home", "blue", 130)
	home.pressed.connect(func(): lobby_pressed.emit())
	row.add_child(home)
	var station := UiKit.icon_button("station", "blue", 130)
	station.pressed.connect(func(): station_pressed.emit())
	row.add_child(station)
	_station = station
	UiKit.set_alert(station, _station_alert())
	if has_next:
		var nxt := UiKit.icon_button("play", "green", 130)
		nxt.custom_minimum_size.x = 220
		nxt.pressed.connect(func(): next_pressed.emit())
		row.add_child(nxt)
	_show()
	# Sequence: stars pop, then the coins count up, then the x2 button wakes up.
	var tw := create_tween()
	tw.tween_interval(0.35)
	for i in won:
		tw.tween_callback(_pop_star.bind(star_nodes[i], i))
		tw.tween_interval(STAR_DELAY)
	tw.tween_method(_set_coins, 0.0, float(_coins), 0.9)
	tw.tween_callback(func():
		if is_instance_valid(_x2) and _x2.visible:
			_x2.disabled = false
			RetentionPanel.pulse(_x2, 0.05))


func _pop_star(star: Control, i: int) -> void:
	if not is_instance_valid(star):
		return
	star.visible = true
	UiKit.pop(star, 2.2)
	RetentionPanel.sfx(["star%d" % (i + 1), "gate_good", "coin"], 0.0, 1.0)
	_burst(star.get_global_rect().get_center(), 10)


func _set_coins(v: float) -> void:
	var n := int(round(v))
	if n != _coins_shown:
		_coins_shown = n
		_coin_label.text = str(n)
		Sfx.play("coin", -10.0)


func _on_x2() -> void:
	if _ad_busy or _doubled:
		return
	_ad_busy = true
	var ads: Node = get_node_or_null("/root/Ads")
	var done := func(ok: bool):
		_ad_busy = false
		if not ok or _doubled or not is_instance_valid(_x2):
			return
		_doubled = true
		Game.add_coins(_coins)
		doubled.emit(_coins)
		_x2.visible = false
		RetentionPanel.sfx(["coin_bag", "win"])
		UiKit.pop(_coin_label, 1.5)
		_burst(_coin_label.get_global_rect().get_center(), 14)
		var tw := create_tween()
		tw.tween_method(_set_coins, float(_coins), float(_coins * 2), 0.9)
	if ads == null:
		done.call(true)
	else:
		ads.show_rewarded("x2_coins", done)


func show_loss(level: int, cause: String, progress := -1.0, peak := 0) -> void:
	_clear()
	var col := _card(0)
	var info: Array = LOSS.get(cause, ["person", "TRY AGAIN"])
	col.add_child(UiKit.ribbon("", str(level)))
	if progress >= 0.0:
		col.add_child(_road(clampf(progress, 0.0, 1.0)))
	var cause_row := HBoxContainer.new()
	cause_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cause_row.add_theme_constant_override("separation", 16)
	col.add_child(cause_row)
	var ic := RetentionPanel.icon_safe(String(info[0]), 150, UiKit.RED)
	cause_row.add_child(ic)
	if peak > 0:
		var pk := HBoxContainer.new()
		pk.add_theme_constant_override("separation", 6)
		pk.add_child(RetentionPanel.icon_safe(RetentionPanel.first_icon(["crown", "trophy"]), 60))
		pk.add_child(RetentionPanel.icon_safe(RetentionPanel.first_icon(["badge", "person"]), 60))
		pk.add_child(UiKit.label(str(peak), 60, Color.WHITE, 12))
		cause_row.add_child(pk)
	col.add_child(UiKit.label(String(info[1]), 52, Color.WHITE, 14))
	# v1.1: the single upgrade that would have helped most (Game.best_upgrade_after_loss), as
	# room icon + its in-game number before > after; a hand bobs on the Station when affordable.
	var tip: Dictionary = Game.best_upgrade_after_loss()
	if not tip.is_empty():
		col.add_child(_upgrade_tip(tip))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	var home := UiKit.icon_button("home", "blue", 140)
	home.pressed.connect(func(): lobby_pressed.emit())
	row.add_child(home)
	var station := UiKit.icon_button("station", "blue", 140)
	station.pressed.connect(func(): station_pressed.emit())
	row.add_child(station)
	_station = station
	UiKit.set_alert(station, _station_alert())
	if bool(tip.get("affordable", false)):
		_hand_on(station)
	var retry := UiKit.icon_button("retry", "green", 140)
	retry.custom_minimum_size.x = 220
	retry.pressed.connect(func(): retry_pressed.emit())
	row.add_child(retry)
	_show()
	RetentionPanel.pulse(retry, 0.04)


## Loss tip card (green): the room's icon, its in-game number now > next, and its price
## (coin + number; dimmed when the player cannot afford it yet).
func _upgrade_tip(tip: Dictionary) -> Control:
	var room := String(tip["room"])
	var r: Dictionary = Game.economy["station"].get(room, {})
	var lv := Game.room_level(room)
	var card := RetentionPanel.card_box(Color("2e8b3e"), 10, 22, 5)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	h.add_child(RetentionPanel.icon_safe(String(r.get("icon", "station")), 84))
	h.add_child(UiKit.label(StationPanel.value_text(room, lv), 50, Color.WHITE, 10))
	h.add_child(RetentionPanel.icon_safe("play", 34, UiKit.YELLOW))
	h.add_child(UiKit.label(StationPanel.value_text(room, lv + 1), 50, UiKit.YELLOW, 10))
	var price := HBoxContainer.new()
	price.add_theme_constant_override("separation", 4)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_child(RetentionPanel.icon_safe("coin", 40))
	price.add_child(UiKit.label(UiKit.fmt_coins(int(tip["cost"])), 36, Color.WHITE, 8))
	price.modulate.a = 1.0 if bool(tip.get("affordable", false)) else 0.55
	h.add_child(price)
	return card


## A hand bobbing on a button (fingertip on its upper half), freed with it.
func _hand_on(b: Control) -> void:
	var hand := RetentionPanel.icon_safe("hand", 96)
	hand.size = Vector2(96, 96)
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.z_index = 5
	b.add_child(hand)
	hand.position = Vector2(-4, -44)
	var tw := hand.create_tween().set_loops()
	tw.tween_property(hand, "position", Vector2(-20, -60), 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(hand, "position", Vector2(-4, -44), 0.35).set_trans(Tween.TRANS_SINE)


## Road bar: how far the squad got, flag at the finish, percent above the marker.
func _road(progress: float) -> Control:
	var road := Control.new()
	road.custom_minimum_size = Vector2(0, 160)
	road.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := RetentionPanel.progress_bar(52, UiKit.YELLOW)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 10
	bar.offset_right = -96
	bar.offset_top = 92
	bar.offset_bottom = 144
	RetentionPanel.bar_set(bar, 0, 100, " ")
	road.add_child(bar)
	var flag := RetentionPanel.icon_safe(RetentionPanel.first_icon(["trophy_gold", "trophy"]), 88)
	flag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	flag.offset_left = -96
	flag.offset_right = -8
	flag.offset_top = 70
	flag.offset_bottom = 158
	road.add_child(flag)
	var pct := UiKit.label("0%", 60, UiKit.YELLOW, 14)
	pct.size = Vector2(170, 80)
	road.add_child(pct)
	var animate := func():
		var tw := create_tween()
		tw.tween_method(func(v: float):
			bar.value = v * 100.0
			pct.text = "%d%%" % int(floor(v * 100.0))
			pct.position = Vector2(clampf(bar.position.x + bar.size.x * v - 85.0, 0.0, road.size.x - 170.0), 4), 0.0, progress, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.3)
	animate.call_deferred()
	return road


## Star chest bar: stars towards the next chest; full = the chest bounces and opens on tap.
func _chest_row() -> Control:
	var prog := Game.star_chest_progress()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var bar := RetentionPanel.progress_bar(44, UiKit.YELLOW, 360)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var from := int(prog.get("from", 0))
	var need := int(prog.get("need", 15))
	var have := int(prog.get("have", 0))
	RetentionPanel.bar_set(bar, have - from, need - from, "%d/%d" % [mini(have, need), need])
	row.add_child(RetentionPanel.icon_safe("star_icon", 52))
	row.add_child(bar)
	var chest := UiKit.icon_button(RetentionPanel.first_icon(["star_chest", "chest"]), "yellow", 96)
	chest.disabled = not bool(prog.get("ready", false))
	chest.pressed.connect(func():
		var p := StarChestPanel.new()
		p.closed.connect(func():
			if is_instance_valid(row):
				var again := Game.star_chest_progress()
				chest.disabled = not bool(again.get("ready", false))
				RetentionPanel.bar_set(bar, int(again["have"]) - int(again["from"]), int(again["need"]) - int(again["from"]), "%d/%d" % [mini(int(again["have"]), int(again["need"])), int(again["need"])]))
		if get_parent():
			get_parent().add_child(p)
		else:
			add_child(p))
	row.add_child(chest)
	if not chest.disabled:
		RetentionPanel.pulse(chest, 0.08)
	return row


func _ad_button(placement: String, text: String) -> Button:
	var b := UiKit.button("", "green", 10, Vector2(300, 110))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -8
	b.add_child(row)
	row.add_child(RetentionPanel.icon_safe(RetentionPanel.first_icon(["ad_play", "play"]), 64))
	row.add_child(UiKit.icon("coin", 56, UiKit.YELLOW))
	row.add_child(UiKit.label(text, 52, Color.WHITE, 10))
	var ads: Node = get_node_or_null("/root/Ads") if is_inside_tree() else null
	if ads:
		ads.note_offer(placement)
	return b


## Re-checks the Station "!" (e.g. after the Station panel opened from here closes).
func refresh_alerts() -> void:
	if is_instance_valid(_station):
		UiKit.set_alert(_station, _station_alert())


func _station_alert() -> bool:
	return bool(Game.alerts().get("station", false))


func _burst(at: Vector2, n: int) -> void:
	var layer := Control.new()
	layer.top_level = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 49
	add_child(layer)
	for i in n:
		var ic := RetentionPanel.icon_safe("star_icon", 36)
		ic.size = Vector2(36, 36)
		ic.position = at - ic.size * 0.5
		layer.add_child(ic)
		var a := TAU * float(i) / float(n) + randf_range(-0.2, 0.2)
		var d := randf_range(110, 200)
		var tw := ic.create_tween().set_parallel()
		tw.tween_property(ic, "position", at + Vector2(cos(a), sin(a)) * d - ic.size * 0.5, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(ic, "modulate:a", 0.0, 0.5).set_delay(0.15)
	var t := create_tween()
	t.tween_interval(0.75)
	t.tween_callback(layer.queue_free)


static func _fmt(x: float) -> String:
	return str(int(x)) if absf(x - round(x)) < 0.01 else "%.1f" % x


func _card(height := 800.0) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	UiKit.full_rect(dim)
	add_child(dim)
	var p := UiKit.panel(Color("3b6fd1"))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(660, height)
	add_child(p)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	p.add_child(col)
	return col


func _show() -> void:
	visible = true
	var tw := create_tween()
	tw.tween_interval(0.001)
	tw.tween_callback(func():
		for c in get_children():
			if c is PanelContainer and not c.is_queued_for_deletion():
				UiKit.pop(c, 0.5))


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	visible = false

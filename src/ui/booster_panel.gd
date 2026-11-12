class_name BoosterPanel
extends RetentionPanel
## Before a level: the level number (crown on boss levels) and three cards.
## Head start: the tokens you own; tap to take one into the level (tick + glow), or watch one
## rewarded ad per level for a free token (picked at once). The big Play button spends the
## picked tokens (Game.use_boosters) and emits start(used) with what was really spent, e.g.
## {"headstart": 1}; the caller passes it to Game.level_upgrades(used) /
## Game.level_started(level, used). The X just closes (no start).
## Shield and bomb (v2 powers, spec section 7): not picked; every charge you have (free +
## stored) comes along by itself (tick when there is one) and only the ones used are spent.
## While the free charge recharges the card shows a clock and the time left (h:mm), and the
## ad button under it refills the free charge now (rewarded ad).

signal start(boosters: Dictionary)

var level := 1
var _picked := {}
var _cards := {}


func _init(lv := 1) -> void:
	level = lv


func _ready() -> void:
	var boss := Economy.is_boss(level, Game.economy)
	var col := _frame("boss_crown" if boss and has_icon("boss_crown") else "", 0, str(level), false)
	var order: Array = Game.economy.get("boosters", {}).get("order", ["headstart", "shield", "bomb"])
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	for id in order:
		var card := _booster_card(String(id))
		_cards[String(id)] = card
		row.add_child(card)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	col.add_child(spacer)
	var play := UiKit.icon_button("play", "green", 170)
	play.custom_minimum_size.x = 420
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(_on_play)
	col.add_child(play)
	_refresh()
	pulse(play, 0.04)


func _booster_card(id: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var tile := UiKit.button("", "blue", 10, Vector2(188, 250))
	tile.pressed.connect(_toggle.bind(id))
	v.add_child(tile)
	var cfg: Dictionary = Game.economy.get("boosters", {}).get(id, {})
	var ic := icon_safe(String(cfg.get("icon", id)), 120)
	ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	ic.offset_left = -60
	ic.offset_right = 60
	ic.offset_top = 18
	ic.offset_bottom = 138
	tile.add_child(ic)
	# What it does, as a number: +5 troops, +1 charge.
	var what := UiKit.label(_effect_text(id, cfg), 40, UiKit.YELLOW, 9)
	what.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	what.offset_left = -90
	what.offset_right = 90
	what.offset_top = 138
	what.offset_bottom = 184
	tile.add_child(what)
	# Tokens owned.
	var count := UiKit.label("", 44, Color.WHITE, 10)
	count.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	count.offset_left = -90
	count.offset_right = 90
	count.offset_top = -70
	count.offset_bottom = -20
	tile.add_child(count)
	var mark := check_mark(64)
	mark.position = Vector2(134, -14)
	tile.add_child(mark)
	# Powers: the recharge clock and time left, over the effect number while recharging.
	var timer := HBoxContainer.new()
	timer.alignment = BoxContainer.ALIGNMENT_CENTER
	timer.add_theme_constant_override("separation", 4)
	timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer.offset_left = -90
	timer.offset_right = 90
	timer.offset_top = 136
	timer.offset_bottom = 184
	timer.add_child(icon_safe("clock", 40))
	var tl := UiKit.label("", 36, Color.WHITE, 9)
	timer.add_child(tl)
	timer.visible = false
	tile.add_child(timer)
	var ad: Button
	if is_power(id):
		ad = ad_button("booster_" + id, "", Vector2(188, 96), "clock")
		ad.pressed.connect(_on_refill.bind(id))
	else:
		ad = ad_button("booster_" + id, "+1", Vector2(188, 96))
		ad.pressed.connect(_on_ad.bind(id))
	v.add_child(ad)
	v.set_meta("tile", tile)
	v.set_meta("what", what)
	v.set_meta("count", count)
	v.set_meta("mark", mark)
	v.set_meta("ad", ad)
	v.set_meta("timer", timer)
	v.set_meta("timer_label", tl)
	return v


static func is_power(id: String) -> bool:
	return SaveData.POWERS.has(id)


## A recharge countdown as h:mm (minutes rounded up), next to the clock icon.
## A recharge countdown that cannot be misread: h:mm:ss from an hour up ("4:59:59", it
## visibly ticks), m:ss below ("59:59"). Used by the HUD and this panel.
static func time_text(seconds: int) -> String:
	if seconds <= 0:
		return ""
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func _effect_text(id: String, cfg: Dictionary) -> String:
	if id == "headstart":
		return "+%d" % int(cfg.get("troops", 5))
	return "+%d" % int(cfg.get("charges", 1))


func _refresh() -> void:
	var owned := Game.boosters()
	for id in _cards:
		var v: VBoxContainer = _cards[id]
		var have := int(owned.get(id, 0))
		if is_power(id):
			_refresh_power(id, v, have)
			continue
		var picked := bool(_picked.get(id, false))
		var tile: Button = v.get_meta("tile")
		(v.get_meta("count") as Label).text = "×%d" % have
		(v.get_meta("mark") as Control).visible = picked
		var colr := "green" if picked else ("blue" if have > 0 else "grey")
		for st in ["normal", "hover"]:
			tile.add_theme_stylebox_override(st, UiKit._tex_box(colr, "rectangle"))
		tile.add_theme_stylebox_override("pressed", UiKit._tex_box(colr, "rectangle", true))
		tile.modulate.a = 1.0 if have > 0 or picked else 0.7
		var ad: Button = v.get_meta("ad")
		ad.visible = Game.booster_ad_available(id)


func _refresh_power(id: String, v: VBoxContainer, have: int) -> void:
	var st: Dictionary = Game.power_state(id)
	var secs := int(st["seconds_left"])
	var tile: Button = v.get_meta("tile")
	(v.get_meta("count") as Label).text = "×%d" % have
	(v.get_meta("mark") as Control).visible = have > 0
	(v.get_meta("timer") as Control).visible = secs > 0
	(v.get_meta("what") as Control).visible = secs <= 0
	(v.get_meta("timer_label") as Label).text = time_text(secs)
	var colr := "green" if have > 0 else "grey"
	for sname in ["normal", "hover"]:
		tile.add_theme_stylebox_override(sname, UiKit._tex_box(colr, "rectangle"))
	tile.add_theme_stylebox_override("pressed", UiKit._tex_box(colr, "rectangle", true))
	tile.modulate.a = 1.0 if have > 0 else 0.7
	(v.get_meta("ad") as Button).visible = Game.can_refill_power(id)


var _tick := 0.0


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		for id in _cards:
			if is_power(id):
				_refresh_power(id, _cards[id], Game.power_available(id))


func _toggle(id: String) -> void:
	if is_power(id):
		# Powers come along by themselves: a tap just shows what is there.
		UiKit.pop((_cards[id] as Control).get_meta("tile"), 0.92)
		sfx(["tap"], -6.0)
		return
	if bool(_picked.get(id, false)):
		_picked.erase(id)
	elif int(Game.boosters().get(id, 0)) > 0:
		_picked[id] = true
		sfx(["recruit", "upgrade"], -4.0)
		UiKit.pop((_cards[id] as Control).get_meta("tile"), 0.85)
	else:
		sfx(["error"])
	_refresh()


func _on_ad(id: String) -> void:
	watch_ad("booster_" + id, func(ok: bool):
		if ok and Game.grant_booster_ad(id):
			_picked[id] = true
			var tile: Control = (_cards[id] as Control).get_meta("tile")
			sfx(["upgrade", "recruit"])
			burst(centre(tile), 10)
			UiKit.pop(tile, 0.8)
		_refresh())


## Rewarded "refill now" for a recharging shield or bomb.
func _on_refill(id: String) -> void:
	watch_ad("booster_" + id, func(ok: bool):
		if ok and Game.refill_power(id):
			var tile: Control = (_cards[id] as Control).get_meta("tile")
			sfx(["upgrade", "recruit"])
			burst(centre(tile), 10)
			UiKit.pop(tile, 0.8)
		_refresh())


# ---------------------------------------------------------------- for tests

func power_count(id: String) -> int:
	return int(Game.boosters().get(id, 0))


func power_timer_text(id: String) -> String:
	var v: Control = _cards[id]
	return (v.get_meta("timer_label") as Label).text if (v.get_meta("timer") as Control).visible else ""


func power_refill_visible(id: String) -> bool:
	return ((_cards[id] as Control).get_meta("ad") as Control).visible


## What the Play button sends: one of each picked booster the player really has.
func picked() -> Dictionary:
	var out := {}
	for id in _picked:
		if bool(_picked[id]):
			out[id] = 1
	return out


func _on_play() -> void:
	if _closing:
		return
	var used := Game.use_boosters(picked())
	if not used.is_empty():
		log_event("boosters_used", {"level": level, "boosters": used})
	start.emit(used)
	close()


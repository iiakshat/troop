class_name BoosterPanel
extends RetentionPanel
## Before a level: the level number (crown on boss levels), the 3 boosters (head start, extra
## shield, extra bomb) as cards with the tokens you own; tap a card to take one into the level
## (tick + glow), or watch one rewarded ad per booster per level for a free token (it gets
## picked at once). The big Play button spends the picked tokens (Game.use_boosters) and emits
## start(used) with what was really spent, e.g. {"headstart": 1, "bomb": 1}; the caller passes
## it to Game.level_upgrades(used) / Game.level_started(level, used). The X just closes (no
## start). Nothing is preselected and nothing is spent until Play.

signal start(boosters: Dictionary)

var level := 1
var _picked := {}
var _cards := {}


func _init(lv := 1) -> void:
	level = lv


func _ready() -> void:
	var boss := Economy.is_boss(level, Game.economy)
	var col := _frame("boss_crown" if boss and has_icon("boss_crown") else "", 900, str(level), false)
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
	var ad := ad_button("booster_" + id, "+1", Vector2(188, 96))
	ad.pressed.connect(_on_ad.bind(id))
	v.add_child(ad)
	v.set_meta("tile", tile)
	v.set_meta("count", count)
	v.set_meta("mark", mark)
	v.set_meta("ad", ad)
	return v


static func _effect_text(id: String, cfg: Dictionary) -> String:
	if id == "headstart":
		return "+%d" % int(cfg.get("troops", 5))
	return "+%d" % int(cfg.get("charges", 1))


func _refresh() -> void:
	var owned := Game.boosters()
	for id in _cards:
		var v: VBoxContainer = _cards[id]
		var have := int(owned.get(id, 0))
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


func _toggle(id: String) -> void:
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


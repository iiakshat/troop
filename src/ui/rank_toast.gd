class_name RankToast
extends RefCounted
## Corner card when a rank joins the squad for the first time (sim event rank_join with
## first_time): slides in at the top left, holds, slides out; 2.5 s in all (config-free UI
## timing). Icon + name + damage + rate + "= N" value line, the same numbers as the Codex.
## Never takes taps (the level keeps playing under it). RankToast is only the factory (a
## static show() cannot live on a CanvasItem, which has its own show()); the card is a
## PanelContainer that frees itself.
##   RankToast.show(parent, "sergeant")

const DURATION := 2.5
const WIDTH := 430.0


## Adds a toast for `unit` (an ally id from units.json) to `parent`. Returns it (or null if the
## unit is unknown).
static func show(parent: Node, unit: String) -> PanelContainer:
	if parent == null or not is_instance_valid(parent):
		return null
	var allies: Dictionary = Game.units.get("allies", {})
	if not allies.has(unit):
		return null
	var t := build(unit, allies[unit], allies)
	parent.add_child(t)
	_play(t)
	return t


## The card itself (not in the tree yet).
static func build(unit: String, u: Dictionary, allies: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 40
	card.add_theme_stylebox_override("panel", RetentionPanel.box(Color("3b6fd1"), 24, 6, UiKit.INK, 12))
	card.custom_minimum_size = Vector2(WIDTH, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(RetentionPanel.icon_safe(CodexPanel.rank_icon(unit), 110))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var title := UiKit.label(String(u.get("name", unit.capitalize())).to_upper(), 38, UiKit.YELLOW, 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(title)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stats)
	for s in [["fist", CodexPanel.number(float(u.get("dmg", 1)))], [CodexPanel.RATE_ICON, CodexPanel.number(float(u.get("rate", 1.0)))]]:
		stats.add_child(RetentionPanel.icon_safe(String(s[0]), 40))
		stats.add_child(UiKit.label(String(s[1]), 34, Color.WHITE, 8))
	for sp in CodexPanel.specials(u):
		stats.add_child(RetentionPanel.icon_safe(sp, 40))
	var v := CodexPanel.value_text(allies, unit)
	if v != "":
		var l := UiKit.label(v, 40, Color.WHITE, 9)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(l)
	return card


## v1.1: at the start of the level after a Station purchase, the same corner card shows what
## improved: per room its in-game icon and now > next number (StationPanel.value_text), and the
## Squad Power. `list` = Game.take_improvements(). Returns the card or null when empty.
static func show_upgrades(parent: Node, list: Array) -> PanelContainer:
	if parent == null or not is_instance_valid(parent) or list.is_empty():
		return null
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 40
	card.add_theme_stylebox_override("panel", RetentionPanel.box(Color("2e8b3e"), 24, 6, UiKit.INK, 12))
	card.custom_minimum_size = Vector2(WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(RetentionPanel.icon_safe("power", 56))
	head.add_child(UiKit.label(str(Game.squad_power()), 44, UiKit.YELLOW, 9))
	col.add_child(head)
	for e in list.slice(0, 3):
		var room := String(e["room"])
		var r: Dictionary = Game.economy["station"].get(room, {})
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if r.is_empty() and not Armory.track(room).is_empty():
			line.add_child(ArmoryPanel.art_icon(room, 46))   # v2: a weapon step bought
		else:
			line.add_child(RetentionPanel.icon_safe(StationPanel.effect_icon(String(r.get("effect", ""))), 46))
		line.add_child(UiKit.label(StationPanel.value_text(room, int(e["before"])), 38, Color.WHITE, 8))
		line.add_child(RetentionPanel.icon_safe("play", 28, UiKit.YELLOW))
		line.add_child(UiKit.label(StationPanel.value_text(room, int(e["after"])), 38, UiKit.YELLOW, 8))
		col.add_child(line)
	parent.add_child(card)
	_play(card, ["upgrade", "rank_up"])
	return card


static func _play(card: PanelContainer, sounds: Array = ["rank_up", "recruit"]) -> void:
	# Top-left corner, under the HUD's top bar.
	var top := 150.0 + UiKit.safe_insets(card).x
	card.position = Vector2(-WIDTH - 20, top)
	RetentionPanel.sfx(sounds)
	var tw := card.create_tween()
	tw.tween_property(card, "position:x", 16.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(DURATION - 0.6)
	tw.tween_property(card, "position:x", -WIDTH - 20, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(card.queue_free)

class_name MissionsPanel
extends RetentionPanel
## Today's 3 missions. Each row: the mission's icon, a progress bar with "have/goal", its
## reward, and a claim button that lights up when done (a check once claimed). Below: the bonus
## chest with one pip per claimed mission; it opens when all 3 are claimed. A clock shows the
## real time until tomorrow's missions. Uses Game.missions() / claim_mission() /
## mission_bonus_ready() / claim_mission_bonus().

var _rows: Array = []
var _chest_btn: Button
var _pips: Array[Control] = []
var _timer: Label
var _tick := 0.0


func _ready() -> void:
	var col := _frame(first_icon(["missions", "trophy"]), 0)
	var list := Game.missions()
	for i in list.size():
		var r := _row(i, list[i])
		_rows.append(r)
		col.add_child(r)
	# Bonus chest: pips fill as missions are claimed.
	var bonus := card_box(Color("2a58b5"), 12)
	col.add_child(bonus)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 18)
	bonus.add_child(brow)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 10)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_child(pips)
	for i in list.size():
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(54, 54)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
		_pips.append(pip)
	_chest_btn = UiKit.icon_button(first_icon(["chest", "star_chest"]), "yellow", 150)
	_chest_btn.pressed.connect(_on_bonus)
	brow.add_child(_chest_btn)
	var tbox := HBoxContainer.new()
	tbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tbox.add_theme_constant_override("separation", 10)
	col.add_child(tbox)
	tbox.add_child(icon_safe("clock", 52))
	_timer = UiKit.label("", 46, Color.WHITE, 10)
	tbox.add_child(_timer)
	Game.missions_changed.connect(_refresh)
	_refresh()


func _row(i: int, m: Dictionary) -> PanelContainer:
	var card := card_box(Color("3b6fd1"), 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var ic := icon_safe(String(m.get("icon", "star_icon")), 104)
	row.add_child(ic)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)
	var bar := progress_bar(50)
	mid.add_child(bar)
	mid.add_child(reward_row(m.get("reward", {}), 48, 36, 12))
	var right := CenterContainer.new()
	right.custom_minimum_size = Vector2(150, 120)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	var claim := UiKit.icon_button(first_icon(["gift", "coin"]), "green", 128)
	claim.custom_minimum_size.x = 144
	claim.pressed.connect(_on_claim.bind(i))
	right.add_child(claim)
	var mark := check_mark(86)
	right.add_child(mark)
	card.set_meta("bar", bar)
	card.set_meta("claim", claim)
	card.set_meta("mark", mark)
	return card


func _refresh() -> void:
	if not is_inside_tree():
		return
	var list := Game.missions()
	var claimed := 0
	for i in mini(list.size(), _rows.size()):
		var m: Dictionary = list[i]
		var card: PanelContainer = _rows[i]
		var bar: ProgressBar = card.get_meta("bar")
		bar_set(bar, int(m["progress"]), int(m["goal"]))
		var claim: Button = card.get_meta("claim")
		var done := bool(m["done"])
		var got := bool(m["claimed"])
		claimed += 1 if got else 0
		claim.visible = not got
		claim.disabled = not done
		(card.get_meta("mark") as Control).visible = got
		card.modulate = Color(1, 1, 1, 0.7) if got else Color.WHITE
		if done and not got and not claim.has_meta("pulse"):
			claim.set_meta("pulse", true)
			claim.set_meta("pulse_tw", pulse(claim, 0.06))
	for i in _pips.size():
		var on := i < claimed
		_pips[i].add_theme_stylebox_override("panel", box(UiKit.YELLOW if on else Color(0.05, 0.1, 0.25, 0.8), 27, 5))
	var bonus_ready := Game.mission_bonus_ready()
	var bonus_claimed := bool(Game.save.get("missions", {}).get("bonus_claimed", false))
	_chest_btn.disabled = not bonus_ready
	_chest_btn.modulate.a = 0.45 if bonus_claimed else 1.0
	if bonus_ready and not _chest_btn.has_meta("pulse"):
		_chest_btn.set_meta("pulse", true)
		_chest_btn.set_meta("pulse_tw", pulse(_chest_btn, 0.06))
	_update_timer()


func _stop_pulse(c: Control) -> void:
	if c.has_meta("pulse_tw"):
		(c.get_meta("pulse_tw") as Tween).kill()
		c.remove_meta("pulse_tw")
	c.remove_meta("pulse")
	c.scale = Vector2.ONE


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_timer()


func _update_timer() -> void:
	_timer.text = clock_text(seconds_to_midnight())


func _on_claim(i: int) -> void:
	var card: PanelContainer = _rows[i]
	var claim: Button = card.get_meta("claim")
	var from := centre(claim)
	var reward := Game.claim_mission(i)
	if reward.is_empty():
		return
	_stop_pulse(claim)
	sfx(["mission_done", "upgrade"])
	burst(from, 10)
	fly_reward(reward, from)
	UiKit.pop(card.get_meta("mark"), 0.3)
	_refresh()


func _on_bonus() -> void:
	var reward := Game.claim_mission_bonus()
	if reward.is_empty():
		return
	_stop_pulse(_chest_btn)
	var chest := StarChestPanel.new()
	chest.reward = reward
	add_child(chest)
	_refresh()

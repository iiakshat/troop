class_name DailyPanel
extends RetentionPanel
## 7-day login calendar. Days 1-6 in two rows, day 7 (the big chest) as a wide cell. Claimed
## days carry a check; today's cell glows and pulses; future days are plain. One big gift
## button claims today (juicy pop, coins fly into the pill); after that it turns into a real
## countdown to local midnight. A broken streak shows honestly: the streak flame reads 0 and
## the calendar is back at day 1. Uses Game.daily_state() / Game.claim_daily().

const COL_CLAIMED := Color("8fd18b")
const COL_TODAY := Color("ffd23f")
const COL_FUTURE := Color("3b6fd1")

var _cells: Array[PanelContainer] = []
var _claim: Button
var _timer: Label
var _streak: Label
var _state: Dictionary
var _tick := 0.0


func _ready() -> void:
	var col := _frame(first_icon(["gift", "chest"]), 1060)
	_state = Game.daily_state()
	# Streak: flame + number of days in a row (0 when the streak broke).
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	top.add_child(icon_safe(first_icon(["fire", "star_icon"]), 54))
	_streak = UiKit.label("", 46, UiKit.YELLOW, 10)
	top.add_child(_streak)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)
	var rewards: Array = _state.get("rewards", [])
	for i in rewards.size():
		var cell := _cell(i + 1, rewards[i], i == rewards.size() - 1)
		_cells.append(cell)
		if i < rewards.size() - 1:
			grid.add_child(cell)
		else:
			cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(cell)
	var bottom := CenterContainer.new()
	bottom.custom_minimum_size = Vector2(0, 130)
	col.add_child(bottom)
	_claim = UiKit.button("", "green", 10, Vector2(340, 124))
	var gi := icon_safe(first_icon(["gift", "chest"]), 86)
	gi.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	gi.offset_left = -43
	gi.offset_right = 43
	gi.offset_top = -50
	gi.offset_bottom = 36
	_claim.add_child(gi)
	_claim.pressed.connect(_on_claim)
	bottom.add_child(_claim)
	var tbox := HBoxContainer.new()
	tbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tbox.add_theme_constant_override("separation", 10)
	bottom.add_child(tbox)
	tbox.add_child(icon_safe("clock", 60))
	_timer = UiKit.label("", 56, Color.WHITE, 12)
	tbox.add_child(_timer)
	_claim.set_meta("timer_box", tbox)
	_refresh()


func _cell(day: int, reward: Dictionary, big: bool) -> PanelContainer:
	var cell := card_box(COL_FUTURE, 8)
	cell.custom_minimum_size = Vector2(576, 150) if big else Vector2(184, 196)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(v)
	v.add_child(UiKit.label(str(day), 34, Color.WHITE, 8))
	var body := Control.new()
	body.custom_minimum_size = Vector2(0, 104 if big else 120)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	var content: Control
	var items := reward_items(reward)
	if big or items.size() <= 1:
		content = items_row(items, 92 if big else 72, 38, 10)
	else:
		content = VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", -2)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for it in items:
			content.add_child(items_row([it], 44 if items.size() < 3 else 38, 30, 4))
	UiKit.full_rect(content)
	body.add_child(content)
	var mark := check_mark(78 if big else 70)
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mark.offset_left = -40
	mark.offset_right = 40
	mark.offset_top = -40
	mark.offset_bottom = 40
	mark.visible = false
	body.add_child(mark)
	cell.set_meta("mark", mark)
	cell.set_meta("content", content)
	return cell


## Which state each day's cell is in: "claimed", "today" (claimable now), "next" (tomorrow's
## after a claim today) or "future". Pure, for tests.
static func cell_states(state: Dictionary, days: int) -> Array:
	var out := []
	var day := int(state.get("day", 1))
	var can := bool(state.get("can_claim", false))
	for n in range(1, days + 1):
		if can:
			out.append("claimed" if n < day else ("today" if n == day else "future"))
		else:
			out.append("claimed" if n <= day else ("next" if n == day % days + 1 else "future"))
	return out


func _refresh() -> void:
	_state = Game.daily_state()
	var can := bool(_state.get("can_claim", false))
	var streak := 0 if bool(_state.get("missed", false)) else int(_state.get("streak", 0))
	_streak.text = str(streak)
	var states := cell_states(_state, _cells.size())
	for i in _cells.size():
		var cell := _cells[i]
		var st: String = states[i]
		var colr := COL_FUTURE
		if st == "claimed":
			colr = COL_CLAIMED
		elif st == "today":
			colr = COL_TODAY
		cell.add_theme_stylebox_override("panel", box(colr, 22, 7 if st == "today" else 5, Color.WHITE if st == "today" else UiKit.INK, 8))
		(cell.get_meta("mark") as Control).visible = st == "claimed"
		(cell.get_meta("content") as Control).modulate.a = 0.45 if st == "claimed" else 1.0
		if st == "today" and not cell.has_meta("pulse"):
			cell.set_meta("pulse", true)
			cell.set_meta("pulse_tw", pulse(cell, 0.05))
	_claim.visible = can
	(_claim.get_meta("timer_box") as Control).visible = not can
	if can and not _claim.has_meta("pulse"):
		_claim.set_meta("pulse", true)
		_claim.set_meta("pulse_tw", pulse(_claim, 0.05))
	_update_timer()


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_timer()
		if not _claim.visible and Game.daily_state().get("can_claim", false):
			_refresh()


func _update_timer() -> void:
	_timer.text = clock_text(seconds_to_midnight())


func _on_claim() -> void:
	var states := cell_states(_state, _cells.size())
	var idx := states.find("today")
	var reward := Game.claim_daily()
	if reward.is_empty():
		_refresh()
		return
	sfx(["daily_claim", "upgrade"])
	var cell: PanelContainer = _cells[idx] if idx >= 0 else _cells[0]
	if cell.has_meta("pulse_tw"):
		(cell.get_meta("pulse_tw") as Tween).kill()
	UiKit.pop(cell, 1.35)
	burst(centre(cell))
	if _claim.has_meta("pulse_tw"):
		(_claim.get_meta("pulse_tw") as Tween).kill()
	_claim.remove_meta("pulse")
	_claim.scale = Vector2.ONE
	if String(reward.get("chest", "")) != "":
		# Day 7: the chest opens on its own screen, then the calendar shows the check.
		var chest := StarChestPanel.new()
		chest.reward = reward
		add_child(chest)
	else:
		fly_reward(reward, centre(cell))
	_refresh()

class_name StarChestPanel
extends RetentionPanel
## Chest opening: the chest shakes, bursts open and the rewards pop out one by one into a row;
## the big button (or the X) collects and closes, coins flying into the pill.
## With no `reward` set it opens the star chest itself (Game.open_star_chest()) when it is
## ready, or shows the honest progress (stars have / need) when it is not. The daily day 7,
## mission bonus and spin chests pass their already-granted reward in (`reward` = what
## Game.claim_daily()/claim_mission_bonus()/spin returned).

var reward: Dictionary = {}
var _chest: TextureRect
var _items: HFlowContainer
var _collect: Button
var _stage: Control


func _ready() -> void:
	hold_coins = true
	var col := _frame(first_icon(["star_chest", "chest"]), 0)
	if not reward.is_empty():
		set_coins_shown(int(Game.save.get("coins", 0)) - int(reward.get("coins", 0)))
	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(0, 330)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_stage)
	var opened := not reward.is_empty()
	if not opened:
		var prog := Game.star_chest_progress()
		if bool(prog.get("ready", false)):
			reward = Game.open_star_chest()
			opened = not reward.is_empty()
	var chest_name := "star_chest"
	if opened:
		chest_name = String(Game.economy.get("chests", {}).get(String(reward.get("chest", "star")), {}).get("icon", "star_chest"))
	_chest = icon_safe(first_icon([chest_name, "chest"]), 260)
	_chest.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_chest.offset_left = -130
	_chest.offset_right = 130
	_chest.offset_top = -140
	_chest.offset_bottom = 120
	_stage.add_child(_chest)
	_items = HFlowContainer.new()
	_items.alignment = FlowContainer.ALIGNMENT_CENTER
	_items.add_theme_constant_override("h_separation", 10)
	_items.add_theme_constant_override("v_separation", 10)
	_items.custom_minimum_size = Vector2(0, 150)
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_items)
	var bottom := CenterContainer.new()
	bottom.custom_minimum_size = Vector2(0, 130)
	col.add_child(bottom)
	if opened:
		_collect = UiKit.icon_button("coin", "green", 124)
		_collect.custom_minimum_size.x = 300
		_collect.pressed.connect(_on_collect)
		_collect.modulate.a = 0.0
		_collect.disabled = true
		bottom.add_child(_collect)
		_open_sequence()
	else:
		_show_progress(bottom)


## Stars progress towards the next chest (goal gradient), no fake promises.
func _show_progress(_where: Control) -> void:
	var prog := Game.star_chest_progress()
	_chest.modulate = Color(1, 1, 1, 0.55)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(560, 0)
	_items.add_child(row)
	row.add_child(icon_safe("star_icon", 70))
	var bar := progress_bar(56, UiKit.YELLOW, 440)
	var from := int(prog.get("from", 0))
	var need := int(prog.get("need", 15))
	bar_set(bar, int(prog.get("have", 0)) - from, need - from, "%d/%d" % [int(prog.get("have", 0)), need])
	row.add_child(bar)
	# No button here: the chest is not ready and the red X closes (a green play would read
	# as "open" or "start a level").


func _open_sequence() -> void:
	var tw := create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(func(): _chest.pivot_offset = _chest.size * 0.5)
	for i in 6:
		var a := 0.12 if i % 2 == 0 else -0.12
		tw.tween_property(_chest, "rotation", a, 0.07)
	tw.tween_property(_chest, "rotation", 0.0, 0.06)
	tw.tween_callback(func():
		sfx(["chest_open", "upgrade"])
		burst(centre(_chest), 18)
		UiKit.pop(_chest, 1.3))
	tw.tween_interval(0.25)
	var items := reward_items(reward)
	for i in items.size():
		tw.tween_callback(_pop_item.bind(items[i]))
		tw.tween_interval(0.22)
	tw.tween_callback(func():
		_collect.disabled = false
		var t2 := _collect.create_tween()
		t2.tween_property(_collect, "modulate:a", 1.0, 0.2)
		pulse(_collect, 0.05))


func _pop_item(it: Array) -> void:
	var cell := card_box(Color("3b6fd1"), 8)
	cell.custom_minimum_size = Vector2(112, 146)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(v)
	var ic := icon_safe(String(it[0]), 80)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	if String(it[1]) != "":
		v.add_child(UiKit.label(String(it[1]), 38, Color.WHITE, 8))
	cell.set_meta("icon", String(it[0]))
	_items.add_child(cell)
	sfx(["coin"] if String(it[0]) == "coin" else ["recruit", "coin"], -4.0)
	after(0.0, func(): UiKit.pop(cell, 0.3))


func _on_collect() -> void:
	_collect.disabled = true
	var any := false
	for c in _items.get_children():
		if c.has_meta("icon") and String(c.get_meta("icon")) == "coin":
			fly("coin", centre(c), centre(_coin_pill), 10)
			any = true
	sfx(["coin_bag", "coin"])
	count_coins()
	after(0.85 if any else 0.1, close)

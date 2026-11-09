class_name SpinPanel
extends RetentionPanel
## Lucky spin. Honest odds: every slice's angle is its true chance x 360 degrees (Spin.
## probability, the same numbers the pick uses), with the reward's icon and amount inside.
## One free spin a day, then up to N rewarded-ad spins (the ad button shows how many are left);
## when none are left a clock shows the real time until midnight. The wheel eases out over a
## few seconds, ticking each time a slice edge passes the pointer, and lands inside the slice
## Game.spin_free()/spin_ad() picked (the reward is granted before the wheel turns, so closing
## mid-spin never loses it). Chest slices open on the chest screen.

const WHEEL := 540.0
const SPIN_TIME := 4.2
const COLORS := [Color("ffd23f"), Color("3fa9ff"), Color("ff7a45"), Color("5fd35b"), Color("c86bff"), Color("ff5b8a"), Color("35d0c4"), Color("ffa62b")]

var _wheel: Control
var _pointer: Control
var _spin_btn: Button
var _ad_btn: Button
var _ad_left: Label
var _timer_box: HBoxContainer
var _timer: Label
var _win: HBoxContainer
var _probs: Array = []
var _slices: Array = []
var _spinning := false
var _last_slice := -1
var _tick := 0.0


func _ready() -> void:
	var col := _frame(first_icon(["wheel", "star_icon"]), 0)
	_slices = Spin.slices(Game.economy)
	_probs = Game.spin_state().get("probabilities", [])
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, WHEEL + 40)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage)
	_wheel = Control.new()
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wheel.offset_left = -WHEEL * 0.5
	_wheel.offset_right = WHEEL * 0.5
	_wheel.offset_top = 30
	_wheel.offset_bottom = 30 + WHEEL
	_wheel.pivot_offset = Vector2(WHEEL, WHEEL) * 0.5
	_wheel.draw.connect(_draw_wheel)
	stage.add_child(_wheel)
	_add_slice_icons()
	var hub := icon_safe(first_icon(["wheel", "star_icon"]), 110)
	hub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hub.offset_left = -55
	hub.offset_right = 55
	hub.offset_top = 30 + WHEEL * 0.5 - 55
	hub.offset_bottom = 30 + WHEEL * 0.5 + 55
	stage.add_child(hub)
	_pointer = Control.new()
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pointer.offset_left = -36
	_pointer.offset_right = 36
	_pointer.offset_top = 0
	_pointer.offset_bottom = 80
	_pointer.pivot_offset = Vector2(36, 12)
	_pointer.draw.connect(_draw_pointer)
	stage.add_child(_pointer)
	# What you won pops here.
	_win = HBoxContainer.new()
	_win.alignment = BoxContainer.ALIGNMENT_CENTER
	_win.custom_minimum_size = Vector2(0, 90)
	_win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_win)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.custom_minimum_size = Vector2(0, 130)
	col.add_child(bottom)
	_spin_btn = UiKit.button("", "green", 10, Vector2(340, 124))
	var si := icon_safe(first_icon(["wheel", "play"]), 86)
	si.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	si.offset_left = -43
	si.offset_right = 43
	si.offset_top = -50
	si.offset_bottom = 36
	_spin_btn.add_child(si)
	_spin_btn.pressed.connect(_on_free)
	bottom.add_child(_spin_btn)
	_ad_btn = ad_button("spin", "", Vector2(340, 124), first_icon(["wheel", "play"]))
	_ad_left = UiKit.label("", 34, Color.WHITE, 8)
	var badge := card_box(UiKit.RED, 4, 20, 4)
	badge.position = Vector2(286, -16)
	badge.custom_minimum_size = Vector2(60, 50)
	badge.add_child(_ad_left)
	_ad_btn.add_child(badge)
	_ad_btn.pressed.connect(_on_ad)
	bottom.add_child(_ad_btn)
	_timer_box = HBoxContainer.new()
	_timer_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_timer_box.add_theme_constant_override("separation", 10)
	bottom.add_child(_timer_box)
	_timer_box.add_child(icon_safe("clock", 60))
	_timer = UiKit.label("", 56, Color.WHITE, 12)
	_timer_box.add_child(_timer)
	_refresh()


## Slice i covers [start, end) radians, measured clockwise from straight up (where the
## pointer is). Angles are exactly probability x TAU. Pure, for tests.
static func slice_bounds(probs: Array) -> Array:
	var out := []
	var a := 0.0
	for p in probs:
		out.append([a, a + float(p) * TAU])
		a += float(p) * TAU
	return out


## Which slice is under the pointer when the wheel is turned by `rotation` (clockwise, rad).
static func slice_at(probs: Array, rotation: float) -> int:
	var a := fposmod(-rotation, TAU)
	var b := slice_bounds(probs)
	for i in b.size():
		if a >= float(b[i][0]) and a < float(b[i][1]):
			return i
	return maxi(b.size() - 1, 0)


## Final wheel rotation so the pointer lands at fraction `t` (0..1) inside slice `i`, after at
## least `turns` full turns from `from`.
static func target_rotation(probs: Array, i: int, from: float, turns: int, t := 0.5) -> float:
	var b: Array = slice_bounds(probs)[i]
	var a := lerpf(float(b[0]), float(b[1]), t)
	var want := fposmod(-a, TAU)
	var base := from + turns * TAU
	return base + fposmod(want - fposmod(base, TAU), TAU)


func _add_slice_icons() -> void:
	var bounds := slice_bounds(_probs)
	var r := WHEEL * 0.5
	for i in _slices.size():
		var mid := (float(bounds[i][0]) + float(bounds[i][1])) * 0.5
		var span := float(bounds[i][1]) - float(bounds[i][0])
		var dir := Vector2(sin(mid), -cos(mid))
		var reward: Dictionary = _slices[i].get("reward", {})
		var item := Control.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.size = Vector2(120, 120)
		item.pivot_offset = Vector2(60, 60)
		item.position = Vector2(r, r) + dir * r * 0.66 - item.size * 0.5
		item.rotation = mid
		_wheel.add_child(item)
		var isz := clampf(span * r * 0.55, 32.0, 76.0)
		var ic := icon_safe(String(_slices[i].get("icon", "coin")), int(isz))
		ic.position = Vector2(60 - isz * 0.5, 4)
		ic.size = Vector2(isz, isz)
		item.add_child(ic)
		var amount := _amount_text(reward)
		if amount != "":
			var l := UiKit.label(amount, int(clampf(isz * 0.55, 24, 38)), Color.WHITE, 7)
			l.position = Vector2(0, isz + 2)
			l.size = Vector2(120, 40)
			item.add_child(l)


static func _amount_text(reward: Dictionary) -> String:
	if int(reward.get("coins", 0)) > 0:
		return num(int(Rewards.scaled(reward, Economy.reward_scale(int(Game.save.get("unlocked", 1)), Game.economy), Game.economy).get("coins", 0)))
	for b in ["headstart", "shield", "bomb"]:
		if int(reward.get(b, 0)) > 0:
			return "×%d" % int(reward[b])
	return ""


func _draw_wheel() -> void:
	var c := Vector2(WHEEL, WHEEL) * 0.5
	var r := WHEEL * 0.5
	_wheel.draw_circle(c, r + 8, UiKit.INK)
	var bounds := slice_bounds(_probs)
	for i in bounds.size():
		var a0 := float(bounds[i][0]) - PI * 0.5
		var a1 := float(bounds[i][1]) - PI * 0.5
		var pts := PackedVector2Array([c])
		var steps := maxi(int((a1 - a0) / TAU * 96.0), 2)
		for k in steps + 1:
			var a := lerpf(a0, a1, float(k) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		_wheel.draw_colored_polygon(pts, COLORS[i % COLORS.size()])
	for i in bounds.size():
		var a := float(bounds[i][0]) - PI * 0.5
		_wheel.draw_line(c, c + Vector2(cos(a), sin(a)) * r, UiKit.INK, 5, true)
	_wheel.draw_arc(c, r, 0, TAU, 128, UiKit.INK, 8, true)
	# Rim bulbs.
	for k in 24:
		var a := TAU * k / 24.0
		_wheel.draw_circle(c + Vector2(cos(a), sin(a)) * (r - 1), 6, Color.WHITE if k % 2 == 0 else UiKit.YELLOW)


func _draw_pointer() -> void:
	var s := _pointer.size
	var pts := PackedVector2Array([Vector2(4, 4), Vector2(s.x - 4, 4), Vector2(s.x * 0.5, s.y - 4)])
	_pointer.draw_colored_polygon(pts, UiKit.RED)
	pts.append(pts[0])
	_pointer.draw_polyline(pts, UiKit.INK, 6, true)


func _refresh() -> void:
	var st := Game.spin_state()
	var free := bool(st.get("can_free", false))
	var ad := bool(st.get("can_ad", false))
	_spin_btn.visible = free
	_ad_btn.visible = not free and ad
	_ad_left.text = str(int(st.get("ad_left", 0)))
	_timer_box.visible = not free and not ad
	_spin_btn.disabled = _spinning
	_ad_btn.disabled = _spinning
	_update_timer()


func _process(delta: float) -> void:
	if _spinning:
		var s := slice_at(_probs, _wheel.rotation)
		if s != _last_slice:
			_last_slice = s
			sfx(["spin_tick", "tick"], -6.0)
			_pointer.rotation = -0.35
			var tw := _pointer.create_tween()
			tw.tween_property(_pointer, "rotation", 0.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_timer()


func _update_timer() -> void:
	_timer.text = clock_text(seconds_to_midnight())


func _on_free() -> void:
	if _spinning:
		return
	_spin(Game.spin_free())


func _on_ad() -> void:
	if _spinning:
		return
	watch_ad("spin", func(ok: bool):
		if ok:
			_spin(Game.spin_ad()))


func _spin(result: Dictionary) -> void:
	if result.is_empty():
		_refresh()
		return
	_spinning = true
	for c in _win.get_children():
		c.queue_free()
	_refresh()
	var i := int(result["index"])
	var from := fposmod(_wheel.rotation, TAU)
	_wheel.rotation = from
	_last_slice = slice_at(_probs, from)
	var to := target_rotation(_probs, i, from, 5, randf_range(0.2, 0.8))
	var tw := create_tween()
	tw.tween_property(_wheel, "rotation", to, SPIN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_landed.bind(result))


func _landed(result: Dictionary) -> void:
	_spinning = false
	var reward: Dictionary = result.get("reward", {})
	sfx(["spin_win", "win"])
	var row := reward_row(reward, 84, 56, 12)
	_win.add_child(row)
	burst(centre(_win), 16)
	after(0.0, func(): UiKit.pop(row, 0.3))
	if String(reward.get("chest", "")) != "":
		var chest := StarChestPanel.new()
		chest.reward = reward
		add_child(chest)
	else:
		fly_reward(reward, centre(row))
	_refresh()

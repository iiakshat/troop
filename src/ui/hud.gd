class_name Hud
extends Control
## In-level overlay: level + progress, coins, power buttons, hints, banners,
## the swipe tutorial hand, pause, and the end-of-level strike bar.

signal power_pressed(id: String)
signal strike_stopped(mult: int)
signal pause_pressed

var _progress: ProgressBar
var _troops: Label
var _troops_pop := 0.0
var _level_label: Label
var _power_buttons: Dictionary = {}
var _hint_label: Label
var _hint_t := 0.0
var _banner: Label
var _banner_t := 0.0
var _hand: Label
var _hand_t := 0.0
var _hand_on := false
var _pulse: Dictionary = {}      # power id -> seconds of pulsing
var _strike_root: Control
var _strike_needle: ColorRect
var _strike_bar: HBoxContainer
var _strike_on := false
var _strike_done := false
var _strike_t := 0.0
var _zones: Array = []
var _sweep := 1.1


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zones = Game.economy["strike_zones"]
	_sweep = float(Game.economy["strike_sweep_seconds"])

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 24
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var pause := UiKit.button("II", Color(0, 0, 0, 0.45), 36, Vector2(78, 78))
	pause.pressed.connect(func(): pause_pressed.emit())
	top.add_child(pause)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(mid)
	_level_label = UiKit.label("LEVEL 1", 38)
	mid.add_child(_level_label)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 18)
	_progress.add_theme_stylebox_override("background", UiKit.box(Color(0, 0, 0, 0.45), 9))
	var fill := UiKit.box(UiKit.GOLD, 9)
	fill.shadow_size = 0
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.max_value = 1.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(_progress)
	# Small troop counter: a little blue figure and the number.
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.45), 20))
	pill.custom_minimum_size = Vector2(110, 0)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pill)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 8)
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(pr)
	pr.add_child(_person_icon())
	_troops = UiKit.label("1", 36, Color("8fd0ff"), 8)
	pr.add_child(_troops)

	_hint_label = UiKit.label("", 44, Color.WHITE, 12)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint_label.offset_top = 160
	_hint_label.offset_left = -340
	_hint_label.offset_right = 340
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)

	_banner = UiKit.label("", 88, UiKit.RED, 16)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -360
	_banner.offset_right = 360
	_banner.offset_top = -260
	_banner.offset_bottom = -140
	_banner.visible = false
	add_child(_banner)

	_hand = UiKit.label("<<  SWIPE  >>", 64, Color.WHITE, 14)
	_hand.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hand.offset_left = -340
	_hand.offset_right = 340
	_hand.offset_top = -420
	_hand.offset_bottom = -320
	_hand.visible = false
	add_child(_hand)

	_add_power("shield", "SHIELD", UiKit.BLUE, true)
	_add_power("bomb", "BOMB", UiKit.RED, false)
	_build_strike()


func _add_power(id: String, text: String, color: Color, left: bool) -> void:
	var b := UiKit.button(text, color, 34, Vector2(170, 120))
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT if left else Control.PRESET_BOTTOM_RIGHT)
	if left:
		b.offset_left = 24
		b.offset_right = 194
	else:
		b.offset_left = -194
		b.offset_right = -24
	b.offset_top = -160
	b.offset_bottom = -40
	b.pressed.connect(func(): power_pressed.emit(id))
	b.visible = false
	add_child(b)
	_power_buttons[id] = {"button": b, "text": text}


func _person_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(22, 34)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := ColorRect.new()
	head.color = Color("8fd0ff")
	head.position = Vector2(6, 2)
	head.size = Vector2(10, 10)
	c.add_child(head)
	var body := ColorRect.new()
	body.color = Color("8fd0ff")
	body.position = Vector2(2, 14)
	body.size = Vector2(18, 18)
	c.add_child(body)
	return c


func set_troops(n: int) -> void:
	_troops.text = str(n)
	_troops_pop = 1.0


func set_level(n: int, name: String) -> void:
	_level_label.text = "LEVEL %d  ·  %s" % [n, name.to_upper()]


func set_progress(p: float) -> void:
	_progress.value = p


func set_charges(charges: Dictionary) -> void:
	for id in _power_buttons:
		var pb: Dictionary = _power_buttons[id]
		var b: Button = pb["button"]
		var n := int(charges.get(id, 0))
		b.visible = n > 0 or b.visible
		b.text = "%s\n×%d" % [pb["text"], n]
		b.disabled = n <= 0


func show_hint(ev: Dictionary) -> void:
	_hint_label.text = String(ev.get("text", ""))
	_hint_t = float(ev.get("dur", 2.5))
	_hint_label.modulate.a = 1.0
	UiKit.pop(_hint_label, 0.7)
	var p := String(ev.get("power", ""))
	if p != "" and _power_buttons.has(p):
		_pulse[p] = 3.5


func show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner_t = 1.6
	UiKit.pop(_banner, 2.0)
	Sfx.play("swoosh")


func set_tutorial(active: bool) -> void:
	_hand_on = active
	_hand.visible = active


func _process(delta: float) -> void:
	if _troops_pop > 0.0:
		_troops_pop = maxf(_troops_pop - delta * 4.0, 0.0)
		_troops.pivot_offset = _troops.size * 0.5
		_troops.scale = Vector2.ONE * (1.0 + 0.4 * _troops_pop)
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t < 0.5:
			_hint_label.modulate.a = maxf(_hint_t / 0.5, 0.0)
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			_banner.visible = false
	if _hand_on:
		_hand_t += delta
		_hand.position.x = (size.x - _hand.size.x) * 0.5 + sin(_hand_t * 6.0) * 60.0
	for id in _pulse.keys():
		_pulse[id] = float(_pulse[id]) - delta
		var b: Button = _power_buttons[id]["button"]
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2.ONE * (1.0 + 0.12 * absf(sin(Time.get_ticks_msec() / 120.0)))
		if float(_pulse[id]) <= 0.0:
			b.scale = Vector2.ONE
			_pulse.erase(id)
	if _strike_on and not _strike_done:
		_strike_t += delta
		var k := pingpong(_strike_t / _sweep, 1.0)
		var w := _strike_bar.size.x
		_strike_needle.position.x = _strike_bar.position.x + k * w - _strike_needle.size.x * 0.5


# ---------------------------------------------------------------- strike

func _build_strike() -> void:
	_strike_root = Control.new()
	UiKit.full_rect(_strike_root)
	_strike_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_strike_root.visible = false
	add_child(_strike_root)
	var title := UiKit.label("TAP TO STRIKE!", 64, UiKit.GOLD, 14)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	title.offset_left = -340
	title.offset_right = 340
	title.offset_top = -420
	title.offset_bottom = -340
	_strike_root.add_child(title)
	_strike_bar = HBoxContainer.new()
	_strike_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_strike_bar.offset_left = -320
	_strike_bar.offset_right = 320
	_strike_bar.offset_top = -320
	_strike_bar.offset_bottom = -230
	_strike_bar.add_theme_constant_override("separation", 0)
	_strike_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strike_root.add_child(_strike_bar)
	var colors := {1: Color("8a8f99"), 2: Color("4fb3c9"), 3: Color("43b56b"), 5: UiKit.GOLD}
	for z in _zones:
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := UiKit.box(colors.get(int(z), Color.GRAY), 0, 3)
		sb.shadow_size = 0
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UiKit.label("×%d" % int(z), 40)
		p.add_child(l)
		_strike_bar.add_child(p)
	_strike_needle = ColorRect.new()
	_strike_needle.color = Color.WHITE
	_strike_needle.size = Vector2(14, 130)
	_strike_needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strike_root.add_child(_strike_needle)
	_strike_root.gui_input.connect(_on_strike_input)


func start_strike() -> void:
	_strike_on = true
	_strike_done = false
	_strike_t = 0.0
	_strike_root.visible = true
	for id in _power_buttons:
		_power_buttons[id]["button"].visible = false
	await get_tree().process_frame
	_strike_needle.position.y = _strike_bar.position.y - 20


func _on_strike_input(event: InputEvent) -> void:
	if _strike_done or not _strike_on:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if not pressed:
		return
	_strike_done = true
	var k := pingpong(_strike_t / _sweep, 1.0)
	var idx := clampi(int(k * _zones.size()), 0, _zones.size() - 1)
	var mult := int(_zones[idx])
	var zone: Control = _strike_bar.get_child(idx)
	UiKit.pop(zone, 1.5)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(func(): _strike_root.visible = false)
	strike_stopped.emit(mult)

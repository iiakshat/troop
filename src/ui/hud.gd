class_name Hud
extends Control
## In-level overlay: pause, progress, small troop counter, Shield/Bomb icon buttons, gang
## banners. No hint hand (spec v2 §11/§12.3): "this is new" is NewItemCard (LevelView opens it
## on each level hint event), gestures are Tutorial's. A power hint here only pulses its button.

signal power_pressed(id: String)
signal pause_pressed

var _progress: ProgressBar
var _troops: HBoxContainer
var _troops_pop := 0.0
var _cap_bar: ProgressBar
var _power_buttons: Dictionary = {}
var _banner: Label
var _banner_t := 0.0
var _pulse: Dictionary = {}
var tutor := false   # a Tutorial runs this level: it owns the hints in Tutorial.OWNS


func _ready() -> void:
	UiKit.safe_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 26
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var pause := UiKit.icon_button("pause", "yellow", 92)
	pause.pressed.connect(func(): pause_pressed.emit())
	top.add_child(pause)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 30)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.12, 0.3, 0.95)  # opaque: stays visible against a night sky
	bg.set_corner_radius_all(15)
	bg.set_border_width_all(4)
	bg.border_color = UiKit.INK
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiKit.YELLOW
	fill.set_corner_radius_all(12)
	fill.set_border_width_all(4)
	fill.border_color = UiKit.INK
	_progress.add_theme_stylebox_override("background", bg)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.max_value = 1.0
	_progress.step = 0.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_progress)
	# The finish: the Gang HQ (hood) icon sits on the bar's right end.
	var goal := UiKit.icon("hood", 44)
	goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	goal.offset_left = -30
	goal.offset_right = 14
	goal.offset_top = -22
	goal.offset_bottom = 22
	_progress.add_child(goal)
	_troops = UiKit.pill("person", "1", Color("8fd0ff"))
	# Troop counter with the squad's capacity bar under it.
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 4)
	tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tcol)
	tcol.add_child(_troops)
	_cap_bar = ProgressBar.new()
	_cap_bar.show_percentage = false
	_cap_bar.custom_minimum_size = Vector2(0, 16)
	_cap_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(0.05, 0.12, 0.3, 0.6)
	cbg.set_corner_radius_all(8)
	cbg.set_border_width_all(3)
	cbg.border_color = UiKit.INK
	var cfill := StyleBoxFlat.new()
	cfill.bg_color = Color("8fd0ff")
	cfill.set_corner_radius_all(6)
	_cap_bar.add_theme_stylebox_override("background", cbg)
	_cap_bar.add_theme_stylebox_override("fill", cfill)
	tcol.add_child(_cap_bar)

	_banner = UiKit.label("", 92, UiKit.RED, 18)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -360
	_banner.offset_right = 360
	_banner.offset_top = -300
	_banner.offset_bottom = -170
	_banner.visible = false
	add_child(_banner)

	_add_power("shield", "blue", true)
	_add_power("bomb", "red", false)


func _add_power(id: String, color: String, left: bool) -> void:
	var b := UiKit.icon_button(id, color, 150, "round")
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT if left else Control.PRESET_BOTTOM_RIGHT)
	if left:
		b.offset_left = 30
		b.offset_right = 180
	else:
		b.offset_left = -180
		b.offset_right = -30
	b.offset_top = -200
	b.offset_bottom = -50
	b.pressed.connect(func(): power_pressed.emit(id))
	b.visible = false
	add_child(b)
	_power_buttons[id] = b


## A rank joined the squad for the first time ever: its stat card in the corner (2.5 s).
func show_rank(unit: String) -> void:
	RankToast.show(self, unit)


func set_level(_n: int, _name: String) -> void:
	pass


func set_progress(p: float) -> void:
	_progress.value = p


func set_troops(n: int) -> void:
	UiKit.pill_set(_troops, str(n))
	_troops_pop = 1.0
	_cap_bar.value = n
	# Full squad: the bar turns gold.
	(_cap_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = UiKit.GOLD if n >= _cap_bar.max_value else Color("8fd0ff")


func set_capacity(cap: int) -> void:
	_cap_bar.max_value = maxi(cap, 1)
	_cap_bar.visible = cap > 0


func set_charges(charges: Dictionary) -> void:
	for id in _power_buttons:
		var b: Button = _power_buttons[id]
		var n := int(charges.get(id, 0))
		b.visible = n > 0 or b.visible
		b.disabled = n <= 0
		UiKit.set_badge(b, n)


## A level hint event `ev` = {"id", "icon", "power"?}, after LevelView's NewItemCard (which
## marks the ids it shows). What is left (an id the card does not list) is marked once; a
## power hint pulses its own button. Never a hand (spec v2 §12.3).
func show_hint(ev: Dictionary) -> void:
	var id := String(ev.get("id", ev.get("icon", "")))
	if id == "" or Game.hint_seen(id) or (tutor and Tutorial.OWNS.has(id)):
		return
	Game.mark_hint(id)
	var power := String(ev.get("power", ""))
	if _power_buttons.has(power):
		_pulse[power] = 3.0


func show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.label_settings.font_color = color
	_banner.visible = true
	_banner_t = 1.5
	UiKit.pop(_banner, 2.0)
	Sfx.play("banner")


## LevelView's legacy swipe-row signal. Tutorial teaches the drag (with the gesture hand) and
## LevelView no longer freezes once it has: nothing to show here.
func set_tutorial(_active: bool) -> void:
	pass


func enter_finale() -> void:
	for id in _power_buttons:
		(_power_buttons[id] as Control).visible = false
	_progress.get_parent().visible = false


func _process(delta: float) -> void:
	if _troops_pop > 0.0:
		_troops_pop = maxf(_troops_pop - delta * 4.0, 0.0)
		_troops.pivot_offset = _troops.size * 0.5
		_troops.scale = Vector2.ONE * (1.0 + 0.3 * _troops_pop)
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			_banner.visible = false
	for id in _pulse.keys():
		_pulse[id] = float(_pulse[id]) - delta
		var b: Button = _power_buttons[id]
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2.ONE * (1.0 + 0.14 * absf(sin(Time.get_ticks_msec() / 110.0)))
		if float(_pulse[id]) <= 0.0:
			b.scale = Vector2.ONE
			_pulse.erase(id)

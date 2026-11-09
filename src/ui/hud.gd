class_name Hud
extends Control
## In-level overlay: pause, progress, small troop counter, Shield/Bomb icon buttons, gang
## banners and one-time icon hints (a pointing hand, no instructions). Each hint shows once
## ever (save: seen_hints).

signal power_pressed(id: String)
signal pause_pressed

var _progress: ProgressBar
var _troops: HBoxContainer
var _troops_pop := 0.0
var _cap_bar: ProgressBar
var _power_buttons: Dictionary = {}
var _banner: Label
var _banner_t := 0.0
var _hint_root: Control
var _hint_icon: TextureRect
var _hand: TextureRect
var _hint_t := 0.0
var _hint_mode := ""
var _hint_target: Control = null
var _pulse: Dictionary = {}


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
	bg.bg_color = Color(0.05, 0.12, 0.3, 0.6)
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
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_progress)
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

	_hint_root = Control.new()
	UiKit.full_rect(_hint_root)
	_hint_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_root.visible = false
	add_child(_hint_root)
	_hint_icon = UiKit.icon("hand", 150)
	_hint_root.add_child(_hint_icon)
	_hand = UiKit.icon("hand", 130, Color.WHITE)
	_hint_root.add_child(_hand)

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


## A one-time icon cue. `ev` = {"id", "icon", "power"?}.
func show_hint(ev: Dictionary) -> void:
	var id := String(ev.get("id", ev.get("icon", "")))
	if id == "" or Game.hint_seen(id):
		return
	Game.mark_hint(id)
	var icon_name := String(ev.get("icon", "hand"))
	if icon_name == "swipe":
		return  # the swipe tutorial (set_tutorial) handles it
	_hint_icon.texture = UiKit.icon_texture(icon_name)
	_hint_root.visible = true
	_hint_t = 2.6
	_hint_mode = "power" if ev.has("power") else "icon"
	_hint_target = _power_buttons.get(String(ev.get("power", "")), null)
	if _hint_target:
		_pulse[String(ev["power"])] = 3.0
	UiKit.pop(_hint_icon, 0.3)


func show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.label_settings.font_color = color
	_banner.visible = true
	_banner_t = 1.5
	UiKit.pop(_banner, 2.0)
	Sfx.play("banner")


func set_tutorial(active: bool) -> void:
	_hint_mode = "swipe" if active else ""
	_hint_root.visible = active
	_hint_t = 99.0 if active else 0.0
	if active:
		_hint_icon.texture = UiKit.icon_texture("swipe")


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
	if _hint_root.visible:
		_hint_t -= delta
		var t := Time.get_ticks_msec() / 1000.0
		var c := size * 0.5
		match _hint_mode:
			"swipe":
				_hint_icon.visible = false
				_hand.position = Vector2(c.x - 65 + sin(t * 5.0) * 150.0, size.y * 0.62)
				_hand.rotation = 0.0
			"power":
				_hint_icon.visible = false
				if _hint_target:
					var tp := _hint_target.global_position + _hint_target.size * 0.5
					_hand.position = tp + Vector2(-40, -200 + sin(t * 8.0) * 22.0)
					_hand.rotation = PI
			_:
				_hint_icon.visible = true
				_hint_icon.position = Vector2(c.x - 75, size.y * 0.2 + sin(t * 4.0) * 10.0)
				_hand.position = Vector2(c.x + 40, size.y * 0.2 + 90 + sin(t * 6.0) * 14.0)
				_hand.rotation = -0.6
		if _hint_t <= 0.0:
			_hint_root.visible = false

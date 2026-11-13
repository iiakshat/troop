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
var _troops_n := -1        # the count shown (a drop pulses the pill red)
var _troops_hurt := 0.0    # spec v2.1 §1.1: 1 on a loss, fading
## Review v2.1: every loss also shows as a red -N tucked under the troop pill, never on the
## enemy's side of the street (losses within MINUS_WINDOW s add up, shown MINUS_HOLD s).
const MINUS_WINDOW := 0.3
const MINUS_HOLD := 0.9
var _minus: Label
var _minus_n := 0
var _minus_t := 0.0        # seconds since the last loss
var _power: HBoxContainer
var _power_shown := -1.0
var _power_text := ""
var _power_pop := 0.0
var _power_base := -1.0      # the steady firepower (hero at full tap rate) last frame
var _power_delta: PowerDelta # owner play-test: +N / -N under the firepower for 2.5 s
var _cap_bar: ProgressBar
var _power_buttons: Dictionary = {}
var _power_ready_ms: Dictionary = {}   # v2: power id -> ticks when its free charge is back
var _shield_ring: DrainRing            # drains around the shield button while the shield is up
var _shield_full := 0.0
var _shield_last := 0.0
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
	# Spec v2 §12.4: live firepower (lightning + number, no words) next to the troop count.
	_power = UiKit.pill("power", "1", UiKit.YELLOW)
	# Troop counter and firepower with the squad's capacity bar under them.
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 4)
	tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tcol)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 8)
	pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcol.add_child(pills)
	pills.add_child(_troops)
	pills.add_child(_power)
	_minus = Label.new()
	_minus.add_theme_font_override("font", UiKit.FONT)
	_minus.add_theme_font_size_override("font_size", 34)
	_minus.add_theme_color_override("font_color", Color("ff3b3b"))
	_minus.add_theme_color_override("font_outline_color", UiKit.INK)
	_minus.add_theme_constant_override("outline_size", 10)
	_minus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minus.visible = false
	add_child(_minus)
	_power_delta = PowerDelta.make(_power, 30, 2.0)
	add_child(_power_delta)
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
	# v2 powers: an empty button shows a clock and the time until the free charge is back.
	var timer := HBoxContainer.new()
	timer.alignment = BoxContainer.ALIGNMENT_CENTER
	timer.add_theme_constant_override("separation", 2)
	timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	timer.offset_left = -90
	timer.offset_right = 90
	timer.offset_top = -10
	timer.offset_bottom = 34
	timer.add_child(UiKit.icon("clock", 38))
	var tl := UiKit.label("", 32, Color.WHITE, 8)
	timer.add_child(tl)
	timer.visible = false
	b.add_child(timer)
	b.set_meta("timer", timer)
	b.set_meta("timer_label", tl)
	if id == "shield":
		# While the shield is up: a ring around the button drains with the sim's timer.
		_shield_ring = DrainRing.new()
		_shield_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["offset_left", "offset_top"]:
			_shield_ring.set(side, -12.0)
		for side in ["offset_right", "offset_bottom"]:
			_shield_ring.set(side, 12.0)
		_shield_ring.color = Color(String(ShieldBubble.look().get("rim", "62e6ff")))
		_shield_ring.visible = false
		b.add_child(_shield_ring)


## A ring that drains clockwise from the top (`frac` 1 = full), on a dark track.
class DrainRing extends Control:
	var frac := 0.0
	var color := Color("62e6ff")
	var alpha := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		draw_arc(c, r, 0.0, TAU, 72, Color(UiKit.INK, 0.6), 13.0, true)
		if frac > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 72, Color(color, alpha), 8.0, true)


## The sim's shield seconds left this frame (0 when none or when the level is not running).
## The ring is full at each new shield (a press or a revive) and blinks in the last second,
## like the bubble in the street.
func set_shield(t: float) -> void:
	if _shield_ring == null:
		return
	if t > _shield_last + 0.05 or _shield_full <= 0.0:
		_shield_full = t
	_shield_last = t
	_shield_ring.visible = t > 0.0
	if t <= 0.0:
		_shield_full = 0.0
		return
	_shield_ring.frac = clampf(t / maxf(_shield_full, 0.001), 0.0, 1.0)
	_shield_ring.alpha = ShieldBubble.blink(t, ShieldBubble.look())
	_shield_ring.queue_redraw()


func shield_ring() -> Control:
	return _shield_ring


## A rank joined the squad for the first time ever: its stat card in the corner (2.5 s).
func show_rank(unit: String) -> void:
	RankToast.show(self, unit)


func set_level(_n: int, _name: String) -> void:
	pass


func set_progress(p: float) -> void:
	_progress.value = p


func set_troops(n: int) -> void:
	UiKit.pill_set(_troops, NumFormat.fmt(n))
	_troops_pop = 1.0
	if _troops_n >= 0 and n < _troops_n:
		_troops_hurt = 1.0   # spec v2.1 §1.1: a loss pulses the pill red
		if _minus_t > MINUS_WINDOW + 0.05 or not _minus.visible:
			_minus_n = 0
		_minus_n += _troops_n - n
		_minus_t = 0.0
		_minus.text = "-" + NumFormat.fmt(_minus_n)
		_minus.visible = true
	_troops_n = n
	_cap_bar.value = n
	# Full squad: the bar turns gold.
	(_cap_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = UiKit.GOLD if n >= _cap_bar.max_value else Color("8fd0ff")


## Live firepower (LevelSim.live_power), called every frame, in the lobby's Squad Power format
## (Economy.fmt_power: one decimal below 100, then 12.3K / 1.25M): the label only changes when
## the shown number does, and a gain (troops joining, tapping) pops it.
## Owner play-test: every change of the squad's firepower (a gate taken, troops joining or
## falling, a weapon picked up) shows as a green +N / red -N under it for 2.5 s; changes within
## that time add up. `steady` is the firepower with the hero at full tap rate (steady_power):
## the hint follows it, so the hero heating up and cooling down between taps does not flash a
## number all the time. Without it the hint follows `v`.
func set_firepower(v: float, steady := -1.0) -> void:
	var base := steady if steady >= 0.0 else v
	if _power_base >= 0.0 and absf(base - _power_base) > 0.0001:
		_power_delta.add(base - _power_base)
	_power_base = base
	var txt := Economy.fmt_power(v)
	if txt == _power_text:
		return
	if v > _power_shown and _power_shown >= 0.0:
		_power_pop = 1.0
	_power_shown = v
	_power_text = txt
	UiKit.pill_set(_power, txt)


func firepower_text() -> String:
	return (_power.get_meta("label") as Label).text


## The +N / -N under the firepower ("" when none shows; tests).
func firepower_delta_text() -> String:
	return _power_delta.shown()


## A LevelSim's firepower with the hero at full tap rate (its live_power without the tap heat):
## the squad's own strength, for set_firepower's change hint. Reads the sim and leaves it as it was.
static func steady_power(sim: Object) -> float:
	var sq: Object = sim.get("squad")
	if sq == null:
		return float(sim.call("live_power"))
	var rate: float = sq.get("hero_rate")
	sq.set("hero_rate", 1.0)
	var p := float(sim.call("live_power"))
	sq.set("hero_rate", rate)
	return p


func set_capacity(cap: int) -> void:
	_cap_bar.max_value = maxi(cap, 1)
	_cap_bar.visible = cap > 0


func set_charges(charges: Dictionary) -> void:
	for id in _power_buttons:
		var b: Button = _power_buttons[id]
		var n := int(charges.get(id, 0))
		# v2: out of charges, the free one is recharging (it was used here, or the save's timer
		# still runs): the button stays, dimmed, with the countdown.
		var secs := 0
		if n <= 0 and SaveData.POWERS.has(id):
			secs = int(Game.power_state(id)["seconds_left"])
			if secs <= 0 and b.visible:
				secs = int(Game.economy.get("powers", {}).get("recharge_s", 18000))
		b.visible = n > 0 or b.visible or secs > 0
		b.disabled = n <= 0
		UiKit.set_badge(b, n)
		if secs > 0:
			_power_ready_ms[id] = Time.get_ticks_msec() + secs * 1000
		else:
			_power_ready_ms.erase(id)
		(b.get_meta("timer") as Control).visible = secs > 0
		(b.get_meta("timer_label") as Label).text = BoosterPanel.time_text(secs)


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


## A power button's screen rect (LevelView.use_power's guard against stray fire taps).
func power_rect(id: String) -> Rect2:
	var b: Control = _power_buttons.get(id, null)
	return b.get_global_rect() if b != null else Rect2()


func enter_finale() -> void:
	set_shield(0.0)
	for id in _power_buttons:
		(_power_buttons[id] as Control).visible = false
	_progress.get_parent().visible = false


func _process(delta: float) -> void:
	if _minus.visible:
		_minus_t += delta
		if _minus_t > MINUS_HOLD:
			_minus.visible = false
		else:
			var r := _troops.get_global_rect()
			_minus.size = _minus.get_minimum_size()
			_minus.global_position = Vector2(r.position.x + (r.size.x - _minus.size.x) * 0.5, r.end.y + 2.0)
			_minus.modulate.a = clampf((MINUS_HOLD - _minus_t) / 0.3, 0.0, 1.0)
	if _troops_pop > 0.0:
		_troops_pop = maxf(_troops_pop - delta * 4.0, 0.0)
		_troops.pivot_offset = _troops.size * 0.5
		_troops.scale = Vector2.ONE * (1.0 + 0.3 * _troops_pop)
	if _troops_hurt > 0.0 or _troops.modulate != Color.WHITE:
		_troops_hurt = maxf(_troops_hurt - delta * 2.5, 0.0)
		_troops.modulate = Color.WHITE.lerp(Color(1.0, 0.3, 0.28), _troops_hurt)
		_troops.pivot_offset = _troops.size * 0.5
		_troops.rotation = 0.06 * sin(_troops_hurt * 40.0) * _troops_hurt
	if _power_pop > 0.0:
		_power_pop = maxf(_power_pop - delta * 5.0, 0.0)
		_power.pivot_offset = _power.size * 0.5
		_power.scale = Vector2.ONE * (1.0 + 0.18 * _power_pop)
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			_banner.visible = false
	for id in _power_ready_ms:
		var left := ceili((int(_power_ready_ms[id]) - Time.get_ticks_msec()) / 1000.0)
		((_power_buttons[id] as Button).get_meta("timer_label") as Label).text = BoosterPanel.time_text(left)
	for id in _pulse.keys():
		_pulse[id] = float(_pulse[id]) - delta
		var b: Button = _power_buttons[id]
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2.ONE * (1.0 + 0.14 * absf(sin(Time.get_ticks_msec() / 110.0)))
		if float(_pulse[id]) <= 0.0:
			b.scale = Vector2.ONE
			_pulse.erase(id)

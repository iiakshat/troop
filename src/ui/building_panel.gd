class_name BuildingPanel
extends Control
## One city building: its art (ruin or rebuilt; greyed while its district is not reached),
## level pips, coins per hour now ▸ next (coin + clock icons), the build time, and one big
## button: rebuild / upgrade (hammer + coin price). While it is being built: a bar with the
## time left and a rewarded-ad speed-up (ad icon + the time it takes off). Locked states show
## district_lock + the district to liberate; maxed shows a crown; all builders busy shows a
## hammer + busy/max. No words. Frees itself on close and emits `closed`.

signal closed

var id := ""
var _panel: PanelContainer
var _art: TextureRect
var _pips: HBoxContainer
var _now: Label
var _arrow: Control
var _next: Label
var _info: HBoxContainer
var _time: Label
var _bar_bg: Panel
var _bar: Panel
var _bar_label: Label
var _btn: Button
var _first_hand: Control = null
var _ad: Button
var _state: Dictionary = {}
var _tick := 0.0
var _offered := false


func _init(building_id := "") -> void:
	id = building_id


func _ready() -> void:
	UiKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	UiKit.full_rect(dim)
	add_child(dim)
	_panel = UiKit.panel()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = -470
	_panel.offset_bottom = 470
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var rib := UiKit.ribbon("hammer")
	rib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(rib)
	var close := UiKit.icon_button("close", "red", 96)
	close.pressed.connect(_close)
	head.add_child(close)

	_art = TextureRect.new()
	_art.custom_minimum_size = Vector2(400, 380)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_art)

	_pips = HBoxContainer.new()
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.add_theme_constant_override("separation", 10)
	col.add_child(_pips)
	for i in City.max_level(Game.economy):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(56, 24)
		_pips.add_child(pip)

	var inc := HBoxContainer.new()
	inc.alignment = BoxContainer.ALIGNMENT_CENTER
	inc.add_theme_constant_override("separation", 10)
	col.add_child(inc)
	inc.add_child(UiKit.icon("coin", 58))
	_now = UiKit.label("0", 52, Color.WHITE, 10)
	inc.add_child(_now)
	_arrow = UiKit.icon("play", 36, UiKit.YELLOW)
	inc.add_child(_arrow)
	_next = UiKit.label("0", 52, UiKit.YELLOW, 10)
	inc.add_child(_next)
	inc.add_child(UiKit.label("/", 46, Color.WHITE, 10))
	inc.add_child(UiKit.icon("clock", 50))

	_info = HBoxContainer.new()
	_info.alignment = BoxContainer.ALIGNMENT_CENTER
	_info.add_theme_constant_override("separation", 10)
	col.add_child(_info)
	_info.add_child(UiKit.icon("clock", 46))
	_time = UiKit.label("0:00", 42, Color.WHITE, 10)
	_info.add_child(_time)

	_bar_bg = Panel.new()
	_bar_bg.custom_minimum_size = Vector2(520, 56)
	_bar_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar_bg.add_theme_stylebox_override("panel", UiKit.flat_box(Color(0.1, 0.12, 0.25, 0.85), 28, 5))
	col.add_child(_bar_bg)
	_bar = Panel.new()
	_bar.add_theme_stylebox_override("panel", UiKit.flat_box(UiKit.GREEN, 22, 0))
	_bar.position = Vector2(6, 6)
	_bar.size = Vector2(0, 44)
	_bar_bg.add_child(_bar)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 8)
	brow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(brow)
	_bar_bg.add_child(brow)
	brow.add_child(UiKit.icon("clock", 40))
	_bar_label = UiKit.label("0:00", 36, Color.WHITE, 9)
	brow.add_child(_bar_label)

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap)
	_btn = UiKit.button("", "green", 46, Vector2(460, 128))
	_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn.pressed.connect(_build)
	col.add_child(_btn)
	if Game.first_build_pending():
		# First build: the pointing hand taps on the Build button (spec v2 §11).
		_first_hand = PointerHand.on(_btn, Vector2(0.72, 0.55), 110.0)
	_ad = UiKit.button("", "yellow", 46, Vector2(460, 128))
	_ad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ad.pressed.connect(_speed_up)
	col.add_child(_ad)

	Game.city_changed.connect(refresh)
	Game.coins_changed.connect(_on_coins)
	Game.build_finished.connect(_on_done)
	refresh()
	UiKit.pop(_panel, 0.7)


func _close() -> void:
	closed.emit()
	queue_free()


func _paint(b: Button, color: String) -> void:
	for s in ["normal", "hover"]:
		b.add_theme_stylebox_override(s, UiKit._tex_box(color, "rectangle"))
	b.add_theme_stylebox_override("pressed", UiKit._tex_box(color, "rectangle", true))


func refresh() -> void:
	if not is_inside_tree():
		return
	var st: Dictionary = Game.building_state(id)
	_state = st
	var status := String(st["status"])
	var reason := String(st["reason"])
	var lv := int(st["lv"])
	var earning := int(st["earning_lv"])
	var mx := int(st["max"])
	var d := int(st["district"])
	var tex_name := id if earning >= 1 else "%s_ruin" % id
	var path := "res://assets/city/%s.png" % tex_name
	_art.texture = load(path) as Texture2D if ResourceLoader.exists(path) else UiKit.icon_texture("city_hall")
	_art.modulate = Color(0.45, 0.45, 0.5) if status == "locked" else Color.WHITE

	for i in _pips.get_child_count():
		var c := UiKit.YELLOW if i < earning else Color(0, 0, 0, 0.3)
		if status == "building" and i == lv - 1:
			c = Color("ff9f1c")
		(_pips.get_child(i) as Panel).add_theme_stylebox_override("panel", UiKit.flat_box(c, 10, 3))

	var maxed := lv >= mx
	var building := status == "building"
	# While building, "next" is the level being built; otherwise the level after this one.
	var next_income := City.income_at(id, lv, Game.economy) if building else float(st["next_income"])
	_now.text = str(int(round(float(st["income"]))))
	_next.text = str(int(round(next_income)))
	_arrow.visible = building or not maxed
	_next.visible = _arrow.visible

	_info.visible = not building and not maxed
	_time.text = UiKit.fmt_time(int(st["build_time"]))
	_bar_bg.visible = building
	if building:
		var total := maxi(City.build_time(id, lv, Game.economy), 1)
		var rem := int(st["remaining"])
		var f := clampf(1.0 - float(rem) / total, 0.0, 1.0)
		_bar.size = Vector2(maxf((_bar_bg.custom_minimum_size.x - 12.0) * f, 0.0), 44)
		_bar_label.text = UiKit.fmt_time(rem)

	_btn.visible = not building
	_btn.disabled = false
	var cost := int(st["cost"])
	if status == "locked":
		_btn.disabled = true
		UiKit.button_row(_btn, ["district_lock"], str(maxi(d - 1, 1)))
	elif status == "upgrade_locked":
		_btn.disabled = true
		UiKit.button_row(_btn, ["district_lock"], str(d))
	elif status == "maxed" or maxed:
		_btn.disabled = true
		UiKit.button_row(_btn, ["crown"])
	elif reason == "builders":
		_btn.disabled = true
		var t: int = Game.now()
		UiKit.button_row(_btn, ["hammer"], "%d/%d" % [City.builders_busy(Game.save, t), int(Game.economy["city"].get("max_parallel_builds", 1))])
	else:
		UiKit.button_row(_btn, ["hammer", "coin"], UiKit.fmt_coins(cost))
		_paint(_btn, "green" if int(Game.save["coins"]) >= cost else "grey")
	if is_instance_valid(_first_hand):
		_first_hand.visible = first_hand_shows(st, int(Game.save["coins"]))

	_ad.visible = building
	if building:
		UiKit.button_row(_ad, ["ad_play", "clock"], "-" + UiKit.fmt_time(int(st["speedup"])))
		if not _offered:
			_offered = true
			Ads.note_offer("speed_up")
	else:
		_offered = false


## Spec v2 §12.3: the first-build hand taps the Build button only while that button is live
## (hammer + coin + a price the player can pay). Locked, maxed, busy or too dear: no hand.
static func first_hand_shows(st: Dictionary, coins: int) -> bool:
	var status := String(st.get("status", ""))
	if status in ["locked", "upgrade_locked", "maxed", "building"] or String(st.get("reason", "")) == "builders":
		return false
	return int(st.get("lv", 0)) < int(st.get("max", 1)) and coins >= int(st.get("cost", 0))


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 0.25:
		_tick = 0.0
		if String(_state.get("status", "")) == "building":
			refresh()


func _build() -> void:
	if Game.start_build(id):
		if is_instance_valid(_first_hand):
			_first_hand.queue_free()
		Sfx.play("build")
		UiKit.pop(_art, 0.8)
		refresh()
	else:
		Sfx.play("error")
		UiKit.shake(_btn)


func _speed_up() -> void:
	_ad.disabled = true
	Ads.show_rewarded("speed_up", _on_ad)


func _on_ad(ok: bool) -> void:
	if not is_inside_tree():
		return
	_ad.disabled = false
	if ok and Game.speed_up_build(id) > 0:
		Sfx.play("upgrade")
		UiKit.bump(_bar_bg, 1.06)
	refresh()


func _on_coins(_c: int) -> void:
	refresh()


func _on_done(bid: String) -> void:
	if bid == id:
		UiKit.pop(_art, 0.8)
		refresh()

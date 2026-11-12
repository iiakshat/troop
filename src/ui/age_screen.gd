class_name AgeScreen
extends Control
## Neutral age screen (spec v2 §8). Shown once, on the first launch, before any ad or analytics
## SDK starts. A birth-year wheel and a play button: numbers and icons only, no "are you a kid"
## wording, no pre-chosen answer (the wheel starts on an empty slot and play stays grey until a
## year is picked), no hint that one answer unlocks more. The answer goes to
## Game.set_birth_year, which decides child / adult (Audience) and emits Game.audience_ready.
## Not shown under autoplay, headless, or any debug run (age=1 forces it, for screenshots).

signal done

const ROW_H := 104.0
const ROWS := 5                      # visible rows; the middle one is the choice
const BLANK := "- - - -"
const DEBUG_KEYS := ["level", "autoplay", "panel", "save", "lobby", "coins", "reset", "stop_at",
	"frames", "shots", "screenshot", "chain", "district", "boosters", "tutor"]

var years: Array = []                # newest first; slot 0 of the wheel is the blank
var _pos := 0.0                      # wheel position in rows (0 = blank)
var _drag_from := -1.0
var _drag_pos := 0.0
var _vel := 0.0
var _last_y := 0.0
var _snap: Tween
var _wheel: Control
var _play: Button
var _finished := false


## Should main.gd show the age screen now?
static func needed(args: Dictionary) -> bool:
	if args.has("age"):
		return true
	if DisplayServer.get_name() == "headless":
		return false
	for k in DEBUG_KEYS:
		if args.has(k):
			return false
	return Game.needs_age()


func _init(now_year := -1) -> void:
	if now_year < 0:
		now_year = int(Time.get_datetime_dict_from_system()["year"])
	years = Audience.wheel_years(now_year)


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = UiKit.SKY.darkened(0.35)
	UiKit.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var safe := Control.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)
	UiKit.safe_rect(safe)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 36)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(col)
	var card := UiKit.panel(UiKit.CREAM)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(card)
	_wheel = Control.new()
	_wheel.custom_minimum_size = Vector2(420, ROW_H * ROWS)
	_wheel.clip_contents = true
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.draw.connect(_draw_wheel)
	card.add_child(_wheel)
	_play = UiKit.icon_button("play", "green", 150, "round")
	_play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play.pressed.connect(confirm)
	col.add_child(_play)
	_refresh()


## The year in the middle of the wheel, or 0 on the blank slot.
func chosen_year() -> int:
	var i := int(round(_pos))
	return 0 if i <= 0 or i > years.size() else int(years[i - 1])


## Moves the wheel to `year` (tests, keyboard).
func select_year(year: int) -> void:
	var i := years.find(year)
	_pos = 0.0 if i < 0 else float(i + 1)
	_refresh()


func can_confirm() -> bool:
	return chosen_year() > 0


func confirm() -> void:
	if _finished or not can_confirm():
		return
	_finished = true
	Game.set_birth_year(chosen_year())
	done.emit()
	queue_free()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_step(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_step(-1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _in_wheel(mb.position):
				_begin_drag(mb.position.y)
			elif not mb.pressed and _drag_from >= 0.0:
				_end_drag()
	elif e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed and _in_wheel(st.position):
			_begin_drag(st.position.y)
		elif not st.pressed and _drag_from >= 0.0:
			_end_drag()
	elif (e is InputEventMouseMotion or e is InputEventScreenDrag) and _drag_from >= 0.0:
		var y: float = e.position.y
		_vel = (_last_y - y) / ROW_H
		_last_y = y
		_pos = clampf(_drag_pos + (_drag_from - y) / ROW_H, 0.0, float(years.size()))
		_refresh()


func _unhandled_key_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_down"):
		_step(1)
	elif e.is_action_pressed("ui_up"):
		_step(-1)
	elif e.is_action_pressed("ui_accept"):
		confirm()


func _in_wheel(p: Vector2) -> bool:
	return _wheel != null and Rect2(_wheel.global_position - global_position, _wheel.size).has_point(p)


func _begin_drag(y: float) -> void:
	if _snap:
		_snap.kill()
	_drag_from = y
	_last_y = y
	_drag_pos = _pos
	_vel = 0.0


func _end_drag() -> void:
	_drag_from = -1.0
	_snap_to(round(clampf(_pos + _vel * 6.0, 0.0, float(years.size()))))


func _step(d: int) -> void:
	_snap_to(clampf(round(_pos) + d, 0.0, float(years.size())))


func _snap_to(target: float) -> void:
	if _snap:
		_snap.kill()
	if not is_inside_tree():
		_pos = target
		_refresh()
		return
	_snap = create_tween()
	_snap.tween_method(_set_pos, _pos, target, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_pos(v: float) -> void:
	_pos = v
	_refresh()


func _refresh() -> void:
	if _wheel:
		_wheel.queue_redraw()
	if _play:
		var on := can_confirm()
		_play.disabled = not on
		_play.modulate = Color.WHITE if on else Color(1, 1, 1, 0.35)


func _draw_wheel() -> void:
	var w := _wheel.size.x
	var mid := _wheel.size.y * 0.5
	_wheel.draw_rect(Rect2(8, mid - ROW_H * 0.5, w - 16, ROW_H), Color(UiKit.YELLOW, 0.55))
	var first := maxi(int(floor(_pos)) - ROWS / 2 - 1, 0)
	var last := mini(int(ceil(_pos)) + ROWS / 2 + 1, years.size())
	for i in range(first, last + 1):
		var text: String = BLANK if i == 0 else str(years[i - 1])
		var y := mid + (i - _pos) * ROW_H
		var dist := absf(i - _pos)
		var fs := int(lerpf(78, 46, clampf(dist / 2.0, 0.0, 1.0)))
		var col := Color(UiKit.INK, clampf(1.0 - dist * 0.32, 0.15, 1.0))
		var ts := UiKit.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		_wheel.draw_string(UiKit.FONT, Vector2((w - ts.x) * 0.5, y + fs * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

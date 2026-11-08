class_name RevivePanel
extends RetentionPanel
## "So close": shown once per level when the squad is wiped out, before the loss screen.
## A road bar shows how far you got (flag at the finish, your squad marker at `progress`, the
## percent), the peak squad you reached, and one rewarded-ad button that brings back
## `troops` (= pct % of the peak, from units.json revive.pct, rounded up like
## LevelSim.revive_troops()). No countdown, no pressure: the X (give up) is always there.
## Signals: revive (the ad was watched to the end; call LevelSim.revive(troops)), give_up (X or
## back). `closed` follows either. Closing the ad early keeps the panel open.

signal revive
signal give_up

var progress := 0.0
var peak := 0
var troops := 0
var _revived := false


func _init(p := 0.0, peak_squad := 0, revive_troops := -1) -> void:
	progress = clampf(p, 0.0, 1.0)
	peak = maxi(peak_squad, 0)
	troops = revive_troops if revive_troops >= 0 else troops_for(peak)


## Troops a revive gives back for a peak squad: ceil(peak x pct / 100), at least 1.
static func troops_for(peak_squad: int, units: Dictionary = {}) -> int:
	var u: Dictionary = units if not units.is_empty() else Game.units
	var pct := float(u.get("revive", {}).get("pct", 50))
	return maxi(int(ceil(peak_squad * pct / 100.0)), 1)


func _ready() -> void:
	var col := _frame("", 0, "%d%%" % int(floor(progress * 100.0)), false, Color("3b6fd1"))
	# How far you got: squad marker on the road, flag at the end.
	var road := Control.new()
	road.custom_minimum_size = Vector2(0, 170)
	road.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(road)
	var bar := progress_bar(56, UiKit.YELLOW)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 20
	bar.offset_right = -96
	bar.offset_top = 90
	bar.offset_bottom = 146
	bar_set(bar, 0, 100, " ")
	road.add_child(bar)
	var flag := icon_safe(first_icon(["trophy_gold", "trophy"]), 92)
	flag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	flag.offset_left = -100
	flag.offset_right = -8
	flag.offset_top = 70
	flag.offset_bottom = 162
	road.add_child(flag)
	var marker := VBoxContainer.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_theme_constant_override("separation", 0)
	marker.size = Vector2(110, 90)
	road.add_child(marker)
	var m_icon := icon_safe(first_icon(["badge", "person"]), 76)
	m_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	marker.add_child(m_icon)
	# Peak squad and what the revive brings back.
	var peak_row := HBoxContainer.new()
	peak_row.alignment = BoxContainer.ALIGNMENT_CENTER
	peak_row.add_theme_constant_override("separation", 10)
	col.add_child(peak_row)
	peak_row.add_child(icon_safe(first_icon(["crown", "trophy"]), 70))
	peak_row.add_child(icon_safe(first_icon(["badge", "person"]), 70))
	peak_row.add_child(UiKit.label(str(peak), 72, Color.WHITE, 14))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	col.add_child(spacer)
	var ad := ad_button("revive", "+%d" % troops, Vector2(470, 160), first_icon(["badge", "person"]))
	ad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ad.pressed.connect(_on_revive)
	col.add_child(ad)
	_animate.call_deferred(bar, marker, road, ad)


func _animate(bar: ProgressBar, marker: Control, road: Control, ad: Button) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float):
		bar.value = v * 100.0
		var x := bar.position.x + bar.size.x * v
		marker.position = Vector2(x - marker.size.x * 0.5, bar.position.y - 82), 0.0, progress, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.2)
	tw.tween_callback(func(): pulse(ad, 0.05))
	sfx(["lose"], -6.0)


func _on_revive() -> void:
	if _revived:
		return
	watch_ad("revive", func(ok: bool):
		if ok and not _revived:
			_revived = true
			sfx(["rank_up", "recruit"])
			revive.emit()
			close())


func close() -> void:
	if not _closing and not _revived:
		give_up.emit()
	super.close()

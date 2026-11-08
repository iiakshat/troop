class_name ResultPanel
extends Control
## Level result. Win: trophy ribbon, the bottles you broke, the multiplier and coins
## counting up, Next / Home. Loss: the icon of what beat you, a 3-word tip, Retry / Home.

signal next_pressed
signal retry_pressed
signal lobby_pressed
signal station_pressed

const LOSS := {
	"thug": ["thug", "GROW BIGGER"], "knifer": ["knife", "GROW EARLIER"],
	"brute": ["brute", "BRING INSPECTORS"], "gunman": ["shield", "SHIELD UP"],
	"riot": ["riot", "BOMB OR PIERCE"], "biker": ["speed", "KILL THEM FAST"],
	"boss": ["boss", "BUILD UP FIRST"], "gate": ["aim", "SHOOT RED GATES"],
	"barricade": ["aim", "SHOOT IT FIRST"], "car": ["police_car", "SHOOT IT FIRST"],
}


func _ready() -> void:
	UiKit.full_rect(self)
	visible = false


func show_win(level: int, r: Dictionary, has_next: bool) -> void:
	_clear()
	var col := _card()
	col.add_child(UiKit.ribbon("trophy", str(level)))
	var bottles := HBoxContainer.new()
	bottles.alignment = BoxContainer.ALIGNMENT_CENTER
	bottles.add_theme_constant_override("separation", 6)
	col.add_child(bottles)
	var total := int(r.get("broken", 0)) + int(r.get("gold", 0))
	for i in total:
		var gold := i >= int(r.get("broken", 0))
		bottles.add_child(UiKit.icon("broken_bottle", 70, UiKit.YELLOW if gold else Color("7dffb0")))
	var mult := float(r.get("mult", 1.0))
	col.add_child(UiKit.label("×%s" % BottleShot._fmt(mult), 72, UiKit.YELLOW, 16))
	var coins_row := HBoxContainer.new()
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coins_row.add_theme_constant_override("separation", 10)
	col.add_child(coins_row)
	coins_row.add_child(UiKit.icon("coin", 96, UiKit.YELLOW))
	var coin_label := UiKit.label("0", 104, Color.WHITE, 18)
	coins_row.add_child(coin_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	var home := UiKit.icon_button("home", "blue", 140)
	home.pressed.connect(func(): lobby_pressed.emit())
	row.add_child(home)
	var station := UiKit.icon_button("station", "blue", 140)
	station.pressed.connect(func(): station_pressed.emit())
	row.add_child(station)
	UiKit.set_alert(station, StationPanel.anything_affordable())
	if has_next:
		var nxt := UiKit.icon_button("play", "green", 140)
		nxt.custom_minimum_size.x = 220
		nxt.pressed.connect(func(): next_pressed.emit())
		row.add_child(nxt)
	_show()
	var coins := int(r.get("coins", 0))
	var tw := create_tween()
	tw.tween_method(func(v: float):
		coin_label.text = str(int(v))
		Sfx.play("coin", -8.0), 0.0, float(coins), 1.0).set_delay(0.35)


func show_loss(level: int, cause: String) -> void:
	_clear()
	var col := _card()
	var info: Array = LOSS.get(cause, ["person", "TRY AGAIN"])
	var rib := UiKit.ribbon("", str(level))
	col.add_child(rib)
	var ic := UiKit.icon(String(info[0]), 200, UiKit.RED)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	col.add_child(UiKit.label(String(info[1]), 52, Color.WHITE, 14))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	var home := UiKit.icon_button("home", "blue", 140)
	home.pressed.connect(func(): lobby_pressed.emit())
	row.add_child(home)
	var station := UiKit.icon_button("station", "blue", 140)
	station.pressed.connect(func(): station_pressed.emit())
	row.add_child(station)
	UiKit.set_alert(station, StationPanel.anything_affordable())
	var retry := UiKit.icon_button("retry", "green", 140)
	retry.custom_minimum_size.x = 220
	retry.pressed.connect(func(): retry_pressed.emit())
	row.add_child(retry)
	_show()


func _card() -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	UiKit.full_rect(dim)
	add_child(dim)
	var p := UiKit.panel(Color("3b6fd1"))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -330
	p.offset_right = 330
	p.offset_top = -380
	p.offset_bottom = 380
	add_child(p)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	p.add_child(col)
	return col


func _show() -> void:
	visible = true
	await get_tree().process_frame
	for c in get_children():
		if c is PanelContainer:
			UiKit.pop(c, 0.5)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	visible = false

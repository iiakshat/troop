class_name ResultPanel
extends Control
## Win (coins tally) or loss (why you lost + how to fix it) card.

signal next_pressed
signal retry_pressed
signal lobby_pressed

const LOSS_TIPS := {
	"thug": ["THE GANG WAS BIGGER", "Grow your squad before each fight.\nAdd first, then multiply."],
	"knifer": ["KNIFERS RUSHED YOU", "They're fast: you get less time to shoot.\nGrow bigger before they arrive."],
	"brute": ["ARMOUR BEAT YOU", "Pistols and knives can't hurt brutes.\nTake INSPECTORS or NO ARMOUR gates."],
	"gunman": ["GUNMEN PICKED YOU OFF", "Tap SHIELD when gunmen stop to shoot."],
	"gate": ["A RED GATE GOT YOU", "Stay in a red gate's lane early\nand shoot it until it flips."],
	"barricade": ["BARRICADE!", "Shoot barricades down before you reach them."],
}


func show_win(level: int, troops: int, mult: int, coins: int, has_next: bool) -> void:
	_clear()
	var p := _card()
	var col: VBoxContainer = p.get_child(0)
	col.add_child(UiKit.label("LEVEL %d CLEAR!" % level, 70, UiKit.GOLD, 14))
	col.add_child(UiKit.label("%d TROOPS  ×%d" % [troops, mult], 46))
	var coin_label := UiKit.label("+0", 96, UiKit.GOLD, 16)
	col.add_child(coin_label)
	col.add_child(UiKit.label("COINS", 34, Color("b8c2d6"), 6))
	var b1 := UiKit.button("NEXT LEVEL" if has_next else "LOBBY", UiKit.GREEN, 54, Vector2(0, 120))
	b1.pressed.connect(func(): (next_pressed if has_next else lobby_pressed).emit())
	col.add_child(b1)
	if has_next:
		var b2 := UiKit.button("UPGRADES", UiKit.BLUE, 40, Vector2(0, 96))
		b2.pressed.connect(func(): lobby_pressed.emit())
		col.add_child(b2)
	_show(p)
	# Count the coins up.
	var tw := create_tween()
	tw.tween_method(func(v: float):
		coin_label.text = "+%d" % int(v)
		Sfx.play("coin", -6.0), 0.0, float(coins), 0.9).set_delay(0.3)


func show_loss(level: int, cause: String) -> void:
	_clear()
	var p := _card()
	var col: VBoxContainer = p.get_child(0)
	var tip: Array = LOSS_TIPS.get(cause, ["DEFEATED", "Plan your gates before the fight."])
	col.add_child(UiKit.label("DEFEATED", 84, UiKit.RED, 16))
	col.add_child(UiKit.label(tip[0], 46))
	var why := UiKit.label(tip[1], 34, Color("d6deeb"), 6)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(why)
	var b1 := UiKit.button("TRY AGAIN", UiKit.GREEN, 54, Vector2(0, 120))
	b1.pressed.connect(func(): retry_pressed.emit())
	col.add_child(b1)
	var b2 := UiKit.button("LOBBY", UiKit.BLUE, 40, Vector2(0, 96))
	b2.pressed.connect(func(): lobby_pressed.emit())
	col.add_child(b2)
	_show(p)


func _ready() -> void:
	UiKit.full_rect(self)
	visible = false


func _card() -> PanelContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	UiKit.full_rect(dim)
	add_child(dim)
	var p := UiKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(600, 0)
	p.offset_left = -300
	p.offset_right = 300
	p.offset_top = -330
	p.offset_bottom = 330
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(col)
	return p


func _show(p: Control) -> void:
	add_child(p)
	visible = true
	await get_tree().process_frame
	UiKit.pop(p, 0.5)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	visible = false

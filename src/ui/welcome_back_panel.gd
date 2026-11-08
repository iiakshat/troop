class_name WelcomeBackPanel
extends RetentionPanel
## Welcome back: what the rebuilt city earned while you were away (a clock, the city hall and
## the coins), with two choices: collect, or x2 via a rewarded ad. The panel collects itself
## (Game.city_collect(mult)), flies the coins into the pill, then emits collect(mult) and
## collected(coins) and closes. The caller must NOT call city_collect again (it would be
## harmless: the storage is already empty). The X closes without collecting: the coins stay
## in the city storage, nothing is lost.

signal collect(mult: int)
signal collected(coins: int)

var coins := 0
var _done := false
var _amount: Label


func _init(c := 0) -> void:
	coins = maxi(c, 0)


func _ready() -> void:
	var col := _frame(first_icon(["city_hall", "station"]), 0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	row.add_child(icon_safe("clock", 96))
	row.add_child(icon_safe(first_icon(["city_hall", "station"]), 150))
	var amt := HBoxContainer.new()
	amt.alignment = BoxContainer.ALIGNMENT_CENTER
	amt.add_theme_constant_override("separation", 10)
	col.add_child(amt)
	amt.add_child(icon_safe("coin", 110))
	_amount = UiKit.label(num(coins), 110, Color.WHITE, 18)
	amt.add_child(_amount)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	col.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	col.add_child(buttons)
	var take := UiKit.icon_button("coin", "yellow", 140)
	take.custom_minimum_size.x = 210
	take.pressed.connect(_collect.bind(1))
	buttons.add_child(take)
	var ad := ad_button("x2_offline", "×2", Vector2(300, 140))
	ad.pressed.connect(func(): watch_ad("x2_offline", func(ok: bool):
		if ok:
			_collect(2)))
	buttons.add_child(ad)
	pulse(ad, 0.05)


func _collect(mult: int) -> void:
	if _done:
		return
	_done = true
	var got := Game.city_collect(mult)
	_amount.text = num(got)
	if mult > 1:
		UiKit.pop(_amount, 1.4)
		burst(centre(_amount), 14)
	sfx(["collect", "coin_bag", "coin"])
	fly("coin", centre(_amount), centre(_coin_pill), 12)
	collect.emit(mult)
	collected.emit(got)
	after(1.0, close)

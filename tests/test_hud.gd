extends "res://tests/test_case.gd"
## HUD numbers (spec v2 §12.4): big troop counts and the live firepower use NumFormat.


func test_troops_and_firepower_use_short_numbers() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := Hud.new()
	tree.root.add_child(hud)
	if not hud.is_node_ready():
		hud._ready()
	hud.set_troops(12345)
	eq((hud._troops.get_meta("label") as Label).text, "12.3K", "troop count")
	hud.set_troops(9999)
	eq((hud._troops.get_meta("label") as Label).text, "9,999", "in full up to 9,999")
	hud.set_firepower(1250000)
	eq(hud.firepower_text(), "1.25M", "firepower")
	hud.set_firepower(37)
	eq(hud.firepower_text(), "37", "small firepower")
	hud.set_firepower(3.2)
	eq(hud.firepower_text(), Economy.fmt_power(3.2), "the lobby's Squad Power format (one decimal below 100)")
	eq(hud.firepower_text(), "3.2", "a +0.2 knife step shows in the level too")
	check(hud._power.get_parent() == hud._troops.get_parent(), "firepower sits next to the troop count")
	tree.root.remove_child(hud)
	hud.free()

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


## Owner play-test: every change of the squad's firepower shows as a small green +N / red -N
## under the number for 2.5 s; changes within that time add up; the tap heat alone shows none.
func test_firepower_change_shows_plus_or_minus_under_it() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := Hud.new()
	tree.root.add_child(hud)
	if not hud.is_node_ready():
		hud._ready()
	hud.set_firepower(40, 40)
	eq(hud.firepower_delta_text(), "", "the level's first number: no hint")
	hud.set_firepower(50, 50)
	eq(hud.firepower_delta_text(), "+10", "a gate worth +10")
	eq(hud._power_delta.get_theme_color("font_color"), PowerDelta.UP, "green")
	hud.set_firepower(47, 47)
	eq(hud.firepower_delta_text(), "+7", "changes within the window add up")
	hud.set_firepower(45.5, 47)
	eq(hud.firepower_delta_text(), "+7", "the hero cooling down (tap heat) shows nothing")
	hud._power_delta._process(PowerDelta.HOLD + PowerDelta.FADE + 0.1)
	eq(hud.firepower_delta_text(), "", "gone after its time")
	hud.set_firepower(30, 31.5)
	eq(hud.firepower_delta_text(), "-15.5", "a loss, in the pill's format")
	eq(hud._power_delta.get_theme_color("font_color"), PowerDelta.DOWN, "red")
	hud.set_firepower(46, 47)
	eq(hud.firepower_delta_text(), "", "back to where it was: the hint hides")
	hud.set_firepower(12000, 12047)
	eq(hud.firepower_delta_text(), "+12K", "big numbers use 12K / 1.25M")
	tree.root.remove_child(hud)
	hud.free()


func test_steady_power_is_the_firepower_at_full_tap_rate() -> void:
	var sim := LevelSim.new(Config.level(1), Config.units())
	sim.squad.hero_rate = 0.4
	var cold := sim.live_power()
	var steady := Hud.steady_power(sim)
	near(sim.squad.hero_rate, 0.4, "the sim is left as it was")
	near(sim.live_power(), cold, "its live power too")
	sim.squad.hero_rate = 1.0
	near(steady, sim.live_power(), "steady = the hero at full rate")
	check(steady > cold, "a cold hero fires less")

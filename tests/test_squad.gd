extends "res://tests/test_case.gd"


func _squad(c := 0, i := 0) -> Squad:
	var s := Squad.new()
	s.add("constable", c)
	s.add("inspector", i)
	return s


func test_multiply_is_exact() -> void:
	for n in [0, 1, 5, 10, 33]:
		for k in [2, 3]:
			var s := _squad(n, 2)
			var before := s.total()
			s.multiply(k)
			eq(s.total(), before * k, "x%d of %d" % [k, before])
			eq(s.count("hero"), 1, "hero stays one")


func test_multiply_doubles_inspectors() -> void:
	var s := _squad(3, 1)
	s.multiply(2)
	eq(s.count("inspector"), 2, "inspectors doubled")
	eq(s.count("constable"), 7, "constables doubled plus hero's recruit")


func test_operation_order_matters() -> void:
	var a := _squad(7)  # 8 troops
	a.add("constable", 10)
	a.multiply(2)
	var b := _squad(7)
	b.multiply(2)
	b.add("constable", 10)
	eq(a.total(), 36, "(8+10)x2")
	eq(b.total(), 26, "8x2+10")


func test_losses_take_lowest_rank_first() -> void:
	var s := _squad(2, 1)
	eq(s.lose(3), 3, "lost three")
	eq(s.count("constable"), 0, "constables gone first")
	eq(s.count("inspector"), 0, "then inspectors")
	check(s.hero_alive(), "hero falls last")
	s.lose(5)
	check(not s.hero_alive(), "hero dead")
	eq(s.total(), 0, "nothing left")


func test_percent_and_divide_round_down() -> void:
	var s := _squad(20)  # 21
	eq(s.apply_percent(-30), -6, "-30% of 21 loses 6")
	eq(s.total(), 15, "15 left")
	eq(s.apply_percent(50), 7, "+50% of 15 adds 7")
	var d := _squad(20)
	d.divide(2)
	eq(d.total(), 10, "21 / 2 = 10")
	var h := _squad()
	h.divide(2)
	eq(h.total(), 1, "hero never divided away")


func test_armour_and_pierce() -> void:
	var stats := {"hero": {"dmg": 1, "rate": 2.0}, "constable": {"dmg": 1, "rate": 1.0},
		"inspector": {"dmg": 3, "rate": 1.0, "pierce": true}}
	var s := _squad(10)
	eq(s.dps(stats, {}, 0), 12.0, "no armour")
	eq(s.dps(stats, {}, 1), 6.0, "armour 1 halves pistols and knife")
	s.add("inspector", 1)
	eq(s.dps(stats, {}, 1), 9.0, "inspector pierces")


func test_cap_limits_growth() -> void:
	var s := _squad(10)
	s.cap = 30
	eq(s.add("constable", 50), 19, "only room for 19 more")
	eq(s.total(), 30, "full")
	s.lose(10)
	s.multiply(3)
	eq(s.total(), 30, "x3 of 20 stops at the cap")
	eq(s.count("hero"), 1, "hero kept")


func test_value_line_comes_from_config() -> void:
	var stats: Dictionary = Config.units()["allies"]
	eq(Squad.value_vs_constable(stats, "constable"), 1.0, "constable = 1")
	for rank in ["sergeant", "inspector", "swat", "sniper", "commando"]:
		var u: Dictionary = stats[rank]
		var want := float(u["dmg"]) * float(u["rate"]) * float(u.get("multi", 1)) * float(u.get("splash", 1))
		want /= float(stats["constable"]["dmg"]) * float(stats["constable"]["rate"])
		check(absf(Squad.value_vs_constable(stats, rank) - want) < 1e-6, "%s value line from config" % rank)
	# Against one armoured boss the sniper is worth far more than against a crowd.
	var vs_boss := Squad.value_vs_constable(stats, "sniper", 360.0, 1, 1)
	check(vs_boss >= 2.0 * Squad.value_vs_constable(stats, "sniper"), "sniper shines vs bosses (%.1f)" % vs_boss)
	eq(Squad.value_vs_constable(stats, "nobody"), 0.0, "unknown rank = 0")


func test_commando_splash_hits_up_to_five() -> void:
	var stats: Dictionary = Config.units()["allies"]
	var s := Squad.new()
	s.counts["hero"] = 0
	s.add("commando", 1)
	var one := float(stats["commando"]["dmg"]) * float(stats["commando"]["rate"])
	var splash := int(stats["commando"]["splash"])
	eq(s.dps(stats, {}, 0, 1.0, 100), one * splash, "full splash into a crowd")
	eq(s.dps(stats, {}, 0, 1.0, 3), one * 3.0, "never more hits than enemies")
	eq(s.dps(stats, {}, 0, 1.0, 1), one, "one target, one hit")


func test_new_ranks_are_lost_before_the_hero() -> void:
	var s := Squad.new()
	s.add("commando", 2)
	s.add("sniper", 1)
	s.add("sergeant", 3)
	eq(s.lose(4), 4, "lost 4")
	eq(s.count("sergeant"), 0, "sergeants first")
	eq(s.count("sniper"), 0, "then snipers")
	eq(s.count("commando"), 2, "commandos outrank snipers")
	eq(s.count("hero"), 1, "hero last")

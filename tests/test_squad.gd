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


# ---------------------------------------------------------------- formation (v1.1 spatial hits)

func test_slot_troops_sum_to_the_squad() -> void:
	for total in [1, 2, 7, 72, 73, 150]:
		var n := Squad.figures(total, 72)
		eq(n, mini(total, 72), "figures for %d" % total)
		var sum := 0
		for i in n:
			var t := Squad.slot_troops(i, n, total)
			check(t >= 1, "every slot carries someone (%d of %d)" % [i, total])
			sum += t
		eq(sum, total, "slots carry exactly %d" % total)


func test_formation_never_wider_than_the_cap() -> void:
	for n in [2, 5, 20, 40, 72]:
		for i in n:
			check(absf(Squad.slot_offset(i, n, 1.25).x) <= 1.25 + 1e-4, "slot %d of %d inside 1.25 m" % [i, n])
	eq(Squad.slot_offset(0, 30, 1.25), Vector2(0.0, -0.5), "the hero leads from the centre")


func test_footprint_hits_only_the_overlap_up_to_capacity() -> void:
	# A 40-strong squad centred on a 2.6 m obstacle: many overlap, the capacity caps the loss.
	var full := Squad.footprint_hits(40, 72, 0.0, 0.0, 1.3, 0.2, 100, 1.25)
	eq(int(full["overlap"]), 40, "centred on a wide footprint: everyone overlaps")
	eq(int(full["lost"]), 40, "capacity 100 takes them all")
	var capped := Squad.footprint_hits(40, 72, 0.0, 0.0, 1.3, 0.2, 6, 1.25)
	eq(int(capped["lost"]), 6, "capacity 6 takes exactly 6")
	eq((capped["slots"] as Array).size(), 6, "six figures fall")
	# Squad in the next lane: an obstacle 2.8 m away never touches it.
	var clear := Squad.footprint_hits(40, 72, 2.8, 0.0, 1.3, 0.2, 100, 1.25)
	eq(int(clear["lost"]), 0, "centred in the next lane: untouched")
	# Half past the obstacle: about half the squad, never all of it.
	var half := Squad.footprint_hits(40, 72, 1.4, 0.0, 1.3, 0.2, 100, 1.25)
	check(int(half["lost"]) > 5 and int(half["lost"]) < 35, "half past: part of the squad (%d)" % int(half["lost"]))
	# Big squads: slots carry several troops each, still exact.
	var big := Squad.footprint_hits(150, 72, 0.0, 0.0, 0.6, 0.2, 1000, 1.25)
	check(int(big["lost"]) == int(big["overlap"]), "uncapped: the loss is the overlap")
	check(int(big["lost"]) < 150 and int(big["lost"]) > 0, "a narrow barrel hits part of 150 (%d)" % int(big["lost"]))
	# Nearest first: the slots that die are the ones closest to the footprint's centre.
	var near := Squad.footprint_hits(40, 72, 1.0, 0.0, 1.3, 0.2, 3, 1.25)
	for i in (near["slots"] as Array):
		check(Squad.slot_offset(int(i), 40, 1.25).x + 1.0 <= 1.0, "hit slots sit on the obstacle's side")


func test_firepower_is_nominal_dps_with_the_hero_tap_rate() -> void:
	# Spec v2 §12.4: damage per second against a plain unarmoured crowd, every rank at its
	# best (bursts, splash, a sniper round's full damage), the hero at his current tap rate.
	var stats: Dictionary = Config.units()["allies"]
	var weapons: Dictionary = Config.units()["hero_weapons"]
	var s := Squad.new()
	s.hero_rate = 0.4
	check(absf(s.firepower(stats, weapons) - 1.0 * 3.0 * 0.4) < 1e-6, "a cold hero alone: knife x 40%")
	s.hero_rate = 1.0
	check(absf(s.firepower(stats, weapons) - 3.0) < 1e-6, "a hot hero: full knife rate")
	s.add("constable", 10)
	check(absf(s.firepower(stats, weapons) - (3.0 + 16.0)) < 1e-6, "+10 constables x 1.6")
	s.add("swat", 1)
	s.add("commando", 1)
	s.add("sniper", 1)
	var want := 3.0 + 16.0 + 1.0 * 3.2 * 2.0 + 2.0 * 0.96 * 5.0 + 16.0 * 0.4
	check(absf(s.firepower(stats, weapons) - want) < 1e-6, "burst, splash and sniper rounds at their best (%.2f vs %.2f)" % [s.firepower(stats, weapons), want])
	s.hero_weapon = "pistol"
	s.hero_rate = 0.5
	var with_gun := s.firepower(stats, weapons)
	check(absf(with_gun - (want - 1.5 + 2.0 * 3.0 * 0.5)) < 1e-6, "a held pistol fires at the hero's tap rate too")
	s.lose(10)
	check(s.firepower(stats, weapons) < with_gun, "losses drop it")

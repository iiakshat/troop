extends "res://tests/test_case.gd"
## City rules: districts, build timers, offline income, storage cap, clock going backwards.

var eco := Config.economy()
const T0 := 1_800_000_000


func _save(unlocked := 1, stars := {}) -> Dictionary:
	var s := SaveData.migrate({}, eco)
	s["unlocked"] = unlocked
	s["stars"] = stars
	return s


func _built(s: Dictionary, id: String, lv: int, at := T0) -> void:
	s["city"][id] = {"lv": lv, "built_at": at - 10, "ready_at": at - 5}


func test_districts() -> void:
	var s := _save()
	check(City.district_reached(s, 1, eco), "district 1 open from the start")
	check(not City.district_liberated(s, 1, eco), "not liberated yet")
	check(not City.district_reached(s, 2, eco), "district 2 not reached")
	s["stars"] = {"10": 1}
	check(City.district_liberated(s, 1, eco), "boss beaten = liberated")
	check(City.district_reached(s, 2, eco), "district 2 reached")
	eq(City.districts_liberated(s, eco), 1, "one liberated")
	s["stars"]["50"] = 2
	eq(City.districts_liberated(s, eco), 1, "counted in a row from the first")
	eq(City.buildings_in(1, eco), ["cafe", "newsstand", "pharmacy", "bus_stop", "police_post"], "district 1 buildings")
	eq(City.ids(eco).size(), 25, "25 ids")


func test_costs_times_income() -> void:
	var b: Dictionary = eco["city"]["buildings"]["cafe"]
	eq(City.cost("cafe", 1, eco), int(b["cost"]), "rebuild cost")
	eq(City.cost("cafe", 2, eco), Economy.round_price(float(b["cost"]) * float(eco["city"]["upgrade_cost_mult"][1]), eco), "upgrade cost")
	eq(City.cost("cafe", 5, eco), -1, "past max")
	eq(City.cost("nope", 1, eco), -1, "unknown")
	eq(City.income_at("cafe", 0, eco), 0.0, "ruin earns nothing")
	eq(City.income_at("cafe", 1, eco), float(b["income"]), "base income")
	check(absf(City.income_at("cafe", 3, eco) - float(b["income"]) * 1.6 * 1.6) < 1e-6, "x1.6 per upgrade")
	check(City.build_time("cafe", 2, eco) > City.build_time("cafe", 1, eco), "upgrades take longer")
	check(City.build_time("city_hall", 4, eco) <= int(eco["city"]["max_build_seconds"]), "build time capped")
	var prev := 0
	for id in City.ids(eco):
		var c := City.cost(id, 1, eco)
		check(c > prev, id + " costs more than the one before")
		prev = c


func test_build_flow_and_status() -> void:
	var s := _save()
	eq(City.status(s, "cafe", T0, eco), "ruin", "cafe starts ruined")
	eq(City.status(s, "bakery", T0, eco), "locked", "district 2 locked")
	eq(City.can_start(s, "bakery", T0, eco), "locked", "cannot build locked")
	check(City.start_build(s, "cafe", T0, eco), "rebuild starts")
	eq(City.status(s, "cafe", T0 + 1, eco), "building", "under construction")
	var bt := City.build_time("cafe", 1, eco)
	eq(City.remaining(s, "cafe", T0 + 10), bt - 10, "the cafe's timer")
	eq(City.level(s, "cafe", T0 + 10), 0, "earns at lv 0 while rebuilding")
	check(not City.is_ready(s, "cafe", T0 + bt - 1), "not ready a second early")
	check(City.is_ready(s, "cafe", T0 + bt), "ready on time")
	eq(City.level(s, "cafe", T0 + bt), 1, "lv 1 when done")
	var pre := City.pre_liberation_max(eco)
	s["city"]["cafe"] = {"lv": pre, "built_at": T0, "ready_at": T0 + 30}
	eq(City.status(s, "cafe", T0 + 30, eco), "upgrade_locked", "upgrades past pre_liberation_max_level need the district liberated")
	check(not City.start_build(s, "cafe", T0 + 30, eco), "no upgrade past the cap before liberation")
	s["stars"] = {"10": 1}
	eq(City.status(s, "cafe", T0 + 30, eco), "built", "upgradable after the boss")
	check(City.start_build(s, "cafe", T0 + 30, eco), "upgrade starts")
	eq(City.level(s, "cafe", T0 + 31), pre, "keeps earning at its old level while upgrading")
	eq(City.newly_finished(s, T0 + 31, T0 + 31 + City.build_time("cafe", pre + 1, eco)), ["cafe"], "finish detected")
	s["city"]["cafe"] = {"lv": 4, "built_at": T0, "ready_at": T0}
	eq(City.status(s, "cafe", T0 + 1, eco), "maxed", "maxed")
	eq(City.next_cost(s, "cafe", eco), -1, "no next cost")


func test_builder_limit() -> void:
	var s := _save()
	var n := int(eco["city"]["max_parallel_builds"])
	var ids := City.buildings_in(1, eco)
	for i in n:
		check(City.start_build(s, ids[i], T0, eco), "builder %d" % i)
	eq(City.builders_free(s, T0, eco), 0, "all busy")
	eq(City.can_start(s, ids[n], T0, eco), "builders", "waits for a builder")
	check(not City.start_build(s, ids[n], T0, eco), "no extra builder")
	check(City.start_build(s, ids[n], T0 + 100000, eco), "free again later")


func test_offline_income_is_exact_and_capped() -> void:
	var s := _save()
	_built(s, "cafe", 1)
	_built(s, "newsstand", 1)
	s["city_collected_at"] = T0
	var per_h := City.income_at("cafe", 1, eco) + City.income_at("newsstand", 1, eco)
	eq(City.income_per_hour(s, T0, eco), per_h, "income per hour")
	eq(City.pending_income(s, T0 + 3600, eco), floori(per_h), "one hour")
	eq(City.pending_income(s, T0 + 1800, eco), floori(per_h / 2.0), "half an hour")
	var cap_h := float(eco["city"]["storage"]["base_hours"])
	eq(City.storage_cap_hours(s, T0, eco), cap_h, "3 h storage")
	eq(City.pending_income(s, T0 + 100 * 3600, eco), floori(per_h * cap_h), "capped at storage")
	var got := City.collect(s, T0 + 2 * 3600, eco)
	eq(got, floori(per_h * 2), "collected two hours")
	eq(City.pending_income(s, T0 + 2 * 3600, eco), 0, "empty after collecting")
	eq(int(s["city_collected_at"]), T0 + 2 * 3600, "clock restarted")


func test_city_hall_adds_storage() -> void:
	var s := _save()
	_built(s, "city_hall", 2)
	var st: Dictionary = eco["city"]["storage"]
	eq(City.storage_cap_hours(s, T0, eco), float(st["base_hours"]) + 2.0 * float(st["hours_per_level"]), "+1 h per City Hall level")


func test_clock_moving_back_never_goes_negative() -> void:
	var s := _save()
	_built(s, "cafe", 1)
	s["city_collected_at"] = T0
	eq(City.pending_income(s, T0 - 5000, eco), 0, "nothing when the clock is behind")
	eq(City.accrued(s, T0, T0 - 100, eco), 0.0, "accrued never negative")
	eq(City.collect(s, T0 - 60, eco), 0, "collect behind gives 0")
	eq(int(s["city_collected_at"]), T0, "small step back keeps the clock")
	eq(City.collect(s, T0 - 100 * 3600, eco), 0, "far behind gives 0")
	eq(int(s["city_collected_at"]), T0 - 100 * 3600, "far step back resyncs")
	# a running timer never shows more than its full length
	check(City.start_build(s, "newsstand", T0, eco), "build")
	eq(City.remaining(s, "newsstand", T0 - 9999), City.build_time("newsstand", 1, eco), "remaining clamped")


func test_income_during_and_after_construction() -> void:
	var s := _save(11, {"10": 1})
	_built(s, "cafe", 1)
	s["city_collected_at"] = T0
	var lv1 := City.income_at("cafe", 1, eco)
	var lv2 := City.income_at("cafe", 2, eco)
	check(City.start_build(s, "cafe", T0 + 3600, eco), "upgrade after an hour")
	check(absf(float(s["city_bank"]) - lv1) < 1e-6, "first hour banked at lv 1")
	var t_done := T0 + 3600 + City.build_time("cafe", 2, eco)
	var expect := lv1 + lv1 * (t_done - T0 - 3600) / 3600.0 + lv2 * 0.5
	eq(City.pending_income(s, t_done + 1800, eco), floori(expect), "lv 1 until done, lv 2 after")


func test_speed_up() -> void:
	var s := _save(41, {"10": 1, "20": 1, "30": 1, "40": 1})
	check(City.start_build(s, "city_hall", T0, eco), "build")
	var full := City.build_time("city_hall", 1, eco)
	var cut := City.speedup_seconds(s, "city_hall", T0, eco)
	eq(cut, mini(maxi(ceili(full * 0.5), int(eco["city"]["speedup_ad"]["min_seconds"])), full), "half or min, never past done")
	check(cut > 0 and cut < full, "a real cut")
	eq(City.speed_up(s, "city_hall", T0, cut, eco), cut, "taken off")
	eq(City.remaining(s, "city_hall", T0), full - cut, "timer shorter")
	eq(City.speed_up(s, "city_hall", T0, 999999, eco), full - cut, "never past done")
	check(City.is_ready(s, "city_hall", T0), "done")


func test_pending_split_by_building() -> void:
	var s := _save()
	_built(s, "cafe", 1)
	_built(s, "police_post", 1)
	s["city_collected_at"] = T0
	var parts := City.pending_by_building(s, T0 + 3600, eco)
	check(parts.has("cafe") and parts.has("police_post"), "both have bubbles")
	check(int(parts["police_post"]) > int(parts["cafe"]), "bigger earner, bigger bubble")
	check(int(parts["cafe"]) + int(parts["police_post"]) <= City.pending_income(s, T0 + 3600, eco), "never more than pending")

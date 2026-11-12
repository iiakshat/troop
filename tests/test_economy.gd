extends "res://tests/test_case.gd"
## Economy formulas and the shape of config/economy.json.

var eco := Config.economy()

const SPEC_BUILDINGS := [
	["cafe", "newsstand", "pharmacy", "bus_stop", "police_post"],
	["fruit_market", "bakery", "barber", "cinema", "clinic"],
	["fish_market", "warehouse", "lighthouse", "diner", "ferry"],
	["factory", "power_station", "garage", "train_station", "fire_station"],
	["hotel", "bank", "museum", "fountain_park", "city_hall"],
]


func test_round_price() -> void:
	eq(Economy.round_price(61.0, eco), 60, "below 100 to 5")
	eq(Economy.round_price(63.0, eco), 65, "below 100 to 5 (up)")
	eq(Economy.round_price(1234.0, eco), 1250, "below 10000 to 50")
	eq(Economy.round_price(456.0, eco), 460, "below 1000 to 10")
	eq(Economy.round_price(12345.0, eco), 12300, "else to 100")


func test_districts_and_bosses() -> void:
	eq(Economy.district_of(1, eco), 1, "L1 district 1")
	eq(Economy.district_of(10, eco), 1, "L10 district 1")
	eq(Economy.district_of(11, eco), 2, "L11 district 2")
	eq(Economy.district_of(50, eco), 5, "L50 district 5")
	check(Economy.is_boss(10, eco) and Economy.is_boss(50, eco), "every 10th is a boss")
	check(not Economy.is_boss(9, eco), "L9 not a boss")
	eq(Economy.district_count(eco), 5, "5 districts")


func test_level_coin_curve() -> void:
	var c: Dictionary = eco["level_coins"]
	eq(Economy.level_coin_mult(1, eco), float(c["base"]), "L1 = base")
	check(absf(Economy.level_coin_mult(2, eco) - (float(c["base"]) + float(c["per_level"]))) < 1e-9, "+per_level each level")
	var prev := 0.0
	for L in range(1, 51):
		var m := Economy.reward_scale(L, eco)
		check(m > prev, "curve rises at L%d" % L)
		prev = m
	check(Economy.level_coin_mult(10, eco) > Economy.level_coin_mult(11, eco), "boss level pays more than the next")
	# about +3% a level: slow
	check(Economy.reward_scale(50, eco) < 4.0, "curve stays slow")


func test_level_reward() -> void:
	eq(Economy.level_reward(1, 200, false, eco), 200, "L1 first clear = finale coins")
	var r2 := Economy.level_reward(2, 200, false, eco)
	eq(r2, int(round(200 * Economy.level_coin_mult(2, eco))), "L2 curve")
	eq(Economy.level_reward(2, 200, true, eco), int(round(200 * Economy.level_coin_mult(2, eco) * float(eco["level_coins"]["replay_mult"]))), "replay pays less")
	eq(Economy.level_reward(10, 100, false, eco), int(round(100 * Economy.reward_scale(10, eco) * float(eco["level_coins"]["boss_mult"]))), "boss bonus")
	eq(Economy.level_reward(5, -40, false, eco), 0, "never negative")


func test_station_costs_and_gates() -> void:
	for room in eco["station_order"]:
		var r: Dictionary = eco["station"][room]
		var mx := int(r["max"])
		check(mx >= 1 and mx <= 10, room + " has up to 10 levels")
		eq(Economy.station_requirement(room, 1, eco), 0, room + " level 1 open")
		var prev_cost := 0
		var prev_req := 0
		for lv in range(1, mx + 1):
			var c := Economy.station_cost(room, lv, eco)
			check(c > prev_cost, "%s lv%d costs more than the last" % [room, lv])
			var req := Economy.station_requirement(room, lv, eco)
			check(req >= prev_req and req <= 5, "%s lv%d gate rises" % [room, lv])
			prev_cost = c
			prev_req = req
		eq(Economy.station_cost(room, mx + 1, eco), -1, room + " past max")
		eq(Economy.station_cost(room, 0, eco), -1, room + " level 0 invalid")
	# geometric: cost(k) = base x growth^(k-1), rounded
	var a: Dictionary = eco["station"]["training"]
	eq(Economy.station_cost("training", 3, eco), Economy.round_price(float(a["base"]) * pow(float(a["growth"]), 2), eco), "geometric")
	eq(Economy.station_cost("nope", 1, eco), -1, "unknown room")


func test_stars_for_chests() -> void:
	var every := int(eco["stars"]["chest_every"])
	eq(every, 15, "chest every 15 stars")
	eq(Economy.stars_needed_for_chest(0, eco), 15, "first chest at 15")
	eq(Economy.stars_needed_for_chest(1, eco), 30, "second at 30")
	eq(Economy.stars_needed_for_chest(9, eco), 150, "tenth at 150 (all 3-starred)")


func test_city_config_matches_spec() -> void:
	var city: Dictionary = eco["city"]
	var districts: Array = city["districts"]
	eq(districts.size(), 5, "5 districts")
	var seen := {}
	for d in districts.size():
		eq(districts[d]["buildings"], SPEC_BUILDINGS[d], "district %d buildings" % (d + 1))
		for id in districts[d]["buildings"]:
			check(not seen.has(id), id + " listed once")
			seen[id] = true
			eq(int(city["buildings"][id]["district"]), d + 1, id + " district field")
	eq(city["buildings"].size(), 25, "25 buildings")
	eq(City.build_time("cafe", 1, eco), 30, "first build is 30 s")
	var last := City.build_time("city_hall", 1, eco)
	check(last >= 5400 and last <= 9000, "last rebuild about 2 h")
	eq((city["upgrade_cost_mult"] as Array).size(), City.max_level(eco), "a cost multiplier per level")
	eq(City.max_level(eco), 4, "rebuild + 3 upgrades")
	check(absf(float(city["income_mult"]) - 1.6) < 1e-9, "income x1.6 per upgrade")


func test_coins_get_scarcer_deeper_in() -> void:
	# What a district's first clears pay grows slower than what unlocks in it.
	var pay := []
	var buy := []
	for d in range(1, 6):
		var p := 0.0
		for L in range((d - 1) * 10 + 1, d * 10 + 1):
			p += Economy.level_coin_mult(L, eco)
		pay.append(p)
		var b := 0
		for room in eco["station"]:
			for lv in range(1, int(eco["station"][room]["max"]) + 1):
				if Economy.station_requirement(room, lv, eco) == d - 1:
					b += Economy.station_cost(room, lv, eco)
		for id in City.buildings_in(d, eco):
			b += City.cost(id, 1, eco)
		if d >= 2:
			for id in City.buildings_in(d - 1, eco):
				for lv in range(2, City.max_level(eco) + 1):
					b += City.cost(id, lv, eco)
		buy.append(b)
	for d in range(1, 5):
		var pay_growth: float = pay[d] / pay[d - 1]
		var buy_growth: float = float(buy[d]) / float(buy[d - 1])
		check(buy_growth > pay_growth, "district %d: prices grow faster than the curve (%.2f vs %.2f)" % [d + 1, buy_growth, pay_growth])


func test_reward_tables_are_sane() -> void:
	var days: Array = eco["daily"]["days"]
	eq(days.size(), 7, "7-day calendar")
	check(days[6].has("chest"), "day 7 is a chest")
	check(eco["chests"].has(String(days[6]["chest"])), "day 7 chest exists")
	var total := 0.0
	for s in eco["spin"]["slices"]:
		check(float(s["weight"]) > 0.0, "positive slice weight")
		total += float(s["weight"])
		if s["reward"].has("chest"):
			check(eco["chests"].has(String(s["reward"]["chest"])), "spin chest exists")
	check(total > 0.0, "spin has weight")
	eq(int(eco["spin"]["free_per_day"]), 1, "1 free spin a day")
	eq(int(eco["spin"]["ad_per_day"]), 3, "3 ad spins a day")
	check(eco["chests"].has(String(eco["missions"]["bonus_chest"])), "mission bonus chest exists")
	check(eco["chests"].has(String(eco["stars"]["chest"])), "star chest exists")
	var stats := {}
	for m in eco["missions"]["pool"]:
		check(int(m["goal"][0]) <= int(m["goal"][1]), m["id"] + " goal range")
		check(int(m["coins"]) > 0, m["id"] + " pays")
		stats[m["stat"]] = true
	check(stats.size() >= int(eco["missions"]["per_day"]), "enough distinct mission stats")
	for b in eco["boosters"]["order"]:
		check(SaveData.BOOSTERS.has(b) or SaveData.POWERS.has(b), b + " is a booster or a power")
	for p in ["x2_coins", "revive", "x2_offline", "spin", "booster_headstart", "booster_shield", "booster_bomb"]:
		check((eco["ads"]["placements"] as Array).has(p), "placement " + p)


func test_purchase_curve_holds() -> void:
	# v1.1 item 5: a typical player (tests/econ_model.gd) has 1-3 things to buy after nearly
	# every win, never nothing in the first three districts, and fewer buys deeper in.
	var Model = load("res://tests/econ_model.gd")
	var rows: Array = Model.run(eco, Config.load_json("res://config/finale.json"), Config.units())
	eq(rows.size(), Config.LEVEL_COUNT, "one row per level")
	var s: Dictionary = Model.summary(rows)
	check(float(s["in_band"]) >= 0.85, "1-3 buys after at least 85%% of wins (%.2f)" % float(s["in_band"]))
	for L in s["none"]:
		check(int(L) > 30, "something to buy after every win in districts 1-3 (none at L%d)" % int(L))
	var early := 0
	var late := 0
	for r in rows:
		if int(r["level"]) <= 20:
			early += int(r["buys"])
		elif int(r["level"]) > 30:
			late += int(r["buys"])
	check(late < early, "coins buy less deeper in (%d vs %d)" % [late, early])
	for r in rows:
		check(float(r["power"]) + 0.001 >= float(r["rec"]), "a spending player meets the recommended power at L%d" % (int(r["level"]) + 1))


## Plan v2 Task 13 / review focus 5: the levels are calibrated against the no-ad pace (the
## upgrades this model's player brings into each level). A player who earns only by playing
## (no ads, no city, no daily rewards) and buys only squad progress affords that pace at every
## level with at most 2 replays of the previous level, and a brand-new player has nothing at L1.
func test_no_ad_pace_reaches_every_level() -> void:
	var Model = load("res://tests/econ_model.gd")
	var rows: Array = Model.run(eco, Config.load_json("res://config/finale.json"), Config.units())
	var pc: Dictionary = Model.pace_check(rows)
	check((pc["fails"] as Array).is_empty(), "no_ad_pace_reaches_every_level (more than 2 replays at %s)" % str(pc["fails"]))
	var p1: Dictionary = Model.pace(rows)["1"]
	check((p1["armory"] as Dictionary).is_empty() and int(p1["squad"]) == 0, "level 1 is played with no upgrades")
	var p10: Dictionary = Model.pace(rows)["10"]
	check(not (p10["armory"] as Dictionary).is_empty(), "by level 10 the pace has weapon steps")


func test_squad_power_and_pointers() -> void:
	var units := Config.units()
	var hero: Dictionary = units["allies"]["hero"]
	var base := Economy.station_power({}, units, eco)
	near(base, float(hero["dmg"]) * float(hero["rate"]), "an empty station: the hero alone, at full tap rate")
	check(Economy.room_power_gain({}, "training", units, eco) > 0.0, "a starting constable adds firepower")
	for room in ["barracks", "evidence"]:
		near(Economy.room_power_gain({}, room, units, eco), 0.0, room + " adds no firepower at level start")
	var rec := Economy.recommended_power(1, eco)
	near(rec, base, "level 1 asks for no upgrades")
	var prev := 0.0
	for L in range(1, Config.LEVEL_COUNT + 1):
		var r := Economy.recommended_power(L, eco)
		check(r >= prev, "recommended power never drops (L%d)" % L)
		prev = r
	var save := SaveData.migrate({}, eco)
	save["coins"] = 0
	eq(Economy.best_purchase(save, 1_800_000_000, eco, units), {}, "nothing pointed at with no coins")
	save["coins"] = 100000
	var best := Economy.best_purchase(save, 1_800_000_000, eco, units)
	check(not best.is_empty() and best["kind"] != "cosmetic", "points at progress, never a cosmetic")
	var loss := Economy.best_upgrade_after_loss(save, eco, units)
	check(not loss.is_empty() and bool(loss["affordable"]) and float(loss["value"]) > 0.0, "a loss points at an affordable upgrade that adds firepower")


## Spec v2 section 12.4: Squad Power is the HUD's firepower unit: nominal damage per second
## against an unarmoured target of the squad a level starts with (the hero at full tap rate and
## the starting constables), with the Armory's multipliers. Nothing else is mixed in.
func test_squad_power_is_level_start_firepower() -> void:
	var units := Config.units()
	var hero: Dictionary = units["allies"]["hero"]
	var con: Dictionary = units["allies"]["constable"]
	var s := _armory_save(100000, 40)
	s["station"]["training"] = 3
	s["station"]["barracks"] = 2
	s["station"]["evidence"] = 2
	var want := float(hero["dmg"]) * float(hero["rate"]) + 3.0 * float(con["dmg"]) * float(con["rate"])
	near(Economy.save_power(s, units, eco), want, "hero + 3 starting constables; cap and coin bonus add nothing")
	near(Economy.firepower({"hero": 1, "constable": 3}, {}, units), want, "the same as firepower() of that squad")
	var swat: Dictionary = units["allies"]["swat"]
	near(Economy.firepower({"swat": 2}, {}, units), 2.0 * float(swat["dmg"]) * float(swat["rate"]) * float(swat.get("multi", 1)), "a burst counts every round")
	# A rank that joins during the level is not in the level-start number: its step adds no
	# Squad Power, but the pointer still values it (the squad a level builds).
	var p0 := Economy.save_power(s, units, eco)
	near(Economy.weapon_power_gain(s, "shotgun", units, eco), 0.0, "a sergeant step: no level-start firepower")
	var shot := _purchase(s, "weapon", "shotgun", units)
	check(float(shot.get("value", 0.0)) > 0.0, "but it has value for the pointer")
	Armory.buy(s, "shotgun")
	near(Economy.save_power(s, units, eco), p0, "Squad Power unchanged by the shotgun")
	var mult := Armory.next_stats(s, "knives")
	Armory.buy(s, "knives")
	var hero_dps := float(hero["dmg"]) * float(hero["rate"])
	near(Economy.save_power(s, units, eco), p0 + hero_dps * (float(mult["dmg_mult"]) * float(mult["rate_mult"]) - 1.0), "a knife step multiplies the hero's dps")
	eq(Economy.fmt_power(3.0), "3", "whole numbers plain")
	eq(Economy.fmt_power(3.36), "3.4", "one decimal below 100")
	eq(Economy.fmt_power(123.4), "123", "whole from 100")
	eq(Economy.fmt_power(9999.0), "9999", "in full up to 9,999")
	eq(Economy.fmt_power(12345.0), "12.3K", "then K")
	eq(Economy.fmt_power(1250000.0), "1.25M", "then M")


## Spec v2 calibration rule 6: the Codex's "= N constables" compares the player's upgraded stats.
func test_upgraded_allies_for_the_codex() -> void:
	var units := Config.units()
	var s := _armory_save(100000, 10)
	for i in 5:
		Armory.buy(s, "shotgun")
	var w: Dictionary = Armory.sim_upgrades(s)["weapons"]
	var up := Economy.upgraded_allies(units["allies"], w)
	var m: Dictionary = w["sergeant"]
	near(float(up["sergeant"]["dmg"]), float(units["allies"]["sergeant"]["dmg"]) * float(m["dmg_mult"]), "sergeant dmg upgraded")
	near(float(up["sergeant"]["rate"]), float(units["allies"]["sergeant"]["rate"]) * float(m["rate_mult"]), "sergeant rate upgraded")
	near(float(up["constable"]["dmg"]), float(units["allies"]["constable"]["dmg"]), "constable untouched")
	eq(float(units["allies"]["sergeant"]["dmg"]), 2.0, "the units table is not changed")
	check(CodexPanel.value_of(up, "sergeant") > CodexPanel.value_of(units["allies"], "sergeant"), "the Codex value grows with the shotgun")


func _purchase(s: Dictionary, kind: String, id: String, units: Dictionary) -> Dictionary:
	for p in Economy.purchases(s, 1_800_000_000, eco, units):
		if String(p["kind"]) == kind and String(p["id"]) == id:
			return p
	return {}


# ---------------------------------------------------------------- v2: the Armory in the economy

func _armory_save(coins: int, unlocked: int) -> Dictionary:
	var s := SaveData.migrate({}, eco)
	s["coins"] = coins
	s["unlocked"] = unlocked
	return s


func test_squad_power_counts_weapons() -> void:
	var units := Config.units()
	var s := _armory_save(100000, 10)
	var p0 := Economy.save_power(s, units, eco)
	near(p0, Economy.station_power({}, units, eco), "no weapon steps: the station's power")
	s["station"]["training"] = 4
	p0 = Economy.save_power(s, units, eco)
	for id in ["knives", "service_pistol"]:
		var g := Economy.weapon_power_gain(s, id, units, eco)
		check(g > 0.0, id + " step adds power (%.2f)" % g)
		Armory.buy(s, id)
		near(Economy.save_power(s, units, eco), p0 + g, id + ": the gain shown is the gain got")
		p0 = Economy.save_power(s, units, eco)
	near(Economy.weapon_power_gain(s, "finale_pistol", units, eco), 0.0, "Bottle Shot handling is not squad power")
	var fx := SaveData.effects(eco, s["station"])
	fx["weapons"] = Armory.sim_upgrades(s)["weapons"]
	near(Economy.squad_power(fx, units, eco), Economy.save_power(s, units, eco), "squad_power(fx with weapons) = save_power")


func test_best_purchase_can_be_a_weapon_step() -> void:
	var units := Config.units()
	var s := _armory_save(60, 2)
	var kinds := {}
	for p in Economy.purchases(s, 1_800_000_000, eco, units):
		kinds[String(p["kind"]) + ":" + String(p["id"])] = int(p["cost"])
	check(kinds.has("weapon:knives") and kinds.has("weapon:service_pistol"), "open weapon steps are for sale")
	check(not kinds.has("weapon:shotgun"), "a locked weapon is not for sale")
	eq(int(kinds.get("weapon:knives", -1)), Armory.next_cost(s, "knives"), "price = the track's next step")
	s["unlocked"] = 8   # under the recommended power at L8: progress first
	var best := Economy.best_purchase(s, 1_800_000_000, eco, units)
	eq(String(best.get("kind", "")), "weapon", "the best buy is a weapon step")
	check(float(best["value"]) > 0.0 and int(best["cost"]) <= 60, "it adds firepower and is affordable")
	# The pointer prefers the most firepower (in the squad a level builds) per coin across rooms
	# and weapons.
	s["coins"] = 5000
	best = Economy.best_purchase(s, 1_800_000_000, eco, units)
	var ratio := float(best["value"]) / float(best["cost"])
	for p in Economy.affordable(s, 1_800_000_000, eco, units):
		if p["kind"] == "room" or p["kind"] == "weapon":
			check(float(p["value"]) / float(p["cost"]) <= ratio + 0.0001, "%s:%s is not a better deal" % [p["kind"], p["id"]])


func test_loss_tip_points_at_weapon_when_it_helps_most() -> void:
	var units := Config.units()
	var s := _armory_save(400, 6)
	var tip := Economy.best_upgrade_after_loss(s, eco, units)
	eq(String(tip.get("kind", "")), "weapon", "a weapon step helps most early on")
	near(float(tip["gain"]), Economy.weapon_power_gain(s, String(tip["id"]), units, eco), "gain is that step's level-start power")
	check(float(tip["value"]) > 0.0, "and it adds firepower in the level")
	eq(String(tip["room"]), String(tip["id"]), "room key kept for the result screen")
	check(bool(tip["affordable"]), "affordable with 400 coins")
	# Every squad weapon maxed: the tip falls back to a station room.
	for id in Armory.ids():
		if not Armory.is_finale(String(id)):
			Armory.set_index(s, String(id), Armory.total_buys(String(id)))
	tip = Economy.best_upgrade_after_loss(s, eco, units)
	eq(String(tip.get("kind", "")), "room", "a room when no weapon step is left")

extends "res://tests/test_case.gd"
## Game autoload wrappers, on a private instance (not in the tree, never writes a file).

const GameScript := preload("res://src/autoload/game.gd")
const T0 := 1_800_000_000


func _game(raw: Variant = {}) -> Node:
	var g: Node = GameScript.new()
	g.save_path = ""
	g.clock_override = T0
	g.date_override = "2026-11-08"
	g.boot(raw)
	g.rng.seed = 42
	return g


func test_win_level_pays_curve_stars_and_stats() -> void:
	var g := _game()
	var coins_seen := []
	g.coins_changed.connect(func(c): coins_seen.append(c))
	var r: Dictionary = g.win_level(1, 200, 3, {"kill": 274, "bottle": 4}, {"troops": 42})
	eq(int(r["coins"]), 200, "L1 first clear pays the finale coins")
	check(bool(r["first_clear"]), "first clear")
	eq(int(r["stars"]), 3, "3 stars")
	eq(int(r["stars_gained"]), 3, "3 gained")
	eq(int(g.save["coins"]), 200, "coins added")
	eq(int(g.save["unlocked"]), 2, "next level unlocked")
	eq(int(g.save["stats"]["win"]), 1, "win counted")
	eq(int(g.save["stats"]["stars3"]), 1, "3-star counted")
	eq(int(g.save["stats"]["kill"]), 274, "kills counted")
	check(not coins_seen.is_empty(), "coins_changed emitted")
	var again: Dictionary = g.win_level(1, 200, 2)
	check(not bool(again["first_clear"]), "replay")
	eq(int(again["coins"]), g.level_reward(1, 200), "replay pays the replay rate")
	check(int(again["coins"]) < 200, "replays pay less")
	eq(int(again["stars"]), 3, "best stars kept")
	eq(int(again["stars_gained"]), 0, "nothing gained")
	g.free()


func test_liberating_a_district() -> void:
	var g := _game()
	for lv in range(1, 10):
		g.save["stars"][str(lv)] = 1
	var r: Dictionary = g.win_level(10, 100, 1)
	eq(int(r["liberated"]), 1, "boss win liberates district 1")
	check(g.district_liberated(1), "district 1 liberated")
	eq(g.districts_liberated(), 1, "count")
	g.free()


func test_star_chest() -> void:
	var g := _game()
	for lv in range(1, 6):
		g.save["stars"][str(lv)] = 3
	var p: Dictionary = g.star_chest_progress()
	eq(int(p["have"]), 15, "15 stars")
	check(bool(p["ready"]), "chest ready at 15")
	var before := int(g.save["coins"])
	var r: Dictionary = g.open_star_chest()
	eq(r["chest"], "star", "star chest")
	check(int(g.save["coins"]) > before, "coins given")
	eq(int(g.save["star_chests_opened"]), 1, "counted")
	check(not bool(g.star_chest_progress()["ready"]), "next at 30")
	eq(int(g.star_chest_progress()["need"]), 30, "need 30")
	eq(g.open_star_chest(), {}, "not twice")
	g.free()


func test_station_gated_by_district() -> void:
	var g := _game()
	g.save["coins"] = 100000
	check(g.buy_room("armory"), "lv 1")
	check(g.buy_room("armory"), "lv 2")
	check(g.buy_room("armory"), "lv 3 (v1.1: open in district 1)")
	eq(g.room_cost("armory"), -1, "lv 4 locked")
	var st: Dictionary = g.room_state("armory")
	eq(int(st["locked"]), 1, "needs district 1")
	check(int(st["cost"]) > 0 and not bool(st["can_buy"]), "price shown, cannot buy")
	check(not g.buy_room("armory"), "refused")
	g.save["stars"]["10"] = 1
	check(g.buy_room("armory"), "open after the boss")
	eq(g.room_level("armory"), 4, "lv 4")
	eq(int(g.save["stats"]["upgrade"]), 4, "upgrades counted for missions")
	g.free()


func test_boosters() -> void:
	var g := _game()
	var start := int(g.boosters()["bomb"])
	check(start >= 1, "starter bomb")
	check(g.use_booster("bomb"), "use")
	eq(int(g.boosters()["bomb"]), start - 1, "spent")
	g.save["boosters"]["shield"] = 1
	eq(g.use_boosters({"shield": 3, "headstart": 1}), {"shield": 1, "headstart": 1}, "spends only what exists")
	check(g.booster_ad_available("shield"), "ad booster available")
	check(g.grant_booster_ad("shield"), "granted after the ad")
	eq(int(g.boosters()["shield"]), 1, "token added")
	check(not g.booster_ad_available("shield"), "one ad per booster per level")
	check(not g.grant_booster_ad("shield"), "refused")
	check(g.booster_ad_available("bomb"), "other boosters still have their ad")
	g.level_started(1, {})
	check(g.booster_ad_available("shield"), "next level, next ad")
	var up: Dictionary = g.level_upgrades({"shield": 1, "bomb": 2, "headstart": 2})
	var base: Dictionary = g.upgrades()
	eq(int(up["shield"]), int(base["shield"]) + 1, "shield charge added")
	eq(int(up["bomb"]), int(base["bomb"]) + 2, "bomb charges added")
	eq(int(up["headstart"]), 2, "headstart count")
	eq(int(up["headstart_troops"]), 2 * int(g.economy["boosters"]["headstart"]["troops"]), "headstart troops")
	g.free()


func test_city_through_game() -> void:
	var g := _game()
	g.save["coins"] = 1000
	var city_events := [0]
	g.city_changed.connect(func(): city_events[0] += 1)
	check(not g.start_build("bakery"), "district 2 locked")
	check(g.start_build("cafe"), "rebuild the cafe")
	eq(int(g.save["coins"]), 1000 - City.cost("cafe", 1, g.economy), "paid")
	eq(String(g.building_state("cafe")["status"]), "building", "building")
	check(city_events[0] >= 1, "city_changed")
	eq(int(g.save["stats"]["build"]), 1, "build counted")
	var inc := City.income_at("cafe", 1, g.economy)
	var t := T0 + 30 + 3600
	eq(g.city_pending(t), floori(inc), "an hour of income after the build")
	eq(g.welcome_back(t), floori(inc) if floori(inc) >= 20 else 0, "welcome back threshold")
	var got: int = g.city_collect(2, t)
	eq(got, floori(inc) * 2, "x2 after the ad")
	eq(int(g.save["stats"]["city_coins"]), got, "collected coins counted")
	eq(g.city_pending(t), 0, "storage empty")
	g.save["coins"] = 0
	check(not g.start_build("newsstand", t), "cannot afford")
	g.free()


func test_daily_through_game() -> void:
	var g := _game()
	var st: Dictionary = g.daily_state()
	check(bool(st["can_claim"]), "claimable")
	eq((st["rewards"] as Array).size(), 7, "7 rewards shown")
	var r: Dictionary = g.claim_daily()
	eq(int(r["coins"]), Economy.round_price(float(g.economy["daily"]["days"][0]["coins"]) * Economy.reward_scale(1, g.economy), g.economy), "day 1 coins")
	eq(int(g.save["coins"]), int(r["coins"]), "coins added")
	eq(g.claim_daily(), {}, "once a day")
	g.date_override = "2026-11-09"
	var before := int(g.boosters()["headstart"])
	g.claim_daily()
	eq(int(g.boosters()["headstart"]), before + 1, "day 2 headstart")
	g.free()


func test_missions_through_game() -> void:
	var g := _game()
	var list: Array = g.missions()
	eq(list.size(), int(g.economy["missions"]["per_day"]), "today's missions")
	var done_events := []
	g.mission_completed.connect(func(i): done_events.append(i))
	var m: Dictionary = list[0]
	g.record_stat(String(m["stat"]), int(m["goal"]))
	eq(done_events, [0], "mission_completed")
	var coins := int(g.save["coins"])
	var r: Dictionary = g.claim_mission(0)
	eq(int(g.save["coins"]), coins + int(r["coins"]), "reward added")
	eq(g.claim_mission(0), {}, "once")
	for i in range(1, list.size()):
		g.record_stat(String(list[i]["stat"]), int(list[i]["goal"]))
		g.claim_mission(i)
	check(g.mission_bonus_ready(), "bonus ready")
	var b: Dictionary = g.claim_mission_bonus()
	eq(b["chest"], String(g.economy["missions"]["bonus_chest"]), "bonus chest")
	g.free()


func test_new_day_pays_unclaimed_missions() -> void:
	var g := _game()
	var list: Array = g.missions()
	g.record_stat(String(list[0]["stat"]), int(list[0]["goal"]))
	var coins := int(g.save["coins"])
	g.date_override = "2026-11-09"
	g.refresh_day()
	check(int(g.save["coins"]) > coins, "finished work is paid on the next day")
	eq(String(g.save["missions"]["date"]), "2026-11-09", "new missions rolled")
	g.free()


func test_spin_through_game() -> void:
	var g := _game()
	var st: Dictionary = g.spin_state()
	check(bool(st["can_free"]) and not bool(st["can_ad"]), "free first")
	eq((st["probabilities"] as Array).size(), Spin.slices(g.economy).size(), "odds for every slice")
	var r: Dictionary = g.spin_free()
	check(r.has("index") and r.has("reward"), "landed")
	eq(g.spin_free(), {}, "one free spin")
	for i in int(g.economy["spin"]["ad_per_day"]):
		check(not g.spin_ad().is_empty(), "ad spin %d" % i)
	eq(g.spin_ad(), {}, "ad spins used up")
	eq(int(g.save["stats"]["spin"]), 1 + int(g.economy["spin"]["ad_per_day"]), "spins counted")
	g.free()


func test_alerts_and_ranks() -> void:
	var g := _game()
	var a: Dictionary = g.alerts()
	for k in ["daily", "missions", "spin", "star_chest", "station", "city"]:
		check(a.has(k), "alert " + k)
	check(bool(a["daily"]) and bool(a["spin"]), "new player has a daily and a spin")
	check(not bool(a["station"]), "nothing affordable with 0 coins")
	g.save["coins"] = 500
	check(bool(g.alerts()["station"]) and bool(g.alerts()["city"]), "affordable things flagged")
	check(g.mark_rank_seen("sergeant"), "first time")
	check(not g.mark_rank_seen("sergeant"), "only once")
	check(g.rank_seen("sergeant"), "remembered")
	g.free()


func test_existing_api_still_works() -> void:
	var g := _game()
	g.add_coins(300)
	check(g.spend(100), "spend")
	check(not g.spend(1000), "cannot overspend")
	eq(int(g.save["coins"]), 200, "coins")
	g.complete_level(1)
	eq(int(g.save["unlocked"]), 2, "complete_level")
	g.add_coins(1000)
	check(g.pick_cosmetic("knives", "fire"), "buy a knife")
	eq(g.knife_skin()["id"], "fire", "equipped")
	check(g.owns("fire") and not g.owns("golden"), "owns")
	g.mark_hint("swipe")
	check(g.hint_seen("swipe"), "hint")
	check(g.upgrades().has("knife") and g.coin_bonus() == 0.0, "upgrades")
	g.free()


func test_rank_card_due_once_and_improvements() -> void:
	var g := _game()
	eq(g.rank_card_due(1), "", "no card at level 1")
	eq(g.rank_card_due(3), "", "none before the sergeant")
	eq(g.rank_card_due(4), "sergeant", "sergeant card before level 4")
	g.mark_rank_card("sergeant")
	eq(g.rank_card_due(4), "", "shown once")
	eq(g.rank_card_due(8), "inspector", "next rank later")
	g.mark_rank_seen("inspector")
	eq(g.rank_card_due(8), "", "a rank already met in a level needs no card")
	g.save["coins"] = 100000
	var p0: int = g.squad_power()
	check(g.buy_room("armory") and g.buy_room("armory"), "two armory levels")
	check(g.squad_power() > p0, "Squad Power grew")
	eq(g.take_improvements(), [{"room": "armory", "before": 0, "after": 2}], "one line per room, first before to last after")
	eq(g.take_improvements(), [], "cleared once taken")
	g.free()

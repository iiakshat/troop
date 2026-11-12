extends "res://tests/test_case.gd"
## Retention UI: the pure helpers (honest wheel geometry, calendar cell states, revive troops,
## codex value lines) and a smoke test that every panel builds and closes cleanly on a fresh
## in-memory save (the Game autoload never writes under the test runner).


func _econ() -> Dictionary:
	return Config.economy()


func test_wheel_slices_are_exactly_the_odds() -> void:
	var e := _econ()
	var probs := []
	for i in Spin.slices(e).size():
		probs.append(Spin.probability(i, e))
	var b := SpinPanel.slice_bounds(probs)
	eq(b.size(), probs.size(), "one slice per reward")
	check(is_equal_approx(float(b[0][0]), 0.0), "first slice starts at the pointer")
	check(is_equal_approx(float(b[b.size() - 1][1]), TAU), "slices fill the circle exactly")
	for i in b.size():
		var span := float(b[i][1]) - float(b[i][0])
		check(is_equal_approx(span, float(probs[i]) * TAU), "slice %d angle = its chance x 360" % i)
		var w := float(Spin.slices(e)[i]["weight"]) / Spin.total_weight(e)
		check(is_equal_approx(span / TAU, w), "slice %d share = weight / total" % i)


func test_wheel_lands_inside_the_picked_slice() -> void:
	var e := _econ()
	var probs := []
	for i in Spin.slices(e).size():
		probs.append(Spin.probability(i, e))
	for i in probs.size():
		for from in [0.0, 1.3, 5.9, 40.2]:
			for t in [0.2, 0.5, 0.8]:
				var r := SpinPanel.target_rotation(probs, i, from, 5, t)
				check(r >= from + 5 * TAU - 0.001, "at least 5 full turns")
				check(r < from + 6 * TAU + 0.001, "less than 6 turns")
				eq(SpinPanel.slice_at(probs, r), i, "lands in slice %d (from %s, t %s)" % [i, from, t])


func test_daily_cell_states() -> void:
	eq(DailyPanel.cell_states({"can_claim": true, "day": 1}, 7), ["today", "future", "future", "future", "future", "future", "future"], "new player")
	eq(DailyPanel.cell_states({"can_claim": true, "day": 4}, 7), ["claimed", "claimed", "claimed", "today", "future", "future", "future"], "day 4 to claim")
	eq(DailyPanel.cell_states({"can_claim": false, "day": 4}, 7), ["claimed", "claimed", "claimed", "claimed", "next", "future", "future"], "day 4 claimed today")
	eq(DailyPanel.cell_states({"can_claim": false, "day": 7}, 7), ["claimed", "claimed", "claimed", "claimed", "claimed", "claimed", "claimed"], "week done")
	eq(DailyPanel.cell_states({"can_claim": true, "day": 1, "missed": true}, 7)[0], "today", "missed streak starts over at day 1")


func test_revive_troops_round_up() -> void:
	var u := {"revive": {"pct": 50}}
	eq(RevivePanel.troops_for(64, u), 32, "half of 64")
	eq(RevivePanel.troops_for(5, u), 3, "ceil(2.5)")
	eq(RevivePanel.troops_for(0, u), 1, "at least 1")
	eq(RevivePanel.troops_for(10, {"revive": {"pct": 30}}), 3, "pct from config")


func test_codex_value_lines() -> void:
	var stats := {
		"constable": {"dmg": 1, "rate": 1.6},
		"sergeant": {"dmg": 2, "rate": 1.6},
		"swat": {"dmg": 1, "rate": 3.2, "multi": 2},
		"commando": {"dmg": 2, "rate": 0.96, "splash": 5},
		"odd": {"dmg": 1, "rate": 2.4},
	}
	eq(CodexPanel.value_text(stats, "constable"), "= 1", "constable is the unit")
	eq(CodexPanel.value_text(stats, "sergeant"), "= 2", "double damage")
	eq(CodexPanel.value_text(stats, "swat"), "= 4", "burst counts")
	eq(CodexPanel.value_text(stats, "commando"), "= 6", "splash counts")
	eq(CodexPanel.value_text(stats, "odd"), "= 1.5", "fractions keep one decimal")
	eq(CodexPanel.value_text(stats, "hero"), "", "hero has no value line")
	eq(CodexPanel.specials({"pierce": true, "target": "toughest"}), ["aim", "armour_pierce"], "sniper specials")
	eq(CodexPanel.unlock_level({"unlock": 21}), 21, "unlock level from config")
	eq(CodexPanel.unlock_level({}), 1, "default unlock")
	# Every ally in the real config gets a positive value.
	var allies: Dictionary = Config.units()["allies"]
	for id in allies:
		if id != "hero":
			check(CodexPanel.value_of(allies, String(id)) > 0.0, "%s has a value" % id)


func test_reward_items() -> void:
	var items := RetentionPanel.reward_items({"coins": 250, "shield": 1, "bomb": 2})
	eq(items, [["coin", "250"], ["shield", "×1"], ["bomb", "×2"]], "coins then boosters")
	eq(RetentionPanel.clock_text(3725), "1:02:05", "clock with hours")
	eq(RetentionPanel.clock_text(65), "1:05", "clock under an hour")
	eq(RetentionPanel.num(12345), "12.3K", "short number")


## Adds a node to the root and makes sure _ready ran (during the runner's _initialize the root
## is not ready yet, so Godot would defer it).
func _add(tree: SceneTree, n: Node) -> void:
	tree.root.add_child(n)
	if not n.is_node_ready() and n.has_method("_ready"):
		n._ready()


func test_panels_build_and_close() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({})
	var panels: Array = [
		DailyPanel.new(), MissionsPanel.new(), SpinPanel.new(), BoosterPanel.new(10),
		RevivePanel.new(0.8, 40), CodexPanel.new(), StarChestPanel.new(), WelcomeBackPanel.new(500),
		RankUnlockPanel.new("sergeant"),
	]
	for p in panels:
		var name: String = (p.get_script() as Script).get_global_name()
		var closed := [false]
		p.closed.connect(func(): closed[0] = true)
		_add(tree, p)
		check(p.get_child_count() >= 2, "%s built its frame" % name)
		check(is_instance_valid(p._close_btn) and p._close_btn.visible, "%s has a visible close button" % name)
		p._close_btn.pressed.emit()
		check(closed[0], "%s emits closed on X" % name)
		check(p.is_queued_for_deletion(), "%s frees itself" % name)
		tree.root.remove_child(p)
		p.free()
	# Daily claim through the panel pays day 1 and turns into the timer.
	var d := DailyPanel.new()
	_add(tree, d)
	var before := int(game.save["coins"])
	d._on_claim()
	check(int(game.save["coins"]) >= before, "day 1 paid")
	check(not d._claim.visible, "claim button gives way to the timer")
	tree.root.remove_child(d)
	d.free()
	# Booster panel: head start is picked and spent; shield and bomb are powers (v2): they come
	# along by themselves, show the recharge countdown, and an ad refills a recharging one.
	game.save["boosters"] = {"headstart": 1}
	game.save["powers"] = {"shield": {"stored": 0, "ready_at": 0, "used": 0}, "bomb": {"stored": 2, "ready_at": 0, "used": 0}}
	game.use_power("shield")
	var bp := BoosterPanel.new(3)
	var got := [{}]
	bp.start.connect(func(b): got[0] = b)
	_add(tree, bp)
	bp._toggle("bomb")     # a power: not a token to pick
	bp._toggle("headstart")
	eq(bp.power_count("bomb"), 3, "bomb card counts 1 free + 2 stored")
	eq(bp.power_count("shield"), 0, "the free shield is recharging")
	check(bp.power_timer_text("shield") != "", "the shield card shows its countdown")
	eq(bp.power_timer_text("bomb"), "", "no countdown while the free bomb is ready")
	check(bp.power_refill_visible("shield") and not bp.power_refill_visible("bomb"), "ad refill only for the recharging power")
	bp._on_play()
	eq(got[0], {"headstart": 1}, "start sends the head start that was spent")
	eq(int(game.save["boosters"]["headstart"]), 0, "head-start token spent")
	eq(int(game.save["powers"]["bomb"]["stored"]), 2, "picking does not spend powers")
	tree.root.remove_child(bp)
	bp.free()
	# Revive: X gives up exactly once.
	var rv := RevivePanel.new(0.5, 20)
	var gave := [0]
	rv.give_up.connect(func(): gave[0] += 1)
	_add(tree, rv)
	eq(rv.troops, 10, "revive troops from peak")
	rv.close()
	rv.close()
	eq(gave[0], 1, "give_up once")
	tree.root.remove_child(rv)
	rv.free()
	# Result screen builds both layouts.
	var res := ResultPanel.new()
	_add(tree, res)
	res.show_win(3, {"coins": 120, "stars": 3, "broken": 2, "gold": 1, "mult": 2.0}, true)
	check(res.visible, "win shows")
	res.show_loss(3, "pothole", 0.7, 30)
	check(res.visible, "loss shows")
	tree.root.remove_child(res)
	res.free()
	# Rank toast for a real rank, none for an unknown id.
	var holder := Control.new()
	_add(tree, holder)
	check(RankToast.show(holder, "constable") != null, "toast for a rank")
	check(RankToast.show(holder, "nobody") == null, "no toast for unknown ids")
	tree.root.remove_child(holder)
	holder.free()
	game.save = keep
	game.save_path = keep_path


func test_codex_sorted_by_value_and_one_rank_icon() -> void:
	var allies: Dictionary = Config.units()["allies"]
	var ids := CodexPanel.ranks_by_value(allies)
	eq(ids.size(), allies.size(), "every rank listed")
	eq(String(ids[0]), "hero", "hero first")
	for i in range(2, ids.size()):
		check(CodexPanel.value_of(allies, String(ids[i - 1])) <= CodexPanel.value_of(allies, String(ids[i])), "sorted by value at %s" % ids[i])
	for id in allies:
		var ic := CodexPanel.rank_icon(String(id))
		check(RetentionPanel.has_icon(ic), "%s has an icon (%s)" % [id, ic])
	eq(CodexPanel.rank_icon("sniper"), "rank_sniper", "sniper uses the v1.1 headgear icon")


func test_map_power_hint() -> void:
	eq(CityMap.power_hint("beaten", 3, 5, 200, 100), {"show": false, "warn": false}, "beaten: nothing")
	eq(CityMap.power_hint("current", 5, 5, 200, 100), {"show": true, "warn": true}, "current, under: warns")
	eq(CityMap.power_hint("locked", 7, 5, 90, 100), {"show": true, "warn": false}, "ahead, strong enough")
	eq(CityMap.power_hint("locked", 7, 5, 200, 100)["warn"], false, "two ahead never warns")
	eq(CityMap.power_hint("locked", 6, 5, 110, 100)["warn"], false, "a small gap does not warn")
	eq(CityMap.power_hint("locked", 6, 5, 120, 100)["warn"], true, "the next node warns on a real gap")
	eq(CityMap.power_hint("current", 5, 5, 200, 100, true)["warn"], false, "no warning under the first-build pointer")
	eq(CityMap.power_hint("locked", 5 + CityMap.POWER_AHEAD + 1, 5, 90, 100)["show"], false, "not too far ahead")


func test_armory_panel_shows_lock_and_level() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({})
	game.save["unlocked"] = 1
	game.save["coins"] = 5000
	var ap := ArmoryPanel.new()
	var closed := [false]
	ap.closed.connect(func(): closed[0] = true)
	_add(tree, ap)
	eq(ap.card_ids(), Armory.ids(), "one card per weapon track, in config order")
	check(ap.is_card_locked("shotgun"), "the shotgun is locked at level 1")
	eq(ap.lock_text("shotgun"), str(Armory.unlock_level("shotgun")), "its card shows the unlock level number")
	check(ap.lock_icon_visible("shotgun"), "and the lock icon")
	check(not ap.is_card_locked("knives") and not ap.lock_icon_visible("knives"), "knives are open")
	eq(ap.pips_filled("knives"), 0, "no steps yet")
	eq(ap.name_text("knives"), String(Armory.tier_info("knives", 1)["name"]), "tier 1 name shown")
	check(ap.calibre_text("knives") != "", "with its calibre")
	ap.buy("knives")
	eq(game.weapon_level("knives"), Vector2i(1, 1), "bought one step")
	eq(ap.pips_filled("knives"), 1, "one pip filled")
	for i in 4:
		ap.buy("knives")
	eq(game.weapon_level("knives"), Vector2i(2, 0), "the 5th buy evolved the knife")
	eq(ap.name_text("knives"), String(Armory.tier_info("knives", 2)["name"]), "the new tier's name")
	eq(ap.pips_filled("knives"), 0, "the bar starts again")
	check(ap.art_path("knives").ends_with("knives_t2.png"), "the new tier's art")
	ap.buy("shotgun")
	eq(game.weapon_level("shotgun"), Vector2i(1, 0), "a locked weapon is not bought")
	ap._close()
	check(closed[0], "closed emitted")
	tree.root.remove_child(ap)
	ap.free()
	game.save = keep
	game.save_path = keep_path


func test_style_panel_sells_hero_outfit() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({})
	game.save["coins"] = 1000
	for o in game.economy["cosmetics"]["outfits"]:
		check(o.has("shirt") and o.has("pants"), "%s recolours shirt and pants" % o["id"])
		if int(o["price"]) > 0:
			check(String(o.get("accessory", "")) != "", "%s comes with an accessory" % o["id"])
			check(HeroAccessory.KINDS.has(String(o["accessory"])), "%s accessory can be built" % o["id"])
	var sp := StylePanel.new()
	_add(tree, sp)
	var price := SaveData.cosmetic(game.economy, "outfits", "tracksuit")["price"] as int
	check(sp.accessory_icon_visible("tracksuit"), "the card shows the outfit's accessory")
	sp._pick("outfits", "tracksuit")
	eq(int(game.save["coins"]), 1000 - price, "paid for the outfit")
	check(game.owns("tracksuit"), "owned")
	eq(String(game.save["outfit"]), "tracksuit", "and worn")
	eq(String(game.outfit()["accessory"]), String(SaveData.cosmetic(game.economy, "outfits", "tracksuit")["accessory"]), "the level gets its accessory")
	game.save["coins"] = 10
	sp._pick("outfits", "gold")
	check(not game.owns("gold"), "cannot buy without coins")
	eq(String(game.save["outfit"]), "tracksuit", "still wearing the tracksuit")
	tree.root.remove_child(sp)
	sp.free()
	game.save = keep
	game.save_path = keep_path

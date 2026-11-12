extends "res://tests/test_case.gd"
## Armory (spec v2 section 6): weapon tracks, steps, evolutions, prices, locks and what the
## sim and Bottle Shot get from them.

var cfg := Config.armory()
var units := Config.units()


func _save(coins := 100000, unlocked := 50) -> Dictionary:
	var s := SaveData.default_save()
	s["coins"] = coins
	s["unlocked"] = unlocked
	return s


func test_buy_steps_then_evolve() -> void:
	var s := _save()
	eq(Armory.level(s, "service_pistol", cfg), Vector2i(1, 0), "everyone starts at tier 1 step 0")
	var before := float(Armory.stats(s, "service_pistol", cfg)["dmg_mult"])
	var last := {}
	for i in 4:
		last = Armory.buy(s, "service_pistol", cfg)
		check(bool(last["ok"]), "step %d bought" % (i + 1))
		check(not bool(last["evolved"]), "steps 1-4 do not evolve")
	eq(Armory.level(s, "service_pistol", cfg), Vector2i(1, 4), "4 steps filled")
	var mid := float(Armory.stats(s, "service_pistol", cfg)["dmg_mult"])
	check(mid > before, "each step adds a little")
	last = Armory.buy(s, "service_pistol", cfg)
	check(bool(last["evolved"]), "the 5th buy evolves")
	eq(Vector2i(int(last["tier"]), int(last["step"])), Vector2i(2, 0), "tier 2 step 0")
	var after := float(Armory.stats(s, "service_pistol", cfg)["dmg_mult"])
	check(after - mid > mid - before, "the evolution is a jump, bigger than the 4 steps together (%s -> %s -> %s)" % [before, mid, after])


func test_buy_to_max() -> void:
	var s := _save(10000000)
	var n := 0
	while Armory.buy(s, "knives", cfg)["ok"]:
		n += 1
		if n > 100:
			break
	var t: Dictionary = cfg["tracks"]["knives"]
	eq(n, (t["tiers"] as Array).size() * int(t["steps_per_tier"]), "every tier's bar fills once")
	check(Armory.is_maxed(s, "knives", cfg), "maxed")
	eq(Armory.next_cost(s, "knives", cfg), -1, "no price when maxed")


func test_locked_until_unlock_level() -> void:
	check(Armory.is_locked("shotgun", 3, cfg), "sergeant shotgun locked before L4")
	check(not Armory.is_locked("shotgun", 4, cfg), "open from L4")
	check(not Armory.is_locked("knives", 1, cfg), "knives open from the start")
	check(Armory.is_locked("finale_bow", 20, cfg), "bow locked before district 3")
	var s := _save(100000, 3)
	var r := Armory.buy(s, "shotgun", cfg)
	check(not bool(r["ok"]), "cannot buy a locked weapon")
	eq(int(s["coins"]), 100000, "no coins spent")


func test_cannot_buy_without_coins() -> void:
	var s := _save(5)
	var r := Armory.buy(s, "knives", cfg)
	check(not bool(r["ok"]), "too poor")
	eq(int(s["coins"]), 5, "coins unchanged")
	eq(Armory.level(s, "knives", cfg), Vector2i(1, 0), "nothing bought")
	s["coins"] = Armory.next_cost(s, "knives", cfg)
	check(bool(Armory.buy(s, "knives", cfg)["ok"]), "exact price is enough")
	eq(int(s["coins"]), 0, "price spent exactly")


func test_costs_rise_monotonically() -> void:
	for id in cfg["order"]:
		var t: Dictionary = cfg["tracks"][id]
		var prev := 0
		for tier in range(1, (t["tiers"] as Array).size() + 1):
			for step in int(t["steps_per_tier"]):
				var c := Armory.cost(String(id), tier, step, cfg)
				check(c > 0, "%s t%d s%d has a price" % [id, tier, step])
				check(c >= prev, "%s t%d s%d price never drops (%d < %d)" % [id, tier, step, c, prev])
				prev = c
		check(prev > Armory.cost(String(id), 1, 0, cfg), id + " the last buy costs more than the first")


func test_every_weapon_has_a_track() -> void:
	var owners := []
	for id in cfg["order"]:
		owners.append(String(cfg["tracks"][id]["owner"]))
	for rank in units["allies"]:
		check(owners.has(rank), rank + " has a weapon track")
	for w in ["pistol", "bow", "stars", "sniper"]:
		check(owners.has("finale_" + w), "Bottle Shot " + w + " has a track")
	for id in cfg["order"]:
		var t: Dictionary = cfg["tracks"][id]
		var owner := String(t["owner"])
		if units["allies"].has(owner):
			eq(int(t["unlock_level"]), int(units["allies"][owner]["unlock"]), id + " unlocks with its rank")
		for tier in t["tiers"]:
			check(String(tier["name"]) != "" and String(tier["calibre"]) != "", id + " tier has a name and calibre")
			check(String(tier["art"]).begins_with("armory/"), id + " tier art path")


func test_sim_upgrades_change_damage_not_counts() -> void:
	var s := _save()
	for i in 5:
		Armory.buy(s, "service_pistol", cfg)
	var up := Armory.sim_upgrades(s, cfg)
	var w: Dictionary = up["weapons"]
	check(w.has("constable"), "constable multipliers present")
	check(not w.has("finale_pistol"), "Bottle Shot tracks never reach the sim")
	var plain := Armory.sim_upgrades(_save(), cfg)
	var lvl := Config.level(5)
	var a := LevelSim.new(lvl, units, plain)
	var b := LevelSim.new(lvl, units, up)
	eq(b.squad.total(), a.squad.total(), "same start")
	a.squad.add("constable", 12)
	b.squad.add("constable", 12)
	eq(b.squad.total(), a.squad.total(), "+12 gate adds exactly 12 either way")
	var da := Squad.hit_value(a.stats["constable"], 0, 2.0)
	var db := Squad.hit_value(b.stats["constable"], 0, 2.0)
	check(db > da, "constable dps higher with pistol tier 2 (%s vs %s)" % [db, da])
	eq(float(b.stats["hero"]["dmg"]), float(a.stats["hero"]["dmg"]), "hero untouched by the pistol track")
	# Gate arithmetic through a whole run stays exact.
	var gate_lvl := {"events": [{"at": 20, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 7}]}, {"at": 60, "type": "finish"}]}
	eq(Autopilot.run(gate_lvl, units, [1], up)["troops"], Autopilot.run(gate_lvl, units, [1], plain)["troops"], "+7 gate gives the same squad")


func test_finale_extra_changes_handling() -> void:
	var s := _save()
	eq(Armory.finale_extra(s, "pistol", cfg), {}, "nothing bought = no change")
	for i in 5:
		Armory.buy(s, "finale_pistol", cfg)
	var fin: Dictionary = Config.load_json("res://config/finale.json")
	var out := Armory.apply_finale(fin, s, cfg)
	var base: Dictionary = fin["weapons"]["pistol"]
	var up: Dictionary = out["weapons"]["pistol"]
	eq(int(up["mag"]), int(base["mag"]) + 1, "tier 2 pistol: one more round")
	check(float(up["kick_deg"]) < float(base["kick_deg"]), "less kick")
	eq(float(up["hit_radius"]), float(base["hit_radius"]), "no aim assist")
	eq(float(fin["weapons"]["pistol"]["kick_deg"]), float(base["kick_deg"]), "the input config is not changed")


func test_no_brand_names() -> void:
	var banned := ["glock", "desert eagle", "mp5", "ak-47", "ak47", "colt", "beretta", "remington", "barrett",
		"uzi", "sig", "s&w", "smith", "winchester", "ruger", "python", "cobra", "viper", "m16", "m4", "hk", "kalash"]
	for id in cfg["order"]:
		for tier in cfg["tracks"][id]["tiers"]:
			var words := (String(tier["name"]) + " " + String(tier["calibre"])).to_lower()
			for b in banned:
				for w in words.split(" "):
					check(w != b and not (b.length() > 3 and words.contains(b)), "%s: %s contains %s" % [id, tier["name"], b])

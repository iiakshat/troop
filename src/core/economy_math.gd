class_name Economy
extends RefCounted
## Pure economy formulas over config/economy.json: level coin curve, police-station prices
## and district gates, star chests, clean price rounding. Every function takes the economy
## dictionary as an optional last argument; when it is left out the file is loaded once and
## cached. Tested in tests/test_economy.gd.

static var _cache: Dictionary = {}


static func cfg(economy: Dictionary = {}) -> Dictionary:
	if not economy.is_empty():
		return economy
	if _cache.is_empty():
		_cache = Config.economy()
	return _cache


# ---------------------------------------------------------------- rounding

## Rounds a raw price or reward to a clean number (below 100 to 5, below 1000 to 10, ...).
static func round_price(x: float, economy: Dictionary = {}) -> int:
	var steps: Array = cfg(economy).get("price_round", {}).get("steps", [])
	for s in steps:
		if x < float(s[0]):
			var step := float(s[1])
			return int(round(x / step) * step)
	return int(round(x))


# ---------------------------------------------------------------- levels and districts

static func district_levels(economy: Dictionary = {}) -> int:
	return int(cfg(economy).get("city", {}).get("district_levels", 10))


## District (1-based) a level belongs to: levels 1-10 = 1, 11-20 = 2, ...
static func district_of(level: int, economy: Dictionary = {}) -> int:
	var per := district_levels(economy)
	return floori(float(maxi(level, 1) - 1) / per) + 1


static func district_count(economy: Dictionary = {}) -> int:
	return (cfg(economy).get("city", {}).get("districts", []) as Array).size()


static func is_boss(level: int, economy: Dictionary = {}) -> bool:
	var every := int(cfg(economy)["level_coins"].get("boss_every", 10))
	return every > 0 and level % every == 0


## Scale for coin rewards outside levels (daily, missions, spin, chests): grows with the
## player's level, with no boss or replay factor.
static func reward_scale(level: int, economy: Dictionary = {}) -> float:
	var c: Dictionary = cfg(economy)["level_coins"]
	return float(c["base"]) + float(c["per_level"]) * (maxi(level, 1) - 1)


## Multiplier applied to the finale's coins when level L is won (first clear).
static func level_coin_mult(level: int, economy: Dictionary = {}) -> float:
	var m := reward_scale(level, economy)
	if is_boss(level, economy):
		m *= float(cfg(economy)["level_coins"].get("boss_mult", 1.0))
	return m


## Coins a win pays from Bottle Shot's coins (level_coins, the level's curve already in them):
## all of them on a first clear, x replay_mult when the level was already beaten.
static func level_reward(_level: int, finale_coins: int, replay: bool, economy: Dictionary = {}) -> int:
	var m := 1.0
	if replay:
		m = float(cfg(economy)["level_coins"].get("replay_mult", 1.0))
	return maxi(int(round(maxi(finale_coins, 0) * m)), 0)


# ---------------------------------------------------------------- the payout (spec v2.1 §3.1)

## The one payout function (Bottle Shot's coins, the result screen's multiplier and
## tests/econ_model.gd all use it). economy.json "payout":
##   coins = base x mult(L) x (1 + troops x min(troops / coin_ref, 1))
##           x bottle_factor(hits, gold) x (1 + heat x heat) x station
## `troops` / `coin_ref`: the finishing squad over the level's stored route finish (coin_ref <= 0
## counts as a full finish); `hits`: normal bottles broken; `gold`: the gold bottle broke; `heat`:
## the level's mean tap heat (0..1); `station`: the coin bonus as a multiplier (1.0 = none, 1.2 =
## the evidence room's +20%). A first clear; level_reward applies the replay rate.
static func level_coins(level: int, troops: int, coin_ref: int, hits: int, gold: bool, heat: float, station: float, economy: Dictionary = {}) -> int:
	var p: Dictionary = cfg(economy).get("payout", {})
	var share := 1.0 if coin_ref <= 0 else clampf(float(maxi(troops, 0)) / float(coin_ref), 0.0, 1.0)
	var c := float(p.get("base", 100.0)) * level_coin_mult(level, economy)
	c *= 1.0 + float(p.get("troops", 0.0)) * share
	c *= bottle_factor(hits, gold, economy)
	c *= 1.0 + float(p.get("heat", 0.0)) * clampf(heat, 0.0, 1.0)
	c *= maxf(station, 0.0)
	return maxi(int(round(c)), 0)


## Bottle Shot's multiplier: 1 + hit x min(hits, max_hits) + gold x (gold bottle broke). Every
## bottle and the gold make the payout's cap (1.7, owner decision 2026-11-12).
static func bottle_factor(hits: int, gold: bool, economy: Dictionary = {}) -> float:
	var p: Dictionary = cfg(economy).get("payout", {})
	var n := clampi(hits, 0, int(p.get("max_hits", 4)))
	return 1.0 + float(p.get("hit", 0.0)) * n + (float(p.get("gold", 0.0)) if gold else 0.0)


## The tap term as the whole percent the result screen shows (+0..10 %).
static func heat_pct(heat: float, economy: Dictionary = {}) -> int:
	return int(round(100.0 * float(cfg(economy).get("payout", {}).get("heat", 0.0)) * clampf(heat, 0.0, 1.0)))


## The finish Bottle Shot is handed as "troops" (LevelSim.coin_troops, district-1 troops) that
## counts as the stored route's: a full district-1 squad (units.json world.squad_cap[0]).
static func full_coin_troops(units: Dictionary = {}) -> int:
	var caps: Array = _units(units).get("world", {}).get("squad_cap", [300])
	return maxi(int(caps[0]) if not caps.is_empty() else 300, 1)


# ---------------------------------------------------------------- police station

static func room(name: String, economy: Dictionary = {}) -> Dictionary:
	return cfg(economy)["station"].get(name, {})


static func room_max(name: String, economy: Dictionary = {}) -> int:
	return int(room(name, economy).get("max", 0))


## Price of level `lv` (1-based) of a room: base x growth^(lv-1), or the explicit costs list
## when a room has one. -1 for an unknown room or a level past the max.
static func station_cost(name: String, lv: int, economy: Dictionary = {}) -> int:
	var r := room(name, economy)
	if r.is_empty() or lv < 1 or lv > int(r.get("max", 0)):
		return -1
	if r.has("costs"):
		return int(r["costs"][lv - 1])
	return round_price(float(r["base"]) * pow(float(r["growth"]), lv - 1), economy)


## District that must be liberated before level `lv` of a room can be bought (0 = none).
static func station_requirement(name: String, lv: int, economy: Dictionary = {}) -> int:
	var r := room(name, economy)
	if r.is_empty() or lv < 1:
		return 0
	if r.has("req"):
		var req: Array = r["req"]
		return int(req[clampi(lv - 1, 0, req.size() - 1)])
	return maxi(ceili((lv - 2) / 2.0), 0)


## Spec v2.1 §3.3: the level from which level `lv` of a room opens, for buying and in the levels
## (the room's "from_level" list: training 1 from L4, 2 from L6, 3 from L8); 0 = no level gate.
static func room_level_gate(name: String, lv: int, economy: Dictionary = {}) -> int:
	var gates: Array = room(name, economy).get("from_level", [])
	if lv < 1 or lv > gates.size():
		return 0
	return int(gates[lv - 1])


## The level the next level of `name` waits for (the player's furthest level is below it), or 0.
static func room_lock_level(save: Dictionary, name: String, economy: Dictionary = {}) -> int:
	var lv := int(save.get("station", {}).get(name, 0)) + 1
	if lv > room_max(name, economy):
		return 0
	var need := room_level_gate(name, lv, economy)
	return need if need > int(save.get("unlocked", 1)) else 0


## The station a level gets: a room's levels count only from their level gate (so L1-L3 stay
## the hero-alone tap lessons whatever training is owned); rooms without gates come whole.
static func level_station(station: Dictionary, level: int, economy: Dictionary = {}) -> Dictionary:
	var out := station.duplicate()
	for name in out:
		var n := 0
		for k in range(1, int(out[name]) + 1):
			if room_level_gate(String(name), k, economy) > level:
				break
			n = k
		out[name] = n
	return out


# ---------------------------------------------------------------- stars

## Total stars needed to open the next star chest when `opened` chests are already open.
static func stars_needed_for_chest(opened: int, economy: Dictionary = {}) -> int:
	var every := int(cfg(economy).get("stars", {}).get("chest_every", 15))
	return every * (maxi(opened, 0) + 1)


# ---------------------------------------------------------------- squad power (v1.1 5a)

static var _units_cache: Dictionary = {}


static func _units(units: Dictionary) -> Dictionary:
	if not units.is_empty():
		return units
	if _units_cache.is_empty():
		_units_cache = Config.units()
	return _units_cache


## Nominal firepower of a squad (spec v2 section 12.4): damage per second against a plain
## unarmoured crowd, summed over `counts` = {owner: troops} ("hero" = 1 for the hero), each owner
## with its Armory multipliers (`weapons` = Armory.sim_upgrades()["weapons"]: {owner: {dmg_mult,
## rate_mult}}). The hero counts at full tap rate (spec section 2). One implementation for every
## lightning number: this is Squad.firepower(), the HUD's live number, on upgraded stats.
static func firepower(counts: Dictionary, weapons: Dictionary = {}, units: Dictionary = {}) -> float:
	var stats := upgraded_allies(_units(units)["allies"], weapons)
	var sq := Squad.new()
	sq.counts = {}
	for owner in counts:
		if stats.has(owner):
			sq.counts[String(owner)] = int(counts[owner])
	sq.hero_rate = 1.0
	return sq.firepower(stats, {})


## Squad Power (lobby, level nodes, Armory and Station pills) = the firepower a level starts
## with: the hero at full tap rate plus the starting constables (station training), with the
## Armory's multipliers (fx.weapons). Same unit and icon as the HUD's live firepower (spec v2
## section 12.4). The squad cap and the coin bonus are not firepower, so they add nothing here.
static func squad_power(fx: Dictionary, units: Dictionary = {}, _economy: Dictionary = {}) -> float:
	var w: Dictionary = fx.get("weapons", {}) if fx.get("weapons") is Dictionary else {}
	return firepower({"hero": 1, "constable": int(fx.get("squad", 0))}, w, units)


## The squad a level builds, for weighing purchases (economy.json power.ref_troops: troops of
## each rank on top of the starting squad; a rank counts once it has unlocked).
static func ref_squad(fx: Dictionary, unlocked: int, units: Dictionary = {}, economy: Dictionary = {}) -> Dictionary:
	var allies: Dictionary = _units(units)["allies"]
	var refs: Dictionary = cfg(economy).get("power", {}).get("ref_troops", {})
	var out := {"hero": 1, "constable": int(fx.get("squad", 0))}
	for owner in refs:
		if owner == "hero" or not allies.has(owner):
			continue
		if int(allies[owner].get("unlock", 1)) <= maxi(unlocked, 1):
			out[owner] = int(out.get(owner, 0)) + int(refs[owner])
	return out


## What a purchase is worth to the pointer and the loss tip: the firepower it adds to the squad
## a level builds (ref_squad), so a step for a rank that joins mid-level counts too. The squad cap
## and the coin bonus are weighed with economy.json power.cap_value (firepower per troop of
## extra cap) and power.coin_value (per percent of coin bonus); they are never shown as power.
static func _value(fx: Dictionary, unlocked: int, units: Dictionary, economy: Dictionary) -> float:
	var p: Dictionary = cfg(economy).get("power", {})
	var w: Dictionary = fx.get("weapons", {}) if fx.get("weapons") is Dictionary else {}
	var v := firepower(ref_squad(fx, unlocked, units, economy), w, units)
	v += float(p.get("cap_value", 0.0)) * float(fx.get("capacity", 0))
	v += float(p.get("coin_value", 0.0)) * float(fx.get("coins", 0.0)) * 100.0
	return v


## A copy of units.json "allies" with each owner's dmg and rate times its Armory multipliers
## (`weapons` = Armory.sim_upgrades()["weapons"]), the way LevelSim._init applies them. The
## Codex compares ranks on it (spec v2 rule 6: the player's current upgraded stats).
static func upgraded_allies(allies: Dictionary, weapons: Dictionary) -> Dictionary:
	var out := allies.duplicate(true)
	for owner in weapons:
		if out.has(owner) and weapons[owner] is Dictionary:
			var u: Dictionary = out[owner]
			u["dmg"] = float(u["dmg"]) * float(weapons[owner].get("dmg_mult", 1.0))
			u["rate"] = float(u["rate"]) * float(weapons[owner].get("rate_mult", 1.0))
	return out


## Everything Squad Power counts for a save: the station's effects and the armory's weapons.
static func save_fx(save: Dictionary, economy: Dictionary = {}) -> Dictionary:
	var fx := SaveData.effects(cfg(economy), save.get("station", {}))
	fx["weapons"] = Armory.sim_upgrades(save)["weapons"]
	return fx


## Squad Power of a save (station + armory).
static func save_power(save: Dictionary, units: Dictionary = {}, economy: Dictionary = {}) -> float:
	return squad_power(save_fx(save, economy), units, economy)


## Squad Power of a station (room -> level dict) with no weapon steps.
static func station_power(station: Dictionary, units: Dictionary = {}, economy: Dictionary = {}) -> float:
	return squad_power(SaveData.effects(cfg(economy), station), units, economy)


## Power the station would have with one more level of `room`, minus what it has now (only
## training adds firepower at level start).
static func room_power_gain(station: Dictionary, room: String, units: Dictionary = {}, economy: Dictionary = {}) -> float:
	var next := station.duplicate()
	next[room] = int(station.get(room, 0)) + 1
	return station_power(next, units, economy) - station_power(station, units, economy)


## Squad Power the save would gain from the next step of weapon track `id`: the hero's knives
## and the constables' pistol (with starting constables) show at level start; other ranks join
## during the level, so their steps add 0 here (their worth is weapon_value). 0 when maxed or
## for a Bottle Shot track (those change handling, not the squad).
static func weapon_power_gain(save: Dictionary, id: String, units: Dictionary = {}, economy: Dictionary = {}) -> float:
	var fx := _next_weapon_fx(save, id, economy)
	if fx.is_empty():
		return 0.0
	return squad_power(fx, units, economy) - save_power(save, units, economy)


## The pointer's value of the next step of weapon track `id` (see _value), 0 when maxed or for a
## Bottle Shot track.
static func weapon_value(save: Dictionary, id: String, units: Dictionary = {}, economy: Dictionary = {}) -> float:
	var fx := _next_weapon_fx(save, id, economy)
	if fx.is_empty():
		return 0.0
	var unlocked := int(save.get("unlocked", 1))
	return _value(fx, unlocked, units, economy) - _value(save_fx(save, economy), unlocked, units, economy)


## The pointer's value of one more level of station room `room`.
static func room_value(save: Dictionary, room: String, units: Dictionary = {}, economy: Dictionary = {}) -> float:
	var station: Dictionary = save.get("station", {})
	var next := station.duplicate()
	next[room] = int(station.get(room, 0)) + 1
	var fx := save_fx(save, economy)
	var fx2 := SaveData.effects(cfg(economy), next)
	fx2["weapons"] = fx["weapons"]
	var unlocked := int(save.get("unlocked", 1))
	return _value(fx2, unlocked, units, economy) - _value(fx, unlocked, units, economy)


## save_fx with track `id` one step further ({} when maxed or a Bottle Shot track).
static func _next_weapon_fx(save: Dictionary, id: String, economy: Dictionary) -> Dictionary:
	if Armory.is_finale(id) or Armory.is_maxed(save, id):
		return {}
	var fx := save_fx(save, economy)
	var nx := Armory.next_stats(save, id)
	var owner := String(Armory.track(id)["owner"])
	(fx["weapons"] as Dictionary)[owner] = {"dmg_mult": nx["dmg_mult"], "rate_mult": nx["rate_mult"]}
	return fx


## Squad Power / firepower as text (spec v2 section 12.4): one decimal below 100 (so a single
## step shows), whole numbers from 100, in full up to 9,999, then 12.3K and 1.25M.
static func fmt_power(v: float) -> String:
	if v < 100.0:
		return String.num(roundf(v * 10.0) / 10.0, 1).trim_suffix(".0")
	var n := int(round(v))
	if n < 10000:
		return str(n)
	if n < 1000000:
		return "%sK" % _trim3(n / 1000.0)
	return "%sM" % _trim3(n / 1000000.0)


## 12.3 / 1.25 / 123: three significant digits, rounded down (never shows more than there is).
static func _trim3(v: float) -> String:
	if v >= 100.0:
		return str(int(v))
	if v >= 10.0:
		return String.num(floorf(v * 10.0) / 10.0, 1).trim_suffix(".0")
	return String.num(floorf(v * 100.0) / 100.0, 2).trim_suffix("0").trim_suffix(".0")


## Recommended Squad Power for a level: linear between the "power.recommended" anchors
## [[level, power], ...], fitted by tests/econ_sim.gd to what a player who spends their coins
## has at that level. Every level is still winnable below it; under it the map node warns.
static func recommended_power(level: int, economy: Dictionary = {}) -> float:
	var pts: Array = cfg(economy).get("power", {}).get("recommended", [])
	if pts.is_empty():
		return 0.0
	if level <= int(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if level <= int(b[0]):
			var f := float(level - int(a[0])) / maxf(float(int(b[0]) - int(a[0])), 1.0)
			return lerpf(float(a[1]), float(b[1]), f)
	return float(pts[pts.size() - 1][1])


# ---------------------------------------------------------------- what to buy (v1.1 item 5)

## Everything the player could spend coins on right now (coins aside): the next level of each
## station room that is not locked or maxed, the next step of each Armory track that is open
## and not maxed, the next build of each building that can start (district reached, a builder
## free), and each cosmetic not owned yet. Each entry: {kind: room|weapon|building|cosmetic, id,
## cost, gain, value}; gain = Squad Power added (room, weapon: level-start firepower, so 0 for a
## rank that joins mid-level, the cap, the coin bonus and a Bottle Shot track), coins per hour
## added (building) or 0 (cosmetic); value = what the pointer weighs a room or weapon step by
## (room_value / weapon_value: firepower in the squad a level builds), 0 otherwise. Sorted
## cheapest first.
static func purchases(save: Dictionary, now: int, economy: Dictionary = {}, units: Dictionary = {}) -> Array:
	var eco := cfg(economy)
	var out := []
	var liberated := City.districts_liberated(save, eco)
	var station: Dictionary = save.get("station", {})
	for room in eco.get("station_order", []):
		var c := SaveData.room_cost(eco, station, String(room), liberated)
		if c >= 0 and room_lock_level(save, String(room), eco) == 0:
			out.append({"kind": "room", "id": String(room), "cost": c, "gain": room_power_gain(station, String(room), units, eco),
				"value": room_value(save, String(room), units, eco)})
	var unlocked := int(save.get("unlocked", 1))
	for id in Armory.ids():
		var c := Armory.next_cost(save, String(id))
		if c >= 0 and not Armory.is_locked(String(id), unlocked) and Armory.next_tier_lock(save, String(id)) == 0:
			out.append({"kind": "weapon", "id": String(id), "cost": c, "gain": weapon_power_gain(save, String(id), units, eco),
				"value": weapon_value(save, String(id), units, eco)})
	for id in City.ids(eco):
		var c := City.next_cost(save, id, eco)
		if c >= 0 and City.can_start(save, id, now, eco) == "":
			var lv := City.target_level(save, id)
			var gain := City.income_at(id, lv + 1, eco) - City.income_at(id, lv, eco)
			out.append({"kind": "building", "id": id, "cost": c, "gain": gain, "value": 0.0})
	var owned: Array = save.get("owned", [])
	for kind in ["outfits", "knives"]:
		for cos in eco.get("cosmetics", {}).get(kind, []):
			if not owned.has(String(cos["id"])) and int(cos["price"]) > 0:
				out.append({"kind": "cosmetic", "id": String(cos["id"]), "cost": int(cos["price"]), "gain": 0, "value": 0.0, "set": kind})
	out.sort_custom(func(a, b): return int(a["cost"]) < int(b["cost"]))
	return out


## The purchases the player can afford now.
static func affordable(save: Dictionary, now: int, economy: Dictionary = {}, units: Dictionary = {}) -> Array:
	var coins := int(save.get("coins", 0))
	return purchases(save, now, economy, units).filter(func(p): return int(p["cost"]) <= coins)


## Squad progress (a station room or a weapon step) that adds firepower in a level.
static func is_power_buy(p: Dictionary) -> bool:
	return (p["kind"] == "room" or p["kind"] == "weapon") and float(p.get("value", 0.0)) > 0.0


## The single best thing to buy now ({} when nothing useful is affordable). Below the
## recommended power for the current level: the room or weapon step with the most value per
## coin (firepower in the squad a level builds). Otherwise the building with the most income per coin (it pays for later buys), else
## the best room or weapon step. Cosmetics and Bottle Shot handling are never pointed at
## (they are a choice, not progress).
static func best_purchase(save: Dictionary, now: int, economy: Dictionary = {}, units: Dictionary = {}) -> Dictionary:
	var eco := cfg(economy)
	var best_power := {}
	var best_bld := {}
	for p in affordable(save, now, eco, units):
		var ratio := float(p["value"] if is_power_buy(p) else p["gain"]) / maxf(float(p["cost"]), 1.0)
		if is_power_buy(p) and (best_power.is_empty() or ratio > float(best_power["ratio"])):
			best_power = p.duplicate()
			best_power["ratio"] = ratio
		elif p["kind"] == "building" and (best_bld.is_empty() or ratio > float(best_bld["ratio"])):
			best_bld = p.duplicate()
			best_bld["ratio"] = ratio
	var level := maxi(int(save.get("unlocked", 1)), 1)
	var under := save_power(save, units, eco) < recommended_power(level, eco)
	if under and not best_power.is_empty():
		return best_power
	if not best_bld.is_empty():
		return best_bld
	return best_power


## The upgrade that would have helped a lost level most: the station room (not the coin bonus) or
## weapon step (open, not maxed) that adds the most firepower in a level (value), preferring ones the player can
## afford now. {kind: room|weapon, id, room (= id, for the result screen), cost, gain (Squad
## Power added), value, affordable}, or {} when everything is locked or maxed.
static func best_upgrade_after_loss(save: Dictionary, economy: Dictionary = {}, units: Dictionary = {}) -> Dictionary:
	var eco := cfg(economy)
	var coins := int(save.get("coins", 0))
	var best := {}
	for p in purchases(save, 0, eco, units):
		# A coin bonus never wins a fight: the loss tip is about the squad.
		if not is_power_buy(p) or (p["kind"] == "room" and String(room(String(p["id"]), eco).get("effect", "")) == "coins"):
			continue
		var c := int(p["cost"])
		var v := float(p["value"])
		var e := {"kind": p["kind"], "id": p["id"], "room": p["id"], "cost": c, "gain": float(p["gain"]), "value": v, "affordable": c <= coins}
		if best.is_empty():
			best = e
		elif bool(e["affordable"]) != bool(best["affordable"]):
			if bool(e["affordable"]):
				best = e
		elif v > float(best["value"]) + 0.0001 or (absf(v - float(best["value"])) <= 0.0001 and c < int(best["cost"])):
			best = e
	return best

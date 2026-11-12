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


## Coins a win pays: finale coins x curve, x replay_mult if the level was already beaten.
static func level_reward(level: int, finale_coins: int, replay: bool, economy: Dictionary = {}) -> int:
	var m := level_coin_mult(level, economy)
	if replay:
		m *= float(cfg(economy)["level_coins"].get("replay_mult", 1.0))
	return maxi(int(round(maxi(finale_coins, 0) * m)), 0)


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


# ---------------------------------------------------------------- stars

## Total stars needed to open the next star chest when `opened` chests are already open.
static func stars_needed_for_chest(opened: int, economy: Dictionary = {}) -> int:
	var every := int(cfg(economy).get("stars", {}).get("chest_every", 15))
	return every * (maxi(opened, 0) + 1)


# ---------------------------------------------------------------- squad power (v1.1 5a)

## Throws per second one Range level adds to the hero (LevelSim: rate + 0.5 x speed).
const SPEED_STEP := 0.5

static var _units_cache: Dictionary = {}


static func _units(units: Dictionary) -> Dictionary:
	if not units.is_empty():
		return units
	if _units_cache.is_empty():
		_units_cache = Config.units()
	return _units_cache


## Squad Power: one number from the station's real effects (SaveData.effects): the hero's knife
## damage x throw rate, the starting constables' damage x rate, the squad cap, the power charges
## and the coin bonus, weighted by economy.json "power". The lobby shows it and level nodes
## compare against it.
static func squad_power(fx: Dictionary, units: Dictionary = {}, economy: Dictionary = {}) -> int:
	var p: Dictionary = cfg(economy).get("power", {})
	var u := _units(units)
	var hero: Dictionary = u["allies"]["hero"]
	var con: Dictionary = u["allies"]["constable"]
	var hero_dps := (float(hero["dmg"]) + float(fx.get("knife", 0))) * (float(hero["rate"]) + SPEED_STEP * float(fx.get("speed", 0)))
	var squad_dps := float(fx.get("squad", 0)) * float(con["dmg"]) * float(con["rate"])
	var cap := float(LevelSim.squad_cap_for(u, 1, int(fx.get("capacity", 0))))  # district 1 cap + barracks %
	var charges := float(fx.get("shield", 0)) + float(fx.get("bomb", 0))
	var v := float(p.get("dps", 10.0)) * (hero_dps + squad_dps) + float(p.get("cap", 0.2)) * cap
	v += float(p.get("charge", 15.0)) * charges + float(p.get("coin_pct", 1.0)) * float(fx.get("coins", 0.0)) * 100.0
	return int(round(v))


## Squad Power of a station (room -> level dict).
static func station_power(station: Dictionary, units: Dictionary = {}, economy: Dictionary = {}) -> int:
	return squad_power(SaveData.effects(cfg(economy), station), units, economy)


## Power the station would have with one more level of `room`, minus what it has now.
static func room_power_gain(station: Dictionary, room: String, units: Dictionary = {}, economy: Dictionary = {}) -> int:
	var next := station.duplicate()
	next[room] = int(station.get(room, 0)) + 1
	return station_power(next, units, economy) - station_power(station, units, economy)


## Recommended Squad Power for a level: linear between the "power.recommended" anchors
## [[level, power], ...], fitted by tests/econ_sim.gd to what a player who spends their coins
## has at that level. Every level is still winnable below it; under it the map node warns.
static func recommended_power(level: int, economy: Dictionary = {}) -> int:
	var pts: Array = cfg(economy).get("power", {}).get("recommended", [])
	if pts.is_empty():
		return 0
	if level <= int(pts[0][0]):
		return int(pts[0][1])
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if level <= int(b[0]):
			var f := float(level - int(a[0])) / maxf(float(int(b[0]) - int(a[0])), 1.0)
			return int(round(lerpf(float(a[1]), float(b[1]), f)))
	return int(pts[pts.size() - 1][1])


# ---------------------------------------------------------------- what to buy (v1.1 item 5)

## Everything the player could spend coins on right now (coins aside): the next level of each
## station room that is not locked or maxed, the next build of each building that can start
## (district reached, a builder free), and each cosmetic not owned yet. Each entry:
## {kind: room|building|cosmetic, id, cost, gain}; gain = Squad Power added (room), coins per
## hour added (building) or 0 (cosmetic). Sorted cheapest first.
static func purchases(save: Dictionary, now: int, economy: Dictionary = {}, units: Dictionary = {}) -> Array:
	var eco := cfg(economy)
	var out := []
	var liberated := City.districts_liberated(save, eco)
	var station: Dictionary = save.get("station", {})
	for room in eco.get("station_order", []):
		var c := SaveData.room_cost(eco, station, String(room), liberated)
		if c >= 0:
			out.append({"kind": "room", "id": String(room), "cost": c, "gain": room_power_gain(station, String(room), units, eco)})
	for id in City.ids(eco):
		var c := City.next_cost(save, id, eco)
		if c >= 0 and City.can_start(save, id, now, eco) == "":
			var lv := City.target_level(save, id)
			var gain := City.income_at(id, lv + 1, eco) - City.income_at(id, lv, eco)
			out.append({"kind": "building", "id": id, "cost": c, "gain": gain})
	var owned: Array = save.get("owned", [])
	for kind in ["outfits", "knives"]:
		for cos in eco.get("cosmetics", {}).get(kind, []):
			if not owned.has(String(cos["id"])) and int(cos["price"]) > 0:
				out.append({"kind": "cosmetic", "id": String(cos["id"]), "cost": int(cos["price"]), "gain": 0, "set": kind})
	out.sort_custom(func(a, b): return int(a["cost"]) < int(b["cost"]))
	return out


## The purchases the player can afford now.
static func affordable(save: Dictionary, now: int, economy: Dictionary = {}, units: Dictionary = {}) -> Array:
	var coins := int(save.get("coins", 0))
	return purchases(save, now, economy, units).filter(func(p): return int(p["cost"]) <= coins)


## The single best thing to buy now ({} when nothing useful is affordable). Below the
## recommended power for the current level: the room with the most power per coin. Otherwise
## the building with the most income per coin (it pays for later buys), else the best room.
## Cosmetics are never pointed at (they are a choice, not progress).
static func best_purchase(save: Dictionary, now: int, economy: Dictionary = {}, units: Dictionary = {}) -> Dictionary:
	var eco := cfg(economy)
	var best_room := {}
	var best_bld := {}
	for p in affordable(save, now, eco, units):
		var ratio := float(p["gain"]) / maxf(float(p["cost"]), 1.0)
		if p["kind"] == "room" and (best_room.is_empty() or ratio > float(best_room["ratio"])):
			best_room = p.duplicate()
			best_room["ratio"] = ratio
		elif p["kind"] == "building" and (best_bld.is_empty() or ratio > float(best_bld["ratio"])):
			best_bld = p.duplicate()
			best_bld["ratio"] = ratio
	var level := maxi(int(save.get("unlocked", 1)), 1)
	var under := station_power(save.get("station", {}), units, eco) < recommended_power(level, eco)
	if under and not best_room.is_empty():
		return best_room
	if not best_bld.is_empty():
		return best_bld
	return best_room


## The upgrade that would have helped a lost level most: the room (not locked, not maxed) whose
## next level adds the most Squad Power, preferring ones the player can afford now.
## {room, cost, gain, affordable}, or {} when every room is locked or maxed.
static func best_upgrade_after_loss(save: Dictionary, economy: Dictionary = {}, units: Dictionary = {}) -> Dictionary:
	var eco := cfg(economy)
	var coins := int(save.get("coins", 0))
	var station: Dictionary = save.get("station", {})
	var liberated := City.districts_liberated(save, eco)
	var best := {}
	for room in eco.get("station_order", []):
		var c := SaveData.room_cost(eco, station, String(room), liberated)
		if c < 0:
			continue
		var gain := room_power_gain(station, String(room), units, eco)
		var e := {"room": String(room), "cost": c, "gain": gain, "affordable": c <= coins}
		if best.is_empty():
			best = e
		elif bool(e["affordable"]) != bool(best["affordable"]):
			if bool(e["affordable"]):
				best = e
		elif gain > int(best["gain"]) or (gain == int(best["gain"]) and c < int(best["cost"])):
			best = e
	return best

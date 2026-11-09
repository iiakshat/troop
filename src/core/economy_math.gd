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

class_name Armory
extends RefCounted
## The Armory (spec v2 section 6), pure: one weapon track per weapon over config/armory.json.
## save.armory = {track_id: {tier, step}} (missing = tier 1 step 0). Tiers are 1-based; a tier
## takes steps_per_tier buys: buys 1..n-1 fill its bar (step 1..n-1) and buy n evolves the weapon
## to the next tier (step 0). On the last tier buy n fills the bar (step n) and the track is
## maxed. Purchase index i = (tier - 1) x n + step costs base x growth^i, price-rounded.
## Squad tracks feed LevelSim through sim_upgrades() (dmg / rate multipliers per owner, never
## troop counts); Bottle Shot tracks (owner "finale_<weapon>") only change handling through
## apply_finale(). Every function takes the armory config as an optional last argument (the
## file is loaded once and cached when it is left out). Tested in tests/test_armory.gd.

static var _cache: Dictionary = {}


static func cfg(armory_cfg: Dictionary = {}) -> Dictionary:
	if not armory_cfg.is_empty():
		return armory_cfg
	if _cache.is_empty():
		_cache = Config.armory()
	return _cache


static func ids(armory_cfg: Dictionary = {}) -> Array:
	return cfg(armory_cfg).get("order", [])


static func track(id: String, armory_cfg: Dictionary = {}) -> Dictionary:
	return cfg(armory_cfg).get("tracks", {}).get(id, {})


## The track whose owner is `owner` (a rank id, "hero" or "finale_<weapon>"), or "".
static func track_of(owner: String, armory_cfg: Dictionary = {}) -> String:
	for id in ids(armory_cfg):
		if String(track(String(id), armory_cfg).get("owner", "")) == owner:
			return String(id)
	return ""


static func is_finale(id: String, armory_cfg: Dictionary = {}) -> bool:
	return String(track(id, armory_cfg).get("owner", "")).begins_with("finale_")


static func tier_count(id: String, armory_cfg: Dictionary = {}) -> int:
	return (track(id, armory_cfg).get("tiers", []) as Array).size()


static func steps_per_tier(id: String, armory_cfg: Dictionary = {}) -> int:
	return maxi(int(track(id, armory_cfg).get("steps_per_tier", 5)), 1)


## Purchases a track holds from tier 1 step 0 to maxed.
static func total_buys(id: String, armory_cfg: Dictionary = {}) -> int:
	return tier_count(id, armory_cfg) * steps_per_tier(id, armory_cfg)


## {name, calibre, art, dmg_mult, rate_mult, extra} of tier `tier` (1-based, clamped).
static func tier_info(id: String, tier: int, armory_cfg: Dictionary = {}) -> Dictionary:
	var tiers: Array = track(id, armory_cfg).get("tiers", [])
	if tiers.is_empty():
		return {}
	return tiers[clampi(tier, 1, tiers.size()) - 1]


# ---------------------------------------------------------------- progress

## (tier, step) of a track in the save: tier 1 step 0 when nothing was bought.
static func level(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> Vector2i:
	var a: Variant = save.get("armory", {})
	if not (a is Dictionary) or not (a as Dictionary).has(id) or not (a[id] is Dictionary):
		return Vector2i(1, 0)
	var n := tier_count(id, armory_cfg)
	var per := steps_per_tier(id, armory_cfg)
	var tier := clampi(int(a[id].get("tier", 1)), 1, maxi(n, 1))
	var top := per if tier == n else per - 1
	return Vector2i(tier, clampi(int(a[id].get("step", 0)), 0, top))


## Purchases made on a track so far (0 = none).
static func index(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> int:
	var l := level(save, id, armory_cfg)
	return (l.x - 1) * steps_per_tier(id, armory_cfg) + l.y


## (tier, step) after `i` purchases.
static func at_index(id: String, i: int, armory_cfg: Dictionary = {}) -> Vector2i:
	var per := steps_per_tier(id, armory_cfg)
	var total := total_buys(id, armory_cfg)
	i = clampi(i, 0, total)
	if i == total and total > 0:
		return Vector2i(tier_count(id, armory_cfg), per)
	return Vector2i(i / per + 1, i % per)


static func set_index(save: Dictionary, id: String, i: int, armory_cfg: Dictionary = {}) -> void:
	if not (save.get("armory") is Dictionary):
		save["armory"] = {}
	var l := at_index(id, i, armory_cfg)
	save["armory"][id] = {"tier": l.x, "step": l.y}


static func is_maxed(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> bool:
	return index(save, id, armory_cfg) >= total_buys(id, armory_cfg)


static func is_locked(id: String, unlocked_level: int, armory_cfg: Dictionary = {}) -> bool:
	var t := track(id, armory_cfg)
	return t.is_empty() or unlocked_level < int(t.get("unlock_level", 1))


static func unlock_level(id: String, armory_cfg: Dictionary = {}) -> int:
	return int(track(id, armory_cfg).get("unlock_level", 1))


## Spec v2.1 §3.2: the level from which a weapon may evolve into tier `tier` (armory.json
## tier_unlock {"2": 9, "3": 15, "4": 31}; tiers not listed open from L1).
static func tier_unlock_level(tier: int, armory_cfg: Dictionary = {}) -> int:
	return int(cfg(armory_cfg).get("tier_unlock", {}).get(str(tier), 1))


static func tier_unlocked(tier: int, level: int, armory_cfg: Dictionary = {}) -> bool:
	return level >= tier_unlock_level(tier, armory_cfg)


## The level the next buy of a track waits for (it would evolve into a tier the player's
## furthest level has not opened yet), or 0 when it is open (or maxed). The bar fills before it.
static func next_tier_lock(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> int:
	if track(id, armory_cfg).is_empty() or is_maxed(save, id, armory_cfg):
		return 0
	var tier := at_index(id, index(save, id, armory_cfg) + 1, armory_cfg).x
	if tier_unlocked(tier, int(save.get("unlocked", 1)), armory_cfg):
		return 0
	return tier_unlock_level(tier, armory_cfg)


# ---------------------------------------------------------------- prices

## Price of the buy made from (tier, step); -1 for an unknown track or a maxed one.
static func cost(id: String, tier: int, step: int, armory_cfg: Dictionary = {}) -> int:
	var t := track(id, armory_cfg)
	if t.is_empty():
		return -1
	var i := (tier - 1) * steps_per_tier(id, armory_cfg) + step
	return cost_at(id, i, armory_cfg)


## Price of purchase number i (0-based over the whole track); -1 past the end.
static func cost_at(id: String, i: int, armory_cfg: Dictionary = {}) -> int:
	var t := track(id, armory_cfg)
	if t.is_empty() or i < 0 or i >= total_buys(id, armory_cfg):
		return -1
	var c: Dictionary = t.get("cost", {})
	return Economy.round_price(float(c.get("base", 50)) * pow(float(c.get("growth", 1.2)), i))


static func next_cost(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> int:
	return cost_at(id, index(save, id, armory_cfg), armory_cfg)


## Coins spent on a track to reach its current level.
static func spent(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> int:
	return spent_at(id, index(save, id, armory_cfg), armory_cfg)


static func spent_at(id: String, i: int, armory_cfg: Dictionary = {}) -> int:
	var sum := 0
	for k in mini(i, total_buys(id, armory_cfg)):
		sum += cost_at(id, k, armory_cfg)
	return sum


## Buys the next step (or evolution) of a track: spends the coins.
## {ok, evolved, tier, step, cost}; ok false (nothing changes) when locked, maxed, too poor or
## when it would evolve into a tier the player's level has not opened (next_tier_lock).
static func buy(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> Dictionary:
	var l := level(save, id, armory_cfg)
	var out := {"ok": false, "evolved": false, "tier": l.x, "step": l.y, "cost": -1}
	if track(id, armory_cfg).is_empty() or is_locked(id, int(save.get("unlocked", 1)), armory_cfg):
		return out
	if next_tier_lock(save, id, armory_cfg) > 0:
		return out
	var c := next_cost(save, id, armory_cfg)
	out["cost"] = c
	if c < 0 or int(save.get("coins", 0)) < c:
		return out
	save["coins"] = int(save.get("coins", 0)) - c
	set_index(save, id, index(save, id, armory_cfg) + 1, armory_cfg)
	var n := level(save, id, armory_cfg)
	out["ok"] = true
	out["evolved"] = n.x > l.x
	out["tier"] = n.x
	out["step"] = n.y
	return out


# ---------------------------------------------------------------- stats

## Numbers at (tier, step): the tier's dmg_mult / rate_mult / extra plus step x the track's
## per-step increments.
static func stats_at(id: String, tier: int, step: int, armory_cfg: Dictionary = {}) -> Dictionary:
	var t := track(id, armory_cfg)
	var ti := tier_info(id, tier, armory_cfg)
	var st: Dictionary = t.get("step", {})
	var extra := {}
	var base_x: Dictionary = ti.get("extra", {})
	var step_x: Dictionary = st.get("extra", {})
	for k in base_x:
		extra[k] = float(base_x[k]) + float(step_x.get(k, 0.0)) * step
	return {
		"dmg_mult": float(ti.get("dmg_mult", 1.0)) + float(st.get("dmg_mult", 0.0)) * step,
		"rate_mult": float(ti.get("rate_mult", 1.0)) + float(st.get("rate_mult", 0.0)) * step,
		"extra": extra,
	}


static func stats(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> Dictionary:
	var l := level(save, id, armory_cfg)
	return stats_at(id, l.x, l.y, armory_cfg)


## Numbers after the next buy ({} when maxed): for the before > after bars.
static func next_stats(save: Dictionary, id: String, armory_cfg: Dictionary = {}) -> Dictionary:
	if is_maxed(save, id, armory_cfg):
		return {}
	var l := at_index(id, index(save, id, armory_cfg) + 1, armory_cfg)
	return stats_at(id, l.x, l.y, armory_cfg)


## What LevelSim gets: {"weapons": {owner: {dmg_mult, rate_mult}}} for every squad track
## (Bottle Shot tracks never reach the sim).
static func sim_upgrades(save: Dictionary, armory_cfg: Dictionary = {}) -> Dictionary:
	var w := {}
	for id in ids(armory_cfg):
		if is_finale(String(id), armory_cfg):
			continue
		var s := stats(save, String(id), armory_cfg)
		w[String(track(String(id), armory_cfg)["owner"])] = {"dmg_mult": s["dmg_mult"], "rate_mult": s["rate_mult"]}
	return {"weapons": w}


## Bottle Shot handling for `weapon` (pistol, bow, stars, sniper): the track's extra numbers
## ({key_add: n, key_mult: k}); {} when nothing was bought or the weapon has no track.
static func finale_extra(save: Dictionary, weapon: String, armory_cfg: Dictionary = {}) -> Dictionary:
	var id := track_of("finale_" + weapon, armory_cfg)
	if id == "" or index(save, id, armory_cfg) == 0:
		return {}
	return stats(save, id, armory_cfg)["extra"]


## A copy of finale.json with every Bottle Shot weapon's handling upgraded from the save
## (key_add adds, key_mult multiplies; integer keys stay integers).
static func apply_finale(finale_cfg: Dictionary, save: Dictionary, armory_cfg: Dictionary = {}) -> Dictionary:
	var out := finale_cfg.duplicate(true)
	var weapons: Dictionary = out.get("weapons", {})
	for w in weapons:
		var x := finale_extra(save, String(w), armory_cfg)
		var wc: Dictionary = weapons[w]
		for k in x:
			var key := String(k)
			if key.ends_with("_add"):
				var base := key.trim_suffix("_add")
				if wc.has(base):
					wc[base] = int(round(float(wc[base]) + float(x[k])))
			elif key.ends_with("_mult"):
				var base2 := key.trim_suffix("_mult")
				if wc.has(base2):
					wc[base2] = float(wc[base2]) * maxf(float(x[k]), 0.05)
	return out


## (tier, step) index and leftover coins when `coins` worth of purchases are turned into
## steps of a track, rounding up (save migration: never less than what was paid).
## {index, refund}: refund > 0 only when the coins are worth more than the whole track.
static func steps_for_coins(id: String, coins: int, armory_cfg: Dictionary = {}) -> Dictionary:
	var i := 0
	var sum := 0
	var total := total_buys(id, armory_cfg)
	while sum < coins and i < total:
		sum += cost_at(id, i, armory_cfg)
		i += 1
	return {"index": i, "refund": maxi(coins - sum, 0)}

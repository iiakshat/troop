class_name Rewards
extends RefCounted
## Reward dicts, pure. A reward is {coins, headstart, shield, bomb, cosmetic, chest}: every key
## optional. Config rewards hold unscaled coins and may name a chest; resolve() scales the
## coins and rolls the chest into concrete contents, apply() adds them to the save. The chest
## id stays in the result (as "chest") so the UI can show which chest opened.
## Tested in tests/test_rewards.gd.

const BOOSTERS := ["headstart", "shield", "bomb"]


## Copy of a reward with its coins multiplied by `mult` and rounded to a clean number.
## Counts come out as ints (JSON numbers are floats).
static func scaled(reward: Dictionary, mult: float, economy: Dictionary = {}) -> Dictionary:
	var out := normalized(reward)
	if out.has("coins"):
		out["coins"] = Economy.round_price(float(out["coins"]) * mult, economy)
	return out


## Copy with coins and booster counts as ints.
static func normalized(reward: Dictionary) -> Dictionary:
	var out := reward.duplicate(true)
	for k in ["coins"] + BOOSTERS:
		if out.has(k):
			out[k] = int(out[k])
	return out


## Sum of two rewards (numbers add up, other keys from b win).
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if (b[k] is int or b[k] is float) and out.has(k) and (out[k] is int or out[k] is float):
			out[k] = out[k] + b[k]
		else:
			out[k] = b[k]
	return out


## Paid cosmetics the player does not own yet: [{kind, id}].
static func unowned_cosmetics(save: Dictionary, economy: Dictionary = {}) -> Array:
	var out := []
	var owned: Array = save.get("owned", [])
	var cos: Dictionary = Economy.cfg(economy)["cosmetics"]
	for kind in ["outfits", "knives"]:
		for c in cos[kind]:
			if int(c["price"]) > 0 and not owned.has(c["id"]):
				out.append({"kind": kind, "id": String(c["id"])})
	return out


## Rolls chest `id`: coins in its range (rounded to 10, x scale), boosters in their ranges
## (at least min_boosters in total) and maybe a cosmetic the player lacks.
static func roll_chest(id: String, rng: RandomNumberGenerator, save: Dictionary, scale := 1.0, economy: Dictionary = {}) -> Dictionary:
	var c: Dictionary = Economy.cfg(economy).get("chests", {}).get(id, {})
	var out := {"chest": id, "coins": 0, "headstart": 0, "shield": 0, "bomb": 0}
	if c.has("coins"):
		var lo := floori(float(c["coins"][0]) / 10.0)
		var hi := maxi(floori(float(c["coins"][1]) / 10.0), lo)
		out["coins"] = Economy.round_price(rng.randi_range(lo, hi) * 10 * scale, economy)
	var count := 0
	for b in BOOSTERS:
		if c.has(b):
			out[b] = rng.randi_range(int(c[b][0]), int(c[b][1]))
			count += int(out[b])
	while count < int(c.get("min_boosters", 0)):
		out[BOOSTERS[rng.randi_range(0, BOOSTERS.size() - 1)]] += 1
		count += 1
	if rng.randf() < float(c.get("cosmetic_chance", 0.0)):
		var options := unowned_cosmetics(save, economy)
		if options.is_empty():
			out["coins"] = int(out["coins"]) + Economy.round_price(float(c.get("cosmetic_coins", 0)) * scale, economy)
		else:
			var pick: Dictionary = options[rng.randi_range(0, options.size() - 1)]
			out["cosmetic"] = pick["id"]
			out["cosmetic_kind"] = pick["kind"]
	for b in BOOSTERS:
		if int(out[b]) == 0:
			out.erase(b)
	return out


## Turns a config reward into a concrete one: coins x scale, and a "chest" key rolled into
## its contents (already scaled) and merged in.
static func resolve(reward: Dictionary, rng: RandomNumberGenerator, save: Dictionary, scale := 1.0, economy: Dictionary = {}) -> Dictionary:
	var base := reward.duplicate(true)
	var chest := String(base.get("chest", ""))
	base.erase("chest")
	var out := scaled(base, scale, economy)
	if chest != "":
		out = merge(out, roll_chest(chest, rng, save, scale, economy))
	return out


## Adds a resolved reward to the save (coins, booster tokens, cosmetic). Returns it.
static func apply(save: Dictionary, reward: Dictionary) -> Dictionary:
	save["coins"] = maxi(int(save.get("coins", 0)) + int(reward.get("coins", 0)), 0)
	if not (save.get("boosters") is Dictionary):
		save["boosters"] = {}
	for b in BOOSTERS:
		if reward.has(b):
			save["boosters"][b] = maxi(int(save["boosters"].get(b, 0)) + int(reward[b]), 0)
	var cosmetic := String(reward.get("cosmetic", ""))
	if cosmetic != "":
		if not (save.get("owned") is Array):
			save["owned"] = []
		if not (save["owned"] as Array).has(cosmetic):
			(save["owned"] as Array).append(cosmetic)
	return reward

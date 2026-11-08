class_name Missions
extends RefCounted
## Daily missions, pure. save.missions = {date, list:[{id, stat, icon, goal, progress, done,
## claimed, reward}], bonus_claimed}; save.stats = lifetime counters. Every stat recorded also
## moves today's missions that track it. Finishing and claiming all of them unlocks the bonus
## chest. Tested in tests/test_missions.gd.
##
## Stats the game records (Game.record_stat): kill, kill_<enemy>, bottle, gold_bottle, win,
## stars3, city_coins, build, bomb, shield, upgrade, spin.


static func _cfg(economy: Dictionary) -> Dictionary:
	return Economy.cfg(economy)["missions"]


static func list(save: Dictionary) -> Array:
	return save.get("missions", {}).get("list", [])


static func needs_roll(save: Dictionary, today: String) -> bool:
	return String(save.get("missions", {}).get("date", "")) != today


## Rolls today's missions (once per date): `per_day` entries with distinct stats from the pool,
## weighted, only those with min_level <= level. Goals are drawn from their range and grow
## with the level. Returns false when today's missions already exist.
static func roll(save: Dictionary, today: String, rng_seed: int, level: int = -1, economy: Dictionary = {}) -> bool:
	if not needs_roll(save, today):
		return false
	var c := _cfg(economy)
	if level < 1:
		level = int(save.get("unlocked", 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var pool := []
	for e in c["pool"]:
		if int(e.get("min_level", 1)) <= level:
			pool.append(e)
	var picked := []
	var stats_used := []
	var scale := Economy.reward_scale(level, economy)
	while picked.size() < int(c.get("per_day", 3)) and not pool.is_empty():
		var total := 0.0
		for e in pool:
			total += float(e.get("weight", 1))
		var r := rng.randf() * total
		var idx := pool.size() - 1
		for i in pool.size():
			r -= float(pool[i].get("weight", 1))
			if r < 0.0:
				idx = i
				break
		var e: Dictionary = pool[idx]
		pool.remove_at(idx)
		if stats_used.has(e["stat"]):
			continue
		stats_used.append(e["stat"])
		picked.append(_make(e, level, scale, rng, economy))
	save["missions"] = {"date": today, "list": picked, "bonus_claimed": false}
	return true


static func _make(e: Dictionary, level: int, scale: float, rng: RandomNumberGenerator, economy: Dictionary) -> Dictionary:
	var step := maxi(int(e.get("step", 1)), 1)
	var g: Array = e["goal"]
	var lo := int(ceil(float(g[0]) / step))
	var hi := maxi(int(floor(float(g[1]) / step)), lo)
	var goal := rng.randi_range(lo, hi) * step
	goal = maxi(int(round(goal * (1.0 + float(e.get("per_level", 0.0)) * (level - 1)) / step)) * step, step)
	var reward: Dictionary = Rewards.normalized(e.get("reward", {}))
	reward["coins"] = int(reward.get("coins", 0)) + Economy.round_price(float(e.get("coins", 0)) * scale, economy)
	return {
		"id": String(e["id"]), "stat": String(e["stat"]), "icon": String(e.get("icon", "star_icon")),
		"goal": goal, "progress": 0, "done": false, "claimed": false, "reward": reward,
	}


## Adds to a lifetime stat and to today's missions tracking it. Returns the indices of
## missions that just became done.
static func record(save: Dictionary, stat: String, amount: int) -> Array:
	var done_now := []
	if amount <= 0 or stat == "":
		return done_now
	if not (save.get("stats") is Dictionary):
		save["stats"] = {}
	save["stats"][stat] = int(save["stats"].get(stat, 0)) + amount
	var l := list(save)
	for i in l.size():
		var m: Dictionary = l[i]
		if String(m["stat"]) != stat or bool(m["done"]):
			continue
		m["progress"] = mini(int(m["progress"]) + amount, int(m["goal"]))
		if int(m["progress"]) >= int(m["goal"]):
			m["done"] = true
			done_now.append(i)
	return done_now


## Indices of missions done but not claimed yet.
static func claimable(save: Dictionary) -> Array:
	var out := []
	var l := list(save)
	for i in l.size():
		if bool(l[i]["done"]) and not bool(l[i]["claimed"]):
			out.append(i)
	return out


## Claims mission i: returns its reward dict (coins already scaled) or {} if not claimable.
static func claim(save: Dictionary, i: int) -> Dictionary:
	var l := list(save)
	if i < 0 or i >= l.size() or not bool(l[i]["done"]) or bool(l[i]["claimed"]):
		return {}
	l[i]["claimed"] = true
	return Rewards.normalized(l[i]["reward"])


## True when every mission today is claimed and the bonus chest is still closed.
static func bonus_ready(save: Dictionary) -> bool:
	var l := list(save)
	if l.is_empty() or bool(save.get("missions", {}).get("bonus_claimed", false)):
		return false
	for m in l:
		if not bool(m["claimed"]):
			return false
	return true


## Opens the bonus: returns {"chest": id} to roll, or {} if not ready.
static func claim_bonus(save: Dictionary, economy: Dictionary = {}) -> Dictionary:
	if not bonus_ready(save):
		return {}
	save["missions"]["bonus_claimed"] = true
	return {"chest": String(_cfg(economy).get("bonus_chest", "missions"))}

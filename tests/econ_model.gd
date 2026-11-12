extends RefCounted
## Economy simulation (v1.1 item 5, rebased in spec v2.1 section 3.5): a player plays levels 1-50
## once each, in sessions, and spends coins the way the map's pointer suggests. Uses the game's
## own rules (Economy.level_coins, City, SaveData, Armory gates, config/economy.json,
## config/finale.json), so changing a price or a reward and re-running shows the new curve. The
## player (session rhythm, the finish Bottle Shot is handed, bottles, taps, stars, ads) is below
## in DEFAULTS and PROFILES; it is an assumption, fitted to the investigation's measurements
## (_local/inv/verify_ECON of the v2 worktree), not game data.
##   tests/econ_sim.gd prints the tables and writes _local/pace.json + _local/pace_ads.json;
##   tests/test_economy.gd checks the curve holds.
##
## One row per level won: coins before buying, what was affordable, what got bought, power.

## The no-ad pace (spec v2.1 section 2 "power" profile; tune.gd calibrates the levels on it): a
## player who picks good gates and taps, without ads.
const DEFAULTS := {
	"level_seconds": 180,         # one level incl. result screen and map
	"levels_per_session": 5,
	"sessions_per_day": 3,
	"session_gap_hours": 4.0,     # between sessions of one day
	"night_gap_hours": 12.0,      # last session of a day -> first of the next
	# Bottle Shot as the payout function sees it (Economy.level_coins):
	"troops_share": 0.85,         # the finish / the stored route's (greedy pilot measured 0.75-1.0)
	"bottles_missed": 1,          # normal bottles broken = the level's difficulty count - this
	"gold_chance": 0.6,           # chance the gold bottle breaks
	"heat": 0.9,                  # mean tap heat (the greedy pilot at 2 taps/s: 0.96)
	"x2_share": 0.0,              # share of wins doubled by the x2 rewarded ad
	"stars_per_level": 2.0,       # Harder (spec v2.1 section 2): 40-70% kept, mostly 2 stars
	"mission_coins": 125.0,       # average mission reward (unscaled), 3 a day
	"missions_per_day": 3,
	"buy_cosmetics": true,        # buys a cosmetic when nothing else is affordable
}

## Variants on DEFAULTS. ads: the pace with the x2 ad on half the wins (spec v2 section 6;
## _local/pace_ads.json). engaged: the owner-like player of the investigation (4-level sessions
## every 3 h, every bottle, the gold most times, tapping all level, no ads): its power must stay
## within 1.6x the recommended power (test_engaged_power_ceiling).
const PROFILES := {
	"pace": {},
	"ads": {"x2_share": 0.5},
	"engaged": {"level_seconds": 150, "levels_per_session": 4, "sessions_per_day": 4,
		"session_gap_hours": 3.0, "night_gap_hours": 9.0, "troops_share": 0.95, "bottles_missed": 0,
		"gold_chance": 0.7, "heat": 0.96, "stars_per_level": 2.1},
}

const T0 := 1_800_000_000


static func run(eco: Dictionary, finale: Dictionary, units: Dictionary, opts: Dictionary = {}) -> Array:
	var o := DEFAULTS.duplicate()
	o.merge(opts, true)
	var save := SaveData.default_save()
	save["city_collected_at"] = T0
	var t := T0
	var rows := []
	var stars := 0.0
	var chests := 0
	var day_level := 0
	var per_day := int(o["levels_per_session"]) * int(o["sessions_per_day"])
	var daily_i := 0
	var power_total := 0   # coins spent on squad progress so far
	var play_total := 0    # coins earned by playing so far: first wins + their extras (no ads)
	for L in range(1, Config.LEVEL_COUNT + 1):
		var row := {"level": L, "income": 0, "extra": 0, "boot": 0, "boot_buys": 0}
		var spent := {"power": 0}   # coins this row spends on squad progress (rooms, weapon steps)
		# Start of a session (boot): the welcome-back city coins, and on a new day the daily
		# calendar and the free spin. The player spends them on the map before playing, so they
		# are counted in "boot", not in this win's buys.
		if day_level % int(o["levels_per_session"]) == 0:
			var boot := City.collect(save, t, eco)
			if day_level == 0:
				var scale := Economy.reward_scale(L, eco)
				var day: Dictionary = eco["daily"]["days"][daily_i % 7]
				var extra := float(day.get("coins", 0))
				if day.has("chest"):
					extra += _chest_coins(eco, String(day["chest"]))
				extra += _spin_value(eco)
				boot += int(round(extra * scale))
				daily_i += 1
			save["coins"] = int(save["coins"]) + boot
			row["boot"] = boot
			row["boot_buys"] = _spend(save, t, eco, units, o, spent).size()
		# The squad this player brings into level L (spec v2 calibration rule 2: the no-ad pace).
		# A brand-new player goes straight into level 1 with nothing (the day-1 coins above are
		# spent on the map after it, so they first count at level 2).
		row["pace"] = pace_upgrades(save if L > 1 else SaveData.default_save(), eco, L)
		row["power_cost"] = power_total + int(spent["power"]) if L > 1 else 0
		row["play_before"] = play_total
		t += int(o["level_seconds"])
		# The win, through the one payout function (spec v2.1 section 3.1).
		var finale_coins := win_coins(L, save, eco, finale, o)
		var win := Economy.level_reward(L, finale_coins, false, eco)
		row["income"] = win
		row["replay"] = Economy.level_reward(L, finale_coins, true, eco)
		row["ad"] = int(round(win * float(o["x2_share"])))   # the x2 ad pays the win again
		save["coins"] = int(save["coins"]) + win + int(row["ad"])
		var lib_before := City.districts_liberated(save, eco)
		save["stars"][str(L)] = 2
		save["unlocked"] = mini(L + 1, Config.LEVEL_COUNT)
		var lib_after := City.districts_liberated(save, eco)
		for d in range(lib_before + 1, lib_after + 1):
			row["extra"] = int(row["extra"]) + City.liberation_bonus(d, eco)
		stars += float(o["stars_per_level"])
		var need := Economy.stars_needed_for_chest(chests, eco)
		if stars >= need:
			chests += 1
			row["extra"] = int(row["extra"]) + int(round(_chest_coins(eco, "star") * Economy.reward_scale(L, eco)))
		day_level += 1
		if day_level % int(o["levels_per_session"]) == 0 and day_level >= per_day:
			# End of the day: missions and their bonus chest.
			var m := float(o["mission_coins"]) * int(o["missions_per_day"]) + _chest_coins(eco, "missions")
			row["extra"] = int(row["extra"]) + int(round(m * Economy.reward_scale(L, eco)))
		save["coins"] = int(save["coins"]) + int(row["extra"])
		play_total += win + int(row["extra"])
		# Back on the map: the city storage is collected.
		var city := City.collect(save, t, eco)
		save["coins"] = int(save["coins"]) + city
		row["city"] = city
		row["coins"] = int(save["coins"])
		var aff := Economy.affordable(save, t, eco, units)
		row["affordable"] = aff.size()
		row["affordable_progress"] = aff.filter(func(p): return p["kind"] != "cosmetic").size()
		row["cheapest"] = _cheapest(Economy.purchases(save, t, eco, units))
		var bought := _spend(save, t, eco, units, o, spent)
		power_total += int(spent["power"])
		row["bought"] = bought
		row["buys"] = bought.filter(func(b): return not String(b).begins_with("c:")).size()
		row["left"] = int(save["coins"])
		row["power"] = Economy.save_power(save, units, eco)
		row["rec"] = Economy.recommended_power(L + 1, eco)
		row["income_h"] = int(round(City.income_per_hour(save, t, eco)))
		rows.append(row)
		# Session and day rhythm.
		if day_level % int(o["levels_per_session"]) == 0:
			if day_level >= per_day:
				day_level = 0
				t += int(float(o["night_gap_hours"]) * 3600.0)
			else:
				t += int(float(o["session_gap_hours"]) * 3600.0)
	return rows


## Spends like the map's pointer suggests until nothing useful is affordable (one cosmetic
## when nothing else was). Returns what was bought ("r:training", "w:knives", "b:cafe", "c:fire");
## acc.power sums what went on squad progress (rooms and weapon steps).
static func _spend(save: Dictionary, t: int, eco: Dictionary, units: Dictionary, o: Dictionary, acc: Dictionary = {}) -> Array:
	var bought := []
	while true:
		var best := Economy.best_purchase(save, t, eco, units)
		if best.is_empty():
			break
		if best["kind"] == "room" or best["kind"] == "weapon":
			acc["power"] = int(acc.get("power", 0)) + int(best["cost"])
		_buy(save, best, t, eco)
		bought.append("%s:%s" % [String(best["kind"]).left(1), best["id"]])
	if bought.is_empty() and bool(o["buy_cosmetics"]):
		for p in Economy.affordable(save, t, eco, units):
			if p["kind"] == "cosmetic":
				_buy(save, p, t, eco)
				bought.append("c:" + String(p["id"]))
				break
	return bought


## Bottle Shot's expected coins for this player at level L (Economy.level_coins): the finish
## as a share of the stored route's, the difficulty row's bottles less the missed ones (the
## payout counts up to max_hits), the gold bottle at gold_chance, the taps, the evidence room.
static func win_coins(L: int, save: Dictionary, eco: Dictionary, finale: Dictionary, o: Dictionary) -> int:
	var fx: Dictionary = SaveData.effects(eco, save["station"])
	var counts: Array = finale.get("difficulty", {}).get("count", [3])
	var step := (L - 1) % Economy.district_levels(eco)
	var hits := maxi(int(counts[mini(step, counts.size() - 1)]) - int(o["bottles_missed"]), 0)
	var troops := int(round(float(o["troops_share"]) * 1000.0))
	var st := 1.0 + float(fx["coins"])
	var heat := float(o["heat"])
	var gold := float(o["gold_chance"])
	var with_gold := Economy.level_coins(L, troops, 1000, hits, true, heat, st, eco)
	var without := Economy.level_coins(L, troops, 1000, hits, false, heat, st, eco)
	return int(round(gold * with_gold + (1.0 - gold) * without))


## The upgrades LevelSim gets from this save when playing level L (Game.level_upgrades(_, L):
## the station as that level gets it + Armory multipliers), plus `armory` = {track: steps
## bought} for reading. L = 0: everything owned.
static func pace_upgrades(save: Dictionary, eco: Dictionary, L := 0) -> Dictionary:
	var up := SaveData.effects(eco, Economy.level_station(save["station"], L, eco) if L > 0 else save["station"])
	up["weapons"] = Armory.sim_upgrades(save)["weapons"]
	var steps := {}
	for id in Armory.ids():
		var i := Armory.index(save, String(id))
		if i > 0:
			steps[String(id)] = i
	up["armory"] = steps
	return up


## The no-ad pace (plan v2 Task 13): {level (String): the upgrades this player brings into it}.
## tests/tune.gd profile=paced calibrates the levels against it.
static func pace(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[str(int(r["level"]))] = r["pace"]
	return out


## Plan v2 Task 13 assertion `no_ad_pace_reaches_every_level`: a player who earns coins only by
## playing (first wins and what comes with them: missions, star chests, liberation; no ads, no
## city, no daily calendar or spin) and spends them only on squad progress can afford the
## pace's upgrades at every level, replaying the previous level at most twice (replay_mult).
## {replays: [needed per level, from L1], worst, fails: [levels needing more than 2]}.
static func pace_check(rows: Array) -> Dictionary:
	var replays := []
	var fails := []
	var worst := 0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var need := int(r["power_cost"]) - int(r["play_before"])
		var n := 0
		if need > 0:
			var per := int(rows[i - 1]["replay"]) if i > 0 else 0
			n = int(ceil(float(need) / float(per))) if per > 0 else 999
		replays.append(n)
		worst = maxi(worst, n)
		if n > 2:
			fails.append(int(r["level"]))
	return {"replays": replays, "worst": worst, "fails": fails}


static func _buy(save: Dictionary, p: Dictionary, t: int, eco: Dictionary) -> void:
	if p["kind"] == "weapon":
		Armory.buy(save, String(p["id"]))  # spends the coins itself
		return
	save["coins"] = int(save["coins"]) - int(p["cost"])
	match String(p["kind"]):
		"room":
			save["station"][p["id"]] = int(save["station"].get(p["id"], 0)) + 1
		"building":
			City.start_build(save, String(p["id"]), t, eco)
		"cosmetic":
			(save["owned"] as Array).append(p["id"])


static func _cheapest(list: Array) -> int:
	for p in list:
		if p["kind"] != "cosmetic":
			return int(p["cost"])
	return -1


## Expected coins of a chest (middle of its coin range; a cosmetic roll that falls back to
## coins is left out, so this is a slight underestimate).
static func _chest_coins(eco: Dictionary, id: String) -> float:
	var c: Dictionary = eco.get("chests", {}).get(id, {})
	var r: Array = c.get("coins", [0, 0])
	return (float(r[0]) + float(r[1])) * 0.5


## Expected coins of one free spin (coin slices, plus a spin chest's coins).
static func _spin_value(eco: Dictionary) -> float:
	var total := 0.0
	var v := 0.0
	for s in eco["spin"]["slices"]:
		total += float(s["weight"])
		var r: Dictionary = s["reward"]
		if r.has("coins"):
			v += float(s["weight"]) * float(r["coins"])
		elif r.has("chest"):
			v += float(s["weight"]) * _chest_coins(eco, String(r["chest"]))
	return v / maxf(total, 1.0)


## Every level of district 1 (one training level there is a big step), then about every 2-3.
const REC_ANCHORS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 20, 22, 25, 28, 30, 33, 35, 38, 40, 43, 45, 48, 50]


## economy.json power.recommended fitted to these rows: at each anchor level the Squad Power the
## player brings into it (the row before's power after buying; `start` at L1), lowered where the
## straight line from the previous anchor would pass above a level in between, so every level's
## power meets the recommended one. [[level, power], ...], two decimals, rounded down.
static func fit_recommended(rows: Array, start: float) -> Array:
	var entering := {1: start}
	for r in rows:
		entering[int(r["level"]) + 1] = float(r["power"])
	var out := []
	var prev_l := -1
	var prev_v := 0.0
	for a in REC_ANCHORS:
		var v: float = entering[a]
		if prev_l > 0:
			for L in range(prev_l + 1, a):
				var f := float(L - prev_l) / float(a - prev_l)
				v = minf(v, prev_v + (float(entering[L]) - prev_v) / f)
		v = floorf(v * 100.0) / 100.0
		out.append([a, v])
		prev_l = a
		prev_v = v
	return out


## Share of wins after which the coins bought 1-3 progress items (rooms, weapons, buildings; the
## pointer's picks, cheapest-first ties), and the wins with none or more than 3.
## {in_band, none: [levels], over: [levels]}.
static func summary(rows: Array) -> Dictionary:
	var ok := 0
	var none := []
	var over := []
	for r in rows:
		var n := int(r["buys"])
		if n == 0:
			none.append(r["level"])
		elif n > 3:
			over.append(r["level"])
		else:
			ok += 1
	return {"in_band": float(ok) / maxf(rows.size(), 1.0), "none": none, "over": over}

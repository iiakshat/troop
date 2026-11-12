extends Node
## Global state (autoload "Game"): loaded configs and the player's save, plus the meta game.
## The rules live in pure, tested classes in src/core (SaveData, Economy, City, Daily, Missions,
## Spin, Rewards); Game applies them to the save, writes it after every change, logs analytics
## and emits signals. Time comes from now() (unix seconds) and today() (local "YYYY-MM-DD");
## functions taking `t := -1` use now() unless given a time.
##
## API
## Coins and levels
##   add_coins(n)  spend(n) -> bool  complete_level(n)
##   level_started(level, boosters := {})      call when a level begins (analytics, ad rules)
##   level_reward(level, finale_coins) -> int  what a win pays right now (curve, boss, replay)
##   win_level(level, finale_coins, stars, stats := {}, info := {}) -> Dictionary
##       the one call at a win: adds the coins, keeps best stars, unlocks the next level,
##       records stats (win, stars3 + the given counters). Returns {coins, first_clear, stars,
##       stars_gained, star_chest_ready, liberated (district number or 0), mult}. The result
##       screen's x2 ad then simply calls add_coins(result.coins) again.
##   lose_level(level, stats := {}, info := {})
##   record_stat(stat, amount := 1)  record_stats({stat: amount})   (see Missions for names)
## Stars
##   stars(level)  total_stars()  save_stars(level, n) -> stars gained  level_beaten(level)
##   star_chest_progress() -> {have, need, from, ready}  open_star_chest() -> reward
## Districts: current_district()  district_liberated(d)  districts_liberated()
## Police station: room_level(room)  room_cost(room) (-1 maxed or locked)  room_state(room)
##   -> {lv, max, cost, locked (district to liberate, 0 = open), maxed, can_buy}
##   buy_room(room) -> bool  upgrades()  coin_bonus()
## Squad Power (v2 section 12.4: the HUD's firepower unit, a float; Economy.fmt_power shows it):
##   squad_power()  recommended_power(level)  room_power_gain(room)  weapon_power_gain(id)
##   best_purchase(t) -> {kind: room|weapon|building, id, cost, gain, value} or {} (the map's hand)
##   best_upgrade_after_loss() -> {kind: room|weapon, id, room, cost, gain, value, affordable} or {}
##   (the loss screen)
##   take_improvements() -> [{room, before, after}] bought since the last level start
## New Rank card: rank_card_due(level) -> ally id or ""  mark_rank_card(unit)
## Boosters: boosters() -> {headstart, shield, bomb} (shield / bomb = power charges available)
##   use_booster(id) -> bool  use_boosters({id: n}) -> what was really spent (head start only;
##   shield and bomb come into every level by themselves)
##   booster_ad_available(id) -> bool  grant_booster_ad(id) -> bool (after a rewarded ad)
##   level_upgrades(chosen) -> dict for LevelSim (station effects, armory weapons, the power
##   charges the player has, chosen boosters); remembers the charges brought in
## Powers (v2): power_state(id, t) -> {free, free_max, stored, available, seconds_left}
##   power_available(id, t)  use_power(id, t) -> bool  can_refill_power(id, t)
##   refill_power(id, t) -> bool (after a rewarded ad)  settle_powers(remaining, t) (level end;
##   win_level / lose_level call it when info has "charges")
## Armory (v2): weapon_level(id) -> Vector2i(tier, step)  weapon_cost(id) (-1 maxed)
##   weapon_locked(id)  buy_weapon(id) -> {ok, evolved, tier, step, cost}
## City: city_pending(t)  city_collect(mult := 1, t) -> coins  welcome_back(t) -> coins or 0
##   building_state(id, t) -> dict  start_build(id, t) -> bool  speed_up_build(id, t) -> seconds
##   city_income(t)  city_storage_cap(t)
## Daily: daily_state() -> dict (incl. rewards for the 7 days)  claim_daily() -> reward
## Missions: missions() -> list  claim_mission(i) -> reward  mission_bonus_ready()
##   claim_mission_bonus() -> reward
## Spin: spin_state() -> dict  spin_free() / spin_ad() -> {index, reward} ({} if not allowed)
## Ranks: rank_seen(unit)  mark_rank_seen(unit) -> true the first time
## Alerts: alerts() -> {daily, missions, spin, star_chest, station, armory, city} for the "!" badges
## Cosmetics, hints, settings: owns, pick_cosmetic, outfit, knife_skin, hint_seen, mark_hint,
##   toggle, vibrate, reset_progress.
## Audience (v2): needs_age()  is_child()  set_birth_year(year[, region, locale]); the
##   audience_ready signal tells Ads/Analytics they may start (child-safe when is_child()).
## Rewards returned by claim/open/spin functions are already applied; they hold the concrete
## {coins, headstart, shield, bomb, cosmetic, cosmetic_kind, chest} the UI shows.

const SAVE_PATH := "user://save.json"

signal coins_changed(coins: int)
signal city_changed
signal boosters_changed(boosters: Dictionary)
signal missions_changed
signal stars_changed(total: int)
signal daily_changed
signal spin_changed
signal alerts_changed
signal build_finished(id: String)
signal mission_completed(index: int)
signal powers_changed
signal armory_changed(id: String)
## The age screen was answered (or the answer was loaded): Ads and Analytics may start their
## SDKs now, child-safe when is_child().
signal audience_ready

var units: Dictionary
var economy: Dictionary
var save: Dictionary
var save_path := SAVE_PATH            # "" = never write (tests, headless tools)
var rng := RandomNumberGenerator.new()
var clock_override := -1              # tests: fixed unix time
var date_override := ""               # tests: fixed date

var _attempt := 0                     # level attempts this session
var _booster_ads := {}                # booster id -> [attempt, count]
var _powers_brought := {}             # shield / bomb charges the player took into this level
var _powers_t := 0                    # the clock when they were taken (settle never uses an earlier one)
var _tick := 0.0
var _last_tick := 0


func _ready() -> void:
	# Headless tools and tests (a SceneTree script) must not overwrite the player's save.
	if scripted():
		save_path = ""
	boot()


## True under a SceneTree script (tests, tune, tools): the autoload exists there before its
## _ready runs, so write_save checks this too and never writes the real save.json.
static func scripted() -> bool:
	var ml := Engine.get_main_loop()
	return ml != null and ml.get_script() != null


## Loads configs and the save (or migrates `raw` when given, for tests) and rolls today's
## missions.
func boot(raw: Variant = null) -> void:
	units = Config.units()
	economy = Config.economy()
	rng.randomize()
	if raw == null:
		load_save()
	else:
		save = SaveData.migrate(raw, economy)
	_last_tick = now()
	refresh_day()


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	var t := now()
	var done := City.newly_finished(save, _last_tick, t)
	_last_tick = t
	for id in done:
		_log("build_done", {"id": id, "lv": City.target_level(save, id)})
		build_finished.emit(id)
	if not done.is_empty():
		city_changed.emit()
		alerts_changed.emit()
	if Missions.needs_roll(save, today()):
		refresh_day()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if save:
			refresh_day()
			alerts_changed.emit()


func now() -> int:
	return clock_override if clock_override >= 0 else int(Time.get_unix_time_from_system())


func today() -> String:
	return date_override if date_override != "" else Time.get_date_string_from_system()


func _t(t: int) -> int:
	return t if t >= 0 else now()


func load_save() -> void:
	var raw: Variant = {}
	if FileAccess.file_exists(SAVE_PATH):
		raw = Config.load_json(SAVE_PATH)
	if not (raw is Dictionary and not (raw as Dictionary).is_empty()) and FileAccess.file_exists(SAVE_PATH + ".bak"):
		# save.json is missing or broken (the process died mid-write): use the last good one.
		raw = Config.load_json(SAVE_PATH + ".bak")
	save = SaveData.migrate(raw, economy)


## Atomic: writes save.json.tmp, keeps the previous file as save.json.bak, then renames the
## new file into place, so a kill mid-write never leaves a truncated save.
func write_save() -> void:
	if save_path == "" or (save_path == SAVE_PATH and scripted()):
		return
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(save, "\t"))
	f.close()
	var real := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(real, real + ".bak")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real)


func reset_progress() -> void:
	var age := {"birth_year": save.get("birth_year", 0), "is_child": save.get("is_child", true)}
	save = SaveData.migrate({}, economy)
	if int(age["birth_year"]) > 0:
		save.merge(age, true)  # the age answer survives a progress reset (no re-asking)
	write_save()
	refresh_day()
	coins_changed.emit(int(save["coins"]))
	city_changed.emit()
	boosters_changed.emit(boosters())
	alerts_changed.emit()


## New day: rolls today's missions. Yesterday's missions that were done but not claimed are
## paid out first (finished work is never lost).
func refresh_day() -> void:
	var date := today()
	if not Missions.needs_roll(save, date):
		return
	var paid := false
	for i in Missions.claimable(save):
		_grant(Missions.claim(save, i), 1.0)
		paid = true
	if Missions.bonus_ready(save):
		_grant(Missions.claim_bonus(save, economy))
		paid = true
	Missions.roll(save, date, rng.randi(), int(save["unlocked"]), economy)
	write_save()
	if paid:
		coins_changed.emit(int(save["coins"]))
		boosters_changed.emit(boosters())
	missions_changed.emit()


# ---------------------------------------------------------------- coins and levels

func add_coins(n: int) -> void:
	save["coins"] = maxi(int(save["coins"]) + n, 0)
	write_save()
	coins_changed.emit(int(save["coins"]))
	alerts_changed.emit()


func spend(n: int) -> bool:
	if n < 0 or int(save["coins"]) < n:
		return false
	save["coins"] = int(save["coins"]) - n
	write_save()
	coins_changed.emit(int(save["coins"]))
	alerts_changed.emit()
	return true


func complete_level(n: int) -> void:
	save["unlocked"] = clampi(maxi(int(save["unlocked"]), n + 1), 1, Config.LEVEL_COUNT)
	write_save()


func level_started(level: int, chosen_boosters: Dictionary = {}) -> void:
	_attempt += 1
	_log("level_start", {"level": level, "boosters": chosen_boosters, "attempt": _attempt})
	var ads := _svc("Ads")
	if ads:
		ads.mark_level_start()


func level_reward(level: int, finale_coins: int) -> int:
	return Economy.level_reward(level, finale_coins, level_beaten(level), economy)


func win_level(level: int, finale_coins: int, stars_won: int, stats: Dictionary = {}, info: Dictionary = {}) -> Dictionary:
	var first := not level_beaten(level)
	var coins := level_reward(level, finale_coins)
	if info.get("charges") is Dictionary:
		settle_powers(info["charges"])
	var lib_before := districts_liberated()
	save["coins"] = int(save["coins"]) + coins
	var gained := _set_stars(level, stars_won)
	save["unlocked"] = clampi(maxi(int(save["unlocked"]), level + 1), 1, Config.LEVEL_COUNT)
	var counters := stats.duplicate()
	counters["win"] = int(counters.get("win", 0)) + 1
	if stars_won >= 3:
		counters["stars3"] = int(counters.get("stars3", 0)) + 1
	_record(counters)
	var lib_after := districts_liberated()
	# Liberating a district pays a one-time bonus on top of the level's coins (not doubled by
	# the x2 ad, which doubles `coins` only).
	var lib_bonus := 0
	for d in range(lib_before + 1, lib_after + 1):
		lib_bonus += City.liberation_bonus(d, economy)
	save["coins"] = int(save["coins"]) + lib_bonus
	write_save()
	var params := info.duplicate()
	params.merge({"level": level, "result": "win", "stars": stars_won, "coins": coins, "first": first}, true)
	_log("level_end", params)
	coins_changed.emit(int(save["coins"]))
	stars_changed.emit(total_stars())
	if lib_after != lib_before:
		city_changed.emit()
	alerts_changed.emit()
	return {
		"coins": coins, "first_clear": first, "stars": stars(level), "stars_gained": gained,
		"star_chest_ready": bool(star_chest_progress()["ready"]),
		"liberated": lib_after if lib_after > lib_before else 0,
		"liberation_bonus": lib_bonus,
		"mult": Economy.level_coin_mult(level, economy),
	}


func lose_level(level: int, stats: Dictionary = {}, info: Dictionary = {}) -> void:
	if info.get("charges") is Dictionary:
		settle_powers(info["charges"])
	_record(stats)
	write_save()
	var params := info.duplicate()
	params.merge({"level": level, "result": "loss"}, true)
	_log("level_end", params)


func record_stat(stat: String, amount := 1) -> void:
	record_stats({stat: amount})


func record_stats(stats: Dictionary) -> void:
	_record(stats)
	write_save()


## Adds counters to lifetime stats and today's missions. True if a mission got done.
func _record(stats: Dictionary) -> bool:
	var any := false
	for stat in stats:
		for i in Missions.record(save, String(stat), int(stats[stat])):
			any = true
			var m: Dictionary = Missions.list(save)[i]
			_log("mission_done", {"id": m["id"], "goal": m["goal"]})
			mission_completed.emit(i)
	if any:
		missions_changed.emit()
		alerts_changed.emit()
	return any


# ---------------------------------------------------------------- stars and districts

func stars(level: int) -> int:
	return int(save["stars"].get(str(level), 0))


func total_stars() -> int:
	var n := 0
	for k in save["stars"]:
		n += int(save["stars"][k])
	return n


func level_beaten(level: int) -> bool:
	return City.level_beaten(save, level)


## Keeps the best stars for a level. Returns how many stars were gained.
func save_stars(level: int, n: int) -> int:
	var gained := _set_stars(level, n)
	write_save()
	if gained > 0:
		stars_changed.emit(total_stars())
		alerts_changed.emit()
	return gained


func _set_stars(level: int, n: int) -> int:
	var before := stars(level)
	var best := maxi(before, clampi(n, 0, 3))
	if best > 0:
		save["stars"][str(level)] = best
	return best - before


func star_chest_progress() -> Dictionary:
	var opened := int(save["star_chests_opened"])
	var need := Economy.stars_needed_for_chest(opened, economy)
	var have := total_stars()
	return {"have": have, "need": need, "from": Economy.stars_needed_for_chest(opened - 1, economy) if opened > 0 else 0, "ready": have >= need}


func open_star_chest() -> Dictionary:
	if not bool(star_chest_progress()["ready"]):
		return {}
	save["star_chests_opened"] = int(save["star_chests_opened"]) + 1
	var reward := _grant({"chest": String(economy.get("stars", {}).get("chest", "star"))})
	write_save()
	_log("chest_open", {"chest": "star", "n": int(save["star_chests_opened"])})
	alerts_changed.emit()
	return reward


func current_district() -> int:
	return clampi(Economy.district_of(int(save["unlocked"]), economy), 1, maxi(Economy.district_count(economy), 1))


func district_liberated(d: int) -> bool:
	return City.district_liberated(save, d, economy)


func districts_liberated() -> int:
	return City.districts_liberated(save, economy)


# ---------------------------------------------------------------- police station

func room_level(room: String) -> int:
	return int(save["station"].get(room, 0))


func room_cost(room: String) -> int:
	return SaveData.room_cost(economy, save["station"], room, districts_liberated())


func room_state(room: String) -> Dictionary:
	var lv := room_level(room)
	var mx := Economy.room_max(room, economy)
	var cost := Economy.station_cost(room, lv + 1, economy)
	var locked := SaveData.room_lock(economy, save["station"], room, districts_liberated())
	return {
		"lv": lv, "max": mx, "cost": cost, "locked": locked, "maxed": lv >= mx,
		"can_buy": lv < mx and locked == 0 and cost >= 0 and int(save["coins"]) >= cost,
	}


func buy_room(room: String) -> bool:
	var cost := room_cost(room)
	if cost < 0 or not spend(cost):
		return false
	var before := room_level(room)
	save["station"][room] = before + 1
	_note_improvement(room, before, before + 1)
	_record({"upgrade": 1})
	write_save()
	_log("purchase", {"kind": "room", "id": room, "lv": room_level(room), "cost": cost})
	return true


## Bonuses handed to LevelSim: the station's (squad, capacity, coins) and the armory's
## weapons ({owner: {dmg_mult, rate_mult}}).
func upgrades() -> Dictionary:
	var up := SaveData.effects(economy, save["station"])
	up["weapons"] = Armory.sim_upgrades(save)["weapons"]
	return up


func coin_bonus() -> float:
	return float(upgrades()["coins"])


# ---------------------------------------------------------------- squad power (v1.1)

var _improved: Array = []                # [{room, before, after}] since the last level start


func squad_power() -> float:
	return Economy.save_power(save, units, economy)


func recommended_power(level: int) -> float:
	return Economy.recommended_power(level, economy)


func room_power_gain(room: String) -> float:
	return Economy.room_power_gain(save["station"], room, units, economy)


## Squad Power the next step of weapon track `id` adds (0 for Bottle Shot tracks or maxed).
## units.json allies with the player's Armory multipliers (the Codex's "= N constables").
func upgraded_allies() -> Dictionary:
	return Economy.upgraded_allies(units.get("allies", {}), Armory.sim_upgrades(save)["weapons"])


func weapon_power_gain(id: String) -> float:
	return Economy.weapon_power_gain(save, id, units, economy)


func best_purchase(t := -1) -> Dictionary:
	return Economy.best_purchase(save, _t(t), economy, units)


func best_upgrade_after_loss() -> Dictionary:
	return Economy.best_upgrade_after_loss(save, economy, units)


func _note_improvement(room: String, before: int, after: int) -> void:
	for e in _improved:
		if String(e["room"]) == room:
			e["after"] = after
			return
	_improved.append({"room": room, "before": before, "after": after})


## Upgrades bought since the last call (the next level start shows them briefly), then clears.
func take_improvements() -> Array:
	var out := _improved
	_improved = []
	return out


## The rank whose New Rank card is due before `level`: an ally (not the hero or the starting
## constable) that unlocks at exactly this level, or any earlier one never introduced, whose
## card was not shown yet. "" when none.
func rank_card_due(level: int) -> String:
	var best := ""
	var best_lv := 0
	for id in units.get("allies", {}):
		var lv := maxi(int(units["allies"][id].get("unlock", 1)), 1)
		if lv <= 1 or lv > level or hint_seen("rank_card_" + String(id)) or rank_seen(String(id)):
			continue
		if lv > best_lv:
			best = String(id)
			best_lv = lv
	return best


func mark_rank_card(unit: String) -> void:
	mark_hint("rank_card_" + unit)


# ---------------------------------------------------------------- boosters

func boosters() -> Dictionary:
	var b := (save["boosters"] as Dictionary).duplicate()
	for id in SaveData.POWERS:
		b[id] = power_available(id)
	return b


func use_booster(id: String) -> bool:
	if SaveData.POWERS.has(id):
		return use_power(id)
	if int(save["boosters"].get(id, 0)) <= 0:
		return false
	save["boosters"][id] = int(save["boosters"][id]) - 1
	write_save()
	boosters_changed.emit(boosters())
	return true


## Spends one token of each chosen booster ({id: count}); returns what was really spent.
func use_boosters(chosen: Dictionary) -> Dictionary:
	var used := {}
	for id in chosen:
		if not SaveData.BOOSTERS.has(id):
			continue  # v2: shield and bomb are not taken in as tokens any more
		for k in int(chosen[id]):
			if int(save["boosters"].get(id, 0)) <= 0:
				break
			save["boosters"][id] = int(save["boosters"][id]) - 1
			used[id] = int(used.get(id, 0)) + 1
	if not used.is_empty():
		write_save()
		boosters_changed.emit(boosters())
	return used


## One rewarded ad per booster per level attempt (the attempt about to start).
func booster_ad_available(id: String) -> bool:
	var limit := int(economy.get("boosters", {}).get("ad_per_level", 1))
	var used: Array = _booster_ads.get(id, [-1, 0])
	var count := int(used[1]) if int(used[0]) == _attempt + 1 else 0
	return SaveData.BOOSTERS.has(id) and count < limit


## Gives one booster token after its rewarded ad was watched.
func grant_booster_ad(id: String) -> bool:
	if not booster_ad_available(id):
		return false
	var used: Array = _booster_ads.get(id, [-1, 0])
	var count := int(used[1]) if int(used[0]) == _attempt + 1 else 0
	_booster_ads[id] = [_attempt + 1, count + 1]
	save["boosters"][id] = int(save["boosters"].get(id, 0)) + 1
	write_save()
	boosters_changed.emit(boosters())
	return true


## Station effects plus the boosters chosen for this level: shield / bomb add charges,
## headstart is passed as a count and as headstart_troops (count x boosters.headstart.troops).
## v2: every shield / bomb charge the player has (free + stored) comes along; settle_powers()
## spends the ones used. Chosen shield / bomb (debug runs only) add free extra charges.
func level_upgrades(chosen: Dictionary = {}) -> Dictionary:
	var up := upgrades()
	var b: Dictionary = economy.get("boosters", {})
	_powers_brought = {}
	_powers_t = now()
	for id in SaveData.POWERS:
		_powers_brought[id] = power_available(id, _powers_t)
		up[id] = int(_powers_brought[id]) + int(chosen.get(id, 0)) * int(b.get(id, {}).get("charges", 1))
	up["headstart"] = int(chosen.get("headstart", 0))
	up["headstart_troops"] = int(up["headstart"]) * int(b.get("headstart", {}).get("troops", 5))
	return up


# ---------------------------------------------------------------- powers (v2)

func power_state(id: String, t := -1) -> Dictionary:
	var tt := _t(t)
	return {
		"free": PowersTimer.free_ready(save, id, tt, economy), "free_max": PowersTimer.free_max(id, economy),
		"stored": int(PowersTimer.entry(save, id)["stored"]),
		"available": PowersTimer.available(save, id, tt, economy),
		"seconds_left": PowersTimer.seconds_left(save, id, tt, economy),
	}


func power_available(id: String, t := -1) -> int:
	return PowersTimer.available(save, id, _t(t), economy)


func use_power(id: String, t := -1) -> bool:
	if not PowersTimer.use(save, id, _t(t), economy):
		return false
	write_save()
	powers_changed.emit()
	boosters_changed.emit(boosters())
	return true


## True while a free charge is recharging (the "refill with an ad" button).
func can_refill_power(id: String, t := -1) -> bool:
	return PowersTimer.free_ready(save, id, _t(t), economy) < PowersTimer.free_max(id, economy)


## After the rewarded ad: the free charges are ready now.
func refill_power(id: String, t := -1) -> bool:
	if not can_refill_power(id, t):
		return false
	PowersTimer.refill_free(save, id, _t(t), economy)
	write_save()
	_log("power_refill", {"id": id})
	powers_changed.emit()
	boosters_changed.emit(boosters())
	return true


## Level end: `remaining` = the sim's charges left. Spends the owned charges that were used
## (the level's own and power-gate charges count as used first). Returns {id: spent}.
## The clock is never earlier than the level start: a charge that was ready when the level
## began is always paid for, even if the device clock was moved back during the level.
func settle_powers(remaining: Dictionary, t := -1) -> Dictionary:
	var out := {}
	var tt := maxi(_t(t), _powers_t)
	for id in SaveData.POWERS:
		if not _powers_brought.has(id):
			continue
		out[id] = PowersTimer.settle(save, id, int(_powers_brought[id]), int(remaining.get(id, 0)), tt, economy)
	_powers_brought = {}
	if not out.is_empty():
		write_save()
		powers_changed.emit()
		boosters_changed.emit(boosters())
	return out


# ---------------------------------------------------------------- armory (v2)

func weapon_level(id: String) -> Vector2i:
	return Armory.level(save, id)


func weapon_cost(id: String) -> int:
	return Armory.next_cost(save, id)


func weapon_locked(id: String) -> bool:
	return Armory.is_locked(id, int(save["unlocked"]))


func buy_weapon(id: String) -> Dictionary:
	var before := Armory.index(save, id)
	var r := Armory.buy(save, id)
	if not bool(r["ok"]):
		return r
	_note_improvement(id, before, Armory.index(save, id))
	_record({"upgrade": 1})
	write_save()
	_log("purchase", {"kind": "weapon", "id": id, "tier": r["tier"], "step": r["step"], "cost": r["cost"], "evolved": r["evolved"]})
	coins_changed.emit(int(save["coins"]))
	armory_changed.emit(id)
	alerts_changed.emit()
	return r


# ---------------------------------------------------------------- city

func city_pending(t := -1) -> int:
	return City.pending_income(save, _t(t), economy)


func city_income(t := -1) -> float:
	return City.income_per_hour(save, _t(t), economy)


func city_storage_cap(t := -1) -> int:
	return City.storage_cap(save, _t(t), economy)


## Empties the city storage into coins (mult 2 after the x2 rewarded ad). Returns coins added.
func city_collect(mult := 1, t := -1) -> int:
	var got := City.collect(save, _t(t), economy) * maxi(mult, 1)
	save["coins"] = int(save["coins"]) + got
	if got > 0:
		_record({"city_coins": got})
	write_save()
	_log("city_collect", {"coins": got, "mult": mult})
	coins_changed.emit(int(save["coins"]))
	city_changed.emit()
	alerts_changed.emit()
	return got


## Coins for the welcome-back popup, or 0 when it should not show.
func welcome_back(t := -1) -> int:
	var tt := _t(t)
	var wb: Dictionary = economy["city"].get("welcome_back", {})
	var pending := City.pending_income(save, tt, economy)
	var away := tt - int(save["city_collected_at"])
	if pending >= int(wb.get("min_coins", 1)) and away >= int(wb.get("min_away_seconds", 0)):
		return pending
	return 0


func building_state(id: String, t := -1) -> Dictionary:
	var tt := _t(t)
	var lv := City.target_level(save, id)
	var b := City.building(id, economy)
	return {
		"status": City.status(save, id, tt, economy),
		"reason": City.can_start(save, id, tt, economy),
		"lv": lv, "earning_lv": City.level(save, id, tt), "max": City.max_level(economy),
		"district": int(b.get("district", 0)),
		"cost": City.next_cost(save, id, economy),
		"remaining": City.remaining(save, id, tt),
		"build_time": City.build_time(id, lv + 1, economy),
		"income": City.income_at(id, City.level(save, id, tt), economy),
		"next_income": City.income_at(id, lv + 1, economy) if lv < City.max_level(economy) else 0.0,
		"speedup": City.speedup_seconds(save, id, tt, economy),
	}


func start_build(id: String, t := -1) -> bool:
	var tt := _t(t)
	var cost := City.next_cost(save, id, economy)
	if City.can_start(save, id, tt, economy) != "" or cost < 0 or int(save["coins"]) < cost:
		return false
	save["coins"] = int(save["coins"]) - cost
	City.start_build(save, id, tt, economy)
	if not hint_seen("first_build"):
		(save["seen_hints"] as Array).append("first_build")
	_record({"build": 1})
	write_save()
	_log("purchase", {"kind": "building", "id": id, "lv": City.target_level(save, id), "cost": cost})
	coins_changed.emit(int(save["coins"]))
	city_changed.emit()
	alerts_changed.emit()
	return true


## After a rewarded "speedup" ad: cuts the building's timer. Returns seconds taken off.
func speed_up_build(id: String, t := -1) -> int:
	var tt := _t(t)
	var cut := City.speed_up(save, id, tt, City.speedup_seconds(save, id, tt, economy), economy)
	if cut > 0:
		write_save()
		city_changed.emit()
	return cut


# ---------------------------------------------------------------- daily calendar

func daily_state() -> Dictionary:
	var st := Daily.state(save, today(), economy)
	var rewards := []
	for n in range(1, (economy["daily"]["days"] as Array).size() + 1):
		rewards.append(Rewards.scaled(Daily.reward_for_day(n, economy), _scale(), economy))
	st["rewards"] = rewards
	return st


func claim_daily() -> Dictionary:
	var raw := Daily.claim(save, today(), economy)
	if raw.is_empty():
		return {}
	var reward := _grant(raw)
	write_save()
	_log("daily_claim", {"day": int(save["daily"]["day"]), "streak": int(save["daily"]["streak"])})
	daily_changed.emit()
	alerts_changed.emit()
	return reward


# ---------------------------------------------------------------- missions

func missions() -> Array:
	refresh_day()
	return (Missions.list(save) as Array).duplicate(true)


func claim_mission(i: int) -> Dictionary:
	var raw := Missions.claim(save, i)
	if raw.is_empty():
		return {}
	var reward := _grant(raw, 1.0)
	write_save()
	_log("mission_claim", {"id": Missions.list(save)[i]["id"]})
	missions_changed.emit()
	alerts_changed.emit()
	return reward


func mission_bonus_ready() -> bool:
	return Missions.bonus_ready(save)


func claim_mission_bonus() -> Dictionary:
	var raw := Missions.claim_bonus(save, economy)
	if raw.is_empty():
		return {}
	var reward := _grant(raw)
	write_save()
	_log("chest_open", {"chest": "missions"})
	missions_changed.emit()
	alerts_changed.emit()
	return reward


# ---------------------------------------------------------------- lucky spin

func spin_state() -> Dictionary:
	var probs := []
	for i in Spin.slices(economy).size():
		probs.append(Spin.probability(i, economy))
	var date := today()
	return {
		"free_left": Spin.free_left(save, date, economy), "ad_left": Spin.ad_left(save, date, economy),
		"can_free": Spin.can_spin_free(save, date, economy), "can_ad": Spin.can_spin_ad(save, date, economy),
		"probabilities": probs,
	}


func spin_free() -> Dictionary:
	return _spin("free")


## Call after the "spin" rewarded ad was watched.
func spin_ad() -> Dictionary:
	return _spin("ad")


func _spin(kind: String) -> Dictionary:
	if not Spin.use(save, today(), kind, economy):
		return {}
	var i := Spin.pick(rng, economy)
	var reward := _grant(Spin.slices(economy)[i]["reward"])
	_record({"spin": 1})
	write_save()
	_log("spin", {"kind": kind, "index": i})
	spin_changed.emit()
	alerts_changed.emit()
	return {"index": i, "reward": reward}


# ---------------------------------------------------------------- rewards

## Scale for coin rewards outside levels, from the player's current level.
func _scale() -> float:
	return Economy.reward_scale(int(save["unlocked"]), economy)


## Resolves (scales coins, rolls chests) and applies a config reward. Returns what was given.
func _grant(raw: Dictionary, scale := -1.0) -> Dictionary:
	if raw.is_empty():
		return {}
	var reward := Rewards.resolve(raw, rng, save, _scale() if scale < 0.0 else scale, economy)
	Rewards.apply(save, reward)
	if int(reward.get("coins", 0)) != 0:
		coins_changed.emit(int(save["coins"]))
	for b in SaveData.BOOSTERS + SaveData.POWERS:
		if reward.has(b):
			boosters_changed.emit(boosters())
			if SaveData.POWERS.has(b):
				powers_changed.emit()
			break
	return reward


# ---------------------------------------------------------------- ranks and alerts

func rank_seen(unit: String) -> bool:
	return (save["rank_seen"] as Array).has(unit)


## Marks a rank as seen. True the first time (show the rank card).
func mark_rank_seen(unit: String) -> bool:
	if rank_seen(unit):
		return false
	(save["rank_seen"] as Array).append(unit)
	write_save()
	return true


## What has something to claim or buy (drives the "!" badges).
func alerts(t := -1) -> Dictionary:
	var tt := _t(t)
	var date := today()
	var station := false
	for room in economy["station_order"]:
		var c := room_cost(String(room))
		if c >= 0 and int(save["coins"]) >= c:
			station = true
			break
	var armory := false
	for id in Armory.ids():
		var c := Armory.next_cost(save, String(id))
		if c >= 0 and int(save["coins"]) >= c and not weapon_locked(String(id)):
			armory = true
			break
	var city := City.pending_income(save, tt, economy) >= int(economy["city"].get("welcome_back", {}).get("min_coins", 1))
	if not city:
		for id in City.ids(economy):
			var c := City.next_cost(save, id, economy)
			if c >= 0 and int(save["coins"]) >= c and City.can_start(save, id, tt, economy) == "":
				city = true
				break
	# Until the first building is started, the map has one focus (the pointing hand on a
	# ruin): the gift and wheel badges wait.
	var first := first_build_pending()
	return {
		"daily": Daily.can_claim(save, date, economy) and not first,
		"missions": not Missions.claimable(save).is_empty() or Missions.bonus_ready(save),
		"spin": Spin.can_spin_free(save, date, economy) and not first,
		"star_chest": bool(star_chest_progress()["ready"]),
		"station": station,
		"armory": armory,
		"city": city,
	}


# ---------------------------------------------------------------- cosmetics

func owns(id: String) -> bool:
	return (save["owned"] as Array).has(id)


## Buys (if needed) and equips an outfit or knife skin. kind = "outfits" | "knives".
func pick_cosmetic(kind: String, id: String) -> bool:
	var c := SaveData.cosmetic(economy, kind, id)
	if not owns(id):
		if not spend(int(c["price"])):
			return false
		(save["owned"] as Array).append(id)
		_log("purchase", {"kind": kind, "id": id, "cost": int(c["price"])})
	save["outfit" if kind == "outfits" else "knife"] = id
	write_save()
	return true


func outfit() -> Dictionary:
	return SaveData.cosmetic(economy, "outfits", String(save["outfit"]))


func knife_skin() -> Dictionary:
	return SaveData.cosmetic(economy, "knives", String(save["knife"]))


# ---------------------------------------------------------------- hints and settings

## New player after level 1, before any building was started: the map points at a ruin.
func first_build_pending() -> bool:
	return level_beaten(1) and not hint_seen("first_build")


func hint_seen(id: String) -> bool:
	return (save["seen_hints"] as Array).has(id)


func mark_hint(id: String) -> void:
	if not hint_seen(id):
		(save["seen_hints"] as Array).append(id)
		write_save()


func toggle(key: String) -> bool:
	save[key] = not bool(save.get(key, true))
	write_save()
	return bool(save[key])


func vibrate(ms: int) -> void:
	if bool(save.get("vibration", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- audience (spec v2 §8)
# save["birth_year"] (0 = not asked yet) and save["is_child"] (decided once, when answered, from
# the device region/locale at that time; see Audience). Unknown = child.

## True until the neutral age screen was answered.
func needs_age() -> bool:
	return int(save.get("birth_year", 0)) <= 0


func is_child() -> bool:
	if needs_age():
		return true
	return bool(save.get("is_child", true))


## Stores the age-screen answer and announces it. Region/locale default to the device's.
func set_birth_year(year: int, region := "", locale := "") -> void:
	if locale == "":
		locale = Audience.device_locale()
	if region == "":
		region = Audience.device_region() if locale == Audience.device_locale() else Audience.region_of(locale)
	var now_year := int(Time.get_datetime_dict_from_unix_time(now())["year"])
	save["birth_year"] = year
	save["is_child"] = Audience.is_child(year, now_year, region, locale)
	write_save()
	audience_ready.emit()


# ---------------------------------------------------------------- services

func _svc(name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/" + name)


func _log(name: String, params: Dictionary = {}) -> void:
	var a := _svc("Analytics")
	if a:
		a.event(name, params)

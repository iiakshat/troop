class_name SaveData
extends RefCounted
## Pure helpers for the save file: its default shape, migration of older saves, police-station
## prices and effects, cosmetics. Tested in tests/test_save_data.gd.
##
## v3 keys (besides v2's coins, unlocked, station, owned, outfit, knife, seen_hints, settings):
##   stars {"<level>": 1..3}                 best stars per level (1 = beaten)
##   city {building_id: {lv, built_at, ready_at}}  lv = level built or being built (unix seconds)
##   city_collected_at, city_bank            city storage bookkeeping (see City)
##   boosters {headstart, shield, bomb}      consumable tokens
##   daily {day, last_claim_date, streak}    7-day calendar (day = last claimed day, 0 = none)
##   missions {date, list:[{id, stat, goal, progress, done, claimed, reward}], bonus_claimed}
##   spin {date, free_used, ad_used}
##   star_chests_opened, stats {stat: lifetime count}, rank_seen [unit ids]
##   last_interstitial_level = lifetime wins (stats.win) when the last interstitial showed,
##   last_interstitial_at = unix time of it.
## v4 (Siren Squad v2):
##   armory {track_id: {tier, step}}         weapon tracks (Armory); the station lost knife,
##                                           speed and garage
##   powers {shield|bomb: {stored, ready_at, used}}  free charges on a timer + stored ones
##                                           (PowersTimer); boosters keep only headstart
##   last_seen_time                          latest clock seen by the power timers

const VERSION := 4
const BOOSTERS := ["headstart"]
const POWERS := ["shield", "bomb"]


static func default_save() -> Dictionary:
	return {
		"version": VERSION, "coins": 0, "unlocked": 1,
		"station": {}, "owned": ["street", "steel"], "outfit": "street", "knife": "steel",
		"seen_hints": [], "sound": true, "music": true, "vibration": true,
		"stars": {}, "city": {}, "city_collected_at": 0, "city_bank": 0,
		"boosters": {"headstart": 0},
		"armory": {}, "powers": {
			"shield": {"stored": 0, "ready_at": 0, "used": 0},
			"bomb": {"stored": 0, "ready_at": 0, "used": 0}},
		"last_seen_time": 0,
		"daily": {"day": 0, "last_claim_date": "", "streak": 0},
		"missions": {"date": "", "list": [], "bonus_claimed": false},
		"spin": {"date": "", "free_used": 0, "ad_used": 0},
		"star_chests_opened": 0, "stats": {}, "rank_seen": [],
		"last_interstitial_level": 0, "last_interstitial_at": 0,
	}


## Brings any older or edited save up to the current shape, keeping everything it can.
## v1 lobby upgrades (knife / speed / squad) become armory / range / training levels. v2 saves
## keep their station levels (rooms only grew), get a star for every level they had beaten,
## and receive the starter boosters. v3 -> v4: the coins spent on armory and range levels
## become hero-knife track steps worth at least as much (anything past a maxed track comes
## back as coins), garage level g becomes ceil(g/2) stored shields and floor(g/2) stored bombs
## on top of the shield / bomb tokens the save had. Nothing bought is lost.
static func migrate(raw: Variant, economy: Dictionary) -> Dictionary:
	var s := default_save()
	var src: Dictionary = raw if raw is Dictionary else {}
	var old_version := int(src.get("version", 0)) if _is_num(src.get("version")) else 0
	for k in src:
		s[k] = src[k]

	# Police station.
	var station: Dictionary = src.get("station", {}) if src.get("station", {}) is Dictionary else {}
	if src.get("upgrades") is Dictionary:
		var up: Dictionary = src["upgrades"]
		station["armory"] = maxi(_int(station.get("armory", 0)), _int(up.get("knife", 0)))
		station["range"] = maxi(_int(station.get("range", 0)), _int(up.get("speed", 0)))
		station["training"] = maxi(_int(station.get("training", 0)), _int(up.get("squad", 0)))
		s.erase("upgrades")
	var legacy_knife := 0     # coins spent on the v3 armory and range rooms
	var legacy_garage := 0
	if old_version < 4:
		for room in ["armory", "range"]:
			legacy_knife += legacy_spent(economy, room, _int(station.get(room, 0)))
		var gmax := int(economy.get("legacy_station_v3", {}).get("garage", {}).get("max", 4))
		legacy_garage = clampi(_int(station.get("garage", 0)), 0, gmax)
	var clean := {}
	for room in economy["station"]:
		clean[room] = clampi(_int(station.get(room, 0)), 0, int(economy["station"][room]["max"]))
	s["station"] = clean

	# Cosmetics. The knife skin "gold" shared its id with the gold outfit; it is "golden" now.
	if not (s["owned"] is Array):
		s["owned"] = []
	var owned: Array = s["owned"]
	if old_version < 3 and owned.has("gold") and not owned.has("golden"):
		owned.append("golden")
	if String(s.get("knife", "")) == "gold":
		s["knife"] = "golden"
	for id in ["street", "steel"]:
		if not owned.has(id):
			owned.append(id)
	if not (s["seen_hints"] is Array):
		s["seen_hints"] = []

	s["version"] = VERSION
	s["coins"] = maxi(_int(s["coins"]), 0)
	s["unlocked"] = clampi(_int(s["unlocked"]), 1, Config.LEVEL_COUNT)

	# Stars: keep best 1..3 per real level; older saves get one star per beaten level.
	var stars := {}
	var src_stars: Dictionary = src.get("stars", {}) if src.get("stars") is Dictionary else {}
	for k in src_stars:
		var lv := _int(k)
		var n := clampi(_int(src_stars[k]), 0, 3)
		if lv >= 1 and lv <= Config.LEVEL_COUNT and n > 0:
			stars[str(lv)] = n
	if old_version < 3:
		for lv in range(1, int(s["unlocked"])):
			stars[str(lv)] = maxi(int(stars.get(str(lv), 0)), 1)
	s["stars"] = stars

	# City.
	var city := {}
	var src_city: Dictionary = src.get("city", {}) if src.get("city") is Dictionary else {}
	var buildings: Dictionary = economy.get("city", {}).get("buildings", {})
	var max_lv := int(economy.get("city", {}).get("max_level", 4))
	for id in src_city:
		if not buildings.has(id) or not (src_city[id] is Dictionary):
			continue
		var b: Dictionary = src_city[id]
		var lv := clampi(_int(b.get("lv", 0)), 0, max_lv)
		if lv <= 0:
			continue
		var built_at := maxi(_int(b.get("built_at", 0)), 0)
		var ready_at := maxi(_int(b.get("ready_at", built_at)), built_at)
		city[id] = {"lv": lv, "built_at": built_at, "ready_at": ready_at}
	s["city"] = city
	s["city_collected_at"] = maxi(_int(s.get("city_collected_at", 0)), 0)
	s["city_bank"] = maxi(_int(s.get("city_bank", 0)), 0)

	# Boosters: a save without any gets the starter set.
	var boosters := {}
	var start: Dictionary = economy.get("boosters", {}).get("start", {})
	var src_b: Variant = src.get("boosters")
	for id in BOOSTERS:
		if src_b is Dictionary:
			boosters[id] = maxi(_int((src_b as Dictionary).get(id, 0)), 0)
		else:
			boosters[id] = maxi(_int(start.get(id, 0)), 0)
	s["boosters"] = boosters

	# Powers (v4): free charge timers and stored charges.
	var powers := {}
	var src_p: Dictionary = src.get("powers", {}) if src.get("powers") is Dictionary else {}
	for id in POWERS:
		var p: Dictionary = src_p.get(id, {}) if src_p.get(id) is Dictionary else {}
		powers[id] = {"stored": maxi(_int(p.get("stored", 0)), 0),
			"ready_at": maxi(_int(p.get("ready_at", 0)), 0), "used": maxi(_int(p.get("used", 0)), 0)}
	if old_version < 4:
		var old_tokens: Dictionary = src_b if src_b is Dictionary else {}
		powers["shield"]["stored"] += maxi(_int(old_tokens.get("shield", 0)), 0) + ceili(legacy_garage / 2.0)
		powers["bomb"]["stored"] += maxi(_int(old_tokens.get("bomb", 0)), 0) + floori(legacy_garage / 2.0)
	s["powers"] = powers
	s["last_seen_time"] = maxi(_int(s.get("last_seen_time", 0)), 0)

	# Armory (v4): keep known tracks; v3 knife and speed rooms become knife-track steps.
	var arm := {}
	var src_a: Dictionary = src.get("armory", {}) if src.get("armory") is Dictionary else {}
	var acfg := Armory.cfg()
	for id in src_a:
		if Armory.track(String(id), acfg).is_empty() or not (src_a[id] is Dictionary):
			continue
		arm[String(id)] = {"tier": _int(src_a[id].get("tier", 1)), "step": _int(src_a[id].get("step", 0))}
	s["armory"] = arm
	for id in arm.keys():
		Armory.set_index(s, id, Armory.index(s, id, acfg), acfg)  # clamps junk tiers / steps
	if legacy_knife > 0:
		var knife := String(economy.get("legacy_station_v3", {}).get("knife_track", "knives"))
		var paid := legacy_knife + Armory.spent(s, knife, acfg)
		var idx := int(Armory.steps_for_coins(knife, paid, acfg)["index"])
		# Review v2.1: never past a tier the player's furthest level has not opened yet
		# (armory.json tier_unlock, as Armory.buy); what the kept steps do not cost comes back.
		while idx > 0 and not Armory.tier_unlocked(Armory.at_index(knife, idx, acfg).x, int(s["unlocked"]), acfg):
			idx -= 1
		if idx > Armory.index(s, knife, acfg):
			Armory.set_index(s, knife, idx, acfg)
		s["coins"] = int(s["coins"]) + maxi(paid - Armory.spent_at(knife, Armory.index(s, knife, acfg), acfg), 0)

	# Daily calendar.
	var d: Dictionary = src.get("daily", {}) if src.get("daily") is Dictionary else {}
	s["daily"] = {
		"day": clampi(_int(d.get("day", 0)), 0, 7),
		"last_claim_date": String(d.get("last_claim_date", "")) if d.get("last_claim_date") is String else "",
		"streak": maxi(_int(d.get("streak", 0)), 0),
	}

	# Missions.
	var m: Dictionary = src.get("missions", {}) if src.get("missions") is Dictionary else {}
	var list := []
	if m.get("list") is Array:
		for e in m["list"]:
			if not (e is Dictionary) or not (e as Dictionary).has("stat"):
				continue
			var goal := maxi(_int(e.get("goal", 1)), 1)
			var progress := clampi(_int(e.get("progress", 0)), 0, goal)
			list.append({
				"id": String(e.get("id", e["stat"])), "stat": String(e["stat"]), "goal": goal,
				"progress": progress, "done": progress >= goal,
				"claimed": bool(e.get("claimed", false)) and progress >= goal,
				"reward": e.get("reward", {}) if e.get("reward") is Dictionary else {},
				"icon": String(e.get("icon", "star_icon")),
			})
	s["missions"] = {
		"date": String(m.get("date", "")) if m.get("date") is String else "",
		"list": list,
		"bonus_claimed": bool(m.get("bonus_claimed", false)),
	}

	# Lucky spin.
	var sp: Dictionary = src.get("spin", {}) if src.get("spin") is Dictionary else {}
	s["spin"] = {
		"date": String(sp.get("date", "")) if sp.get("date") is String else "",
		"free_used": maxi(_int(sp.get("free_used", 0)), 0),
		"ad_used": maxi(_int(sp.get("ad_used", 0)), 0),
	}

	# Counters.
	s["star_chests_opened"] = maxi(_int(s.get("star_chests_opened", 0)), 0)
	var stats := {}
	if src.get("stats") is Dictionary:
		for k in src["stats"]:
			stats[String(k)] = maxi(_int(src["stats"][k]), 0)
	s["stats"] = stats
	var seen := []
	if src.get("rank_seen") is Array:
		for u in src["rank_seen"]:
			if u is String and not seen.has(u):
				seen.append(u)
	s["rank_seen"] = seen
	s["last_interstitial_level"] = maxi(_int(s.get("last_interstitial_level", 0)), 0)
	s["last_interstitial_at"] = maxi(_int(s.get("last_interstitial_at", 0)), 0)
	return s


static func _is_num(v: Variant) -> bool:
	return v is int or v is float


## int() that never throws on junk (strings, null, arrays) from a hand-edited save.
static func _int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return (v as String).to_int()
	if v is String and (v as String).is_valid_float():
		return int((v as String).to_float())
	return 0


## Coins a v3 save had spent on the first `lv` levels of a room the station no longer has
## (economy.legacy_station_v3; save migration only).
static func legacy_spent(economy: Dictionary, room: String, lv: int) -> int:
	var r: Dictionary = economy.get("legacy_station_v3", {}).get(room, {})
	if r.is_empty():
		return 0
	var sum := 0
	for k in range(1, clampi(lv, 0, int(r.get("max", 10))) + 1):
		sum += Economy.round_price(float(r["base"]) * pow(float(r["growth"]), k - 1), economy)
	return sum


## Price of the next level of a room, or -1 when it is maxed or still locked behind a district
## (`liberated` = number of districts the player has liberated).
static func room_cost(economy: Dictionary, station: Dictionary, room: String, liberated := 99) -> int:
	if not economy["station"].has(room):
		return -1
	var lv := int(station.get(room, 0)) + 1
	if lv > Economy.room_max(room, economy):
		return -1
	if Economy.station_requirement(room, lv, economy) > liberated:
		return -1
	return Economy.station_cost(room, lv, economy)


## District to liberate before the next level of a room can be bought (0 = open or maxed).
static func room_lock(economy: Dictionary, station: Dictionary, room: String, liberated: int) -> int:
	var lv := int(station.get(room, 0)) + 1
	if lv > Economy.room_max(room, economy):
		return 0
	var need := Economy.station_requirement(room, lv, economy)
	return need if need > liberated else 0


## What the sim and economy get from the station.
static func effects(economy: Dictionary, station: Dictionary) -> Dictionary:
	var out := {"squad": 0, "capacity": 0, "coins": 0.0}
	for room in economy["station"]:
		var r: Dictionary = economy["station"][room]
		var lv := int(station.get(room, 0))
		match String(r["effect"]):
			"squad", "capacity":
				out[r["effect"]] = lv * int(r["per"])
			"coins":
				out["coins"] = lv * float(r["per"])
	return out


static func cosmetic(economy: Dictionary, kind: String, id: String) -> Dictionary:
	for c in economy["cosmetics"][kind]:
		if c["id"] == id:
			return c
	return economy["cosmetics"][kind][0]

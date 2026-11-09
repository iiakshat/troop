class_name City
extends RefCounted
## Rebuild-the-city rules, pure: districts, building prices and timers, offline income and its
## storage cap. Times are unix seconds passed in by the caller (Game uses the system clock), so
## tests are deterministic. Numbers live in config/economy.json "city".
##
## A building entry in the save is {lv, built_at, ready_at}: lv is the level built (or being
## built); until ready_at it still earns at lv - 1, so upgrading never pauses income. Income
## accrues from city_collected_at into a storage that holds a few hours of income (more with
## City Hall). Before any building changes, the income so far is banked (city_bank) so every
## coin is counted at the rate that was really in force. If the clock moves back, nothing
## accrues (never negative). Tested in tests/test_city.gd.


static func cfg(economy: Dictionary = {}) -> Dictionary:
	return Economy.cfg(economy)["city"]


# ---------------------------------------------------------------- static content

static func building(id: String, economy: Dictionary = {}) -> Dictionary:
	return cfg(economy)["buildings"].get(id, {})


## Every building id, district by district.
static func ids(economy: Dictionary = {}) -> Array:
	var out := []
	for d in cfg(economy)["districts"]:
		out.append_array(d["buildings"])
	return out


static func buildings_in(district: int, economy: Dictionary = {}) -> Array:
	for d in cfg(economy)["districts"]:
		if int(d["id"]) == district:
			return (d["buildings"] as Array).duplicate()
	return []


static func max_level(economy: Dictionary = {}) -> int:
	return int(cfg(economy).get("max_level", 4))


## Coins to build level `lv` (1 = rebuild the ruin, 2.. = upgrades). -1 if invalid.
static func cost(id: String, lv: int, economy: Dictionary = {}) -> int:
	var b := building(id, economy)
	if b.is_empty() or lv < 1 or lv > max_level(economy):
		return -1
	var mult: Array = cfg(economy)["upgrade_cost_mult"]
	return Economy.round_price(float(b["cost"]) * float(mult[lv - 1]), economy)


## Seconds it takes to build level `lv`.
static func build_time(id: String, lv: int, economy: Dictionary = {}) -> int:
	var b := building(id, economy)
	if b.is_empty() or lv < 1 or lv > max_level(economy):
		return 0
	var c := cfg(economy)
	var mult: Array = c["upgrade_time_mult"]
	return mini(int(round(float(b["time"]) * float(mult[lv - 1]))), int(c.get("max_build_seconds", 14400)))


## Coins per hour a building earns at level `lv` (0 for a ruin).
static func income_at(id: String, lv: int, economy: Dictionary = {}) -> float:
	var b := building(id, economy)
	if b.is_empty() or lv <= 0:
		return 0.0
	return float(b["income"]) * pow(float(cfg(economy)["income_mult"]), lv - 1)


# ---------------------------------------------------------------- districts

static func level_beaten(save: Dictionary, level: int) -> bool:
	return int(save.get("stars", {}).get(str(level), 0)) >= 1 or level < int(save.get("unlocked", 1))


## A district is liberated once its last (boss) level is beaten.
static func district_liberated(save: Dictionary, d: int, economy: Dictionary = {}) -> bool:
	return d >= 1 and level_beaten(save, d * Economy.district_levels(economy))


## A district is reached (its buildings can be rebuilt) once the one before it is liberated.
static func district_reached(save: Dictionary, d: int, economy: Dictionary = {}) -> bool:
	return d <= 1 or district_liberated(save, d - 1, economy)


## How many districts in a row, from the first, are liberated.
static func districts_liberated(save: Dictionary, economy: Dictionary = {}) -> int:
	var n := 0
	while n < Economy.district_count(economy) and district_liberated(save, n + 1, economy):
		n += 1
	return n


# ---------------------------------------------------------------- building state

static func entry(save: Dictionary, id: String) -> Dictionary:
	return save.get("city", {}).get(id, {})


## Level built or under construction (0 = ruin).
static func target_level(save: Dictionary, id: String) -> int:
	return int(entry(save, id).get("lv", 0))


## Seconds left on a building's timer (0 when done). Never more than the build's full length,
## even if the clock was moved back.
static func remaining(save: Dictionary, id: String, now: int) -> int:
	var e := entry(save, id)
	if e.is_empty():
		return 0
	var ready := int(e["ready_at"])
	return clampi(ready - now, 0, maxi(ready - int(e["built_at"]), 0))


static func is_ready(save: Dictionary, id: String, now: int) -> bool:
	return target_level(save, id) >= 1 and remaining(save, id, now) == 0


static func is_building(save: Dictionary, id: String, now: int) -> bool:
	return target_level(save, id) >= 1 and remaining(save, id, now) > 0


## Level a building earns at right now. now < 0 counts every timer as finished.
static func level(save: Dictionary, id: String, now: int = -1) -> int:
	var lv := target_level(save, id)
	if now >= 0 and remaining(save, id, now) > 0:
		return lv - 1
	return lv


## locked (district not reached) | ruin | building | built (can upgrade) | upgrade_locked
## (district not liberated yet) | maxed
static func status(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> String:
	var b := building(id, economy)
	if b.is_empty() or not district_reached(save, int(b["district"]), economy):
		return "locked"
	var lv := target_level(save, id)
	if lv == 0:
		return "ruin"
	if remaining(save, id, now) > 0:
		return "building"
	if lv >= max_level(economy):
		return "maxed"
	if bool(cfg(economy).get("upgrade_needs_liberation", true)) and not district_liberated(save, int(b["district"]), economy):
		return "upgrade_locked"
	return "built"


## Price of the next level, or -1 when maxed.
static func next_cost(save: Dictionary, id: String, economy: Dictionary = {}) -> int:
	return cost(id, target_level(save, id) + 1, economy)


static func builders_busy(save: Dictionary, now: int) -> int:
	var n := 0
	for id in save.get("city", {}):
		if remaining(save, id, now) > 0:
			n += 1
	return n


static func builders_free(save: Dictionary, now: int, economy: Dictionary = {}) -> int:
	return maxi(int(cfg(economy).get("max_parallel_builds", 1)) - builders_busy(save, now), 0)


## "" when a build or upgrade can start now (coins aside), otherwise why not:
## locked | building | maxed | upgrade_locked | builders (all builders busy).
static func can_start(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> String:
	var st := status(save, id, now, economy)
	if st != "ruin" and st != "built":
		return st
	if builders_free(save, now, economy) <= 0:
		return "builders"
	return ""


## Starts building the next level (the caller has already taken the coins). Banks the income
## earned so far first, so the accounting stays exact.
static func start_build(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> bool:
	if can_start(save, id, now, economy) != "":
		return false
	settle(save, now, economy)
	var lv := target_level(save, id) + 1
	if not (save.get("city") is Dictionary):
		save["city"] = {}
	save["city"][id] = {"lv": lv, "built_at": now, "ready_at": now + build_time(id, lv, economy)}
	return true


## Seconds a rewarded-ad speed-up would take off this building's timer.
static func speedup_seconds(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> int:
	var rem := remaining(save, id, now)
	var sp: Dictionary = cfg(economy).get("speedup_ad", {})
	var cut := maxi(int(ceil(rem * float(sp.get("fraction", 0.5)))), int(sp.get("min_seconds", 0)))
	return mini(cut, rem)


## Takes `seconds` off a running timer (never past done). Returns the seconds taken off.
static func speed_up(save: Dictionary, id: String, now: int, seconds: int, economy: Dictionary = {}) -> int:
	var rem := remaining(save, id, now)
	if rem <= 0 or seconds <= 0:
		return 0
	settle(save, now, economy)
	var cut := mini(seconds, rem)
	var e: Dictionary = save["city"][id]
	e["ready_at"] = now + rem - cut
	e["built_at"] = mini(int(e["built_at"]), int(e["ready_at"]))
	return cut


## Buildings whose timers finished in (from_t, to_t].
static func newly_finished(save: Dictionary, from_t: int, to_t: int) -> Array:
	var out := []
	for id in save.get("city", {}):
		var r := int(save["city"][id]["ready_at"])
		if r > from_t and r <= to_t:
			out.append(id)
	return out


# ---------------------------------------------------------------- income and storage

## Coins per hour of every finished level. now < 0 counts running timers as finished.
static func income_per_hour(save: Dictionary, now: int = -1, economy: Dictionary = {}) -> float:
	var total := 0.0
	for id in save.get("city", {}):
		total += income_at(id, level(save, id, now), economy)
	return total


static func storage_cap_hours(save: Dictionary, now: int = -1, economy: Dictionary = {}) -> float:
	var st: Dictionary = cfg(economy)["storage"]
	return float(st["base_hours"]) + float(st["hours_per_level"]) * level(save, String(st["city_hall"]), now)


## Most coins the storage can hold right now.
static func storage_cap(save: Dictionary, now: int, economy: Dictionary = {}) -> int:
	return floori(income_per_hour(save, now, economy) * storage_cap_hours(save, now, economy))


## Exact income between two times: each building earns at lv - 1 until its timer ends and
## at lv afterwards. Zero when to_t <= from_t (clock moved back).
static func accrued(save: Dictionary, from_t: int, to_t: int, economy: Dictionary = {}) -> float:
	if to_t <= from_t:
		return 0.0
	var total := 0.0
	for id in save.get("city", {}):
		var e: Dictionary = save["city"][id]
		var lv := int(e["lv"])
		var split := clampi(int(e["ready_at"]), from_t, to_t)
		total += income_at(id, lv - 1, economy) * (split - from_t) / 3600.0
		total += income_at(id, lv, economy) * (to_t - split) / 3600.0
	return total


## Coins waiting in storage now (banked + accrued, capped). Never negative.
static func pending_income(save: Dictionary, now: int, economy: Dictionary = {}) -> int:
	var cap := float(storage_cap(save, now, economy))
	var bank := float(save.get("city_bank", 0.0))
	var got := bank + accrued(save, int(save.get("city_collected_at", 0)), now, economy)
	return floori(clampf(got, 0.0, cap))


## Moves income earned so far into the bank (capped) and restarts the accrual clock.
static func settle(save: Dictionary, now: int, economy: Dictionary = {}) -> void:
	var since := int(save.get("city_collected_at", 0))
	if now <= since:
		return
	var cap := float(storage_cap(save, now, economy))
	var bank := float(save.get("city_bank", 0.0)) + accrued(save, since, now, economy)
	save["city_bank"] = clampf(bank, 0.0, cap)
	save["city_collected_at"] = now


## Empties the storage: returns the coins (the caller adds them). If the clock is far behind
## the last collection (more than a full storage), the clock is resynced to now.
static func collect(save: Dictionary, now: int, economy: Dictionary = {}) -> int:
	var amount := pending_income(save, now, economy)
	var since := int(save.get("city_collected_at", 0))
	save["city_bank"] = 0.0
	if now > since:
		save["city_collected_at"] = now
	elif since - now > int(storage_cap_hours(save, now, economy) * 3600.0):
		save["city_collected_at"] = now
	return amount


## The pending coins split by building, in proportion to what each earns (for coin bubbles).
static func pending_by_building(save: Dictionary, now: int, economy: Dictionary = {}) -> Dictionary:
	var out := {}
	var total := income_per_hour(save, now, economy)
	var pending := pending_income(save, now, economy)
	if total <= 0.0 or pending <= 0:
		return out
	for id in save.get("city", {}):
		var inc := income_at(id, level(save, id, now), economy)
		if inc > 0.0:
			out[id] = floori(pending * inc / total)
	return out

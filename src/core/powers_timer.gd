class_name PowersTimer
extends RefCounted
## Shield and bomb charges (spec v2 section 7), pure. Each power has economy.powers.free[id]
## free charges that recharge together powers.recharge_s seconds after the first of them is
## used, plus stored charges (daily rewards, spin, chests, ads) on top. Free charges are used
## first. save.powers[id] = {stored, ready_at, used} (used = free charges spent since the timer
## started); save.last_seen_time = the latest clock seen when a charge was used or refilled.
## Clock guard (like the daily calendar): a clock moved back never makes a charge ready (the
## ready time is absolute and kept), and a new timer starts from the latest time seen, so
## winding the clock forward and back cannot chain refills. Tested in tests/test_powers_timer.gd.

const IDS := ["shield", "bomb"]


static func _cfg(economy: Dictionary) -> Dictionary:
	return Economy.cfg(economy).get("powers", {})


static func free_max(id: String, economy: Dictionary = {}) -> int:
	return maxi(int(_cfg(economy).get("free", {}).get(id, 1)), 0)


static func recharge_s(economy: Dictionary = {}) -> int:
	return maxi(int(_cfg(economy).get("recharge_s", 18000)), 0)


## The save's entry for a power, created (and repaired) on demand.
static func entry(save: Dictionary, id: String) -> Dictionary:
	if not (save.get("powers") is Dictionary):
		save["powers"] = {}
	var p: Variant = save["powers"].get(id)
	if not (p is Dictionary):
		p = {}
		save["powers"][id] = p
	for k in ["stored", "ready_at", "used"]:
		p[k] = maxi(SaveData._int(p.get(k, 0)), 0)
	return p


## Free charges ready at `now`.
static func free_ready(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> int:
	var p := entry(save, id)
	var n := free_max(id, economy)
	if now >= int(p["ready_at"]):
		return n
	return clampi(n - int(p["used"]), 0, n)


## Charges the player can take into a level now: free ready + stored.
static func available(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> int:
	return free_ready(save, id, now, economy) + int(entry(save, id)["stored"])


## Seconds until the free charges are all back (0 when they are).
static func seconds_left(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> int:
	if free_ready(save, id, now, economy) >= free_max(id, economy):
		return 0
	return maxi(int(entry(save, id)["ready_at"]) - now, 0)


static func _seen(save: Dictionary, now: int) -> int:
	var last := maxi(SaveData._int(save.get("last_seen_time", 0)), now)
	save["last_seen_time"] = last
	return last


## Uses one charge: a free one first (its timer starts with the first free one used), else a
## stored one. False when there is none.
static func use(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> bool:
	var p := entry(save, id)
	if free_ready(save, id, now, economy) > 0:
		var last := _seen(save, now)
		if now >= int(p["ready_at"]):
			p["used"] = 0
		p["used"] = int(p["used"]) + 1
		if int(p["used"]) == 1:
			p["ready_at"] = last + recharge_s(economy)
		return true
	if int(p["stored"]) > 0:
		p["stored"] = int(p["stored"]) - 1
		_seen(save, now)
		return true
	return false


## The rewarded "refill now": every free charge is ready at once.
static func refill_free(save: Dictionary, id: String, now: int, economy: Dictionary = {}) -> void:
	var p := entry(save, id)
	_seen(save, now)
	p["used"] = 0
	p["ready_at"] = 0


static func add_stored(save: Dictionary, id: String, n: int) -> void:
	var p := entry(save, id)
	p["stored"] = maxi(int(p["stored"]) + n, 0)


## After a level: the player brought `brought` owned charges and `remaining` charges of that
## power were left at the end (the level's own and power-gate charges count as used first).
## Spends the difference from the save; returns how many owned charges were spent.
static func settle(save: Dictionary, id: String, brought: int, remaining: int, now: int, economy: Dictionary = {}) -> int:
	var spent := clampi(brought - remaining, 0, maxi(brought, 0))
	var done := 0
	for i in spent:
		if use(save, id, now, economy):
			done += 1
	return done

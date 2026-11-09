class_name Spin
extends RefCounted
## Lucky spin, pure. Each slice's chance is exactly weight / total weight, and the wheel must be
## drawn with each slice's angle in that same proportion (probability(i) x 360 degrees): the
## picture never misstates the odds. save.spin = {date, free_used, ad_used}; the counters reset
## on a new date. Tested in tests/test_spin.gd.


static func _cfg(economy: Dictionary) -> Dictionary:
	return Economy.cfg(economy)["spin"]


static func slices(economy: Dictionary = {}) -> Array:
	return _cfg(economy)["slices"]


static func total_weight(economy: Dictionary = {}) -> float:
	var t := 0.0
	for s in slices(economy):
		t += float(s["weight"])
	return t


## Chance of slice i (0..1). Also its share of the wheel's circle.
static func probability(i: int, economy: Dictionary = {}) -> float:
	var s := slices(economy)
	if i < 0 or i >= s.size():
		return 0.0
	return float(s[i]["weight"]) / total_weight(economy)


## Weighted pick: slice index.
static func pick(rng: RandomNumberGenerator, economy: Dictionary = {}) -> int:
	var s := slices(economy)
	var r := rng.randf() * total_weight(economy)
	for i in s.size():
		r -= float(s[i]["weight"])
		if r < 0.0:
			return i
	return s.size() - 1


static func _today_state(save: Dictionary, today: String) -> Dictionary:
	var sp: Dictionary = save.get("spin", {})
	# Only a later date resets the counters ("YYYY-MM-DD" compares as a string): moving the
	# clock back keeps today's used spins, so toggling the date grants nothing.
	if today > String(sp.get("date", "")):
		return {"date": today, "free_used": 0, "ad_used": 0}
	return sp


static func free_left(save: Dictionary, today: String, economy: Dictionary = {}) -> int:
	return maxi(int(_cfg(economy).get("free_per_day", 1)) - int(_today_state(save, today)["free_used"]), 0)


static func ad_left(save: Dictionary, today: String, economy: Dictionary = {}) -> int:
	return maxi(int(_cfg(economy).get("ad_per_day", 0)) - int(_today_state(save, today)["ad_used"]), 0)


static func can_spin_free(save: Dictionary, today: String, economy: Dictionary = {}) -> bool:
	return free_left(save, today, economy) > 0


static func can_spin_ad(save: Dictionary, today: String, economy: Dictionary = {}) -> bool:
	return free_left(save, today, economy) == 0 and ad_left(save, today, economy) > 0


## Uses one spin of the kind ("free" or "ad"). Returns false if none is left.
static func use(save: Dictionary, today: String, kind: String, economy: Dictionary = {}) -> bool:
	var ok := can_spin_free(save, today, economy) if kind == "free" else can_spin_ad(save, today, economy)
	if not ok:
		return false
	var st := _today_state(save, today).duplicate()
	var key := "free_used" if kind == "free" else "ad_used"
	st[key] = int(st[key]) + 1
	save["spin"] = st
	return true

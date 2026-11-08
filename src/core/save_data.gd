class_name SaveData
extends RefCounted
## Pure helpers for the save file and upgrade prices.


## Price of the next level of an upgrade, or -1 when it is maxed.
static func upgrade_cost(economy: Dictionary, id: String, current: int) -> int:
	var up: Dictionary = economy["upgrades"].get(id, {})
	if up.is_empty() or current >= int(up["max"]):
		return -1
	return int(up["costs"][current])


## Keeps only known upgrade ids, clamped to their max (protects against old or edited saves).
static func clean_upgrades(raw: Variant, economy: Dictionary) -> Dictionary:
	var out := {}
	var src: Dictionary = raw if raw is Dictionary else {}
	for id in economy["upgrades"]:
		var mx := int(economy["upgrades"][id]["max"])
		out[id] = clampi(int(src.get(id, 0)), 0, mx)
	return out

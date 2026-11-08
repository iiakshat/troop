class_name SaveData
extends RefCounted
## Pure helpers for the save file: police-station prices and effects, cosmetics, and
## migration of older saves. Tested in tests/test_save_data.gd.

const VERSION := 2


static func default_save() -> Dictionary:
	return {
		"version": VERSION, "coins": 0, "unlocked": 1,
		"station": {}, "owned": ["street", "steel"], "outfit": "street", "knife": "steel",
		"seen_hints": [], "sound": true, "music": true, "vibration": true,
	}


## Brings any older or edited save up to the current shape. v1 lobby upgrades
## (knife / speed / squad) become armory / range / training levels.
static func migrate(raw: Variant, economy: Dictionary) -> Dictionary:
	var s := default_save()
	var src: Dictionary = raw if raw is Dictionary else {}
	for k in src:
		s[k] = src[k]
	var station: Dictionary = src.get("station", {}) if src.get("station", {}) is Dictionary else {}
	if src.get("upgrades") is Dictionary:
		var up: Dictionary = src["upgrades"]
		station["armory"] = maxi(int(station.get("armory", 0)), int(up.get("knife", 0)))
		station["range"] = maxi(int(station.get("range", 0)), int(up.get("speed", 0)))
		station["training"] = maxi(int(station.get("training", 0)), int(up.get("squad", 0)))
		s.erase("upgrades")
	var clean := {}
	for room in economy["station"]:
		clean[room] = clampi(int(station.get(room, 0)), 0, int(economy["station"][room]["max"]))
	s["station"] = clean
	for id in ["street", "steel"]:
		if not (s["owned"] as Array).has(id):
			(s["owned"] as Array).append(id)
	s["version"] = VERSION
	s["coins"] = maxi(int(s["coins"]), 0)
	s["unlocked"] = clampi(int(s["unlocked"]), 1, Config.LEVEL_COUNT)
	return s


## Price of the next level of a room, or -1 when it is maxed or still locked.
static func room_cost(economy: Dictionary, station: Dictionary, room: String) -> int:
	var r: Dictionary = economy["station"].get(room, {})
	if r.is_empty() or not room_unlocked(economy, station, room):
		return -1
	var lv := int(station.get(room, 0))
	if lv >= int(r["max"]):
		return -1
	return int(r["costs"][lv])


## Rooms can still carry a "desk" requirement, but none do now: everything is open.
static func room_unlocked(economy: Dictionary, station: Dictionary, room: String) -> bool:
	return int(station.get("desk", 0)) >= int(economy["station"][room].get("desk", 0))


## What the sim and economy get from the station.
static func effects(economy: Dictionary, station: Dictionary) -> Dictionary:
	var out := {"knife": 0, "speed": 0, "squad": 0, "capacity": 0, "coins": 0.0, "shield": 0, "bomb": 0}
	for room in economy["station"]:
		var r: Dictionary = economy["station"][room]
		var lv := int(station.get(room, 0))
		match String(r["effect"]):
			"knife", "speed", "squad", "capacity":
				out[r["effect"]] = lv * int(r["per"])
			"coins":
				out["coins"] = lv * float(r["per"])
			"charges":
				out["shield"] = 1 if lv >= 1 else 0
				out["bomb"] = 1 if lv >= 2 else 0
	return out


static func cosmetic(economy: Dictionary, kind: String, id: String) -> Dictionary:
	for c in economy["cosmetics"][kind]:
		if c["id"] == id:
			return c
	return economy["cosmetics"][kind][0]

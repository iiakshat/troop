class_name TouchClassifier
extends RefCounted
## Tap or swipe (spec v2 §2), per finger. Pure logic, no nodes, tested.
## A touch that stays within `tap_max_px` of where it went down and lifts within `tap_max_s`
## is a tap: it fires and never steers. Once a touch moves past `tap_max_px` it is a swipe for
## good: it steers and never fires. A still hold that lasts longer is neither.
## Numbers: config/units.json "input". `density` scales the pixel threshold (screen scale).

var tap_max_px := 15.0
var tap_max_s := 0.25
var zone_top := 0.5
var _touches: Dictionary = {}   # id -> {from: Vector2, t: float, steer: bool}


func _init(cfg: Dictionary = {}, density := 1.0) -> void:
	tap_max_px = float(cfg.get("tap_max_px", tap_max_px)) * maxf(density, 1.0)
	tap_max_s = float(cfg.get("tap_max_s", tap_max_s))
	zone_top = float(cfg.get("zone_top", zone_top))


func press(id: int, pos: Vector2, t: float) -> void:
	_touches[id] = {"from": pos, "t": t, "steer": false}


## "steer" for every move of a finger that has become a swipe, else "".
func move(id: int, pos: Vector2, _t: float) -> String:
	if not _touches.has(id):
		return ""
	var tc: Dictionary = _touches[id]
	if not tc["steer"] and pos.distance_to(tc["from"]) > tap_max_px:
		tc["steer"] = true
	return "steer" if tc["steer"] else ""


## "tap", "steer_end" (a swipe lifted) or "" (a long still hold, or an unknown finger).
func release(id: int, pos: Vector2, t: float) -> String:
	if not _touches.has(id):
		return ""
	var tc: Dictionary = _touches[id]
	_touches.erase(id)
	if tc["steer"]:
		return "steer_end"
	if pos.distance_to(tc["from"]) > tap_max_px:
		return ""   # moved past the threshold between events and lifted at once: not a tap
	return "tap" if t - float(tc["t"]) <= tap_max_s else ""


## Where the finger went down (for the swipe anchor), or null.
func origin(id: int) -> Variant:
	return (_touches[id] as Dictionary)["from"] if _touches.has(id) else null


func is_steering(id: int) -> bool:
	return _touches.has(id) and bool((_touches[id] as Dictionary)["steer"])


## The tap zone: the lower part of the screen, from `zone_top` of its height down.
func in_zone(pos: Vector2, screen: Vector2) -> bool:
	return pos.y >= screen.y * zone_top


func clear() -> void:
	_touches.clear()

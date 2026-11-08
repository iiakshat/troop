extends Node
## Global state: loaded configs and the player's save (coins, unlocked level, police
## station rooms, cosmetics, settings, hints already shown). Rules live in SaveData.

const SAVE_PATH := "user://save.json"

signal coins_changed(coins: int)

var units: Dictionary
var economy: Dictionary
var save: Dictionary


func _ready() -> void:
	units = Config.units()
	economy = Config.economy()
	load_save()


func load_save() -> void:
	var raw: Variant = {}
	if FileAccess.file_exists(SAVE_PATH):
		raw = Config.load_json(SAVE_PATH)
	save = SaveData.migrate(raw, economy)


func write_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save, "\t"))


func reset_progress() -> void:
	save = SaveData.default_save()
	save = SaveData.migrate(save, economy)
	write_save()


# ---------------------------------------------------------------- coins and levels

func add_coins(n: int) -> void:
	save["coins"] = int(save["coins"]) + n
	write_save()
	coins_changed.emit(int(save["coins"]))


func spend(n: int) -> bool:
	if n < 0 or int(save["coins"]) < n:
		return false
	save["coins"] = int(save["coins"]) - n
	write_save()
	coins_changed.emit(int(save["coins"]))
	return true


func complete_level(n: int) -> void:
	save["unlocked"] = clampi(maxi(int(save["unlocked"]), n + 1), 1, Config.LEVEL_COUNT)
	write_save()


# ---------------------------------------------------------------- police station

func room_level(room: String) -> int:
	return int(save["station"].get(room, 0))


func room_cost(room: String) -> int:
	return SaveData.room_cost(economy, save["station"], room)


func buy_room(room: String) -> bool:
	var cost := room_cost(room)
	if cost < 0 or not spend(cost):
		return false
	save["station"][room] = room_level(room) + 1
	write_save()
	return true


## Bonuses handed to LevelSim (knife, speed, squad, shield, bomb).
func upgrades() -> Dictionary:
	return SaveData.effects(economy, save["station"])


func coin_bonus() -> float:
	return float(upgrades()["coins"])


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
	save["outfit" if kind == "outfits" else "knife"] = id
	write_save()
	return true


func outfit() -> Dictionary:
	return SaveData.cosmetic(economy, "outfits", String(save["outfit"]))


func knife_skin() -> Dictionary:
	return SaveData.cosmetic(economy, "knives", String(save["knife"]))


# ---------------------------------------------------------------- hints and settings

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

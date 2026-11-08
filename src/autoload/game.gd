extends Node
## Global state: loaded configs and the player's save (coins, unlocked level, upgrades).

const SAVE_PATH := "user://save.json"

var units: Dictionary
var economy: Dictionary
var save := {
	"coins": 0,
	"unlocked": 1,
	"upgrades": {"knife": 0, "speed": 0, "squad": 0},
	"sound": true,
	"vibration": true,
}


func _ready() -> void:
	units = Config.units()
	economy = Config.economy()
	load_save()


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = Config.load_json(SAVE_PATH)
	if data is Dictionary:
		for k in data:
			save[k] = data[k]
	save["upgrades"] = SaveData.clean_upgrades(save.get("upgrades", {}), economy)


func write_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save, "\t"))


func upgrades() -> Dictionary:
	return save["upgrades"]


func upgrade_cost(id: String) -> int:
	return SaveData.upgrade_cost(economy, id, int(upgrades().get(id, 0)))


func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or int(save["coins"]) < cost:
		return false
	save["coins"] = int(save["coins"]) - cost
	upgrades()[id] = int(upgrades().get(id, 0)) + 1
	write_save()
	return true


func add_coins(n: int) -> void:
	save["coins"] = int(save["coins"]) + n
	write_save()


func complete_level(n: int) -> void:
	save["unlocked"] = clampi(maxi(int(save["unlocked"]), n + 1), 1, Config.LEVEL_COUNT)
	write_save()


func vibrate(ms: int) -> void:
	if bool(save.get("vibration", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)

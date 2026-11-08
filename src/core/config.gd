class_name Config
extends RefCounted
## Loads the JSON tuning files in config/. Pure, so tests and tools can use it headless.

const LEVEL_COUNT := 5


static func load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Config: cannot open %s" % path)
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null:
		push_error("Config: bad JSON in %s" % path)
		return {}
	return data


static func units() -> Dictionary:
	return load_json("res://config/units.json")


static func economy() -> Dictionary:
	return load_json("res://config/economy.json")


static func level(n: int) -> Dictionary:
	return load_json("res://config/levels/level_%d.json" % n)

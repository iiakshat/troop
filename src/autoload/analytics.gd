extends Node
## Analytics stub (autoload "Analytics"). No SDK and no network: events are appended as JSON
## lines to user://events.log ({"t": unix, "s": session, "e": name, "p": params}). When the file
## would pass analytics.max_bytes (config/economy.json, 2 MB) it is moved to events.old.log and
## a new one starts, so at most about twice that is kept. A real SDK (e.g. Firebase) can be
## dropped in behind event() later; collect nothing personal (see ../CLAUDE.md, privacy).
##
## Call sites: session_start, level_start, level_end (result, stars, troops, time), purchase
## (room / building / cosmetic), ad_offer, ad_watch, ad_interstitial (placement), daily_claim,
## mission_done, mission_claim, spin, city_collect, build_done.

const LOG_PATH := "user://events.log"
const OLD_PATH := "user://events.old.log"

var enabled := true
var max_bytes := 2 * 1024 * 1024
var log_path := LOG_PATH
var old_path := OLD_PATH
var session := ""


func _ready() -> void:
	var a: Dictionary = Config.economy().get("analytics", {})
	enabled = bool(a.get("enabled", true))
	max_bytes = int(a.get("max_bytes", max_bytes))
	# Headless tools and tests (a SceneTree script) must not touch the player's log.
	if Engine.get_main_loop() and Engine.get_main_loop().get_script() != null:
		enabled = false
	session = "%08x" % (randi() & 0x7fffffff)
	event("session_start", {
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"os": OS.get_name(),
	})


func event(name: String, params: Dictionary = {}) -> void:
	if not enabled:
		return
	var line := JSON.stringify({"t": int(Time.get_unix_time_from_system()), "s": session, "e": name, "p": params})
	_append(line)


func _append(line: String) -> void:
	var f: FileAccess = null
	if FileAccess.file_exists(log_path):
		f = FileAccess.open(log_path, FileAccess.READ_WRITE)
		if f == null:
			return
		if f.get_length() + line.to_utf8_buffer().size() + 1 > max_bytes:
			f.close()
			_rotate()
			f = FileAccess.open(log_path, FileAccess.WRITE)
		else:
			f.seek_end()
	else:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if f:
		f.store_line(line)
		f.close()


func _rotate() -> void:
	var old_abs := ProjectSettings.globalize_path(old_path)
	var log_abs := ProjectSettings.globalize_path(log_path)
	if FileAccess.file_exists(old_path):
		DirAccess.remove_absolute(old_abs)
	DirAccess.rename_absolute(log_abs, old_abs)


## The last `limit` events in the current log, newest last (debug and tests).
func read_events(limit := 100) -> Array:
	var out := []
	if not FileAccess.file_exists(log_path):
		return out
	var f := FileAccess.open(log_path, FileAccess.READ)
	if f == null:
		return out
	for raw in f.get_as_text().split("\n", false):
		var v: Variant = JSON.parse_string(raw)
		if v is Dictionary:
			out.append(v)
	return out.slice(maxi(out.size() - limit, 0))

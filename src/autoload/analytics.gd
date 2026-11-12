extends Node
## Analytics stub (autoload "Analytics"). No SDK and no network: events are appended as JSON
## lines to user://events.log ({"t": unix, "s": session, "e": name, "p": params}). When the file
## would pass analytics.max_bytes (config/economy.json, 2 MB) it is moved to events.old.log and
## a new one starts, so at most about twice that is kept. A real SDK (e.g. Firebase) can be
## dropped in behind event() later; collect nothing personal (see ../CLAUDE.md, privacy).
##
## Call sites: session_start, level_start, level_end (result, stars, troops, time), purchase
## (room / building / cosmetic), ad_offer, ad_watch, ad_interstitial (placement), daily_claim,
## mission_done, mission_claim, spin, city_collect, build_done, tap_rate (note_tap/end_taps).
##
## Provider (v2 §8): "firebase" only for an adult (age screen answered, Game.is_child() false)
## on a build with the Firebase plugin (singletons GodotxFirebaseCore + GodotxFirebaseAnalytics);
## otherwise "local". For a child Firebase is never started (the build removes Firebase's
## auto-start provider, so nothing runs until initialize() is called here) and every event,
## including tap_rate, stays in the local log. The local log is always written (PC, debug).
## Firebase: ad-ID and SSAID collection are off in the manifest (addons/siren_privacy);
## consent: analytics_storage granted, ad_storage / ad_user_data / ad_personalization denied.

const LOG_PATH := "user://events.log"
const OLD_PATH := "user://events.old.log"
const FB_CORE := "GodotxFirebaseCore"
const FB_ANALYTICS := "GodotxFirebaseAnalytics"
const TAP_BUCKET := 10.0
## Firebase reserves these event names (and the firebase_ / google_ / ga_ prefixes).
const RESERVED := ["ad_activeview", "ad_click", "ad_exposure", "ad_impression", "ad_query",
	"ad_reward", "adunit_exposure", "app_background", "app_clear_data", "app_exception",
	"app_remove", "app_store_refund", "app_store_subscription_cancel",
	"app_store_subscription_convert", "app_store_subscription_renew", "app_update",
	"app_upgrade", "dynamic_link_app_open", "dynamic_link_app_update",
	"dynamic_link_first_open", "error", "first_open", "first_visit", "in_app_purchase",
	"notification_dismiss", "notification_foreground", "notification_open",
	"notification_receive", "os_update", "session_start", "session_start_with_rollout",
	"user_engagement"]

var provider := "local"      # "local" | "firebase"
var sink := Callable()       # tests: receives every event (name, params)
var enabled := true
var max_bytes := 2 * 1024 * 1024
var log_path := LOG_PATH
var old_path := OLD_PATH
var session := ""
var _fb: Object = null       # GodotxFirebaseAnalytics once it is running
var _fb_started := false
var _taps := {}              # {level, bucket, taps} for the open tap_rate bucket


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
	var g: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if g and g.has_signal("audience_ready"):
		g.audience_ready.connect(start_sdk)
		if not g.needs_age():
			start_sdk.call_deferred()


## "firebase" only for an adult with the plugin present.
static func provider_for(is_child: bool, has_plugin: bool) -> String:
	return "firebase" if has_plugin and not is_child else "local"


## Starts Firebase for an adult once the audience is known. A child: nothing starts, ever.
func start_sdk() -> void:
	if _fb_started or not is_inside_tree():
		return
	var g: Node = get_node_or_null("/root/Game")
	var child: bool = g == null or g.is_child()
	var has := Engine.has_singleton(FB_CORE) and Engine.has_singleton(FB_ANALYTICS)
	if provider_for(child, has) != "firebase" or not enabled:
		return
	_fb_started = true
	var core: Object = Engine.get_singleton(FB_CORE)
	var fa: Object = Engine.get_singleton(FB_ANALYTICS)
	fa.connect("analytics_initialized", func(ok: bool):
		if not ok:
			return
		fa.call("set_consent", {"analytics_storage": "granted", "ad_storage": "denied",
			"ad_user_data": "denied", "ad_personalization": "denied"})
		fa.call("set_analytics_collection_enabled", true)
		_fb = fa
		provider = "firebase", CONNECT_ONE_SHOT)
	core.connect("core_initialized", func(ok: bool):
		if ok:
			fa.call("initialize"), CONNECT_ONE_SHOT)
	core.call("initialize")


func event(name: String, params: Dictionary = {}) -> void:
	if sink.is_valid():
		sink.call(name, params)
	# A SceneTree script (tests, tools) never writes the player's log, even before _ready ran.
	if not enabled or (Engine.get_main_loop() != null and Engine.get_main_loop().get_script() != null):
		return
	var line := JSON.stringify({"t": int(Time.get_unix_time_from_system()), "s": session, "e": name, "p": params})
	_append(line)
	if _fb != null and provider == "firebase":
		_fb.call("log_event", firebase_name(name), firebase_params(params))


## A valid Firebase event name: [a-z0-9_], starts with a letter, at most 40 characters, never a
## reserved name or prefix (those get a "game_" prefix).
static func firebase_name(name: String) -> String:
	var out := ""
	for ch in name.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" else "_"
	if out == "" or not (out[0] >= "a" and out[0] <= "z"):
		out = "e_" + out
	if out in RESERVED or out.begins_with("firebase_") or out.begins_with("google_") or out.begins_with("ga_"):
		out = "game_" + out
	return out.substr(0, 40)


## Firebase parameters: at most 25, names like event names, values int / float / string
## (strings cut to 100 characters, bools as 0/1, anything else as JSON text).
static func firebase_params(params: Dictionary) -> Dictionary:
	var out := {}
	for k in params:
		if out.size() >= 25:
			break
		var v: Variant = params[k]
		var key := firebase_name(String(k))
		match typeof(v):
			TYPE_INT, TYPE_FLOAT:
				out[key] = v
			TYPE_BOOL:
				out[key] = 1 if v else 0
			TYPE_STRING, TYPE_STRING_NAME:
				out[key] = String(v).substr(0, 100)
			_:
				out[key] = JSON.stringify(v).substr(0, 100)
	return out


## Tap-to-fire measurement (v2 §2): call on every hero tap with the seconds since the level
## started; taps are counted in 10 s buckets and logged as tap_rate {level, bucket, taps} when a
## bucket closes. Call end_taps() when the level ends. Children: local log only (provider).
func note_tap(level: int, seconds: float) -> void:
	var bucket := int(floor(maxf(seconds, 0.0) / TAP_BUCKET))
	if not _taps.is_empty() and (int(_taps["level"]) != level or int(_taps["bucket"]) != bucket):
		end_taps()
	if _taps.is_empty():
		_taps = {"level": level, "bucket": bucket, "taps": 0}
	_taps["taps"] = int(_taps["taps"]) + 1


func end_taps() -> void:
	if _taps.is_empty():
		return
	var t := _taps
	_taps = {}
	event("tap_rate", t)


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

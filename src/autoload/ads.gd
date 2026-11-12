extends Node
## Ads facade (autoload "Ads"). The rest of the game only talks to this interface.
## Provider (v2 §8): "admob" on an Android build with the AdMob plugin (addons/AdmobPlugin,
## singleton "AdmobPlugin"), else "placeholder" (PC, headless, tests, autoplay, skip_ads, or
## config/ads.json provider = "placeholder"). AdMob starts only after the age screen
## (Game.audience_ready), with request_config(Game.is_child()):
##   child: child-directed, under age of consent, max rating G, non-personalised, no ad/first-party
##          ID, no UMP form
##   adult: UMP consent form first where required (GDPR regions), then normal ads, max rating
##          from config/ads.json adult_tags (G or PG; the Families policy cap for mixed audiences)
## IDs: Google's official test IDs until the owner sets is_real (config/ads.json). When AdMob
## has no rewarded ad ready (no network, still loading) the placeholder popup stands in, so the
## reward button always works; a missing interstitial is simply skipped.
##
## Rewarded (always opt-in, the player taps a button with the ad icon):
##   Ads.show_rewarded(placement, func(ok: bool): ...)
##   Ads.note_offer(placement)   call when an ad button is shown (analytics; a revive offer also
##                               blocks the next interstitial)
## Interstitials (config economy.ads.interstitial): only between levels, from level from_level,
## at most one per every_levels completed (won) levels, at least min_seconds apart, never right
## after a rewarded ad or a revive offer, always closable. Ask can_show_interstitial(level)
## with the level just finished, then show_interstitial(placement[, on_closed]).
## Call mark_level_start() when a level starts (Game.level_started does).
## Placements: x2_coins, revive, x2_offline, spin, booster_headstart, booster_shield,
## booster_bomb, speed_up.
##
## Stub placeholder (owner, 2026-11-08): every ad opens a blank full-screen popup
## (ad_placeholder.gd: CanvasLayer 100, countdown number in a shrinking ring, ad icon, close X,
## no words) and pauses the game while it shows. Rewarded: economy.ads.rewarded_seconds, reward
## only at 0, closing early = cb(false). Interstitial: interstitial_seconds, then the X, closing
## itself interstitial_close_after seconds later. Skipped instantly (reward granted at once)
## when headless, when skip_ads is set, or when the game runs with autoplay=1 / skip_ads=1.
## Analytics: ad_offer (button shown), ad_start (popup opened), ad_watch (watched to the end),
## ad_skip (closed early).

signal reward_granted(placement: String)
signal interstitial_shown(placement: String)
signal interstitial_closed(placement: String)

const Placeholder := preload("res://src/autoload/ad_placeholder.gd")

const ADMOB_SINGLETON := "AdmobPlugin"
const ADMOB_NODE := "res://addons/AdmobPlugin/Admob.gd"
const ADS_CONFIG := "res://config/ads.json"

var stub_mode := true        # true while the placeholder provider is active
var provider := "placeholder"  # "placeholder" | "admob"
var skip_ads := false        # debug: no popup, rewards at once (main.gd / autoplay)
var cfg: Dictionary = {}     # economy.ads (placements, timings, interstitial rules)
var ads_cfg: Dictionary = {} # config/ads.json (provider, IDs, audience tags)
var consent := ""            # UMP outcome: "", "not_required", "obtained", "required", "error"
var _admob: Node = null      # the plugin's Admob node when provider == "admob"
var _sdk_started := false
var _pending_rewarded := {}  # {placement, cb, earned} while a real rewarded ad shows
var _pending_interstitial := {}  # {placement, on_closed} while a real interstitial shows
var _blocked := false        # a rewarded ad or revive offer since the last level start
var _popup: CanvasLayer = null
var _was_paused := false


func _ready() -> void:
	cfg = Config.economy().get("ads", {})
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		if kv[0] in ["autoplay", "skip_ads"] and (kv.size() < 2 or kv[1] != "0"):
			skip_ads = true
	var raw: Variant = Config.load_json(ADS_CONFIG)
	ads_cfg = raw if raw is Dictionary else {}
	var g: Node = get_node_or_null("/root/Game")
	if g and g.has_signal("audience_ready"):
		g.audience_ready.connect(start_sdk)
		if not g.needs_age():
			start_sdk.call_deferred()


## Which provider to use: AdMob only with the plugin present, ads not skipped, and the config
## not forcing the placeholder.
static func provider_for(has_plugin: bool, skip: bool, wanted := "admob") -> String:
	if wanted != "admob" or skip or not has_plugin:
		return "placeholder"
	return "admob"


## The ad-request settings for an audience (config/ads.json child_tags / adult_tags; the child
## values are fixed by the spec and cannot be loosened by config).
static func request_config(is_child: bool, acfg: Dictionary = {}) -> Dictionary:
	if is_child:
		return {"child_directed": true, "under_age_of_consent": true, "max_rating": "G",
			"npa": true, "ad_id": false, "consent_form": false}
	var a: Dictionary = acfg.get("adult_tags", {})
	var rating := String(a.get("max_rating", "PG"))
	if not rating in ["G", "PG"]:
		rating = "PG"  # Families policy: a mixed-audience app shows adults at most PG
	return {"child_directed": false, "under_age_of_consent": false, "max_rating": rating,
		"npa": bool(a.get("npa", false)), "ad_id": bool(a.get("ad_id", true)),
		"consent_form": bool(a.get("consent_form", true))}


## Starts the ad SDK once the audience is known (Game.audience_ready, or at boot when the age
## screen was answered before). Safe to call more than once.
func start_sdk() -> void:
	if _sdk_started or not is_inside_tree():
		return
	var has_plugin := Engine.has_singleton(ADMOB_SINGLETON) and ResourceLoader.exists(ADMOB_NODE)
	provider = provider_for(has_plugin, skip_ads, String(ads_cfg.get("provider", "admob")))
	stub_mode = provider == "placeholder"
	if stub_mode:
		return
	_sdk_started = true
	var g: Node = get_node_or_null("/root/Game")
	var rc := request_config(g == null or g.is_child(), ads_cfg)
	_admob = _make_admob(rc)
	add_child(_admob)
	_log("ad_sdk", {"provider": provider, "child": rc["child_directed"]})
	if rc["consent_form"]:
		_admob.consent_info_updated.connect(_on_consent_info, CONNECT_ONE_SHOT)
		_admob.consent_info_update_failed.connect(func(_e): _consent_done("error"), CONNECT_ONE_SHOT)
		_admob.update_consent_info()
	else:
		_init_admob()


func _make_admob(rc: Dictionary) -> Node:
	var a: Node = load(ADMOB_NODE).new()
	var real := bool(ads_cfg.get("is_real", false))
	var ids: Dictionary = ads_cfg.get("android", {}).get("real" if real else "test", {})
	a.is_real = real
	if real:
		a.android_real_rewarded_id = String(ids.get("rewarded", ""))
		a.android_real_interstitial_id = String(ids.get("interstitial", ""))
	else:
		a.android_debug_rewarded_id = String(ids.get("rewarded", ""))
		a.android_debug_interstitial_id = String(ids.get("interstitial", ""))
	# AdmobConfig enums: ContentRating G/PG/T/MA = 0..3; tags TRUE=1, FALSE=0;
	# PersonalizationState DISABLED=2 (non-personalised only), DEFAULT=0.
	a.max_ad_content_rating = ["G", "PG", "T", "MA"].find(String(rc["max_rating"]))
	a.child_directed = 1 if rc["child_directed"] else 0
	a.under_age_of_consent = 1 if rc["under_age_of_consent"] else 0
	a.personalization_state = 2 if rc["npa"] else 0
	a.first_party_id_enabled = bool(rc["ad_id"])
	a.auto_configure_on_initialize = true
	a.remove_interstitial_ads_after_displayed = true
	a.remove_rewarded_ads_after_displayed = true
	var hashed: Array[String] = []
	for d in ads_cfg.get("test_device_hashed_ids", []):
		hashed.append(String(d))
	a.test_device_hashed_ids = hashed
	a.initialization_completed.connect(func(_s): _load_all())
	a.rewarded_ad_failed_to_load.connect(func(_i, _e): _retry_load("rewarded"))
	a.interstitial_ad_failed_to_load.connect(func(_i, _e): _retry_load("interstitial"))
	a.rewarded_ad_user_earned_reward.connect(func(_i, _r): _pending_rewarded["earned"] = true)
	a.rewarded_ad_dismissed_full_screen_content.connect(func(_i): _real_rewarded_closed())
	a.rewarded_ad_failed_to_show_full_screen_content.connect(func(_i, _e): _real_rewarded_closed())
	a.interstitial_ad_dismissed_full_screen_content.connect(func(_i): _real_interstitial_closed())
	a.interstitial_ad_failed_to_show_full_screen_content.connect(func(_i, _e): _real_interstitial_closed())
	return a


func _on_consent_info() -> void:
	var st: Object = _admob.get_consent_status()
	var status := String(st.to_status_string()) if st != null else ""
	if status == "REQUIRED" and _admob.is_consent_form_available():
		_admob.consent_form_loaded.connect(func(): _admob.show_consent_form(), CONNECT_ONE_SHOT)
		_admob.consent_form_failed_to_load.connect(func(_e): _consent_done("error"), CONNECT_ONE_SHOT)
		_admob.consent_form_dismissed.connect(func(_e): _consent_done("obtained"), CONNECT_ONE_SHOT)
		_admob.load_consent_form()
	else:
		_consent_done("not_required" if status == "NOT_REQUIRED" else status.to_lower())


func _consent_done(outcome: String) -> void:
	if consent != "":
		return
	consent = outcome
	_log("ad_consent", {"outcome": outcome})
	_init_admob()


func _init_admob() -> void:
	_admob.set_request_configuration()  # child tags before anything is requested
	_admob.initialize()


func _load_all() -> void:
	_admob.load_rewarded_ad()
	_admob.load_interstitial_ad()


func _retry_load(kind: String) -> void:
	# No fill or no network: try again later, never in a tight loop.
	var wait := float(ads_cfg.get("load_timeout_seconds", 8)) * 4.0
	get_tree().create_timer(wait, true).timeout.connect(func():
		if _admob == null:
			return
		if kind == "rewarded" and not _admob.is_rewarded_ad_loaded():
			_admob.load_rewarded_ad()
		elif kind == "interstitial" and not _admob.is_interstitial_ad_loaded():
			_admob.load_interstitial_ad())


## True when a real AdMob ad of `kind` is ready to show right now.
func real_ad_ready(kind: String) -> bool:
	if provider != "admob" or _admob == null:
		return false
	return _admob.is_rewarded_ad_loaded() if kind == "rewarded" else _admob.is_interstitial_ad_loaded()


func _real_rewarded_closed() -> void:
	if _pending_rewarded.is_empty():
		return
	var p := _pending_rewarded
	_pending_rewarded = {}
	_resume()
	_rewarded_done(String(p["placement"]), p["cb"], bool(p.get("earned", false)), 0)
	_admob.load_rewarded_ad()


func _real_interstitial_closed() -> void:
	if _pending_interstitial.is_empty():
		return
	var p := _pending_interstitial
	_pending_interstitial = {}
	_resume()
	_interstitial_done(String(p["placement"]), p["on_closed"])
	_admob.load_interstitial_ad()


func _pause_for_real_ad() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true


func _resume() -> void:
	if is_inside_tree():
		get_tree().paused = _was_paused


## True while a placeholder ad covers the screen.
func is_showing() -> bool:
	return _popup != null or not _pending_rewarded.is_empty() or not _pending_interstitial.is_empty()


## No popup: headless runs, tests, autoplay, or the skip_ads flag.
func skips_popup() -> bool:
	return skip_ads or not is_inside_tree() or DisplayServer.get_name() == "headless"


## Shows a rewarded ad and calls cb(true) once it was watched to the end, cb(false) if it was
## closed early (or another ad is already showing). reward_granted fires before cb(true).
func show_rewarded(placement: String, cb: Callable) -> void:
	_blocked = true
	if is_showing():
		_call(cb, false)
		return
	_log("ad_start", {"placement": placement, "kind": "rewarded", "provider": _source("rewarded")})
	if skips_popup():
		_rewarded_done(placement, cb, true, 0)
		return
	if real_ad_ready("rewarded"):
		_pending_rewarded = {"placement": placement, "cb": cb, "earned": false}
		_pause_for_real_ad()
		_admob.show_rewarded_ad()
		return
	var seconds := float(cfg.get("rewarded_seconds", 5))
	_open("rewarded", seconds, 0.0, func(ok: bool, left: int): _rewarded_done(placement, cb, ok, left))


func note_offer(placement: String) -> void:
	if placement == "revive":
		_blocked = true
	_log("ad_offer", {"placement": placement})


func mark_level_start() -> void:
	_blocked = false


## The interstitial rules as a pure function (tested in tests/test_ads.gd).
static func rule(level: int, wins: int, last_wins: int, seconds_since: int, blocked: bool, icfg: Dictionary) -> bool:
	if blocked:
		return false
	if level < int(icfg.get("from_level", 6)):
		return false
	if wins - last_wins < int(icfg.get("every_levels", 2)):
		return false
	return seconds_since >= int(icfg.get("min_seconds", 0))


## May an interstitial show now, after finishing `level`?
func can_show_interstitial(level: int) -> bool:
	if not is_inside_tree() or _popup != null:
		return false
	var g: Node = get_node_or_null("/root/Game")
	if g == null:
		return false
	var s: Dictionary = g.save
	var wins := int(s.get("stats", {}).get("win", 0))
	var since := int(g.now()) - int(s.get("last_interstitial_at", 0))
	return rule(level, wins, int(s.get("last_interstitial_level", 0)), since, _blocked, cfg.get("interstitial", {}))


## Shows an interstitial and records it for the spacing rules. on_closed() (optional) runs when
## it is gone (at once when the popup is skipped).
func show_interstitial(placement := "between_levels", on_closed := Callable()) -> void:
	if is_showing():
		_call0(on_closed)
		return
	if provider == "admob" and not skips_popup() and not real_ad_ready("interstitial"):
		_call0(on_closed)  # AdMob has nothing ready (no network): skip, never a blank popup
		return
	var g: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if g:
		g.save["last_interstitial_level"] = int(g.save.get("stats", {}).get("win", 0))
		g.save["last_interstitial_at"] = int(g.now())
		g.write_save()
	_log("ad_start", {"placement": placement, "kind": "interstitial", "provider": _source("interstitial")})
	interstitial_shown.emit(placement)
	if skips_popup():
		_interstitial_done(placement, on_closed)
		return
	if real_ad_ready("interstitial"):
		_pending_interstitial = {"placement": placement, "on_closed": on_closed}
		_pause_for_real_ad()
		_admob.show_interstitial_ad()
		return
	_open("interstitial", float(cfg.get("interstitial_seconds", 3)),
		float(cfg.get("interstitial_close_after", 2)),
		func(_ok: bool, _left: int): _interstitial_done(placement, on_closed))


## "admob" when a real ad will show, else "placeholder" (analytics).
func _source(kind: String) -> String:
	return "admob" if real_ad_ready(kind) and not skips_popup() else "placeholder"


func _rewarded_done(placement: String, cb: Callable, ok: bool, left: int) -> void:
	if ok:
		_log("ad_watch", {"placement": placement, "kind": "rewarded"})
		reward_granted.emit(placement)
	else:
		_log("ad_skip", {"placement": placement, "kind": "rewarded", "seconds_left": left})
	_call(cb, ok)


func _interstitial_done(placement: String, on_closed: Callable) -> void:
	_log("ad_watch", {"placement": placement, "kind": "interstitial"})
	interstitial_closed.emit(placement)
	_call0(on_closed)


## Opens the placeholder, pauses the game, and calls done(completed, seconds_left) after the
## popup is gone and the game runs again.
func _open(kind: String, seconds: float, close_after: float, done: Callable) -> void:
	var p := Placeholder.new()
	p.setup(kind, seconds, close_after)
	_popup = p
	_was_paused = get_tree().paused
	get_tree().paused = true
	p.finished.connect(func(completed: bool):
		var left: int = p.seconds_left()
		_close_popup()
		done.call(completed, left), CONNECT_ONE_SHOT)
	add_child(p)


func _close_popup() -> void:
	if _popup == null:
		return
	_popup.queue_free()
	_popup = null
	if is_inside_tree():
		get_tree().paused = _was_paused


func _call(cb: Callable, ok: bool) -> void:
	if cb.is_valid():
		cb.call(ok)


func _call0(cb: Callable) -> void:
	if cb.is_valid():
		cb.call()


func _log(event_name: String, params: Dictionary) -> void:
	var a: Node = get_node_or_null("/root/Analytics") if is_inside_tree() else null
	if a:
		a.event(event_name, params)

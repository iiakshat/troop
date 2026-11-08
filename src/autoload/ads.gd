extends Node
## Ads facade (autoload "Ads"). Stub mode only for now: no SDK. Google ads get connected here
## at the end (owner); the rest of the game only talks to this interface.
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

var stub_mode := true
var skip_ads := false        # debug: no popup, rewards at once (main.gd / autoplay)
var cfg: Dictionary = {}
var _blocked := false        # a rewarded ad or revive offer since the last level start
var _popup: CanvasLayer = null
var _was_paused := false


func _ready() -> void:
	cfg = Config.economy().get("ads", {})
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		if kv[0] in ["autoplay", "skip_ads"] and (kv.size() < 2 or kv[1] != "0"):
			skip_ads = true


## True while a placeholder ad covers the screen.
func is_showing() -> bool:
	return _popup != null


## No popup: headless runs, tests, autoplay, or the skip_ads flag.
func skips_popup() -> bool:
	return skip_ads or not is_inside_tree() or DisplayServer.get_name() == "headless"


## Shows a rewarded ad and calls cb(true) once it was watched to the end, cb(false) if it was
## closed early (or another ad is already showing). reward_granted fires before cb(true).
func show_rewarded(placement: String, cb: Callable) -> void:
	_blocked = true
	if _popup != null:
		_call(cb, false)
		return
	_log("ad_start", {"placement": placement, "kind": "rewarded"})
	if skips_popup():
		_rewarded_done(placement, cb, true, 0)
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
	if _popup != null:
		_call0(on_closed)
		return
	var g: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if g:
		g.save["last_interstitial_level"] = int(g.save.get("stats", {}).get("win", 0))
		g.save["last_interstitial_at"] = int(g.now())
		g.write_save()
	_log("ad_start", {"placement": placement, "kind": "interstitial"})
	interstitial_shown.emit(placement)
	if skips_popup():
		_interstitial_done(placement, on_closed)
		return
	_open("interstitial", float(cfg.get("interstitial_seconds", 3)),
		float(cfg.get("interstitial_close_after", 2)),
		func(_ok: bool, _left: int): _interstitial_done(placement, on_closed))


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

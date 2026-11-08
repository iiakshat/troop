extends Node
## Ads facade (autoload "Ads"). Stub mode only for now: no SDK. Google ads get connected here
## at the end (owner); the rest of the game only talks to this interface.
##
## Rewarded (always opt-in, the player taps a button with the ad icon):
##   Ads.show_rewarded(placement, func(ok: bool): ...)   stub: waits stub_delay, then ok = true
##   Ads.note_offer(placement)   call when an ad button is shown (analytics; a revive offer also
##                               blocks the next interstitial)
## Interstitials (config economy.ads.interstitial): only between levels, from level from_level,
## at most one per every_levels completed (won) levels, at least min_seconds apart, never right
## after a rewarded ad or a revive offer, always closable. Ask can_show_interstitial(level)
## with the level just finished, then show_interstitial().
## Call mark_level_start() when a level starts (Game.level_started does).
## Placements: x2_coins, revive, x2_offline, spin, booster_headstart, booster_shield,
## booster_bomb, speedup.

signal reward_granted(placement: String)
signal interstitial_shown(placement: String)

var stub_mode := true
var stub_delay := 0.6
var cfg: Dictionary = {}
var _blocked := false        # a rewarded ad or revive offer since the last level start


func _ready() -> void:
	cfg = Config.economy().get("ads", {})
	stub_delay = float(cfg.get("stub_delay", stub_delay))


## Shows a rewarded ad and calls cb(true) once it was watched (cb(false) if it failed or was
## skipped; never in stub mode).
func show_rewarded(placement: String, cb: Callable) -> void:
	_blocked = true
	_log("ad_watch", {"placement": placement})
	if stub_mode:
		if is_inside_tree() and stub_delay > 0.0:
			await get_tree().create_timer(stub_delay, true).timeout
		reward_granted.emit(placement)
		if cb.is_valid():
			cb.call(true)


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
	if not is_inside_tree():
		return false
	var g: Node = get_node_or_null("/root/Game")
	if g == null:
		return false
	var s: Dictionary = g.save
	var wins := int(s.get("stats", {}).get("win", 0))
	var since := int(g.now()) - int(s.get("last_interstitial_at", 0))
	return rule(level, wins, int(s.get("last_interstitial_level", 0)), since, _blocked, cfg.get("interstitial", {}))


## Shows an interstitial (stub: nothing appears) and records it for the spacing rules.
func show_interstitial(placement := "between_levels") -> void:
	var g: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if g:
		g.save["last_interstitial_level"] = int(g.save.get("stats", {}).get("win", 0))
		g.save["last_interstitial_at"] = int(g.now())
		g.write_save()
	_log("ad_interstitial", {"placement": placement})
	interstitial_shown.emit(placement)


func _log(name: String, params: Dictionary) -> void:
	var a: Node = get_node_or_null("/root/Analytics") if is_inside_tree() else null
	if a:
		a.event(name, params)

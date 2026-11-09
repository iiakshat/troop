extends "res://tests/test_case.gd"
## Interstitial spacing rules (the Ads autoload's pure rule).

const AdsScript := preload("res://src/autoload/ads.gd")
var icfg: Dictionary = Config.economy()["ads"]["interstitial"]


func test_interstitial_rules() -> void:
	var from := int(icfg["from_level"])
	var every := int(icfg["every_levels"])
	var gap := int(icfg["min_seconds"])
	check(not AdsScript.rule(from - 1, 50, 0, 9999, false, icfg), "never before level %d" % from)
	check(AdsScript.rule(from, 50, 0, 9999, false, icfg), "allowed from level %d" % from)
	check(not AdsScript.rule(from, 10, 10 - every + 1, 9999, false, icfg), "at most one per %d completed levels" % every)
	check(AdsScript.rule(from, 10, 10 - every, 9999, false, icfg), "after %d levels" % every)
	check(not AdsScript.rule(from, 50, 0, 9999, true, icfg), "never right after a rewarded ad or revive offer")
	if gap > 0:
		check(not AdsScript.rule(from, 50, 0, gap - 1, false, icfg), "spaced in time")


func test_first_interstitial_for_a_new_player() -> void:
	# Wins 1..N on levels 1..N: the first interstitial may only come after level from_level.
	var from := int(icfg["from_level"])
	var first := -1
	for level in range(1, 20):
		if AdsScript.rule(level, level, 0, 9999, false, icfg):
			first = level
			break
	eq(first, from, "first interstitial after level %d" % from)


const PopupScript := preload("res://src/autoload/ad_placeholder.gd")
var acfg: Dictionary = Config.economy()["ads"]


func _popup(kind: String) -> Array:
	# [popup, results]: results collects every `finished` value.
	var secs := float(acfg[kind + "_seconds"])
	var p = PopupScript.new()
	p.setup(kind, secs, float(acfg.get("interstitial_close_after", 2)), 0)
	var results := []
	p.finished.connect(func(c: bool): results.append(c))
	return [p, results]


func test_placeholder_rewarded_pays_only_at_zero() -> void:
	var secs := int(acfg["rewarded_seconds"])
	var pr := _popup("rewarded")
	var p = pr[0]
	var results: Array = pr[1]
	eq(p.layer, 100, "on top of everything")
	eq(p.process_mode, Node.PROCESS_MODE_ALWAYS, "runs while the game is paused")
	check(p.close_visible(), "rewarded: close X from the start")
	eq(p.seconds_left(), secs, "starts at the full count")
	p.step(1000)
	eq(p.seconds_left(), secs - 1, "counts down")
	p.step(secs * 1000 - 1)
	eq(results.size(), 0, "no reward before 0")
	p.step(secs * 1000)
	eq(results, [true], "reward at 0, once")
	p.step(secs * 1000 + 500)
	eq(results, [true], "finished only once")
	p.free()


func test_placeholder_rewarded_closed_early_pays_nothing() -> void:
	var pr := _popup("rewarded")
	var p = pr[0]
	p.step(2000)
	p.press_close()
	p.step(99000)
	eq(pr[1], [false], "closing early = no reward")
	p.free()


func test_placeholder_interstitial_close_appears_after_countdown() -> void:
	var secs := int(acfg["interstitial_seconds"])
	var after := float(acfg["interstitial_close_after"])
	var pr := _popup("interstitial")
	var p = pr[0]
	var results: Array = pr[1]
	check(not p.close_visible(), "no X during the countdown")
	p.press_close()
	eq(results.size(), 0, "cannot close before the X shows")
	p.step(secs * 1000 - 1)
	check(not p.close_visible(), "still counting")
	p.step(secs * 1000)
	check(p.close_visible(), "X after the countdown")
	eq(results.size(), 0, "stays until closed or timed out")
	p.step(int((secs + after) * 1000))
	eq(results, [true], "closes itself")
	p.free()


func test_placeholder_interstitial_closable() -> void:
	var pr := _popup("interstitial")
	var p = pr[0]
	p.step(int(acfg["interstitial_seconds"]) * 1000)
	p.press_close()
	eq(pr[1], [true], "X closes it")
	p.free()


func test_skipped_ads_grant_at_once() -> void:
	# Outside the tree (tests, headless) there is no popup: the reward comes immediately.
	var ads = AdsScript.new()
	var got := []
	ads.reward_granted.connect(func(pl: String): got.append(pl))
	ads.show_rewarded("x2_coins", func(ok: bool): got.append(ok))
	eq(got, ["x2_coins", true], "signal then callback, synchronously")
	var closed := []
	ads.show_interstitial("between_levels", func(): closed.append(1))
	eq(closed, [1], "interstitial on_closed runs at once")
	check(not ads.is_showing(), "nothing left on screen")
	ads.free()

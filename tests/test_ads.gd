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

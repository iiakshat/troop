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


# ---------------------------------------------------------------- v2: AdMob + Firebase (Task 12)

const AnalyticsScript := preload("res://src/autoload/analytics.gd")


func test_child_request_config() -> void:
	var c: Dictionary = AdsScript.request_config(true)
	eq(c.get("child_directed"), true, "child: child-directed tag on")
	eq(c.get("max_rating"), "G", "child: max ad content rating G")
	eq(c.get("npa"), true, "child: non-personalised ads")
	eq(c.get("under_age_of_consent"), true, "child: under the age of consent")
	eq(c.get("ad_id"), false, "child: no advertising / first-party ID")
	eq(c.get("consent_form"), false, "child: no UMP form (nothing personal is asked for)")


func test_adult_request_config() -> void:
	var c: Dictionary = AdsScript.request_config(false)
	eq(c.get("child_directed"), false, "adult: not child-directed")
	eq(c.get("npa"), false, "adult: personalised allowed (after UMP consent where required)")
	eq(c.get("consent_form"), true, "adult: UMP consent first")
	check(String(c.get("max_rating")) in ["G", "PG"], "adult: at most PG (Families policy cap for a mixed audience)")
	eq(AdsScript.request_config(false, {"adult_tags": {"max_rating": "T"}})["max_rating"], "PG", "config cannot raise it past PG")
	eq(AdsScript.request_config(true, {"child_tags": {"max_rating": "PG", "npa": false}})["max_rating"], "G", "config cannot loosen the child tags")


func test_firebase_not_started_for_child() -> void:
	eq(AnalyticsScript.provider_for(true, true), "local", "child: Firebase never starts")
	eq(AnalyticsScript.provider_for(true, false), "local", "child without the plugin: local")
	eq(AnalyticsScript.provider_for(false, true), "firebase", "adult with the plugin: Firebase")
	eq(AnalyticsScript.provider_for(false, false), "local", "adult on PC: local")


func test_placeholder_when_plugin_missing() -> void:
	eq(AdsScript.provider_for(false, false, "admob"), "placeholder", "no AdMob plugin (PC, headless)")
	eq(AdsScript.provider_for(true, true, "admob"), "placeholder", "skip_ads / autoplay")
	eq(AdsScript.provider_for(true, false, "placeholder"), "placeholder", "config can force the stub")
	eq(AdsScript.provider_for(true, false, "admob"), "admob", "plugin present")
	var ads = AdsScript.new()
	eq(ads.provider, "placeholder", "a fresh Ads starts as the placeholder")
	ads.free()
	var tree := Engine.get_main_loop() as SceneTree
	var live: Node = tree.root.get_node_or_null("Ads")
	if live:
		eq(live.provider, "placeholder", "on PC/headless the live provider is the placeholder")
	var an: Node = tree.root.get_node_or_null("Analytics")
	if an:
		eq(an.provider, "local", "on PC/headless analytics stays local")


func test_ads_config_uses_google_test_ids() -> void:
	var a: Dictionary = Config.load_json("res://config/ads.json")
	var t: Dictionary = a["android"]["test"]
	eq(t["app_id"], "ca-app-pub-3940256099942544~3347511713", "Google's sample app ID")
	eq(t["rewarded"], "ca-app-pub-3940256099942544/5224354917", "Google's test rewarded unit")
	eq(t["interstitial"], "ca-app-pub-3940256099942544/1033173712", "Google's test interstitial unit")
	eq(bool(a["is_real"]), false, "test IDs until the owner sends real ones")


func test_firebase_event_names_are_valid() -> void:
	eq(AnalyticsScript.firebase_name("level_end"), "level_end", "plain names pass")
	eq(AnalyticsScript.firebase_name("session_start"), "game_session_start", "reserved names are renamed")
	eq(AnalyticsScript.firebase_name("firebase_x"), "game_firebase_x", "reserved prefixes are renamed")
	check(AnalyticsScript.firebase_name("a-b c".repeat(20)).length() <= 40, "at most 40 characters")
	var p: Dictionary = AnalyticsScript.firebase_params({"a": 1, "b": "x".repeat(300), "c": {"d": 2}, "e": true, "f": 1.5})
	eq(p["a"], 1, "ints stay")
	eq(String(p["b"]).length(), 100, "strings cut to 100")
	check(p["c"] is String, "nested values become strings")
	eq(p["e"], 1, "bools become 0/1")
	eq(p["f"], 1.5, "floats stay")


func test_tap_rate_buckets() -> void:
	var an = AnalyticsScript.new()
	an.enabled = false
	var out := []
	an.sink = func(name: String, params: Dictionary): out.append([name, params])
	for t in [0.5, 1.0, 9.9, 10.0, 25.0, 25.5]:
		an.note_tap(7, t)
	an.end_taps()
	eq(out.size(), 3, "one event per 10 s bucket with taps")
	eq(out[0], ["tap_rate", {"level": 7, "bucket": 0, "taps": 3}], "0-10 s")
	eq(out[1], ["tap_rate", {"level": 7, "bucket": 1, "taps": 1}], "10-20 s")
	eq(out[2], ["tap_rate", {"level": 7, "bucket": 2, "taps": 2}], "20-30 s")
	an.free()
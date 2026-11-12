extends "res://tests/test_case.gd"
## Spec v2 §2: a short still touch is a tap (fires, never steers); anything that moves is a
## swipe (steers, never fires). Recorded touch sequences: tap-tap-swipe, swipe-tap, two fingers.

const CFG := {"tap_max_px": 15.0, "tap_max_s": 0.25, "zone_top": 0.5}


func _tc() -> TouchClassifier:
	return TouchClassifier.new(CFG)


## Plays a recorded sequence [[kind, id, x, y, t], ...] and returns the non-empty results,
## with runs of the same result from one finger collapsed ("steer" per move -> one "steer").
func _play(tc: TouchClassifier, seq: Array) -> Array:
	var out: Array = []
	for e in seq:
		var p := Vector2(float(e[2]), float(e[3]))
		var r := ""
		match String(e[0]):
			"press":
				tc.press(int(e[1]), p, float(e[4]))
			"move":
				r = tc.move(int(e[1]), p, float(e[4]))
			"release":
				r = tc.release(int(e[1]), p, float(e[4]))
		if r != "" and (out.is_empty() or out[-1] != r or r == "tap"):
			out.append(r)
	return out


func test_short_still_touch_is_tap() -> void:
	var tc := _tc()
	eq(_play(tc, [["press", 0, 200, 800, 0.0], ["move", 0, 204, 803, 0.05], ["release", 0, 205, 802, 0.12]]),
		["tap"], "a 0.12 s touch that moved 5 px")


func test_moving_touch_is_steer_and_never_tap() -> void:
	var tc := _tc()
	var seq := [["press", 0, 200, 800, 0.0]]
	for i in 6:
		seq.append(["move", 0, 200 + 8 * (i + 1), 800, 0.02 * (i + 1)])
	seq.append(["release", 0, 248, 800, 0.14])
	var out := _play(tc, seq)
	eq(out, ["steer", "steer_end"], "a quick 48 px flick steers and never fires")
	check(not out.has("tap"), "no tap")


func test_small_moves_under_threshold_do_not_steer() -> void:
	var tc := _tc()
	tc.press(0, Vector2(100, 900), 0.0)
	eq(tc.move(0, Vector2(110, 905), 0.05), "", "11 px: still a tap candidate")
	eq(tc.move(0, Vector2(120, 900), 0.08), "steer", "20 px: now a swipe")
	eq(tc.move(0, Vector2(118, 900), 0.1), "steer", "keeps steering once it started")
	eq(tc.release(0, Vector2(118, 900), 0.12), "steer_end", "a swipe never ends in a tap")


func test_rapid_taps_then_swipe() -> void:
	var tc := _tc()
	var seq: Array = []
	for i in 5:
		var t := 0.1 * i
		seq.append(["press", 0, 270, 820, t])
		seq.append(["move", 0, 272, 821, t + 0.02])
		seq.append(["release", 0, 272, 821, t + 0.05])
	var t0 := 0.6
	seq.append(["press", 0, 270, 820, t0])
	for i in 10:
		seq.append(["move", 0, 270 + 20 * (i + 1), 822, t0 + 0.016 * (i + 1)])
	seq.append(["release", 0, 470, 822, t0 + 0.2])
	eq(_play(tc, seq), ["tap", "tap", "tap", "tap", "tap", "steer", "steer_end"],
		"5 taps fire, the swipe steers, a tap never steers")


func test_swipe_then_tap() -> void:
	var tc := _tc()
	var seq := [["press", 0, 100, 800, 0.0], ["move", 0, 160, 800, 0.05], ["release", 0, 160, 800, 0.1],
		["press", 0, 160, 800, 0.2], ["release", 0, 161, 800, 0.26]]
	eq(_play(tc, seq), ["steer", "steer_end", "tap"], "a tap right after a swipe still fires")


func test_slow_hold_is_not_tap() -> void:
	var tc := _tc()
	eq(_play(tc, [["press", 0, 200, 800, 0.0], ["release", 0, 201, 800, 0.4]]), [],
		"a 0.4 s still hold neither fires nor steers")


func test_second_finger_tap_while_steering() -> void:
	var tc := _tc()
	var seq := [["press", 1, 100, 800, 0.0], ["move", 1, 140, 800, 0.05],
		["press", 2, 400, 850, 0.1], ["move", 1, 180, 800, 0.12], ["release", 2, 401, 851, 0.18],
		["move", 1, 220, 800, 0.2], ["release", 1, 220, 800, 0.3]]
	var out := _play(tc, seq)
	eq(out, ["steer", "tap", "steer", "steer_end"], "finger 2 taps while finger 1 steers")


func test_unknown_touch_is_ignored() -> void:
	var tc := _tc()
	eq(tc.move(7, Vector2(10, 10), 0.0), "", "a move with no press")
	eq(tc.release(7, Vector2(10, 10), 0.0), "", "a release with no press")


func test_upper_half_tap_is_ignored() -> void:
	var tc := _tc()
	var screen := Vector2(540, 960)
	check(not tc.in_zone(Vector2(270, 200), screen), "upper half is not the tap zone")
	check(not tc.in_zone(Vector2(270, 479), screen), "just above the middle")
	check(tc.in_zone(Vector2(270, 480), screen), "the middle line starts the zone")
	check(tc.in_zone(Vector2(10, 950), screen), "bottom corner")


func test_threshold_scales_with_screen_density() -> void:
	var tc := TouchClassifier.new(CFG, 2.0)
	tc.press(0, Vector2(100, 900), 0.0)
	eq(tc.move(0, Vector2(125, 900), 0.05), "", "25 px on a 2x screen is under 30 px")
	eq(tc.release(0, Vector2(125, 900), 0.1), "tap", "so it is still a tap")

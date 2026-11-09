extends "res://tests/test_case.gd"
## 7-day login calendar.

var eco := Config.economy()


func _save() -> Dictionary:
	return SaveData.migrate({}, eco)


func test_days_between() -> void:
	eq(Daily.days_between("2026-11-08", "2026-11-09"), 1, "next day")
	eq(Daily.days_between("2026-11-30", "2026-12-01"), 1, "across a month")
	eq(Daily.days_between("2026-12-31", "2027-01-01"), 1, "across a year")
	eq(Daily.days_between("2028-02-28", "2028-03-01"), 2, "leap year")
	eq(Daily.days_between("2026-11-09", "2026-11-08"), -1, "backwards")


func test_first_claim_and_once_a_day() -> void:
	var s := _save()
	var st := Daily.state(s, "2026-11-08", eco)
	check(bool(st["can_claim"]), "first claim allowed")
	eq(int(st["day"]), 1, "starts at day 1")
	var r := Daily.claim(s, "2026-11-08", eco)
	eq(r, Daily.reward_for_day(1, eco), "day 1 reward")
	check(not Daily.can_claim(s, "2026-11-08", eco), "once a day")
	eq(Daily.claim(s, "2026-11-08", eco), {}, "second claim refused")
	check(bool(Daily.state(s, "2026-11-08", eco)["claimed_today"]), "shows claimed")


func test_streak_runs_to_day_7_and_wraps() -> void:
	var s := _save()
	var dates := ["2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"]
	for i in dates.size():
		var day := Daily.next_day(s, dates[i], eco)
		eq(day, i % 7 + 1, "day on " + dates[i])
		var r := Daily.claim(s, dates[i], eco)
		check(not r.is_empty(), "claimed " + dates[i])
	eq(int(s["daily"]["streak"]), 8, "streak counts consecutive days")
	check(Daily.reward_for_day(7, eco).has("chest"), "day 7 is the big chest")


func test_missing_a_day_starts_over_honestly() -> void:
	var s := _save()
	Daily.claim(s, "2026-11-08", eco)
	Daily.claim(s, "2026-11-09", eco)
	Daily.claim(s, "2026-11-10", eco)
	var st := Daily.state(s, "2026-11-12", eco)
	check(bool(st["can_claim"]), "can claim after a gap")
	check(bool(st["missed"]), "the reset is shown")
	eq(int(st["day"]), 1, "back to day 1")
	Daily.claim(s, "2026-11-12", eco)
	eq(int(s["daily"]["day"]), 1, "day 1 claimed")
	eq(int(s["daily"]["streak"]), 1, "streak restarted")


func test_no_reset_option() -> void:
	var e := eco.duplicate(true)
	e["daily"]["reset_on_miss"] = false
	var s := _save()
	Daily.claim(s, "2026-11-08", e)
	Daily.claim(s, "2026-11-09", e)
	eq(Daily.next_day(s, "2026-11-15", e), 3, "carries on when resets are off")
	check(not bool(Daily.state(s, "2026-11-15", e)["missed"]), "nothing lost")


func test_clock_going_back() -> void:
	var s := _save()
	Daily.claim(s, "2026-11-08", eco)
	check(not Daily.can_claim(s, "2026-11-07", eco), "a day back: wait")
	eq(Daily.claim(s, "2026-11-07", eco), {}, "no double claim by moving the date back")
	check(not Daily.can_claim(s, "2026-11-01", eco), "far back: still wait (no claim by winding the date)")
	check(Daily.can_claim(s, "2026-11-09", eco), "the real next day still claims")
	eq(Daily.next_day(s, "2026-11-09", eco), 2, "and carries the streak on")

class_name Daily
extends RefCounted
## 7-day login calendar, pure. `today` is a local date "YYYY-MM-DD" passed in by the caller.
## save.daily = {day: last claimed day (0 = none), last_claim_date, streak}.
## Claim once per calendar day. The day after a claim moves on one day (after 7 it starts
## over); missing a day starts again at day 1 when config daily.reset_on_miss is true, and the
## panel can show that honestly via state(). Tested in tests/test_daily.gd.


## Whole days from date a to date b (b - a). Both "YYYY-MM-DD".
static func days_between(a: String, b: String) -> int:
	var ta := Time.get_unix_time_from_datetime_string(a + "T00:00:00")
	var tb := Time.get_unix_time_from_datetime_string(b + "T00:00:00")
	return int(round(float(tb - ta) / 86400.0))


static func _days(economy: Dictionary) -> Array:
	return Economy.cfg(economy)["daily"]["days"]


## Reward of calendar day n (1..7) as written in the config (coins not scaled yet).
static func reward_for_day(n: int, economy: Dictionary = {}) -> Dictionary:
	var days := _days(economy)
	return (days[clampi(n, 1, days.size()) - 1] as Dictionary).duplicate(true)


## {can_claim, day (the day the next claim gives, 1..7), missed (the streak broke), streak,
## claimed_today}
static func state(save: Dictionary, today: String, economy: Dictionary = {}) -> Dictionary:
	var d: Dictionary = save.get("daily", {})
	var last := String(d.get("last_claim_date", ""))
	var day := int(d.get("day", 0))
	var size := _days(economy).size()
	var out := {"can_claim": true, "day": 1, "missed": false, "streak": int(d.get("streak", 0)), "claimed_today": false}
	if last == "":
		return out
	var gap := days_between(last, today)
	if gap == 0 or gap == -1:
		# Claimed today (or the date stepped back a day, e.g. travelling west): wait.
		out["can_claim"] = false
		out["claimed_today"] = gap == 0
		out["day"] = day
		return out
	if gap == 1:
		out["day"] = day % size + 1
		return out
	# Missed at least a day (or the clock jumped far back): start over, or carry on.
	var reset := bool(Economy.cfg(economy)["daily"].get("reset_on_miss", true))
	out["missed"] = reset and day > 0
	out["day"] = 1 if reset else day % size + 1
	return out


static func can_claim(save: Dictionary, today: String, economy: Dictionary = {}) -> bool:
	return bool(state(save, today, economy)["can_claim"])


## The calendar day the next claim gives (1..7).
static func next_day(save: Dictionary, today: String, economy: Dictionary = {}) -> int:
	return int(state(save, today, economy)["day"])


## Claims today's reward: updates save.daily and returns the reward dict from the config
## (coins not scaled; a "chest" key still to roll). {} when it cannot be claimed today.
static func claim(save: Dictionary, today: String, economy: Dictionary = {}) -> Dictionary:
	var st := state(save, today, economy)
	if not bool(st["can_claim"]):
		return {}
	var d: Dictionary = save.get("daily", {})
	var streak := int(d.get("streak", 0))
	var continued := String(d.get("last_claim_date", "")) != "" and days_between(String(d["last_claim_date"]), today) == 1
	save["daily"] = {
		"day": int(st["day"]),
		"last_claim_date": today,
		"streak": streak + 1 if continued else 1,
	}
	return reward_for_day(int(st["day"]), economy)

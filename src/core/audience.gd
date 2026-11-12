class_name Audience
extends RefCounted
## Who counts as a child (spec v2 §8 and rule 4). Pure; tested in tests/test_audience.gd.
## - Under 13 everywhere (COPPA, Google Families policy).
## - Under 18 when the device region or locale is India (DPDP Act 2023: a "child" is under 18).
## - Unknown or impossible birth year = child (the safe default).
## Age is counted by birth year only (now_year - birth_year), which can make someone look up to
## a year older than they are; the cut-offs are compared with that number, so a player born in
## 2013 counts as 13 for all of 2026.
## For a child: child-directed ads, max rating G, non-personalised, no advertising ID, and
## Firebase is never started (Ads.request_config / Analytics.provider_for).

const CHILD_AGE := 13
const CHILD_AGE_INDIA := 18
const WHEEL_SPAN := 100
const IST_BIAS := 330            # India Standard Time, minutes east of UTC


static func is_child(birth_year: int, now_year: int, region: String, locale: String) -> bool:
	if not valid_year(birth_year, now_year):
		return true
	var age := now_year - birth_year
	var limit := CHILD_AGE_INDIA if in_india(region, locale) else CHILD_AGE
	return age < limit


static func in_india(region: String, locale: String) -> bool:
	if region.strip_edges().to_upper() == "IN":
		return true
	return region_of(locale) == "IN"


## "en_IN" / "hi-IN" -> "IN"; "en" -> "".
static func region_of(locale: String) -> String:
	var parts := locale.strip_edges().replace("-", "_").split("_", false)
	for i in range(1, parts.size()):
		var p := String(parts[i])
		if p.length() == 2 and p == p.to_upper():
			return p
	return ""


static func valid_year(birth_year: int, now_year: int) -> bool:
	return birth_year > now_year - WHEEL_SPAN - 1 and birth_year <= now_year


## The age wheel: this year back WHEEL_SPAN years, newest first.
static func wheel_years(now_year: int) -> Array:
	var out := []
	for y in range(now_year, now_year - WHEEL_SPAN - 1, -1):
		out.append(y)
	return out


## The region from the locale's country part, or "IN" when the clock runs on India Standard Time
## (UTC+5:30 = bias 330 minutes). Godot has no device-region API, and an Indian phone set to
## English (US) still keeps an Indian clock; counting that as India is the safe side.
static func region_from(locale: String, tz_bias_minutes: int) -> String:
	if tz_bias_minutes == IST_BIAS:
		return "IN"
	return region_of(locale)


## Region of this device (see region_from).
static func device_region() -> String:
	var tz: Dictionary = Time.get_time_zone_from_system()
	return region_from(OS.get_locale(), int(tz.get("bias", 0)))


static func device_locale() -> String:
	return OS.get_locale()

class_name NumFormat
extends RefCounted
## Big numbers for the HUD, gate labels and gang counts (spec v2 §12.4): in full up to 9,999,
## then three significant digits with K / M / B (12.3K, 125K, 1.25M). Display only: the game's
## values stay exact 64-bit integers. Digits are cut, never rounded up, so a counter never
## shows more troops than there are.

const UNITS := [[1000000000, "B"], [1000000, "M"], [1000, "K"]]


static func fmt(n: int) -> String:
	if n < 0:
		return "-" + fmt(-n)
	if n < 10000:
		return _grouped(n)
	for u in UNITS:
		var base: int = u[0]
		if n < base:
			continue
		var whole := n / base
		var s: String
		if whole >= 100:
			s = str(whole)
		elif whole >= 10:
			s = _decimal(n / (base / 10), 1)
		else:
			s = _decimal(n / (base / 100), 2)
		return s + String(u[1])
	return str(n)


## With an explicit sign for gains (+500); zero has none.
static func signed(n: int) -> String:
	return ("+" if n > 0 else "") + fmt(n)


## "9,999": thousands separated by commas.
static func _grouped(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## `scaled` / 10^places as a decimal, trailing zeros (and a bare point) dropped: 1250 -> 12.5.
static func _decimal(scaled: int, places: int) -> String:
	var s := str(scaled)
	var head := s.substr(0, s.length() - places)
	var tail := s.substr(s.length() - places).rstrip("0")
	return head if tail == "" else head + "." + tail

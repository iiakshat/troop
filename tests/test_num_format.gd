extends "res://tests/test_case.gd"
## NumFormat (spec v2 §12.4): in full up to 9,999, then 12.3K, 1.25M. Never rounds up.


func test_full_up_to_9999() -> void:
	eq(NumFormat.fmt(0), "0", "zero")
	eq(NumFormat.fmt(7), "7", "small")
	eq(NumFormat.fmt(999), "999", "hundreds")
	eq(NumFormat.fmt(1000), "1,000", "thousand with a separator")
	eq(NumFormat.fmt(9999), "9,999", "top of the full range")


func test_thousands_and_millions_three_digits() -> void:
	eq(NumFormat.fmt(10000), "10K", "10K, no trailing .0")
	eq(NumFormat.fmt(12345), "12.3K", "12.3K")
	eq(NumFormat.fmt(12399), "12.3K", "never rounds up")
	eq(NumFormat.fmt(123456), "123K", "123K")
	eq(NumFormat.fmt(999999), "999K", "999K, not 1000K")
	eq(NumFormat.fmt(1000000), "1M", "1M")
	eq(NumFormat.fmt(1250000), "1.25M", "1.25M")
	eq(NumFormat.fmt(1259999), "1.25M", "1.25M floor")
	eq(NumFormat.fmt(1200000), "1.2M", "1.2M")
	eq(NumFormat.fmt(12500000), "12.5M", "12.5M")
	eq(NumFormat.fmt(125000000), "125M", "125M")
	eq(NumFormat.fmt(2000000000), "2B", "billions")


func test_negative_and_signed() -> void:
	eq(NumFormat.fmt(-1234), "-1,234", "negative")
	eq(NumFormat.fmt(-25000), "-25K", "negative K")
	eq(NumFormat.signed(500), "+500", "signed plus")
	eq(NumFormat.signed(-12345), "-12.3K", "signed minus")
	eq(NumFormat.signed(0), "0", "zero has no sign")

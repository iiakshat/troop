extends RefCounted
## Tiny assertion base for the headless test runner.

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(a: Variant, b: Variant, msg: String) -> void:
	if a != b:
		failures.append("%s: expected %s, got %s" % [msg, str(b), str(a)])


func near(a: float, b: float, msg: String) -> void:
	check(absf(a - b) < 0.001, "%s (%.3f vs %.3f)" % [msg, a, b])

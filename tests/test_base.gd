extends RefCounted
## Base class for tests: assertion helpers that report to the runner.
class_name TestBase

var runner


func check(cond: bool, msg: String = "assertion failed") -> bool:
	if not cond:
		runner.fail(msg)
	return cond


func eq(a: Variant, b: Variant, msg: String = "") -> bool:
	if a != b:
		runner.fail("%s expected %s == %s" % [msg, str(a), str(b)])
		return false
	return true


func near(a: float, b: float, eps: float = 0.001, msg: String = "") -> bool:
	if absf(a - b) > eps:
		runner.fail("%s expected %f ~= %f" % [msg, a, b])
		return false
	return true

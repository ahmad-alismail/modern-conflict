extends TestBase


func test_rng_deterministic() -> void:
	var a := Rng.new(42)
	var b := Rng.new(42)
	for i in 1000:
		if not eq(a.next_u32(), b.next_u32(), "same seed same stream"):
			return
	var c := Rng.new(43)
	check(Rng.new(42).next_u32() != c.next_u32(), "different seeds diverge")


func test_rng_ranges() -> void:
	var r := Rng.new(7)
	var lo := 1.0
	var hi := 0.0
	for i in 5000:
		var f := r.next_float()
		lo = minf(lo, f)
		hi = maxf(hi, f)
		var n := r.range_i(3, 6)
		if not check(n >= 3 and n <= 6, "range_i bounds"):
			return
	check(lo >= 0.0 and hi < 1.0, "randf in [0,1)")
	check(lo < 0.01 and hi > 0.99, "randf covers range")

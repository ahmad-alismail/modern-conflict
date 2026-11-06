extends RefCounted
## Deterministic, serializable PRNG (xorshift32 + splitmix seeding).
## The simulation must only use this RNG, never the global randf()/randi(), so that
## identical command streams reproduce identical matches (replays, tests).
class_name Rng

var state: int = 1


func _init(seed_value: int = 1) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	# splitmix-style scramble so nearby seeds diverge
	var z := (seed_value + 0x9E3779B9) & 0xFFFFFFFF
	z = ((z ^ (z >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF
	z = ((z ^ (z >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF
	z = (z ^ (z >> 16)) & 0xFFFFFFFF
	state = z if z != 0 else 0x6D2B79F5


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state = x & 0xFFFFFFFF
	return state


## Uniform float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next_float()


## Uniform int in [a, b] inclusive.
func range_i(a: int, b: int) -> int:
	if b <= a:
		return a
	return a + int(next_u32() % (b - a + 1))


func chance(p: float) -> bool:
	return next_float() < p


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[range_i(0, arr.size() - 1)]


## Approximately normal (sum of 3 uniforms), mean 0, sd ~1.
func gauss() -> float:
	return (next_float() + next_float() + next_float() - 1.5) * 2.0


func unit_vector() -> Vector2:
	var a := next_float() * TAU
	return Vector2(cos(a), sin(a))

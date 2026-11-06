extends RefCounted
## Procedural sound bank: every clip is synthesized at startup from noise, oscillators,
## envelopes and simple filters into 16-bit mono AudioStreamWAV (22050 Hz). The bank is
## generated once per process (in parallel on the WorkerThreadPool) and cached: `Synth.bank()`.
##
## Loops are seamless by construction: tonal parts use frequencies with a whole number of
## cycles per loop, events are rendered with wrap-around, and noise beds are generated
## longer and crossfaded into their own start.
## Performance: noise comes from one shared table, and filtered-noise layers are rendered by
## a single fused pass (`_fnoise`), so the whole bank takes a few hundred ms.
class_name Synth

const RATE := 22050
const PEAK := 0.89 # -1 dBFS normalization target
const VARIANTS := 3
const _TAB_BITS := 18
const _TAB_MASK := (1 << _TAB_BITS) - 1

## name -> number of variants generated
const CLIPS := {
	"rifle": VARIANTS, "ak": VARIANTS, "lmg": VARIANTS, "hmg": VARIANTS, "sniper": VARIANTS,
	"cannon": VARIANTS, "autocannon": VARIANTS,
	"rocket_launch": 2, "missile_launch": 2, "mortar_launch": 2,
	"grenade": VARIANTS, "explosion_small": VARIANTS, "explosion_medium": VARIANTS, "explosion_large": VARIANTS,
	"impact_bullet": VARIANTS, "ricochet": VARIANTS, "metal_hit": VARIANTS, "collapse": 2,
	"heli_loop": 1, "engine_tank_loop": 1, "engine_truck_loop": 1, "drone_loop": 1, "jet_flyby": 1,
	"incoming_whistle": 2, "smoke_pop": 1, "radio_beep": 1,
	"ui_click": 1, "ui_select": 1, "ui_order": 1, "ui_alert": 1,
	"wind_loop": 1, "battle_distant_loop": 1, "rain_loop": 1,
}

static var _bank: Dictionary = {}
static var _tab := PackedFloat32Array()
static var _task := -1
static var _jobs: Array = []
static var _results: Array = []
static var _t0 := 0
## Milliseconds the last full generation took (wall clock).
static var gen_ms := 0.0
## NaN/Inf samples replaced by 0 during finalization (should always stay 0).
static var bad_samples := 0


## All clips: name -> Array[AudioStreamWAV]. Blocks until generated (first call only).
static func bank() -> Dictionary:
	if _bank.is_empty():
		generate_async()
		_collect()
	return _bank


## Starts generating the bank on the WorkerThreadPool without blocking (no-op when the bank
## exists or is being generated). Poll with is_ready().
static func generate_async() -> void:
	if not _bank.is_empty() or _task >= 0:
		return
	_t0 = Time.get_ticks_usec()
	_table()
	_jobs.clear()
	for clip_name in CLIPS:
		for v in int(CLIPS[clip_name]):
			_jobs.append([clip_name, v])
	_results.clear()
	_results.resize(_jobs.size())
	_task = WorkerThreadPool.add_group_task(func(i: int) -> void: _results[i] = make(_jobs[i][0], _jobs[i][1]),
			_jobs.size(), -1, true, "Synth.bank")


## True once the bank is available (collects a finished background generation).
static func is_ready() -> bool:
	if not _bank.is_empty():
		return true
	if _task < 0 or not WorkerThreadPool.is_group_task_completed(_task):
		return false
	_collect()
	return true


static func _collect() -> void:
	WorkerThreadPool.wait_for_group_task_completion(_task)
	_task = -1
	for i in _jobs.size():
		var clip_name: String = _jobs[i][0]
		if not _bank.has(clip_name):
			var arr: Array[AudioStreamWAV] = []
			_bank[clip_name] = arr
		(_bank[clip_name] as Array).append(_results[i])
	_results.clear()
	gen_ms = (Time.get_ticks_usec() - _t0) / 1000.0


static func is_loop(clip_name: String) -> bool:
	return clip_name.ends_with("_loop")


## Synthesizes one clip variant (thread-safe once the noise table exists).
static func make(clip_name: String, variant: int) -> AudioStreamWAV:
	_table()
	var sd := absi(hash(clip_name)) % 100000 + variant * 7919 + 17
	var j := _Jit.new(sd)
	match clip_name:
		"rifle":
			return _finish(_gunshot(sd, j, 2600.0, 165.0, 70.0, 0.05, 0.9, 3600.0, 0.035, 1900.0, 0.32, 0.9))
		"ak":
			return _finish(_gunshot(sd, j, 2000.0, 125.0, 55.0, 0.07, 1.1, 2700.0, 0.045, 1500.0, 0.38, 1.0))
		"lmg":
			return _finish(_gunshot(sd, j, 2300.0, 140.0, 62.0, 0.06, 1.0, 3100.0, 0.04, 1700.0, 0.22, 0.6))
		"hmg":
			return _finish(_gunshot(sd, j, 1400.0, 95.0, 40.0, 0.1, 1.4, 1900.0, 0.07, 1100.0, 0.55, 1.3))
		"sniper":
			return _finish(_gunshot(sd, j, 3000.0, 115.0, 45.0, 0.09, 1.2, 3000.0, 0.06, 1250.0, 0.95, 1.9))
		"autocannon":
			return _finish(_gunshot(sd, j, 1100.0, 72.0, 34.0, 0.13, 1.6, 1500.0, 0.09, 900.0, 0.7, 1.4))
		"cannon":
			return _finish(_cannon(sd, j))
		"grenade":
			return _finish(_explosion(sd, j, 0.6, 1.8))
		"explosion_small":
			return _finish(_explosion(sd, j, 0.8, 2.2))
		"explosion_medium":
			return _finish(_explosion(sd, j, 1.4, 3.0))
		"explosion_large":
			return _finish(_explosion(sd, j, 2.2, 4.2))
		"impact_bullet":
			return _finish(_impact(sd, j))
		"ricochet":
			return _finish(_ricochet(sd, j))
		"metal_hit":
			return _finish(_metal(sd, j))
		"collapse":
			return _finish(_collapse(sd, j))
		"rocket_launch":
			return _finish(_rocket(sd, j, false))
		"missile_launch":
			return _finish(_rocket(sd, j, true))
		"mortar_launch":
			return _finish(_mortar(sd, j))
		"incoming_whistle":
			return _finish(_whistle(sd, j))
		"jet_flyby":
			return _finish(_jet(sd))
		"smoke_pop":
			return _finish(_smoke_pop(sd))
		"radio_beep":
			return _finish(_radio_beep(sd))
		"ui_click":
			return _finish(_ui_click())
		"ui_select":
			return _finish(_ui_select())
		"ui_order":
			return _finish(_ui_order(sd))
		"ui_alert":
			return _finish(_ui_alert())
		"heli_loop":
			return _finish(_heli_loop(sd), true)
		"engine_tank_loop":
			return _finish(_tank_loop(sd), true)
		"engine_truck_loop":
			return _finish(_truck_loop(sd), true)
		"drone_loop":
			return _finish(_drone_loop(sd), true)
		"wind_loop":
			return _finish(_wind_loop(sd), true)
		"battle_distant_loop":
			return _finish(_battle_loop(sd), true)
		"rain_loop":
			return _finish(_rain_loop(sd), true)
	push_error("Synth: unknown clip " + clip_name)
	return _finish(PackedFloat32Array([0.0, 0.0]))


# --- recipes ----------------------------------------------------------------------
# _fnoise keys: gain, at (s), len (s, default to end), a (attack s), d (decay s), h (hold s),
# lp (first pole Hz), lp_end + sweep (first pole sweeps lp -> lp_end over sweep s),
# lp2 (second pole Hz), hp (Hz), am (Hz), am_depth.

## Gunshot = supersonic crack + low body thump + muzzle blast + urban reverb tail + slapback echoes.
static func _gunshot(sd: int, j: _Jit, crack_hp: float, f0: float, f1: float, body_decay: float, body_gain: float,
		blast_lp: float, blast_decay: float, tail_lp: float, tail_decay: float, dur: float) -> PackedFloat32Array:
	var out := _zeros(int(dur * RATE))
	_fnoise(out, sd, {"gain": 0.4, "len": 0.004, "hp": crack_hp * j.v(0.1), "a": 0.0002, "d": 0.0012 * j.v(0.2)})
	_add(out, _tone(int(body_decay * 6.0 * RATE), f0 * j.v(0.06), f1, body_decay * 0.6, body_decay * j.v(0.1)), body_gain * 0.28)
	_fnoise(out, sd + 1, {"gain": 0.32, "len": blast_decay * 7.0, "lp": blast_lp * j.v(0.1), "lp2": blast_lp * 1.6,
			"a": 0.0005, "d": blast_decay * j.v(0.15)})
	_fnoise(out, sd + 2, {"gain": 0.07, "lp": tail_lp * j.v(0.1), "lp2": tail_lp, "a": 0.02, "d": tail_decay * j.v(0.12)})
	_echoes(out, tail_lp * 1.5, [[0.07 * j.v(0.25), 0.32 * j.v(0.25)], [0.16 * j.v(0.25), 0.24 * j.v(0.25)],
			[0.25 * j.v(0.25), 0.16 * j.v(0.25)]])
	return out


## Tank gun: heavy shock + very low boom and a long rolling rumble.
static func _cannon(sd: int, j: _Jit) -> PackedFloat32Array:
	var out := _zeros(int(3.2 * RATE))
	_fnoise(out, sd, {"gain": 0.35, "len": 0.012, "hp": 600.0, "a": 0.0003, "d": 0.003})
	_add(out, _tone(int(1.2 * RATE), 62.0 * j.v(0.05), 26.0, 0.25, 0.32 * j.v(0.1)), 0.45)
	_fnoise(out, sd + 1, {"gain": 0.36, "len": 1.4, "lp": 2200.0, "lp_end": 260.0, "sweep": 0.35, "lp2": 900.0,
			"a": 0.001, "d": 0.2 * j.v(0.1)})
	_fnoise(out, sd + 2, {"gain": 0.22, "lp": 260.0, "lp2": 180.0, "a": 0.06, "d": 1.1 * j.v(0.1),
			"am": 2.3 * j.v(0.2), "am_depth": 0.35})
	_echoes(out, 700.0, [[0.21 * j.v(0.2), 0.35], [0.52 * j.v(0.2), 0.2]])
	return out


## Explosion: sharp transient, sub boom, filtered blast with closing cutoff, rolling rumble,
## debris crackle and distant echoes. `k` ~ size.
static func _explosion(sd: int, j: _Jit, k: float, dur: float) -> PackedFloat32Array:
	var out := _zeros(int(dur * RATE))
	_fnoise(out, sd, {"gain": 0.3, "len": 0.01, "hp": 900.0 / sqrt(k), "a": 0.0002, "d": 0.0025})
	_add(out, _tone(int(1.5 * RATE), (95.0 - 15.0 * k) * j.v(0.08), 24.0, 0.2 * k, (0.22 + 0.14 * k) * j.v(0.1)), 0.42)
	_fnoise(out, sd + 1, {"gain": 0.36, "lp": 3800.0 / sqrt(k), "lp_end": 180.0, "sweep": 0.25 + 0.3 * k,
			"lp2": 2500.0 / sqrt(k), "a": 0.001, "d": (0.12 + 0.14 * k) * j.v(0.12)})
	_fnoise(out, sd + 2, {"gain": 0.26, "lp": 220.0, "lp2": 160.0, "a": 0.04 + 0.03 * k, "d": (0.45 + 0.45 * k) * j.v(0.12),
			"am": 1.7 * j.v(0.3), "am_depth": 0.45})
	_crackle(out, sd + 4, 0.08, 0.4 + 0.5 * k, int(30 * k), 0.12, 1800.0)
	_echoes(out, 600.0, [[(0.16 + 0.05 * k) * j.v(0.2), 0.3], [(0.45 + 0.1 * k) * j.v(0.2), 0.18]])
	return out


static func _impact(sd: int, j: _Jit) -> PackedFloat32Array:
	var out := _zeros(int(0.28 * RATE))
	var hit := _noise(int(0.06 * RATE), sd)
	_bp(hit, 2200.0 * j.v(0.25), 1200.0, 1.2, 0.03)
	_env(hit, 0.0003, 0.012 * j.v(0.2))
	_add(out, hit, 1.6)
	_add(out, _tone(int(0.08 * RATE), 180.0 * j.v(0.15), 90.0, 0.03, 0.022), 0.8)
	_crackle(out, sd + 1, 0.01, 0.16, 7, 0.09, 2500.0)
	return out


static func _ricochet(sd: int, j: _Jit) -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var out := _zeros(n)
	_fnoise(out, sd, {"gain": 0.35, "len": 0.02, "hp": 1500.0, "a": 0.0002, "d": 0.004})
	# Whizzing tone falling in pitch, with a little vibrato and a noisy edge.
	var hz := 3200.0 * j.v(0.12)
	var ng := int(0.45 * RATE)
	var k := pow(850.0 / hz, 1.0 / ng)
	var ph := 0.0
	var o := sd * 131
	var na := 0.012 * RATE
	var kd := exp(-1.0 / (0.22 * RATE))
	var g := 1.0
	var start := int(0.004 * RATE)
	for i in n - start:
		var w := _tab[(o + i) & _TAB_MASK]
		ph += TAU * hz * (1.0 + 0.012 * sin(i * 0.0035 * 40.0) + 0.004 * w) / RATE
		if i < ng:
			hz *= k
		g *= kd
		out[start + i] += sin(ph) * g * minf(i / na, 1.0) * 0.9
	return out


static func _metal(sd: int, j: _Jit) -> PackedFloat32Array:
	var n := int(1.1 * RATE)
	var out := _zeros(n)
	_fnoise(out, sd, {"gain": 0.4, "len": 0.03, "hp": 1200.0, "a": 0.0002, "d": 0.006})
	var partials := [[430.0, 1.0, 0.45], [1135.0, 0.6, 0.28], [1820.0, 0.5, 0.22], [2660.0, 0.32, 0.14], [3420.0, 0.2, 0.09]]
	for p in partials:
		var hz: float = p[0]
		var amp: float = p[1]
		var dec: float = p[2]
		_add(out, _tone(int(dec * 7.0 * RATE), hz * j.v(0.06), hz, 0.0, dec * j.v(0.2), j.r() * TAU), amp * 0.45)
	_add(out, _tone(int(0.12 * RATE), 130.0, 80.0, 0.05, 0.04), 0.6)
	return out


static func _collapse(sd: int, j: _Jit) -> PackedFloat32Array:
	var out := _zeros(int(5.0 * RATE))
	_fnoise(out, sd, {"gain": 0.3, "lp": 320.0, "lp2": 200.0, "a": 0.25, "h": 1.2, "d": 1.6 * j.v(0.1),
			"am": 0.9, "am_depth": 0.5})
	_fnoise(out, sd + 2, {"gain": 0.1, "lp": 1400.0, "lp2": 1400.0, "hp": 250.0, "a": 0.15, "h": 0.8, "d": 1.4,
			"am": 3.1, "am_depth": 0.7})
	# Structural snaps early, then a long rain of concrete chunks.
	_crackle(out, sd + 4, 0.0, 0.8, 6, 0.35, 3000.0)
	_crackle(out, sd + 5, 0.2, 4.0, 140, 0.15, 1500.0)
	_add(out, _tone(int(1.5 * RATE), 55.0, 28.0, 0.4, 0.5), 0.35, int(0.15 * RATE))
	return out


## Rocket (RPG-style pop + roaring motor) or missile (soft eject thump, ignition, hissing motor).
static func _rocket(sd: int, j: _Jit, missile: bool) -> PackedFloat32Array:
	var dur := 2.2 if missile else 1.7
	var out := _zeros(int(dur * RATE))
	var pop := _noise(int(0.08 * RATE), sd)
	_bp(pop, 700.0 * j.v(0.15), 400.0, 1.5, 0.05)
	_env(pop, 0.0005, 0.02)
	_add(out, pop, 1.0 if missile else 2.0)
	_add(out, _tone(int(0.25 * RATE), 110.0, 55.0, 0.08, 0.06), 0.8 if missile else 1.2)
	var start := 0.18 if missile else 0.0
	var motor := _noise(int((dur - start) * RATE), sd + 1)
	var c0 := 2600.0 if missile else 1500.0
	_bp(motor, c0 * j.v(0.1), c0 * 0.45, 0.9, dur - start)
	var att := 0.05 * RATE
	var kd := exp(-1.0 / ((0.9 if missile else 0.55) * RATE))
	var g := 1.0
	for i in motor.size():
		g *= kd
		motor[i] *= minf(i / att, 1.0) * g * (1.0 - 0.25 * (0.5 + 0.5 * sin(TAU * 23.0 * i / RATE)))
	_add(out, motor, 1.5, int(start * RATE))
	_fnoise(out, sd + 3, {"gain": 0.2, "at": start, "lp": 500.0, "lp2": 2000.0, "a": 0.03, "d": 0.8 if missile else 0.6})
	return out


static func _mortar(sd: int, j: _Jit) -> PackedFloat32Array:
	var out := _zeros(int(1.0 * RATE))
	_add(out, _tone(int(0.5 * RATE), 190.0 * j.v(0.08), 85.0, 0.06, 0.09), 1.6)
	_add(out, _tone(int(0.6 * RATE), 250.0 * j.v(0.05), 240.0, 0.0, 0.14, 0.5), 0.45)
	var thump := _noise(int(0.3 * RATE), sd)
	_bp(thump, 450.0, 250.0, 1.4, 0.08)
	_env(thump, 0.001, 0.05)
	_add(out, thump, 1.8)
	_fnoise(out, sd + 1, {"gain": 0.07, "lp": 700.0, "a": 0.02, "d": 0.28})
	return out


static func _whistle(sd: int, j: _Jit) -> PackedFloat32Array:
	var n := int(1.9 * RATE)
	var air := _noise(n, sd)
	var f_start := 1700.0 * j.v(0.08)
	var f_end := 520.0
	_bp(air, f_start, f_end, 9.0, 1.9)
	var out := _zeros(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * f_start * pow(f_end / f_start, t * t) / RATE
		var g := pow(t, 1.6) * 0.9 + 0.08
		if t > 0.97:
			g *= (1.0 - t) / 0.03
		out[i] = (sin(ph) * 0.55 + air[i] * 1.4) * g
	return out


static func _jet(sd: int) -> PackedFloat32Array:
	var n := int(5.0 * RATE)
	var src := _noise(n, sd)
	_bp(src, 2400.0, 650.0, 0.8, 5.0)
	_fnoise(src, sd + 1, {"gain": 0.25, "lp": 160.0, "lp2": 160.0, "a": 0.001, "d": 1000.0})
	# Ground-reflection flanging (comb filter with a sweeping delay) + doppler-ish swell.
	var out := _zeros(n)
	for i in n:
		var t := float(i) / n
		var d := int((0.0006 + 0.006 * absf(t - 0.45)) * RATE)
		var echo := src[i - d] if i >= d else 0.0
		var u := (t - 0.45) / 0.18
		var v := (t - 0.45) / 0.4
		out[i] = (src[i] + echo * 0.8) * (exp(-u * u) * 0.9 + exp(-v * v) * 0.25)
	return out


static func _smoke_pop(sd: int) -> PackedFloat32Array:
	var out := _zeros(int(1.5 * RATE))
	_add(out, _tone(int(0.15 * RATE), 160.0, 90.0, 0.04, 0.035), 1.2)
	_fnoise(out, sd, {"gain": 0.35, "len": 0.05, "lp": 2500.0, "a": 0.0003, "d": 0.01})
	_fnoise(out, sd + 1, {"gain": 0.18, "at": 0.04, "hp": 1800.0, "lp": 6000.0, "a": 0.06, "h": 0.25, "d": 0.55})
	return out


static func _radio_beep(sd: int) -> PackedFloat32Array:
	var out := _zeros(int(0.5 * RATE))
	var key := _noise(int(0.02 * RATE), sd)
	_bp(key, 1800.0, 1800.0, 2.0, 0.0)
	_env(key, 0.0005, 0.006)
	_add(out, key, 0.6)
	for b in 2:
		var tone := _tone(int(0.085 * RATE), 1250.0, 1250.0, 0.0, 0.0)
		_square_ish(tone)
		_gate(tone, 0.004)
		_add(out, tone, 0.35, int((0.03 + b * 0.12) * RATE))
	var sq := _noise(int(0.14 * RATE), sd + 1)
	_bp(sq, 2400.0, 1600.0, 1.0, 0.1)
	_env(sq, 0.002, 0.05)
	_add(out, sq, 0.8, int(0.29 * RATE))
	return out


static func _ui_click() -> PackedFloat32Array:
	var out := _tone(int(0.05 * RATE), 2600.0, 1800.0, 0.01, 0.006)
	_fnoise(out, 99, {"gain": 0.2, "len": 0.004, "hp": 2000.0, "a": 0.0001, "d": 0.001})
	return out


static func _ui_select() -> PackedFloat32Array:
	var n := int(0.13 * RATE)
	var out := _tone(n, 880.0, 1320.0, 0.03, 0.05)
	_add(out, _tone(n, 1760.0, 2640.0, 0.03, 0.03), 0.25)
	_gate(out, 0.003)
	return out


static func _ui_order(sd: int) -> PackedFloat32Array:
	var n := int(0.26 * RATE)
	var out := _zeros(n)
	var a := _tone(int(0.07 * RATE), 740.0, 740.0, 0.0, 0.0)
	var b := _tone(int(0.09 * RATE), 1110.0, 1110.0, 0.0, 0.0)
	_square_ish(a)
	_square_ish(b)
	_gate(a, 0.004)
	_gate(b, 0.004)
	_add(out, a, 0.5, int(0.005 * RATE))
	_add(out, b, 0.5, int(0.1 * RATE))
	var sq := _noise(n, sd)
	_bp(sq, 2000.0, 2000.0, 1.5, 0.0)
	_add(out, sq, 0.04)
	return out


static func _ui_alert() -> PackedFloat32Array:
	var out := _zeros(int(0.75 * RATE))
	var hz := [880.0, 660.0, 880.0]
	for i in 3:
		var t := _tone(int(0.17 * RATE), hz[i], hz[i], 0.0, 0.0)
		_square_ish(t)
		_gate(t, 0.006)
		_add(out, t, 0.45, int(i * 0.2 * RATE))
	return out


# --- loops ---------------------------------------------------------------------------

## Attack helicopter: 4-blade rotor slap at 20 Hz, turbine whine, engine roar (2 s loop).
static func _heli_loop(sd: int) -> PackedFloat32Array:
	var n := 2 * RATE
	var out := _noise_bed(n, sd, 900.0, 300.0, 0.06)
	var slap_n := int(0.045 * RATE)
	var period := RATE / 20.0
	for s in 40:
		var burst := _zeros(slap_n)
		_fnoise(burst, sd + 100 + s, {"gain": 0.4, "lp": 700.0, "a": 0.0005, "d": 0.011})
		_add(burst, _tone(slap_n, 85.0, 60.0, 0.02, 0.016), 1.3)
		_add_wrap(out, burst, 1.0 if s % 2 == 0 else 0.7, int(s * period))
	_add_wrap(out, _tone(n, 1520.0, 1520.0, 0.0, 0.0), 0.05, 0)
	_add_wrap(out, _tone(n, 3040.0, 3040.0, 0.0, 0.0), 0.025, 0)
	return out


## Tank: diesel/turbine harmonics at 32 Hz with roughness, track clatter at 9 Hz (2 s loop).
static func _tank_loop(sd: int) -> PackedFloat32Array:
	var n := 2 * RATE
	var out := _noise_bed(n, sd, 420.0, 160.0, 0.11)
	_add_harmonics(out, 32.0, 8, 0.32, 0.72)
	_am_loop(out, 4.0, 0.18)
	var click_n := int(0.03 * RATE)
	for c in 18:
		var burst := _noise(click_n, sd + 200 + c)
		_bp(burst, 1500.0 + 300.0 * float(c % 3), 1500.0, 2.5, 0.0)
		_env(burst, 0.0005, 0.006)
		_add_wrap(out, burst, 0.9 * (0.7 + 0.3 * float((c * 7) % 5) / 4.0), int(c * n / 18.0))
	_add_wrap(out, _tone(n, 1150.0, 1150.0, 0.0, 0.0), 0.035, 0)
	return out


## Truck: rough diesel at 26 Hz firing rate, no clatter (2 s loop).
static func _truck_loop(sd: int) -> PackedFloat32Array:
	var n := 2 * RATE
	var out := _noise_bed(n, sd, 600.0, 200.0, 0.1)
	_add_harmonics(out, 26.0, 10, 0.3, 0.68)
	var pulse_n := int(0.02 * RATE)
	for p in 52:
		var burst := _zeros(pulse_n)
		_fnoise(burst, sd + 300 + p, {"gain": 0.2, "lp": 900.0, "a": 0.001, "d": 0.006})
		_add_wrap(out, burst, 0.5 + 0.25 * float((p * 13) % 7) / 6.0, int(p * n / 52.0))
	return out


## Quadcopter: four detuned motors (beating) with buzzy harmonics + prop wash (2 s loop).
static func _drone_loop(sd: int) -> PackedFloat32Array:
	var n := 2 * RATE
	var out := _noise_bed(n, sd, 3000.0, 900.0, 0.08)
	for f in [186.0, 191.5, 197.0, 203.5]:
		_add_harmonics(out, f, 6, 0.12, 0.6)
	_am_loop(out, 0.5, 0.1)
	return out


## Wind: low rushing noise with slow gusts (8 s loop).
static func _wind_loop(sd: int) -> PackedFloat32Array:
	var n := 8 * RATE
	var fade := int(1.5 * RATE)
	var b := _zeros(n + fade)
	# Gust-modulated two-pole lowpass; the modulation has whole cycles over n so the
	# crossfaded region lines up with the loop start.
	var o := sd * 977
	var y1 := 0.0
	var y2 := 0.0
	for i in n + fade:
		var t := float(i) / n
		var gust := 0.5 + 0.3 * sin(TAU * t + 0.6) + 0.2 * sin(TAU * 3.0 * t + 1.7)
		var a := 0.012 + 0.03 * gust
		y1 += (_tab[(o + i) & _TAB_MASK] - y1) * a
		y2 += (y1 - y2) * a
		# Two poles scale noise by ~a, so divide it out: gusts get brighter AND a bit louder.
		b[i] = y2 / a * (0.55 + 0.45 * gust)
	return _crossfade_loop(b, n, fade)


## Distant battle: low rumble bed, muffled artillery booms and MG bursts (8 s loop).
static func _battle_loop(sd: int) -> PackedFloat32Array:
	var n := 8 * RATE
	var out := _noise_bed(n, sd, 140.0, 90.0, 0.2)
	var rng := _Jit.new(sd)
	for e in 6:
		var boom := _zeros(int(1.6 * RATE))
		_fnoise(boom, sd + 400 + e, {"gain": 0.17, "lp": 260.0, "lp2": 180.0, "a": 0.01, "d": 0.45})
		_add_wrap(out, boom, rng.f(1.2, 2.6), int(rng.r() * n))
	var pop_n := int(0.08 * RATE)
	for burst in 8:
		var at := int(rng.r() * n)
		var shots := 3 + int(rng.r() * 7)
		var gap := int(rng.f(0.07, 0.12) * RATE)
		var amp := rng.f(0.25, 0.6)
		for s in shots:
			var pop := _zeros(pop_n)
			_fnoise(pop, sd + 500 + burst * 20 + s, {"gain": 0.45, "lp": 650.0, "lp2": 650.0, "a": 0.001, "d": 0.02})
			_add_wrap(out, pop, amp, at + s * gap)
	return out


## Rain: hiss with random droplet ticks (4 s loop).
static func _rain_loop(sd: int) -> PackedFloat32Array:
	var n := 4 * RATE
	var fade := int(0.5 * RATE)
	var b := _zeros(n + fade)
	_fnoise(b, sd, {"gain": 0.3, "hp": 900.0, "lp": 5000.0, "a": 0.0001, "d": 1000.0})
	var out := _crossfade_loop(b, n, fade)
	var rng := _Jit.new(sd)
	var tick_n := int(0.006 * RATE)
	for d in 220:
		var tick := _zeros(tick_n)
		_fnoise(tick, sd + 600 + d, {"gain": 0.6, "hp": 2500.0, "a": 0.0002, "d": 0.0015})
		_add_wrap(out, tick, rng.f(0.3, 1.2), int(rng.r() * n))
	return out


# --- DSP helpers -----------------------------------------------------------------------

## Deterministic jitter source for per-variant parameter variation.
class _Jit:
	var s := 1

	func _init(sd: int) -> void:
		s = (sd & 0x7fffffff) | 1

	func r() -> float:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		return float(s) / 2147483647.0

	func f(a: float, b: float) -> float:
		return a + (b - a) * r()

	## 1 +- amount
	func v(amount: float) -> float:
		return 1.0 + (r() * 2.0 - 1.0) * amount


## Shared white-noise table (~12 s); clips read it at seed-dependent offsets.
static func _table() -> void:
	if not _tab.is_empty():
		return
	var t := PackedFloat32Array()
	t.resize(1 << _TAB_BITS)
	var s := 0x2545F491
	for i in t.size():
		s = (s * 1103515245 + 12345) & 0x7fffffff
		t[i] = float(s) * 9.313225746e-10 - 1.0
	_tab = t


static func _zeros(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(n, 1))
	b.fill(0.0)
	return b


static func _noise(n: int, sd: int) -> PackedFloat32Array:
	var size := _tab.size()
	n = maxi(n, 1)
	var o := (sd * 7919) % (size - 1)
	if o + n <= size:
		return _tab.slice(o, o + n)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = _tab[(o + i) & _TAB_MASK]
	return b


## Fused filtered-noise layer accumulated into `out` (see key list above the recipes).
## `gain` is the layer's RMS level before its envelope (peaks are ~3x that).
static func _fnoise(out: PackedFloat32Array, sd: int, p: Dictionary) -> void:
	var at := int(float(p.get("at", 0.0)) * RATE)
	var n := out.size() - at
	if p.has("len"):
		n = mini(n, int(float(p["len"]) * RATE))
	if n <= 0:
		return
	var gain: float = p.get("gain", 1.0)
	var lp0: float = p.get("lp", 0.0)
	var lp_end: float = p.get("lp_end", lp0)
	var ns := maxi(int(float(p.get("sweep", 0.0)) * RATE), 1)
	var sweeping := p.has("sweep") and lp0 > 0.0
	var a1 := _pole(lp0)
	var a2 := _pole(float(p.get("lp2", 0.0)))
	# Unit-RMS output regardless of cutoff: divide by the poles' white-noise std gain
	# (one pole: variance x a / (2 - a)); uniform noise has RMS 1/sqrt(3).
	gain *= 1.7320508 / sqrt((a1 / (2.0 - a1)) * (a2 / (2.0 - a2)))
	var hp: float = p.get("hp", 0.0)
	var ha := exp(-TAU * hp / RATE)
	var na := maxi(int(float(p.get("a", 0.001)) * RATE), 1)
	var nh := na + int(float(p.get("h", 0.0)) * RATE)
	var kd := exp(-1.0 / (float(p.get("d", 1.0)) * RATE))
	var am_w := TAU * float(p.get("am", 0.0)) / RATE
	var am_depth: float = p.get("am_depth", 0.0)
	var am_ph := float(sd % 97) * 0.13
	var o := sd * 7919
	var y1 := 0.0
	var y2 := 0.0
	var hy := 0.0
	var hx := 0.0
	var g := 1.0
	var am := 1.0
	for i in n:
		if i & 31 == 0:
			if sweeping:
				a1 = _pole(lp0 * pow(lp_end / lp0, minf(float(i) / ns, 1.0)))
			if am_depth > 0.0:
				am = 1.0 - am_depth * (0.5 + 0.3 * sin(am_w * i + am_ph) + 0.2 * sin(am_w * 2.37 * i + am_ph * 2.0))
		var x := _tab[(o + i) & _TAB_MASK]
		if hp > 0.0:
			hy = ha * (hy + x - hx)
			hx = x
			x = hy
		y1 += (x - y1) * a1
		y2 += (y1 - y2) * a2
		var e := 1.0
		if i < na:
			e = float(i) / na
		elif i >= nh:
			g *= kd
			e = g
		out[at + i] += y2 * e * am * gain


## One-pole lowpass coefficient (1 = bypass for hz <= 0 or near Nyquist).
static func _pole(hz: float) -> float:
	if hz <= 0.0 or hz >= RATE * 0.45:
		return 1.0
	return 1.0 - exp(-TAU * hz / RATE)


## Sine with exponential glide f0 -> f1 over `glide` s and exponential decay (0 = sustained).
static func _tone(n: int, f0: float, f1: float, glide: float, decay: float, phase: float = 0.0) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(n, 1))
	var ng := int(glide * RATE)
	var k := pow(f1 / f0, 1.0 / ng) if ng > 0 else 1.0
	var kd := exp(-1.0 / (decay * RATE)) if decay > 0.0 else 1.0
	var hz := f0
	var ph := phase
	var g := 1.0
	var w := TAU / RATE
	for i in b.size():
		b[i] = sin(ph) * g
		ph += w * hz
		if i < ng:
			hz *= k
		g *= kd
	return b


static func _add(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float, offset: int = 0) -> void:
	var n := mini(src.size(), dst.size() - offset)
	for i in n:
		dst[offset + i] += src[i] * gain


static func _add_wrap(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float, offset: int) -> void:
	var m := dst.size()
	for i in src.size():
		dst[(offset + i) % m] += src[i] * gain


## Lowpassed copies of the signal added back at the given delays: [[delay_s, gain], ...] (max 3).
static func _echoes(b: PackedFloat32Array, lp_hz: float, taps: Array) -> void:
	var dry := b.duplicate()
	var a := _pole(lp_hz)
	var y := 0.0
	for i in dry.size():
		y += (dry[i] - y) * a
		dry[i] = y
	var d := [1 << 30, 1 << 30, 1 << 30]
	var g := [0.0, 0.0, 0.0]
	for t in mini(taps.size(), 3):
		d[t] = int(float(taps[t][0]) * RATE)
		g[t] = float(taps[t][1])
	var d0: int = d[0]
	var d1: int = d[1]
	var d2: int = d[2]
	var g0: float = g[0]
	var g1: float = g[1]
	var g2: float = g[2]
	for i in range(mini(d0, mini(d1, d2)), b.size()):
		var acc := 0.0
		if i >= d0:
			acc += dry[i - d0] * g0
		if i >= d1:
			acc += dry[i - d1] * g1
		if i >= d2:
			acc += dry[i - d2] * g2
		b[i] += acc


## Linear attack, optional hold, exponential decay (time constant `decay`).
static func _env(b: PackedFloat32Array, attack: float, decay: float, hold: float = 0.0) -> void:
	var na := maxi(int(attack * RATE), 1)
	var nh := na + int(hold * RATE)
	var kd := exp(-1.0 / (decay * RATE))
	var g := 1.0
	for i in b.size():
		if i < na:
			b[i] *= float(i) / na
		elif i >= nh:
			g *= kd
			b[i] *= g


## Short linear fade in/out to make tonal blips click-free.
static func _gate(b: PackedFloat32Array, fade: float) -> void:
	var nf := maxi(int(fade * RATE), 1)
	var n := b.size()
	for i in mini(nf, n):
		var g := float(i) / nf
		b[i] *= g
		b[n - 1 - i] *= g


## Soft square-ish timbre (adds odd harmonics) for UI/radio tones.
static func _square_ish(b: PackedFloat32Array) -> void:
	for i in b.size():
		b[i] = tanh(b[i] * 2.5) * 0.8


## Periodic AM with whole cycles per loop (hz must be a multiple of 1 / loop seconds).
static func _am_loop(b: PackedFloat32Array, hz: float, depth: float) -> void:
	var w := TAU * hz / RATE
	for i in b.size():
		b[i] *= 1.0 - depth * (0.5 + 0.5 * sin(w * i))


## Harmonic series on `f` via the Chebyshev recurrence sin(h x) = 2 cos(x) sin((h-1) x) - sin((h-2) x)
## (whole cycles per 2 s loop when f is a multiple of 0.5 Hz).
static func _add_harmonics(b: PackedFloat32Array, f: float, count: int, gain: float, rolloff: float) -> void:
	var w := TAU * f / RATE
	for i in b.size():
		var x := w * i
		var c2 := 2.0 * cos(x)
		var s_prev := 0.0
		var s_cur := sin(x)
		var amp := gain
		var acc := 0.0
		for h in count:
			acc += s_cur * amp
			var s_next := c2 * s_cur - s_prev
			s_prev = s_cur
			s_cur = s_next
			amp *= rolloff
		b[i] += acc


## State-variable bandpass with exponential center sweep hz0 -> hz1 over `t` s (t = 0: fixed).
static func _bp(b: PackedFloat32Array, hz0: float, hz1: float, q: float, t: float) -> void:
	var ns := maxi(int(t * RATE), 1)
	var damp := 1.0 / q
	var low := 0.0
	var band := 0.0
	var f := 0.0
	for i in b.size():
		if i & 31 == 0:
			var hz := hz0 * pow(hz1 / hz0, minf(float(i) / ns, 1.0)) if t > 0.0 else hz0
			f = 2.0 * sin(PI * minf(hz, RATE * 0.16) / RATE)
		var high := b[i] - low - damp * band
		band += f * high
		low += f * band
		b[i] = band


## Sparse debris ticks/thuds between t0 and t1 (density falls off over time).
static func _crackle(b: PackedFloat32Array, sd: int, t0: float, t1: float, count: int, gain: float, lp_hz: float) -> void:
	var rng := _Jit.new(sd)
	for c in count:
		var u := rng.r()
		_fnoise(b, sd + 1000 + c, {"gain": gain * rng.f(0.3, 1.0) * (1.0 - 0.6 * u), "at": t0 + (t1 - t0) * u * u,
				"len": 0.012, "lp": lp_hz * rng.f(0.5, 1.5), "a": 0.0003, "d": rng.f(0.002, 0.006)})


## Lowpassed noise bed (two poles) of exactly n samples, made seamless by crossfading.
static func _noise_bed(n: int, sd: int, hz1: float, hz2: float, gain: float) -> PackedFloat32Array:
	var fade := int(0.3 * RATE)
	var b := _zeros(n + fade)
	_fnoise(b, sd, {"gain": gain, "lp": hz1, "lp2": hz2, "a": 0.0001, "d": 1000.0})
	return _crossfade_loop(b, n, fade)


## Folds the extra `fade` samples after n back over the start (equal-power), so sample
## n-1 flows continuously into sample 0.
static func _crossfade_loop(b: PackedFloat32Array, n: int, fade: int) -> PackedFloat32Array:
	var out := b.slice(0, n)
	for i in fade:
		var t := float(i) / fade
		out[i] = b[n + i] * cos(t * PI * 0.5) + b[i] * sin(t * PI * 0.5)
	return out


## DC removal, NaN guard, normalization, edge fades, 16-bit packing.
static func _finish(b: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var n := b.size()
	var peak := 0.0
	if loop:
		var mean := 0.0
		for i in n:
			mean += b[i]
		mean /= n
		for i in n:
			var v := b[i] - mean
			b[i] = v
			peak = maxf(peak, absf(v))
	else:
		# One-pole DC blocker (20 Hz) fused with the peak scan.
		var a := exp(-TAU * 20.0 / RATE)
		var y := 0.0
		var xp := 0.0
		for i in n:
			var x := b[i]
			y = a * (y + x - xp)
			xp = x
			b[i] = y
			peak = maxf(peak, absf(y))
	if is_nan(peak) or is_inf(peak):
		peak = 0.0
		for i in n:
			var v := b[i]
			if is_nan(v) or is_inf(v):
				b[i] = 0.0
				bad_samples += 1
			else:
				peak = maxf(peak, absf(v))
	var g := PEAK / peak if peak > 1e-9 else 1.0
	if not loop:
		var fi := mini(4, n)
		for i in fi:
			b[i] *= float(i) / fi
		var fo := mini(int(0.02 * RATE), n)
		for i in fo:
			b[n - 1 - i] *= float(i) / fo
	# Pack two 16-bit little-endian samples per int32.
	var half := (n + 1) / 2
	var ints := PackedInt32Array()
	ints.resize(half)
	var sc := g * 32767.0
	for k in half:
		var i := k * 2
		var s0 := clampi(int(round(b[i] * sc)), -32767, 32767)
		var s1 := clampi(int(round(b[i + 1] * sc)), -32767, 32767) if i + 1 < n else 0
		ints[k] = (s0 & 0xFFFF) | (s1 << 16)
	var bytes := ints.to_byte_array()
	if n % 2 == 1:
		bytes.resize(n * 2)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w

extends Node3D
## Audio smoke test (we cannot listen, so assert the mixer's behaviour instead):
##   .tools/godot/<godot> --headless --path . -- --preview=audio
## Waits for the synthesized bank, then checks buses/Settings volumes, rate-limit merging,
## the voice cap, distance culling, loops, pause and ambience; prints PASS/FAIL and quits
## (exit code 1 on failure). Run windowed (tools/gd.sh run --preview=audio) to hear a demo.

var am: AudioManager
var _fails := 0
var _t := 0.0
var _phase := 0
var _tank: Node3D
var _loop: AudioStreamPlayer3D


func _ready() -> void:
	PreviewKit.setup(self, Vector3.ZERO, 40.0, 30.0, 30.0)
	am = AudioManager.new()
	add_child(am)
	_tank = Node3D.new()
	_tank.position = Vector3(10, 0, 0)
	add_child(_tank)


func _process(delta: float) -> void:
	_t += delta
	match _phase:
		0:
			if am.is_ready():
				print("[audio] bank ready after %.2f s (generation %.0f ms)" % [_t, Synth.gen_ms])
				_phase = 1
				_t = 0.0
				_static_checks()
			elif _t > 10.0:
				_check(false, "bank ready within 10 s")
				_finish()
		1:
			# Fill the pool across several merge windows (rate limiting is per 50 ms window).
			var names := ["ak", "lmg", "hmg", "sniper", "autocannon", "grenade", "explosion_small", "metal_hit"]
			for i in 12:
				am.play(names[randi() % names.size()], Vector3(randf_range(-80, 80), 0, randf_range(-80, 80)))
			if _t > 0.6:
				var total := _count_playing("")
				_check(total == AudioManager.VOICES, "pool fills up to the %d-voice cap (%d playing)" % [AudioManager.VOICES, total])
				am.play("explosion_large", Vector3(3, 0, 3))
				_check(_count_playing("explosion_large") == 1, "a loud nearby explosion steals a voice from the full pool")
				am.play("impact_bullet", Vector3(30, 0, 30))
				_check(_count_playing("impact_bullet") == 0, "a quiet distant impact does not steal from the full pool")
				_check(_count_playing("") <= AudioManager.VOICES, "voice cap respected after stealing")
				_phase = 3
				_t = 0.0
		3:
			# Let the burst play a little, then check pause/loop/ambience.
			if _t > 0.3:
				_phase = 2
				_t = 0.0
				am.set_paused(true)
				var paused := 0
				for c in am.get_children():
					if c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).stream_paused:
						paused += 1
				_check(paused > 0, "set_paused freezes playing voices (%d paused)" % paused)
				am.set_paused(false)
				am.stop_loop(_loop)
		2:
			if _t > 1.0:
				_check(not is_instance_valid(_loop), "stop_loop fades out and frees the player")
				var amb := _bus_peak("Ambience")
				print("[audio] ambience bus peak %.1f dB" % amb)
				_finish()


func _static_checks() -> void:
	for b in ["SFX", "Ambience", "UI"]:
		_check(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	var sfx_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	_check(absf(sfx_db - linear_to_db(float(Settings.get_value("audio", "sfx")))) < 0.01, "SFX bus volume from Settings")
	Settings.set_value("audio", "sfx", 0.5, false)
	sfx_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	_check(absf(sfx_db - linear_to_db(0.5)) < 0.01, "SFX bus follows Settings.changed live")
	Settings.set_value("audio", "sfx", Settings.DEFAULTS["audio"]["sfx"], false)

	# 30 rifles in the same frame at nearly the same place -> merged into <= 2 voices.
	var t0 := Time.get_ticks_usec()
	for i in 30:
		am.play("rifle", Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	var per_call := (Time.get_ticks_usec() - t0) / 30.0
	var rifles := _count_playing("rifle")
	_check(rifles >= 1 and rifles <= 2, "30 simultaneous rifles merged into %d voices" % rifles)
	var boosted := false
	for c in am.get_children():
		if c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).playing and (c as AudioStreamPlayer3D).volume_db > -3.0 + 0.5:
			boosted = true
	_check(boosted, "merged requests raise the surviving voice's volume")
	print("[audio] play() cost %.1f us per call" % per_call)

	# Far beyond the audible range -> culled.
	var before := _count_playing("")
	am.play("impact_bullet", Vector3(500, 0, 500))
	_check(_count_playing("") == before, "impact 700 m away is culled")

	# One frame flood: rate limiting keeps it to a few voices per sound.
	var names := ["ak", "lmg", "hmg", "sniper", "autocannon", "grenade", "explosion_small", "impact_bullet", "ricochet", "metal_hit"]
	for i in 120:
		am.play(names[i % names.size()], Vector3(randf_range(-40, 40), 0, randf_range(-40, 40)))
	_check(_count_playing("") <= 3 * names.size() + 2, "120 requests in one window -> %d voices" % _count_playing(""))

	_loop = am.play_loop("engine_tank_loop", _tank)
	_check(_loop != null and _loop.playing and _loop.get_parent() == _tank, "play_loop attaches a playing loop to the unit")
	_check((_loop.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "engine clip loops")
	am.play_ui("ui_click")
	am.set_ambience("dust", 1.0)
	am.set_listener_height(120.0)
	am.play("not_a_sound", Vector3.ZERO)


func _count_playing(sound: String) -> int:
	var n := 0
	for c in am.get_children():
		if c is AudioStreamPlayer3D:
			var p := c as AudioStreamPlayer3D
			if p.playing and (sound == "" or (p.stream != null and _bank_has(sound, p.stream))):
				n += 1
	return n


func _bank_has(sound: String, s: AudioStream) -> bool:
	return Synth.bank()[sound].has(s)


func _bus_peak(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))


func _check(ok: bool, what: String) -> void:
	print("[audio] %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _finish() -> void:
	print("[audio] %s (%d failures)" % ["ALL PASS" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)

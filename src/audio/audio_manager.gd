extends Node
## Procedural battlefield audio (docs/CONTRACTS.md §4). One instance per game session.
##
## - Every clip comes from Synth (generated in the background at startup, cached per process;
##   one-shots requested in the first few hundred ms are dropped, loops start when ready).
## - 48 pooled AudioStreamPlayer3D voices; when all are busy the quietest voice (by estimated
##   level at the listener, fading with age) is stolen, and only for a louder sound.
## - Per-sound rate limiting: within a 50 ms window each sound starts at most N new voices;
##   extra requests raise the nearest recent voice by 1.5 dB (max +6 dB) instead of stacking.
## - Buses Master/SFX/Ambience/UI are created at runtime if missing, with volumes from
##   Settings (live via Settings.changed) and a hard limiter on Master.
## - Ambience: wind (+ rain) by weather and distant battle rumble by intensity.
class_name AudioManager

const VOICES := 48
const UI_VOICES := 6
const MERGE_WINDOW_MS := 50
const MERGE_STEP_DB := 1.5
const MERGE_MAX_DB := 6.0
const BUS_SFX := "SFX"
const BUS_AMB := "Ambience"
const BUS_UI := "UI"

## Attenuation categories: unit size (m, full volume radius), max audible distance (m),
## new voices per merge window, and how much the sound fades as the camera rises (0..1).
const CATEGORIES := {
	"gun": {"unit": 7.0, "max": 330.0, "per_win": 2, "detail": 0.5},
	"heavy": {"unit": 12.0, "max": 480.0, "per_win": 2, "detail": 0.25},
	"boom": {"unit": 22.0, "max": 800.0, "per_win": 3, "detail": 0.0},
	"big": {"unit": 35.0, "max": 1100.0, "per_win": 2, "detail": 0.0},
	"small": {"unit": 3.0, "max": 60.0, "per_win": 2, "detail": 1.0},
	"ping": {"unit": 3.5, "max": 85.0, "per_win": 1, "detail": 1.0},
	"misc": {"unit": 8.0, "max": 260.0, "per_win": 2, "detail": 0.3},
	"whistle": {"unit": 14.0, "max": 450.0, "per_win": 2, "detail": 0.0},
	"tank": {"unit": 8.0, "max": 230.0, "per_win": 4, "detail": 0.3},
	"truck": {"unit": 6.0, "max": 170.0, "per_win": 4, "detail": 0.5},
	"heli": {"unit": 22.0, "max": 650.0, "per_win": 4, "detail": 0.0},
	"drone": {"unit": 3.0, "max": 100.0, "per_win": 4, "detail": 0.8},
	"ui": {"unit": 1.0, "max": 0.0, "per_win": 3, "detail": 0.0},
}

## sound -> [volume dB at unit distance, category, pitch jitter]
const SOUNDS := {
	"rifle": [-3.0, "gun", 0.04], "ak": [-2.0, "gun", 0.04], "lmg": [-3.0, "gun", 0.03],
	"hmg": [0.0, "heavy", 0.03], "sniper": [0.0, "heavy", 0.02], "autocannon": [1.0, "heavy", 0.03],
	"cannon": [3.0, "boom", 0.03], "rocket_launch": [-1.0, "heavy", 0.04], "missile_launch": [-2.0, "heavy", 0.03],
	"mortar_launch": [-2.0, "heavy", 0.04], "grenade": [0.0, "boom", 0.06], "explosion_small": [1.0, "boom", 0.06],
	"explosion_medium": [2.0, "boom", 0.05], "explosion_large": [3.0, "big", 0.05],
	"impact_bullet": [-6.0, "small", 0.08], "ricochet": [-12.0, "ping", 0.1], "metal_hit": [-6.0, "ping", 0.06],
	"collapse": [3.0, "big", 0.04], "jet_flyby": [0.0, "big", 0.03], "incoming_whistle": [-6.0, "whistle", 0.03],
	"smoke_pop": [-6.0, "misc", 0.05], "radio_beep": [-8.0, "misc", 0.0],
	"heli_loop": [-4.0, "heli", 0.0], "engine_tank_loop": [-8.0, "tank", 0.0],
	"engine_truck_loop": [-10.0, "truck", 0.0], "drone_loop": [-14.0, "drone", 0.0],
	"ui_click": [-12.0, "ui", 0.0], "ui_select": [-12.0, "ui", 0.0], "ui_order": [-10.0, "ui", 0.0],
	"ui_alert": [-8.0, "ui", 0.0],
}

const _WIND_DB := {"clear": -20.0, "haze": -17.0, "dust": -6.0, "rain": -12.0}

var _bank: Dictionary = {}
var _voices: Array[SfxVoice] = []
var _ui: Array[AudioStreamPlayer] = []
var _ui_next := 0
var _windows: Dictionary = {}
var _last_variant: Dictionary = {}
var _loops: Array[AudioStreamPlayer3D] = []
var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _battle: AudioStreamPlayer
var _weather := "clear"
var _intensity := 0.0
var _height := 40.0
var _paused := false
var _warned: Dictionary = {}


class SfxVoice:
	var p: AudioStreamPlayer3D
	var sound := ""
	var start_ms := 0
	var length_ms := 1
	var base_db := 0.0
	var boost := 0.0
	var unit := 1.0
	var pos := Vector3.ZERO


## Sounds started in the current merge window for one sound name.
class MergeWindow:
	var start_ms := 0
	var count := 0
	var voices: Array[SfxVoice] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in VOICES:
		var v := SfxVoice.new()
		v.p = AudioStreamPlayer3D.new()
		v.p.bus = BUS_SFX
		v.p.max_db = 6.0
		v.p.attenuation_filter_cutoff_hz = 6000.0
		add_child(v.p)
		_voices.append(v)
	for i in UI_VOICES:
		var u := AudioStreamPlayer.new()
		u.bus = BUS_UI
		add_child(u)
		_ui.append(u)
	_wind = _ambience_player()
	_rain = _ambience_player()
	_battle = _ambience_player()
	Settings.changed.connect(_on_settings_changed)
	Synth.generate_async()
	if Synth.is_ready():
		_on_bank_ready()


# --- contract API ----------------------------------------------------------------

## Positional one-shot. Unknown names and sounds beyond their audible range are ignored.
func play(sound: String, pos: Vector3, volume_db: float = 0.0) -> void:
	if _bank.is_empty() or not _known(sound):
		return
	if Synth.is_loop(sound):
		_warn_once(sound, "AudioManager.play(): '%s' is a loop, use play_loop()" % sound)
		return
	var cfg: Dictionary = CATEGORIES[SOUNDS[sound][1]]
	var lis := _listener_pos()
	var d := lis.distance_to(pos)
	var max_d: float = cfg["max"]
	if max_d > 0.0 and d > max_d:
		return
	var now := Time.get_ticks_msec()
	var base_db: float = float(SOUNDS[sound][0]) + volume_db + _detail_db(cfg)
	if _merge(sound, pos, now, cfg):
		return
	var unit: float = cfg["unit"]
	var level := base_db - _dist_db(d, unit)
	var v := _acquire(level, lis, now)
	if v == null:
		return
	var clip := _pick(sound)
	var jitter: float = SOUNDS[sound][2]
	v.sound = sound
	v.start_ms = now
	v.length_ms = maxi(int(clip.get_length() * 1000.0), 1)
	v.base_db = base_db
	v.boost = 0.0
	v.unit = unit
	v.pos = pos
	v.p.stream = clip
	v.p.unit_size = unit
	v.p.max_distance = max_d
	v.p.volume_db = base_db
	v.p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	v.p.global_position = pos
	v.p.stream_paused = false
	v.p.play()
	var w: MergeWindow = _windows[sound]
	w.voices.append(v)


func play_ui(sound: String) -> void:
	if _bank.is_empty() or not _known(sound):
		return
	var u := _ui[_ui_next]
	_ui_next = (_ui_next + 1) % _ui.size()
	u.stream = _pick(sound)
	u.volume_db = float(SOUNDS[sound][0])
	u.play()


## Camera height above the ground: small details (impacts, rifles) get quieter when zoomed
## out, the wind gets a little louder.
func set_listener_height(h: float) -> void:
	_height = maxf(h, 0.0)


## weather: clear | haze | dust | rain; intensity 0..1 = how much battle is going on.
func set_ambience(weather: String, intensity: float) -> void:
	_weather = weather
	_intensity = clampf(intensity, 0.0, 1.0)


# --- additions ----------------------------------------------------------------------

## Looping sound attached to a unit (engine, rotor). Returns the player (null if unknown);
## stop it with stop_loop(). It is freed with `attach_to` if the unit goes away.
func play_loop(sound: String, attach_to: Node3D, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	if not _known(sound) or not is_instance_valid(attach_to):
		return null
	var cfg: Dictionary = CATEGORIES[SOUNDS[sound][1]]
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_SFX
	p.max_db = 6.0
	p.unit_size = cfg["unit"]
	p.max_distance = cfg["max"]
	p.attenuation_filter_cutoff_hz = 6000.0
	p.volume_db = float(SOUNDS[sound][0]) + volume_db
	p.pitch_scale = randf_range(0.96, 1.04)
	p.set_meta("sound", sound)
	p.set_meta("volume", volume_db)
	attach_to.add_child(p)
	_loops.append(p)
	if not _bank.is_empty():
		_start_loop(p)
	return p


func stop_loop(p: AudioStreamPlayer3D) -> void:
	_loops.erase(p)
	if not is_instance_valid(p):
		return
	if not p.is_inside_tree() or not p.playing:
		p.queue_free()
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", p.volume_db - 40.0, 0.35)
	tw.tween_callback(p.queue_free)


## Tactical pause: freezes one-shots and unit loops (ambience and UI keep playing).
func set_paused(paused: bool) -> void:
	_paused = paused
	for v in _voices:
		v.p.stream_paused = paused and v.p.playing
	for p in _loops:
		if is_instance_valid(p):
			p.stream_paused = paused


## True once the synthesized bank is available.
func is_ready() -> bool:
	return not _bank.is_empty()


# --- internals ----------------------------------------------------------------------

func _exit_tree() -> void:
	# Release live playbacks before the session goes away.
	for c in get_children():
		if c is AudioStreamPlayer3D or c is AudioStreamPlayer:
			c.stop()
	for p in _loops:
		if is_instance_valid(p):
			p.stop()


func _process(delta: float) -> void:
	if _bank.is_empty():
		if Synth.is_ready():
			_on_bank_ready()
		else:
			return
	_update_ambience(delta)


func _on_bank_ready() -> void:
	_bank = Synth.bank()
	_wind.stream = _bank["wind_loop"][0]
	_rain.stream = _bank["rain_loop"][0]
	_battle.stream = _bank["battle_distant_loop"][0]
	for a in [_wind, _rain, _battle]:
		var p: AudioStreamPlayer = a
		p.play(randf() * p.stream.get_length())
	for p in _loops:
		if is_instance_valid(p) and not p.playing:
			_start_loop(p)


func _start_loop(p: AudioStreamPlayer3D) -> void:
	var clip := _pick(String(p.get_meta("sound")))
	p.stream = clip
	if p.is_inside_tree():
		p.play(randf() * clip.get_length())
		p.stream_paused = _paused


## Rate limiting. Returns true when the request was merged into a recent voice.
func _merge(sound: String, pos: Vector3, now: int, cfg: Dictionary) -> bool:
	var w: MergeWindow = _windows.get(sound)
	if w == null:
		w = MergeWindow.new()
		_windows[sound] = w
	if now - w.start_ms >= MERGE_WINDOW_MS:
		w.start_ms = now
		w.count = 0
		w.voices.clear()
	w.count += 1
	if w.count <= int(cfg["per_win"]):
		return false
	var best: SfxVoice = null
	var best_d := INF
	for v in w.voices:
		if v.sound == sound and v.p.playing:
			var dd := v.pos.distance_squared_to(pos)
			if dd < best_d:
				best_d = dd
				best = v
	if best == null:
		return false
	best.boost = minf(best.boost + (MERGE_STEP_DB if best_d < 900.0 else MERGE_STEP_DB * 0.5), MERGE_MAX_DB)
	best.p.volume_db = best.base_db + best.boost
	return true


## Free voice, or the quietest playing one if it is quieter than `level`.
func _acquire(level: float, lis: Vector3, now: int) -> SfxVoice:
	var worst: SfxVoice = null
	var worst_level := level
	for v in _voices:
		if not v.p.playing:
			return v
		var age := float(now - v.start_ms) / v.length_ms
		var l := v.base_db + v.boost - _dist_db(lis.distance_to(v.pos), v.unit) - 24.0 * clampf(age, 0.0, 1.0)
		if l < worst_level:
			worst_level = l
			worst = v
	if worst:
		worst.p.stop()
	return worst


## Random variant, never the same one twice in a row.
func _pick(sound: String) -> AudioStreamWAV:
	var arr: Array = _bank[sound]
	if arr.size() == 1:
		return arr[0]
	var last: int = _last_variant.get(sound, -1)
	var i := randi() % arr.size()
	if i == last:
		i = (i + 1) % arr.size()
	_last_variant[sound] = i
	return arr[i]


func _dist_db(d: float, unit: float) -> float:
	return 20.0 * log(maxf(d, unit) / unit) / log(10.0)


func _detail_db(cfg: Dictionary) -> float:
	return -9.0 * float(cfg["detail"]) * clampf((_height - 30.0) / 150.0, 0.0, 1.0)


func _listener_pos() -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	return cam.global_position if cam else Vector3.ZERO


func _known(sound: String) -> bool:
	if SOUNDS.has(sound) and (_bank.is_empty() or _bank.has(sound)):
		return true
	_warn_once(sound, "AudioManager: unknown sound '%s'" % sound)
	return false


func _warn_once(key: String, msg: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(msg)


func _update_ambience(delta: float) -> void:
	var wind_db: float = _WIND_DB.get(_weather, -18.0) + 5.0 * clampf((_height - 20.0) / 180.0, 0.0, 1.0)
	var rain_db := -10.0 if _weather == "rain" else -80.0
	var battle_db := -70.0 + 58.0 * pow(_intensity, 0.6)
	var k := 1.0 - exp(-delta * 1.5)
	_wind.volume_db = lerpf(_wind.volume_db, wind_db, k)
	_rain.volume_db = lerpf(_rain.volume_db, rain_db, k)
	_battle.volume_db = lerpf(_battle.volume_db, battle_db, k)


func _ambience_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = BUS_AMB
	p.volume_db = -80.0
	add_child(p)
	return p


func _setup_buses() -> void:
	for b in [BUS_SFX, BUS_AMB, BUS_UI]:
		if AudioServer.get_bus_index(b) < 0:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var has_limiter := false
	for e in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, e) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)
	_apply_volumes()


func _apply_volumes() -> void:
	_set_bus_volume("Master", "master")
	_set_bus_volume(BUS_SFX, "sfx")
	_set_bus_volume(BUS_AMB, "ambience")
	_set_bus_volume(BUS_UI, "ui")


func _set_bus_volume(bus: String, key: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v := float(Settings.get_value("audio", key))
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "audio":
		_apply_volumes()

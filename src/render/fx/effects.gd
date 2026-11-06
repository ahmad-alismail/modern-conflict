extends Node3D
## Battlefield visual effects (docs/CONTRACTS.md §3). One instance lives in the world.
##
## Every particle goes into one of three shared world-space GPU particle "batchers"
## fed with emit_particle() (lit smoke/dust, additive glow, opaque debris). Per-particle
## behaviour (size, life, drag, buoyancy, heat...) is packed into the emission data and
## simulated by custom particle shaders, so an effect costs a handful of RenderingServer
## calls, no nodes and no extra draw calls. Lights and crater decals are pooled with hard
## caps; fires, smoke screens and lingering dust are ticked on a pausable clock.
class_name Effects

## Camera shake request (strength ~0.1 grenade .. ~1.5 bomb) at a world position.
signal shake(strength: float, pos: Vector3)

const MAX_DECALS := 120

const _EMIT_ALL := 31 # position | rotation_scale | velocity | color | custom
const _LIGHT_CAP := [4, 8, 12, 16]
const _MULT := [0.4, 0.65, 1.0, 1.3]
const _SMOKE_N := [1536, 2560, 4096, 6144]
const _GLOW_N := [1024, 2048, 3072, 4096]
const _DEBRIS_N := [256, 512, 768, 1024]
const _FRAME_BUDGET := 2500 # max particles emitted per frame, all batchers
const _BATCH_LIFETIME := 40.0 # upper bound for any particle lifetime (s)

const _SMOKE_PROCESS := preload("res://src/render/fx/smoke_particles.gdshader")
const _SMOKE_DRAW := preload("res://src/render/fx/smoke_draw.gdshader")
const _GLOW_PROCESS := preload("res://src/render/fx/glow_particles.gdshader")
const _GLOW_DRAW := preload("res://src/render/fx/glow_draw.gdshader")
const _DEBRIS_PROCESS := preload("res://src/render/fx/debris_particles.gdshader")

const _K_FIRE := 0
const _K_SCREEN := 1
const _K_DUST := 2

## Wind used by smoke (m/s, horizontal). Change with set_wind().
var wind := Vector3(2.4, 0.0, 1.0)

var _smoke: GPUParticles3D
var _glow: GPUParticles3D
var _debris: GPUParticles3D
var _smoke_pm: ShaderMaterial
var _timed_mats: Array[ShaderMaterial] = []
var _time := 0.0
var _paused := false
var _q := 2
var _qm := 1.0
var _frame_emits := 0
var _load := 0.0
var _lights: Array[FxLight] = []
var _decals: Array[Decal] = []
var _decal_next := 0
var _emitters: Array[FxEmitter] = []
var _flyers: Array[FxFlyer] = []
var _pend_t: Array[float] = []
var _pend_fn: Array[Callable] = []
var _light_assign_t := 0.0


class FxLight:
	var node: OmniLight3D
	var active := false
	var t0 := 0.0
	var dur := 0.1
	var energy := 1.0
	var fire: FxEmitter = null

	func value(now: float) -> float:
		var x := clampf((now - t0) / dur, 0.0, 1.0)
		return energy * node.omni_range * (1.0 - x) * (1.0 - x)


class FxEmitter:
	var kind := 0
	var pos := Vector3.ZERO
	var size := Vector3.ONE
	var t0 := 0.0
	var dur := 1.0
	var emit_until := 1.0
	var acc := PackedFloat32Array([0.0, 0.0, 0.0])
	var light: FxLight = null


class FxFlyer:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var t_end := 0.0
	var trail := 0.0
	var size := 1.0


func _ready() -> void:
	_q = clampi(Settings.quality(), 0, 3)
	_qm = _MULT[_q]
	var noise := FxTextures.noise()

	_smoke_pm = _process_mat(_SMOKE_PROCESS)
	var smoke_draw := _draw_mat(_SMOKE_DRAW, noise)
	smoke_draw.render_priority = 0
	_smoke = _make_batch(_smoke_pm, _quad(smoke_draw), _SMOKE_N[_q], GPUParticles3D.DRAW_ORDER_VIEW_DEPTH)

	var glow_draw := _draw_mat(_GLOW_DRAW, noise)
	glow_draw.render_priority = 1
	_glow = _make_batch(_process_mat(_GLOW_PROCESS), _quad(glow_draw), _GLOW_N[_q], GPUParticles3D.DRAW_ORDER_INDEX)

	var rock_mat := StandardMaterial3D.new()
	rock_mat.vertex_color_use_as_albedo = true
	rock_mat.roughness = 0.95
	_debris = _make_batch(_process_mat(_DEBRIS_PROCESS), _rock_mesh(rock_mat), _DEBRIS_N[_q], GPUParticles3D.DRAW_ORDER_INDEX)
	_debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _q >= 3 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_wind(wind)
	Settings.changed.connect(_on_settings_changed)


# --- public API (contract) ------------------------------------------------------

## Muzzle flash. size: ~0.3-0.6 small arms, ~1 HMG/autocannon, 2-3 tank gun.
func muzzle_flash(pos: Vector3, dir: Vector3, size: float) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-8 else Vector3.FORWARD
	var s := clampf(size, 0.1, 5.0)
	emit_glow(pos, Vector3.ZERO, Color(1.0, 0.8, 0.5, 1.8), 0.045 + 0.02 * s, 0.32 * s + 0.08, 0.5 * s + 0.12,
			3, 0, 0.0, 0.0, 2.6, 0.0, 0.0, d)
	emit_glow(pos, Vector3.ZERO, Color(1.0, 0.7, 0.4, 2.0), 0.035 + 0.015 * s, 0.25 * s + 0.06, 0.5 * s + 0.1, 0, 1)
	if s >= 1.2:
		# Heavy gun: blast smoke ring around the muzzle and a dust kick.
		var n := _count(3.0 + 3.0 * s, 1.0)
		for i in n:
			var v := d * randf_range(5.0, 14.0) * s + _rand_unit() * 3.0
			emit_smoke(pos + d * randf() * 0.5 * s, v, Color(0.78, 0.75, 0.7, 0.5), 2.0 + s, 0.5 * s, 2.4 * s + 1.0,
					2.6, 0.35, 0.7, 2.0, 0.08, 0.04, 0.3)
	if s >= 0.8 or (_q >= 2 and randf() < 0.35):
		_flash_light(pos + d * 0.5, Color(1.0, 0.72, 0.42), 1.5 + 2.5 * s, 3.0 + 5.0 * s, 0.05 + 0.04 * s)


## Tracer streak flying from -> to at 500-850 m/s, followed by a small impact.
## impact_kind: "auto" (dirt on the ground, concrete above it), "" for none, or an impact kind.
func tracer(from: Vector3, to: Vector3, color: Color, impact_kind: String = "auto") -> void:
	var seg := to - from
	var dist := seg.length()
	if dist < 0.05:
		return
	var dir := seg / dist
	var life := maxf(dist / randf_range(500.0, 850.0), 0.034)
	var speed := dist / life
	var c := Color(color.r, color.g, color.b, 2.6)
	emit_glow(from, dir * speed, c, life, 0.4, 0.4, 2, 0, 0.0, 0.0, 0.0, 0.0, 0.0,
			Vector3(dist, minf(9.0, dist * 0.7), 0.0))
	if impact_kind == "":
		return
	var kind := impact_kind
	if kind == "auto":
		kind = "dirt" if to.y < 0.4 else "concrete"
	_schedule(life, _impact.bind(to, kind, 0.6))


func impact(pos: Vector3, kind: String) -> void:
	_impact(pos, kind, 1.0)


## Explosion. size 0.5 grenade, 1 shell/rocket, 2 artillery, 3 bomb or vehicle cook-off.
func explosion(pos: Vector3, size: float) -> void:
	var k := clampf(size, 0.2, 4.0)
	var sk := sqrt(k)
	_load += 1.0
	var m := 1.0 / (1.0 + 0.12 * maxf(_load - 4.0, 0.0))
	var near_ground := pos.y < 1.5
	var gy := minf(pos.y, 0.0) if near_ground else pos.y - 60.0
	var debris_y := minf(pos.y, 0.0)
	var lod := _lod(pos)
	var up := Vector3.UP

	# Flash + light.
	emit_glow(pos + up * 0.6 * k, Vector3.ZERO, Color(1.0, 0.8, 0.55, 9.0), 0.11 + 0.05 * k, 2.4 * k + 1.5, 6.0 * k + 3.0, 0, 1)
	emit_glow(pos + up * 0.4 * k, Vector3.ZERO, Color(1.0, 0.95, 0.85, 12.0), 0.06 + 0.03 * k, 1.2 * k + 0.6, 3.2 * k + 1.0, 0, 1)
	_flash_light(pos + up * (1.0 + k), Color(1.0, 0.62, 0.32), 3.0 + 2.5 * k, 8.0 + 12.0 * k, 0.25 + 0.15 * k)

	# Fireball.
	for i in _count(7.0 + 7.0 * k, m):
		var d := _rand_unit()
		if near_ground:
			d.y = absf(d.y) * 0.8 + 0.2
		var v := d * randf_range(3.0, 9.0) * sk + up * 2.0 * sk
		emit_glow(pos + d * randf() * 0.6 * k, v, Color(1.0, 0.9, 0.8, randf_range(1.5, 2.2)),
				randf_range(0.15, 0.3) + 0.12 * k, randf_range(0.8, 1.3) * (0.8 * k + 0.5), randf_range(1.8, 2.6) * (k + 0.5),
				0, 0, 0.0, 3.5, 0.0, 3.0, 0.15)

	# Incandescent core smoke that cools from orange to black.
	for i in _count(8.0 + 8.0 * k, m):
		var d := _rand_unit()
		if near_ground:
			d.y = absf(d.y) * 0.7 + 0.3
		var v := d * randf_range(2.0, 7.0) * sk + up * randf_range(1.0, 4.0) * sk
		emit_smoke(pos + d * randf() * 0.8 * k, v, _grey(0.1, 0.03, 0.95), randf_range(4.0, 7.0) + 3.0 * k,
				(1.2 * k + 0.8) * randf_range(0.8, 1.2), (4.5 * k + 3.0) * randf_range(0.8, 1.2),
				1.8, 1.2 + 0.4 * k, 0.8, randf_range(3.0, 5.0), 0.08 + 0.05 * k, 0.02, 0.3, 0.4, gy)

	# Rolling dark smoke rising into a column.
	for i in _count(6.0 + 8.0 * k, m):
		var v := up * randf_range(4.0, 10.0) * sk + _rand_flat() * randf_range(0.5, 2.5) * sk
		emit_smoke(pos + up * k + _rand_flat() * randf() * 0.6 * k, v, _grey(0.17, 0.04, 0.75), randf_range(7.0, 10.0) + 5.0 * k,
				2.0 * k + 1.0, (6.0 * k + 4.0) * randf_range(0.8, 1.15), 0.9, 1.0, 1.0, 0.8, 0.2, 0.05, 0.35, 0.25, gy)

	if near_ground:
		# Dirt plume thrown up and falling back.
		for i in _count(8.0 + 6.0 * k, m):
			var d := (_rand_flat() * randf() * 0.45 + up).normalized()
			emit_smoke(pos + _rand_flat() * 0.3 * k, d * randf_range(8.0, 17.0) * sk, _earth(0.75).darkened(0.35),
					1.4 + 0.8 * k, 0.45 * k + 0.3, 1.6 * k + 0.8, 1.2, -8.0, 0.3, 0.0, 0.3, 0.03, 0.15, 0.6, gy)
		# Ground dust ring.
		for i in _count(14.0 + 14.0 * k, m):
			var a := randf() * TAU
			var d := Vector3(cos(a), 0.0, sin(a))
			emit_smoke(pos + d * 0.4 * k + up * 0.3, d * randf_range(9.0, 16.0) * pow(k, 0.75) + up * randf_range(0.0, 1.5),
					Color(0.66, 0.6, 0.5, 0.5), 3.0 + 2.5 * k, 1.0 * k + 0.8, 4.2 * k + 3.0, 2.2, 0.25, 0.7,
					0.0, 0.3, 0.04, 0.3, 0.3, gy)
		if pos.y > -1.0:
			_crater(pos, 1.4 + 2.6 * k)

	# Debris chunks and sparks (small: reduced with distance).
	for i in _count(6.0 + 14.0 * k, m * lod):
		var v := (_rand_flat() * randf_range(3.0, 10.0) + up * randf_range(5.0, 14.0)) * sk
		emit_debris(pos + up * 0.3, v, _rubble().darkened(0.25), randf_range(6.0, 14.0), randf_range(0.06, 0.18) * (0.7 + 0.3 * k), debris_y)
	for i in _count(12.0 + 18.0 * k, m * lod):
		var d := _rand_unit()
		d.y = absf(d.y) * 0.9 + 0.1
		emit_glow(pos + up * 0.3 * k, d * randf_range(12.0, 32.0) * pow(k, 0.4), Color(1.0, 0.66, 0.3, 5.0),
				randf_range(0.35, 1.0), 0.05, 0.035, 1, 0, 9.8, 1.0, 0.035, 0.0, 0.0, Vector3(0.0, debris_y, 0.0))

	# Big blasts throw burning fragments trailing smoke.
	if k >= 1.5:
		for i in _count(2.0 + 1.5 * k, m):
			var f := FxFlyer.new()
			f.pos = pos + up * 0.5
			f.vel = _rand_flat() * randf_range(5.0, 12.0) + up * randf_range(11.0, 20.0)
			f.t_end = _time + randf_range(1.0, 2.0)
			f.size = 0.5 + 0.15 * k
			_flyers.append(f)

	shake.emit(clampf(0.08 + 0.3 * pow(k, 1.2), 0.0, 1.6), pos)


## Smoke screen that fills `radius`, builds up within ~2 s, holds, and thins out by `duration`.
func smoke_cloud(pos: Vector3, radius: float, duration: float) -> void:
	var e := FxEmitter.new()
	e.kind = _K_SCREEN
	e.pos = pos
	e.size = Vector3(maxf(radius, 2.0), 0.0, 0.0)
	e.t0 = _time
	e.dur = maxf(duration, 2.0)
	var life := _screen_life(e)
	e.emit_until = _time + maxf(e.dur - life * 0.35, e.dur * 0.5)
	_emitters.append(e)
	# Initial burst: canisters pop and the cloud fills quickly.
	var n := int(_screen_target(e) * 0.75)
	for i in n:
		_screen_puff(e, true)
	for i in _count(3.0 + radius * 0.2, 1.0):
		var p := pos + _rand_flat() * randf() * radius * 0.6
		emit_glow(p + Vector3.UP * 0.3, Vector3.ZERO, Color(1.0, 0.85, 0.6, 3.0), 0.12, 0.5, 1.5, 0, 1)


## Burning wreck: flickering flames + light + tall dark smoke column drifting with the wind.
func fire(pos: Vector3, duration: float, size: float) -> void:
	var e := FxEmitter.new()
	e.kind = _K_FIRE
	e.pos = pos
	e.size = Vector3.ONE * clampf(size, 0.2, 5.0)
	e.t0 = _time
	e.dur = maxf(duration, 1.0)
	e.emit_until = _time + e.dur
	_emitters.append(e)
	_light_assign_t = 0.0


func dust_burst(pos: Vector3, size: float) -> void:
	var s := clampf(size, 0.2, 6.0)
	var lod := _lod(pos)
	for i in _count(8.0 + 6.0 * s, 1.0):
		var d := _rand_flat()
		var v := d * randf_range(2.0, 6.0) * pow(s, 0.6) + Vector3.UP * randf_range(0.5, 2.5)
		emit_smoke(pos + d * randf() * 0.5 * s + Vector3.UP * 0.4 * s, v, _dust(0.65), 4.0 + 2.0 * s,
				1.0 + 0.8 * s, 3.0 + 2.5 * s, 1.5, 0.2, 0.7, 0.0, 0.3, 0.05, 0.35, 0.3, minf(pos.y, 0.0))
	for i in _count(3.0 + 4.0 * s, lod):
		var v := _rand_flat() * randf_range(1.0, 4.0) + Vector3.UP * randf_range(2.0, 6.0)
		emit_debris(pos + Vector3.UP * 0.5 * s, v, _rubble(), randf_range(4.0, 9.0), randf_range(0.05, 0.16), minf(pos.y, 0.0))


## Building collapse: falling concrete, a ground-hugging dust surge and a lingering cloud.
## center: ground center of the footprint; size: (width, height, depth).
func collapse(center: Vector3, size: Vector3) -> void:
	var sx := maxf(size.x, 2.0)
	var sy := maxf(size.y, 2.0)
	var sz := maxf(size.z, 2.0)
	var r := 0.5 * maxf(sx, sz)
	var gy := center.y
	var lod := _lod(center)
	# Falling chunks from the whole volume.
	for i in _count(clampf(30.0 + sx * sz * 0.15, 30.0, 110.0), lod):
		var p := center + Vector3(randf_range(-0.5, 0.5) * sx, randf_range(0.25, 1.0) * sy, randf_range(-0.5, 0.5) * sz)
		var out := Vector3(p.x - center.x, 0.0, p.z - center.z).normalized()
		var v := out * randf_range(0.5, 4.0) + Vector3.UP * randf_range(-2.0, 2.5)
		emit_debris(p, v, _rubble(), randf_range(10.0, 20.0), randf_range(0.15, 0.55), gy, 9.8, 0.2, 5.0)
	# Pyroclastic-style surge rolling out along the ground.
	for i in _count(24.0 + r * 1.2, 1.0):
		var a := randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		var p := center + d * r * randf_range(0.5, 1.0) + Vector3.UP * randf_range(0.5, 3.0)
		emit_smoke(p, d * randf_range(10.0, 20.0) * (0.6 + r / 20.0) + Vector3.UP * randf_range(0.0, 1.5), _dust(0.82),
				randf_range(12.0, 20.0), 5.0 + r * 0.35, 8.0 + r * 0.6, 1.3, 0.15, 0.5, 0.0, 0.3, 0.04, 0.45, 0.15, gy)
	# Dust filling the collapsed volume and slowly rising.
	for i in _count(16.0 + sy * 0.8, 1.0):
		var p := center + Vector3(randf_range(-0.5, 0.5) * sx, randf() * sy, randf_range(-0.5, 0.5) * sz)
		var v := Vector3.UP * randf_range(-3.0, 1.0) + _rand_flat() * 1.5
		emit_smoke(p, v, _dust(0.82).darkened(0.1), randf_range(14.0, 22.0), 5.0 + r * 0.35, 8.0 + r * 0.6 + sy * 0.15,
				0.8, 0.35, 0.6, 0.0, 0.3, 0.05, 0.45, 0.12, gy)
	# Billow rising above the old roof line.
	for i in _count(10.0 + sy * 0.6, 1.0):
		var p := center + Vector3(randf_range(-0.4, 0.4) * sx, randf_range(0.3, 0.8) * sy, randf_range(-0.4, 0.4) * sz)
		emit_smoke(p, Vector3.UP * randf_range(2.0, 5.0) + _rand_flat() * 1.0, _dust(0.75).darkened(0.05), randf_range(14.0, 22.0),
				4.0 + r * 0.2, 9.0 + r * 0.7 + sy * 0.2, 0.7, 0.4, 0.7, 0.0, 0.3, 0.06, 0.45, 0.1, gy)
	# Dust jets blown out of the facades as floors pancake.
	for i in _count(12.0, 1.0):
		var a := randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		var p := center + Vector3(d.x * sx * 0.5, randf_range(0.1, 0.9) * sy, d.z * sz * 0.5)
		emit_smoke(p, d * randf_range(8.0, 14.0) + Vector3.UP * randf_range(-1.0, 1.0), _dust(0.7), randf_range(6.0, 10.0),
				1.5, 5.0 + r * 0.3, 1.6, -0.6, 0.5, 0.0, 0.3, 0.04, 0.4, 0.3, gy)
	var e := FxEmitter.new()
	e.kind = _K_DUST
	e.pos = center
	e.size = Vector3(sx, sy, sz)
	e.t0 = _time
	e.dur = 4.0
	e.emit_until = _time + 4.0
	_emitters.append(e)
	shake.emit(clampf(0.5 + sy * r / 400.0, 0.5, 1.5), center)


## Visual for a flying projectile (Defs.P_*). The caller moves it every frame and must
## call release_projectile() instead of queue_free() so trails can finish.
func projectile(kind: int) -> Node3D:
	var p := FxProjectile.new()
	p.setup(self, kind)
	return p


## Stops a projectile visual. Its smoke trail lives in the shared smoke batcher, so it keeps
## drifting and fades out naturally after the node is gone.
func release_projectile(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	if node is FxProjectile:
		(node as FxProjectile).release()
	else:
		node.queue_free()


## Tactical pause: freezes every particle, light, fire and pending event in place.
func set_paused(p: bool) -> void:
	_paused = p
	var sc := 0.0 if p else 1.0
	for b in [_smoke, _glow, _debris]:
		(b as GPUParticles3D).speed_scale = sc


func is_paused() -> bool:
	return _paused


func set_wind(v: Vector3) -> void:
	wind = Vector3(v.x, 0.0, v.z)
	if _smoke_pm:
		_smoke_pm.set_shader_parameter("wind", wind)


# --- low-level emitters (used by effects and FxProjectile) -----------------------

## One lit smoke/dust puff. Sizes are diameters in meters; buoyancy is upward m/s²
## (negative = falls); heat is the initial incandescent glow that decays over heat_t seconds.
func emit_smoke(pos: Vector3, vel: Vector3, color: Color, life: float, size0: float, size1: float,
		drag := 1.0, buoy := 0.5, wind_f := 1.0, heat := 0.0, heat_t := 0.3, fade_in := 0.06,
		fade_out := 0.35, spin := 0.3, ground_y := 0.0) -> void:
	if _frame_emits >= _FRAME_BUDGET:
		return
	_frame_emits += 1
	var b := Basis(Vector3(drag, buoy, wind_f), Vector3(heat, heat_t, fade_in), Vector3(randf_range(-spin, spin), ground_y, fade_out))
	_smoke.emit_particle(Transform3D(b, pos), vel, color, Color(minf(life, _BATCH_LIFETIME), size0, size1, randf()), _EMIT_ALL)


## One additive glow particle. color.rgb is the HDR tint, color.a the intensity.
## mode: 0 billboard, 1 velocity-stretched spark, 2 tracer, 3 muzzle flash along `extra`.
## tex: 0 flame, 1 round flash. extra: muzzle axis | tracer (dist, streak) | sparks (-, ground_y, -).
func emit_glow(pos: Vector3, vel: Vector3, color: Color, life: float, size0: float, size1: float,
		mode := 0, tex := 0, gravity := 0.0, drag := 0.0, stretch := 0.0, buoy := 0.0, flicker := 0.0,
		extra := Vector3.ZERO) -> void:
	if _frame_emits >= _FRAME_BUDGET:
		return
	_frame_emits += 1
	var b := Basis(Vector3(gravity, drag, stretch), Vector3(buoy, flicker, float(tex)), extra)
	_glow.emit_particle(Transform3D(b, pos), vel, color, Color(minf(life, _BATCH_LIFETIME), size0, size1, float(mode) + randf() * 0.98), _EMIT_ALL)


## One tumbling debris chunk that bounces and settles on ground_y.
func emit_debris(pos: Vector3, vel: Vector3, color: Color, life: float, size: float, ground_y := 0.0,
		gravity := 9.8, bounce := 0.32, spin := 9.0) -> void:
	if _frame_emits >= _FRAME_BUDGET:
		return
	_frame_emits += 1
	var b := Basis(Vector3(gravity, bounce, randf_range(-spin, spin)), Vector3.ZERO, Vector3.ZERO)
	_debris.emit_particle(Transform3D(b, pos), vel, color, Color(minf(life, _BATCH_LIFETIME), size, ground_y, randf()), _EMIT_ALL)


# --- frame update ---------------------------------------------------------------

func _process(delta: float) -> void:
	_frame_emits = 0
	if _paused:
		return
	_time += delta
	_load *= exp(-delta)
	for m in _timed_mats:
		m.set_shader_parameter("fx_time", _time)
	FxProjectile.set_time(_time)
	_tick_pending()
	_tick_emitters(delta)
	_tick_flyers(delta)
	_tick_lights()


func _tick_pending() -> void:
	var i := 0
	while i < _pend_t.size():
		if _pend_t[i] <= _time:
			var fn := _pend_fn[i]
			_pend_t[i] = _pend_t[-1]
			_pend_fn[i] = _pend_fn[-1]
			_pend_t.pop_back()
			_pend_fn.pop_back()
			fn.call()
		else:
			i += 1


func _schedule(delay: float, fn: Callable) -> void:
	_pend_t.append(_time + delay)
	_pend_fn.append(fn)


func _tick_emitters(delta: float) -> void:
	var i := 0
	while i < _emitters.size():
		var e := _emitters[i]
		var age := _time - e.t0
		if age >= e.dur:
			_release_light(e.light)
			_emitters.remove_at(i)
			continue
		match e.kind:
			_K_FIRE:
				_tick_fire(e, age, delta)
			_K_SCREEN:
				if _time < e.emit_until:
					e.acc[0] += delta * _screen_target(e) / _screen_life(e)
					while e.acc[0] >= 1.0:
						e.acc[0] -= 1.0
						_screen_puff(e, false)
			_K_DUST:
				e.acc[0] += delta * 6.0 * (1.0 - age / e.dur) * clampf(e.size.x * e.size.z / 150.0, 0.6, 3.0) * _qm
				while e.acc[0] >= 1.0:
					e.acc[0] -= 1.0
					var p := e.pos + Vector3(randf_range(-0.5, 0.5) * e.size.x, randf() * 0.6 * e.size.y, randf_range(-0.5, 0.5) * e.size.z)
					var r := 0.5 * maxf(e.size.x, e.size.z)
					emit_smoke(p, _rand_flat() * randf_range(1.0, 4.0) + Vector3.UP * randf_range(0.0, 1.5), _dust(0.78),
							randf_range(10.0, 16.0), 3.0 + r * 0.15, 7.0 + r * 0.5, 0.9, 0.3, 0.6, 0.0, 0.3, 0.06, 0.45, 0.12, e.pos.y)
		i += 1


func _tick_fire(e: FxEmitter, age: float, delta: float) -> void:
	var s := e.size.x
	# Ramp up in the first second, die down over the last 20 %.
	var strength := clampf(age / 1.0, 0.15, 1.0) * clampf((e.dur - age) / (e.dur * 0.2), 0.0, 1.0)
	var up := Vector3.UP
	# Flames.
	e.acc[0] += delta * (14.0 + 12.0 * s) * strength * maxf(_qm, 0.5)
	while e.acc[0] >= 1.0:
		e.acc[0] -= 1.0
		var p := e.pos + _rand_flat() * sqrt(randf()) * 0.8 * s + up * randf() * 0.3 * s
		var fs := randf_range(0.8, 1.25) * (0.8 + 1.0 * s)
		emit_glow(p, up * randf_range(1.5, 3.2) * sqrt(s) + _rand_flat() * 0.4, Color(1.0, 1.0, 1.0, randf_range(1.8, 2.8) * strength),
				randf_range(0.55, 1.05), fs, fs * 0.3, 0, 0, 0.0, 1.0, 0.0, 2.5 * sqrt(s), 0.25)
	# Smoke column.
	e.acc[1] += delta * (2.5 + 1.8 * s) * maxf(strength, 0.25) * maxf(_qm, 0.6)
	while e.acc[1] >= 1.0:
		e.acc[1] -= 1.0
		var p := e.pos + _rand_flat() * randf() * 0.5 * s + up * (0.8 + 0.5 * s)
		var shade := randf_range(0.06, 0.13)
		emit_smoke(p, up * randf_range(1.5, 3.0) * sqrt(s) + _rand_flat() * 0.3, Color(shade, shade * 0.95, shade * 0.9, 0.82 * maxf(strength, 0.3)),
				randf_range(10.0, 16.0), 1.0 * s + 0.8, (5.0 * s + 6.0) * randf_range(0.85, 1.2), 0.35, 1.5, 1.0,
				1.6, 0.5, 0.04, 0.35, 0.25, e.pos.y)
	# Embers.
	e.acc[2] += delta * 3.0 * s * strength
	while e.acc[2] >= 1.0:
		e.acc[2] -= 1.0
		emit_glow(e.pos + _rand_flat() * 0.5 * s + up * 0.5 * s, up * randf_range(2.0, 5.0) + _rand_flat() * 1.5, Color(1.0, 0.55, 0.2, 4.0),
				randf_range(1.0, 2.5), 0.05, 0.03, 1, 0, 0.0, 0.6, 0.02, 1.2, 0.5, Vector3(0.0, e.pos.y, 0.0))
	if e.light:
		var t := _time
		var fl := 0.72 + 0.14 * sin(t * 11.0 + e.t0) + 0.09 * sin(t * 23.7 + e.t0 * 3.0) + 0.05 * sin(t * 41.0)
		e.light.node.light_energy = e.light.energy * fl * strength
		e.light.node.position = e.pos + Vector3(0.0, 1.0 + 0.6 * s, 0.0) + Vector3(sin(t * 7.0), 0.0, cos(t * 5.0)) * 0.1 * s


func _tick_flyers(delta: float) -> void:
	var i := 0
	while i < _flyers.size():
		var f := _flyers[i]
		if _time >= f.t_end or f.pos.y < -0.5:
			_flyers.remove_at(i)
			continue
		var prev := f.pos
		f.vel.y -= 9.8 * delta
		f.pos += f.vel * delta
		var seg := f.pos - prev
		var dist := seg.length()
		var fade := clampf((f.t_end - _time) / 0.5, 0.2, 1.0)
		# Fixed spatial spacing so the trail is continuous at any frame rate.
		var d := 0.3 - f.trail
		while d <= dist:
			var p := prev + seg * (d / maxf(dist, 0.0001))
			emit_glow(p, f.vel * 0.02, Color(1.0, 0.6, 0.25, 3.0 * fade), 0.12, 0.3 * f.size, 0.1 * f.size, 1, 0, 0.0, 0.0, 0.03, 0.0, 0.3)
			if randf() < 0.6:
				emit_smoke(p, Vector3.UP * 0.4, _grey(0.16, 0.03, 0.5 * fade), randf_range(2.5, 4.0), 0.45 * f.size, 2.4 * f.size,
						1.2, 0.6, 0.8, 0.0, 0.1, 0.03, 0.3, 0.5, -10.0)
			d += 0.3
		f.trail = dist - (d - 0.3)
		i += 1


# --- smoke screen helpers ----------------------------------------------------------

func _screen_life(e: FxEmitter) -> float:
	return clampf(e.dur * 0.5, 8.0, 20.0)


func _screen_target(e: FxEmitter) -> float:
	var r := e.size.x
	return clampf(0.06 * r * r + 12.0, 14.0, 110.0) * clampf(_qm, 0.7, 1.15)


func _screen_puff(e: FxEmitter, burst: bool) -> void:
	var r := e.size.x
	var d := clampf(r * 0.6, 5.0, 20.0)
	var u := sqrt(randf()) * r * 0.85
	var a := randf() * TAU
	var flat := Vector3(cos(a), 0.0, sin(a))
	var target := e.pos + flat * u + Vector3.UP * (randf_range(0.2, 1.0) * d * 0.65)
	var p := target
	var v := Vector3.UP * randf_range(0.0, 0.4)
	if burst:
		# Start nearer the canisters and billow outward to the target within ~1.5 s.
		p = e.pos + flat * u * 0.5 + Vector3.UP * 0.6
		v = (target - p) * 1.8
	var shade := randf_range(0.8, 0.92)
	emit_smoke(p, v, Color(shade, shade, shade * 0.98, 0.9), _screen_life(e) * randf_range(0.8, 1.15),
			d * 0.55, d * randf_range(0.95, 1.2), 1.8, 0.06, 0.12, 0.0, 0.3, 0.05, 0.55, 0.12, e.pos.y)


# --- impacts -------------------------------------------------------------------------

func _impact(pos: Vector3, kind: String, scale: float) -> void:
	var lod := _lod(pos)
	if lod < 0.4 and scale < 1.0 and randf() < 0.5:
		return
	var gy := minf(pos.y, 0.0) if pos.y < 0.6 else pos.y - 30.0
	var up := Vector3.UP
	match kind:
		"metal", "spark":
			emit_glow(pos, Vector3.ZERO, Color(1.0, 0.85, 0.6, 6.0), 0.05, 0.2 * scale, 0.5 * scale, 0, 1)
			for i in _count(9.0 * scale, lod):
				var d := _rand_unit()
				d.y = absf(d.y) * 0.8 + 0.2
				emit_glow(pos, d * randf_range(4.0, 13.0), Color(1.0, 0.72, 0.35, 5.0), randf_range(0.2, 0.6), 0.035, 0.025,
						1, 0, 9.8, 1.5, 0.03, 0.0, 0.0, Vector3(0.0, minf(pos.y, 0.0), 0.0))
			emit_smoke(pos, up * 0.6, _grey(0.45, 0.05, 0.35), 1.2, 0.2 * scale, 0.9 * scale, 2.0, 0.4, 0.5, 0.0, 0.3, 0.05, 0.3, 0.5, gy)
		"concrete":
			for i in _count(3.0 * scale, 1.0):
				var v := up * randf_range(0.8, 2.5) + _rand_unit() * 1.2
				emit_smoke(pos, v, _dust(0.65).lightened(0.08), randf_range(1.4, 2.4), 0.25 * scale, randf_range(1.0, 1.6) * scale,
						2.4, -0.3, 0.4, 0.0, 0.3, 0.04, 0.3, 0.6, gy)
			for i in _count(4.0 * scale, lod):
				var v := _rand_unit() * randf_range(2.0, 5.0) + up * randf_range(1.0, 4.0)
				emit_debris(pos, v, Color(0.62, 0.6, 0.56), randf_range(1.5, 3.0), randf_range(0.03, 0.07), minf(pos.y, 0.0))
			if randf() < 0.3:
				for i in 3:
					emit_glow(pos, _rand_unit() * randf_range(3.0, 8.0), Color(1.0, 0.75, 0.4, 4.0), randf_range(0.1, 0.3), 0.03, 0.02,
							1, 0, 9.8, 1.0, 0.03, 0.0, 0.0, Vector3(0.0, minf(pos.y, 0.0), 0.0))
		_:
			for i in _count(3.0 * scale, 1.0):
				var v := up * randf_range(1.5, 3.5) + _rand_flat() * randf_range(0.3, 1.5)
				emit_smoke(pos, v, _earth(0.7), randf_range(1.2, 2.0), 0.3 * scale, randf_range(1.0, 1.5) * scale,
						2.2, -0.8, 0.4, 0.0, 0.3, 0.04, 0.3, 0.6, gy)
			for i in _count(3.0 * scale, 1.0):
				var v := up * randf_range(4.0, 7.0) + _rand_flat() * randf_range(0.5, 1.5)
				emit_smoke(pos, v, _earth(0.9).darkened(0.25), 0.7, 0.12 * scale, 0.45 * scale, 0.5, -9.0, 0.0, 0.0, 0.3, 0.02, 0.3, 0.8, gy)
			for i in _count(3.0 * scale, lod):
				var v := up * randf_range(3.0, 6.0) + _rand_flat() * randf_range(0.5, 2.0)
				emit_debris(pos, v, _earth(1.0).darkened(0.3), randf_range(1.5, 3.0), randf_range(0.03, 0.06), minf(pos.y, 0.0))


# --- crater decals -------------------------------------------------------------------

func _crater(pos: Vector3, diameter: float) -> void:
	var d: Decal
	if _decals.size() < MAX_DECALS:
		d = Decal.new()
		d.texture_albedo = FxTextures.crater()
		d.texture_normal = FxTextures.crater_normal()
		d.normal_fade = 0.5
		d.upper_fade = 0.25
		d.lower_fade = 0.25
		d.albedo_mix = 1.0
		d.distance_fade_enabled = true
		d.distance_fade_begin = 600.0
		d.distance_fade_length = 150.0
		d.top_level = true
		add_child(d)
		_decals.append(d)
	else:
		d = _decals[_decal_next]
		_decal_next = (_decal_next + 1) % MAX_DECALS
	var dia := diameter * randf_range(0.85, 1.15)
	d.size = Vector3(dia, 2.5, dia)
	d.modulate = Color(1, 1, 1, clampf(0.55 + diameter * 0.08, 0.6, 1.0))
	d.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), Vector3(pos.x, minf(pos.y, 0.0), pos.z))


# --- light pool ----------------------------------------------------------------------

func _light_cap() -> int:
	return _LIGHT_CAP[_q]


func _new_light() -> FxLight:
	var l := FxLight.new()
	var o := OmniLight3D.new()
	o.shadow_enabled = false
	o.light_specular = 0.3
	o.distance_fade_enabled = true
	o.distance_fade_begin = 260.0
	o.distance_fade_length = 60.0
	o.visible = false
	o.top_level = true
	add_child(o)
	l.node = o
	_lights.append(l)
	return l


func _flash_light(pos: Vector3, color: Color, energy: float, light_range: float, dur: float) -> void:
	var slot: FxLight = null
	for l in _lights:
		if not l.active:
			slot = l
			break
	if slot == null and _lights.size() < _light_cap():
		slot = _new_light()
	if slot == null:
		var best := energy * light_range
		for l in _lights:
			if l.fire != null:
				continue
			var v := l.value(_time)
			if v < best:
				best = v
				slot = l
	if slot == null:
		return
	slot.active = true
	slot.fire = null
	slot.t0 = _time
	slot.dur = maxf(dur, 0.02)
	slot.energy = energy
	slot.node.light_color = color
	slot.node.omni_range = light_range
	slot.node.light_energy = energy
	slot.node.global_position = pos
	slot.node.visible = true


func _release_light(l: FxLight) -> void:
	if l == null:
		return
	l.active = false
	l.fire = null
	l.node.visible = false
	for e in _emitters:
		if e.light == l:
			e.light = null


func _tick_lights() -> void:
	for l in _lights:
		if not l.active or l.fire != null:
			continue
		var x := (_time - l.t0) / l.dur
		if x >= 1.0:
			l.active = false
			l.node.visible = false
		else:
			l.node.light_energy = l.energy * (1.0 - x) * (1.0 - x)
	if _time >= _light_assign_t:
		_light_assign_t = _time + 0.5
		_assign_fire_lights()


## Fires get flickering lights; at most half the pool, nearest to the camera first.
func _assign_fire_lights() -> void:
	var fires: Array[FxEmitter] = []
	for e in _emitters:
		if e.kind == _K_FIRE:
			fires.append(e)
	if fires.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		var cp := cam.global_position
		fires.sort_custom(func(a: FxEmitter, b: FxEmitter) -> bool: return a.pos.distance_squared_to(cp) < b.pos.distance_squared_to(cp))
	var cap := maxi(_light_cap() / 2, 1)
	for i in fires.size():
		var e := fires[i]
		if i >= cap:
			_release_light(e.light)
			continue
		if e.light != null:
			continue
		var slot: FxLight = null
		for l in _lights:
			if not l.active:
				slot = l
				break
		if slot == null and _lights.size() < _light_cap():
			slot = _new_light()
		if slot == null:
			continue
		var s := e.size.x
		slot.active = true
		slot.fire = e
		slot.energy = 2.2 + 1.0 * s
		slot.node.light_color = Color(1.0, 0.55, 0.25)
		slot.node.omni_range = 6.0 + 5.0 * s
		slot.node.global_position = e.pos + Vector3.UP
		slot.node.visible = true
		e.light = slot


# --- setup helpers ---------------------------------------------------------------------

func _on_settings_changed(section: String, key: String) -> void:
	if section != "graphics" or key != "quality":
		return
	_q = clampi(Settings.quality(), 0, 3)
	_qm = _MULT[_q]
	# Changing the amount clears the batcher; acceptable on an explicit settings change.
	if _smoke.amount != _SMOKE_N[_q]:
		_smoke.amount = _SMOKE_N[_q]
		_glow.amount = _GLOW_N[_q]
		_debris.amount = _DEBRIS_N[_q]
	_debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _q >= 3 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	while _lights.size() > _light_cap():
		var l: FxLight = _lights.pop_back()
		_release_light(l)
		l.node.queue_free()


func _make_batch(pm: ShaderMaterial, mesh: Mesh, amount: int, order: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = _BATCH_LIFETIME
	p.emitting = false
	p.fixed_fps = 0
	p.interpolate = false
	p.local_coords = false
	p.draw_order = order
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.visibility_aabb = AABB(Vector3(-4000, -300, -4000), Vector3(8000, 1500, 8000))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.top_level = true
	add_child(p)
	return p


func _process_mat(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	_timed_mats.append(m)
	return m


func _draw_mat(shader: Shader, noise: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("noise_tex", noise)
	_timed_mats.append(m)
	return m


func _quad(mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	return q


## Irregular low-poly chunk (jittered box) for debris.
func _rock_mesh(mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var c: Array[Vector3] = []
	for i in 8:
		var v := Vector3(-0.5 if i & 1 == 0 else 0.5, -0.5 if i & 2 == 0 else 0.5, -0.5 if i & 4 == 0 else 0.5)
		c.append(v * rng.randf_range(0.7, 1.15) + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08)))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = c[f[0]]
		var b: Vector3 = c[f[1]]
		var cc: Vector3 = c[f[2]]
		var d: Vector3 = c[f[3]]
		for v in [a, cc, b, a, d, cc]:
			st.add_vertex(v)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


func _count(base: float, mult: float) -> int:
	return maxi(int(round(base * _qm * mult)), 1)


## Detail multiplier by camera distance (small particles are invisible from far away).
func _lod(pos: Vector3) -> float:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return 1.0
	return clampf(1.3 - cam.global_position.distance_to(pos) / 380.0, 0.3, 1.0)


func _rand_unit() -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	while v.length_squared() > 1.0 or v.length_squared() < 0.0001:
		v = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	return v.normalized()


func _rand_flat() -> Vector3:
	var a := randf() * TAU
	return Vector3(cos(a), 0.0, sin(a))


func _grey(v: float, spread: float, alpha: float) -> Color:
	var g := v + randf_range(-spread, spread)
	return Color(g * 1.04, g, g * 0.94, alpha)


func _earth(alpha: float) -> Color:
	return Color(0.42, 0.35, 0.26).lerp(Color(0.55, 0.47, 0.36), randf()) * Color(1, 1, 1, alpha)


func _dust(alpha: float) -> Color:
	return Color(0.66, 0.61, 0.53).lerp(Color(0.74, 0.7, 0.64), randf()) * Color(1, 1, 1, alpha)


func _rubble() -> Color:
	var t := randf()
	if t < 0.45:
		return Color(0.48, 0.46, 0.43).lerp(Color(0.62, 0.6, 0.56), randf())
	if t < 0.8:
		return Color(0.3, 0.25, 0.2).lerp(Color(0.45, 0.38, 0.3), randf())
	return Color(0.12, 0.11, 0.1)

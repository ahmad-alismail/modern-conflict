extends Node3D
## FX showcase. Args (after `--`):
##   --fx=<scenario>  all | explosion | smoke | fire | collapse | tracers | projectiles | craters | muzzle | impacts
##                    | stress (heavy firefight; prints frame timings once per second)
##   --dist=<m> --pitch=<deg> --yaw=<deg>   camera override
##   --size=<f>       effect size where relevant (explosion, fire)
##   --again=<sec>    explosion scenario: detonate again at this time (tests idle batchers)
##   --tod=<day|dusk|night> --pause=<sec>  (tactical pause at that time, to test freezing)
##   --at=<sec>       capture the screenshot at this scene time (exact, independent of load
##                    hitches) instead of DevHarness' wall-clock delay; pass a large --shot-delay
## Effects fire on a timeline from launch, so screenshots taken at different
## `--shot-delay` values capture different phases.

var fx: Effects
var t := 0.0
var scenario := "all"
var size := 1.0
var _events: Array = []
var _projs: Array = []
var _fire_acc := 0.0
var _pause_at := -1.0
var _snap_at := -1.0
var _snapped := false
var _stat_t := 0.0
var _stat_frames := 0
var _stat_cpu := 0.0
var _stat_gpu := 0.0
var _stat_api := 0.0


func _ready() -> void:
	scenario = DevHarness.arg("fx", "all")
	size = float(DevHarness.arg("size", "1.0"))
	_pause_at = float(DevHarness.arg("pause", "-1"))
	_snap_at = float(DevHarness.arg("at", "-1"))
	var focus := Vector3(0, 3, 0)
	var dist := 60.0
	var pitch := 24.0
	var yaw := 35.0
	match scenario:
		"explosion":
			dist = 32.0
			pitch = 14.0
			_at(0.5, func() -> void: fx.explosion(Vector3.ZERO, size))
			var again := float(DevHarness.arg("again", "-1"))
			if again > 0.0:
				_at(again, func() -> void: fx.explosion(Vector3(4, 0, -3), size))
		"smoke":
			dist = 95.0
			_at(0.3, func() -> void: fx.smoke_cloud(Vector3.ZERO, 30.0, 45.0))
		"fire":
			dist = 45.0
			focus = Vector3(0, 10, 0)
			_add_box(Vector3(0, 0.9, 0), Vector3(6.5, 1.8, 3.2), Color(0.12, 0.11, 0.1))
			_at(0.0, func() -> void: fx.fire(Vector3(0, 1.0, 0), 120.0, size))
		"collapse":
			dist = 80.0
			focus = Vector3(0, 6, 0)
			_add_box(Vector3(-22, 6, 0), Vector3(12, 12, 12), Color(0.75, 0.7, 0.62))
			_at(0.5, func() -> void: fx.collapse(Vector3.ZERO, Vector3(14, 12, 12)))
		"tracers":
			dist = 50.0
			focus = Vector3(0, 1, 0)
		"projectiles":
			dist = 40.0
			focus = Vector3(0, 4, 0)
		"craters":
			dist = 55.0
			pitch = 55.0
			focus = Vector3(0, 0, 0)
			var sizes := [0.5, 1.0, 2.0, 3.0, 1.0, 0.5]
			for i in sizes.size():
				var s: float = sizes[i]
				var p := Vector3((i % 3) * 16.0 - 16.0, 0.0, (i / 3) * 16.0 - 8.0)
				_at(0.2 + i * 0.1, func() -> void: fx.explosion(p, s))
		"muzzle":
			dist = 14.0
			pitch = 10.0
			focus = Vector3(0, 1.5, 0)
		"stress":
			dist = 110.0
			pitch = 32.0
			for i in 6:
				var p := Vector3(randf_range(-40, 40), 0.5, randf_range(-30, 30))
				_at(0.1, func() -> void: fx.fire(p, 300.0, randf_range(0.8, 2.0)))
			_at(0.2, func() -> void: fx.smoke_cloud(Vector3(30, 0, -20), 30.0, 300.0))
			_at(0.2, func() -> void: fx.smoke_cloud(Vector3(-35, 0, 25), 20.0, 300.0))
		"impacts":
			dist = 16.0
			pitch = 25.0
			focus = Vector3(0, 0.5, 0)
		_:
			dist = 85.0
			pitch = 22.0
			focus = Vector3(0, 6, 0)
			_add_box(Vector3(-14, 0.9, 8), Vector3(6.5, 1.8, 3.2), Color(0.12, 0.11, 0.1))
			_add_box(Vector3(30, 7, 22), Vector3(12, 14, 12), Color(0.78, 0.72, 0.62))
			_add_box(Vector3(-30, 5, -24), Vector3(10, 10, 14), Color(0.7, 0.66, 0.6))
			_at(0.1, func() -> void: fx.fire(Vector3(-14, 1.0, 8), 120.0, 1.6))
			_at(0.2, func() -> void: fx.smoke_cloud(Vector3(22, 0, -18), 16.0, 60.0))
			for i in 5:
				var p := Vector3(randf_range(-30, 10), 0, randf_range(-5, 25))
				var s := [0.5, 1.0, 2.0, 1.0, 3.0][i] as float
				_at(0.15 + i * 0.05, func() -> void: fx.explosion(p, s))
			_at(1.5, func() -> void: fx.explosion(Vector3(2, 0, 6), 2.0))
			_at(3.0, func() -> void: fx.collapse(Vector3(30, 0, 22), Vector3(12, 14, 12)))
			_at(4.5, func() -> void: fx.explosion(Vector3(-6, 0, -4), 1.0))
			_at(6.0, func() -> void: fx.explosion(Vector3(10, 0, 12), 3.0))
	dist = float(DevHarness.arg("dist", str(dist)))
	pitch = float(DevHarness.arg("pitch", str(pitch)))
	yaw = float(DevHarness.arg("yaw", str(yaw)))
	PreviewKit.setup(self, focus, dist, pitch, yaw, DevHarness.arg("tod", "day"))
	fx = Effects.new()
	add_child(fx)
	fx.shake.connect(func(s: float, p: Vector3) -> void: print("[preview_fx] shake %.2f at %s" % [s, p]))


func _process(delta: float) -> void:
	if _snap_at >= 0.0 and t >= _snap_at and not _snapped:
		_snapped = true
		await RenderingServer.frame_post_draw
		var path := DevHarness.arg("shot", "user://preview_fx.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("[preview_fx] t=%.2f screenshot -> %s" % [t, path])
		get_tree().quit()
		return
	if _pause_at >= 0.0 and t >= _pause_at and not fx.is_paused():
		fx.set_paused(true)
	if fx.is_paused():
		return
	t += delta
	var i := 0
	while i < _events.size():
		if _events[i][0] <= t:
			var fn: Callable = _events[i][1]
			_events.remove_at(i)
			fn.call()
		else:
			i += 1
	if scenario == "stress":
		_stress(delta)
	match scenario:
		"tracers", "all":
			_firefight(delta)
		"projectiles":
			_projectiles(delta)
		"muzzle":
			# One volley right before the capture time (flashes live only ~3 frames).
			if _snap_at > 0.0 and t >= _snap_at - 0.02 and _fire_acc == 0.0:
				_fire_acc = 1.0
				fx.muzzle_flash(Vector3(-3, 1.5, 2), Vector3(1, 0, -0.3), 0.4)
				fx.muzzle_flash(Vector3(0, 2.2, -1), Vector3(1, 0.02, -0.2), 1.0)
				fx.muzzle_flash(Vector3(3, 2.4, -4), Vector3(1, 0.03, 0.2), 2.5)
		"impacts":
			_fire_acc += delta
			if _fire_acc > 0.3:
				_fire_acc = 0.0
				fx.impact(Vector3(-4, 0, randf_range(-1, 1)), "dirt")
				fx.impact(Vector3(0, 0.8, randf_range(-1, 1)), "concrete")
				fx.impact(Vector3(4, 0.8, randf_range(-1, 1)), "metal")
			if t > 0.5 and _events.is_empty() and _projs.is_empty():
				_at(t + 100.0, func() -> void: pass)
				fx.dust_burst(Vector3(0, 0, -6), 1.5)
				var bomb := fx.projectile(Defs.P_BOMB)
				add_child(bomb)
				_projs.append({"n": bomb, "from": Vector3(-3, 9, -2), "to": Vector3(-3, 0, -2), "t": 0.0, "dur": 1.0, "k": Defs.P_BOMB})
			_projectiles_move(delta)
	if scenario == "all":
		_projectiles(delta)


## ~400 tracers + muzzle flashes per second, ~2 explosions per second, a building
## collapse every 5 s, rockets in flight; prints process CPU, effect API CPU and GPU times.
func _stress(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_fire_acc += delta
	while _fire_acc > 0.0025:
		_fire_acc -= 0.0025
		var a := Vector3(randf_range(-60, 60), 1.2, randf_range(-50, -30))
		var b := Vector3(randf_range(-60, 60), randf_range(0.0, 1.5), randf_range(20, 50))
		if randf() < 0.5:
			var tmp := a
			a = b
			b = tmp
		fx.muzzle_flash(a, (b - a).normalized(), 0.4)
		fx.tracer(a, b, Color(1.0, 0.45, 0.2))
	if randf() < delta * 2.0:
		fx.explosion(Vector3(randf_range(-60, 60), 0, randf_range(-40, 40)), [0.5, 1.0, 1.0, 2.0, 3.0].pick_random())
	if randf() < delta * 0.2:
		fx.collapse(Vector3(randf_range(-50, 50), 0, randf_range(-40, 40)), Vector3(12, 12, 12))
	_stat_api += (Time.get_ticks_usec() - t0) / 1000.0
	_projectiles(delta)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_stat_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_stat_cpu += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_stat_frames += 1
	_stat_t += delta
	if _stat_t >= 1.0:
		var n := float(_stat_frames)
		print("[stress] fps %d | process %.2f ms | fx API %.2f ms | gpu %.2f ms" % [_stat_frames, _stat_cpu / n, _stat_api / n, _stat_gpu / n])
		_stat_t = 0.0
		_stat_frames = 0
		_stat_cpu = 0.0
		_stat_gpu = 0.0
		_stat_api = 0.0


func _firefight(delta: float) -> void:
	_fire_acc += delta
	var rate := 0.025 if scenario == "tracers" else 0.06
	while _fire_acc > rate:
		_fire_acc -= rate
		var a := Vector3(-35 + randf_range(-3, 3), 1.2, 18 + randf_range(-6, 6))
		var b := Vector3(25 + randf_range(-6, 6), randf_range(0.0, 1.5), -10 + randf_range(-8, 8))
		if randf() < 0.5:
			var tmp := a
			a = b
			b = tmp
		fx.muzzle_flash(a, (b - a).normalized(), 0.4)
		if scenario == "tracers" and randf() < 0.5:
			fx.tracer(a + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), b + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), Color(1.0, 0.4, 0.15))
		var col := Color(1.0, 0.45, 0.2) if randf() < 0.7 else Color(0.5, 1.0, 0.3)
		fx.tracer(a, b, col)


func _projectiles(delta: float) -> void:
	_projectiles_spawn(delta)
	_projectiles_move(delta)


func _projectiles_spawn(delta: float) -> void:
	if _projs.size() < 4 and randf() < delta * 2.0:
		var k: int = [Defs.P_ROCKET, Defs.P_MISSILE, Defs.P_SHELL, Defs.P_MORTAR].pick_random()
		var n := fx.projectile(k)
		add_child(n)
		var from := Vector3(-40, randf_range(1.5, 6.0), randf_range(-12, 12))
		var to := Vector3(40, 0.0, randf_range(-12, 12))
		var speed := {Defs.P_ROCKET: 60.0, Defs.P_MISSILE: 45.0, Defs.P_SHELL: 300.0, Defs.P_MORTAR: 30.0}[k] as float
		n.global_position = from
		_projs.append({"n": n, "from": from, "to": to, "t": 0.0, "dur": from.distance_to(to) / speed, "k": k})


func _projectiles_move(delta: float) -> void:
	var i := 0
	while i < _projs.size():
		var p: Dictionary = _projs[i]
		p["t"] = float(p["t"]) + delta
		var f := float(p["t"]) / float(p["dur"])
		var n: Node3D = p["n"]
		var from: Vector3 = p["from"]
		var to: Vector3 = p["to"]
		var pos := from.lerp(to, f)
		if int(p["k"]) == Defs.P_MORTAR:
			pos.y += sin(clampf(f, 0.0, 1.0) * PI) * 25.0
		if f >= 1.0:
			fx.release_projectile(n)
			fx.explosion(to, 0.5 if int(p["k"]) == Defs.P_BOMB else (0.8 if int(p["k"]) == Defs.P_SHELL else 1.0))
			_projs.remove_at(i)
			continue
		n.global_position = pos
		i += 1


func _at(time: float, fn: Callable) -> void:
	_events.append([time, fn])


func _add_box(pos: Vector3, box: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.position = pos
	add_child(mi)

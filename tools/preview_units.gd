extends Node3D
## Vehicle / aircraft showcase. Args:
##   --view=lineup|tanks|heli|drones|light|hac|wrecks|far|perf
##   --focus=x,y,z,dist,pitch,yaw   (camera override)

const GROUND := ["cdf_mbt", "cdf_ifv", "cdf_mrap", "cdf_supply", "pdb_tank", "pdb_technical",
	"pdb_spg", "pdb_mrl", "hac_ugv_gun", "hac_ugv_atgm", "hac_ew", "hac_mast"]
const AIR := ["cdf_heli", "hac_ucav", "hac_wasp", "hac_recon", "hac_fpv"]
const TEAM := [Color(0.25, 0.5, 0.95), Color(0.9, 0.3, 0.2)]

var _moving: Array = []     # UnitModel driven with set_motion
var _squads: Array = []     # [UnitModel, state]
var _t := 0.0


func _ready() -> void:
	var view := DevHarness.arg("view", "lineup")
	var cam := [Vector3(20, 1, 12), 60.0, 30.0, 70.0]
	match view:
		"lineup":
			for i in GROUND.size():
				_add(GROUND[i], Vector3((i % 6) * 9.0, 0, (i / 6) * 12.0), 0.3)
			for i in AIR.size():
				_add(AIR[i], Vector3(i * 9.0 + (0.0 if i else -6.0) + 4.0, 4.5 - i * 0.6, -14.0), 0.3)
			cam = [Vector3(22, 1.5, 1.0), 50.0, 28.0, 90.0]
		"tanks":
			_add("cdf_mbt", Vector3(0, 0, 0), 0.0, 2.0)
			_add("pdb_tank", Vector3(0, 0, 7.5), -0.5, 2.0)
			cam = [Vector3(0.5, 1.2, 3.8), 16.0, 16.0, 40.0]
		"heli":
			var m := _add("cdf_heli", Vector3(0, 3.0, 0), 0.4)
			m.set_turret_yaw(0.3)
			cam = [Vector3(-1.0, 3.0, 0), 15.0, 18.0, 35.0]
		"drones":
			_add("hac_recon", Vector3(0, 1.2, 0), 0.5)
			_add("hac_fpv", Vector3(1.5, 1.0, 0.6), 0.3)
			_add("hac_wasp", Vector3(-1.8, 1.4, 0.3), 0.8)
			cam = [Vector3(-0.2, 1.1, 0.3), 4.2, 20.0, 60.0]
		"light":
			_add("pdb_technical", Vector3(0, 0, 0), 0.6)
			_add("pdb_spg", Vector3(0, 0, 5), 0.6)
			_add("pdb_mrl", Vector3(0, 0, 10), 0.6)
			_add("cdf_mrap", Vector3(-8, 0, 2), 0.3)
			_add("cdf_supply", Vector3(-8, 0, 9), 0.3)
			cam = [Vector3(-3, 1.0, 5), 20.0, 20.0, 50.0]
		"hac":
			_add("hac_ugv_gun", Vector3(0, 0, 0), 0.4)
			_add("hac_ugv_atgm", Vector3(0, 0, 4), 0.4)
			_add("hac_ew", Vector3(-9, 0, 0), 0.3)
			var mast := _add("hac_mast", Vector3(-9, 0, 7), 0.3)
			mast.set_deployed(true)
			cam = [Vector3(-5, 3.0, 4), 24.0, 16.0, 55.0]
		"wrecks":
			for i in GROUND.size():
				var w := UnitModels.create_wreck(GROUND[i])
				w.position = Vector3((i % 6) * 9.0, 0, (i / 6) * 12.0)
				w.rotation.y = 0.3
				add_child(w)
			for i in 3:
				var w := UnitModels.create_wreck(AIR[i])
				w.position = Vector3(i * 12.0, 0, 26.0)
				add_child(w)
			cam = [Vector3(22, 1.0, 13), 46.0, 34.0, 60.0]
		"far":
			_battle()
			cam = [Vector3(0, 0, 0), 80.0, 42.0, 55.0]
		"counts":
			_counts()
		"perf":
			for k in 100:
				var id: String = GROUND[k % GROUND.size()] if k % 3 else ["cdf_rifle", "pdb_militia", "hac_operator", "hac_hound"][k % 4]
				var m := _add(id, Vector3((k % 10) * 12.0 - 60, 0, (k / 10) * 12.0 - 60), randf() * TAU, 3.0)
				if Defs.unit(id)["cat"] == Defs.CAT_INF:
					_squad_layout(m)
					_squads.append([m, k % 3])
			cam = [Vector3(0, 0, 0), 150.0, 45.0, 60.0]
	var f := DevHarness.arg("focus", "")
	if f != "":
		var p := f.split(",")
		cam = [Vector3(float(p[0]), float(p[1]), float(p[2])), float(p[3]), float(p[4]), float(p[5])]
	PreviewKit.setup(self, cam[0], cam[1], cam[2], cam[3])


## Prints MeshInstance3D / surface / vertex counts per unit type (per soldier for squads).
func _counts() -> void:
	for id in Defs.UNITS:
		var m := UnitModels.create(id, TEAM[0])
		var mis := m.find_children("*", "MeshInstance3D", true, false)
		var surf := 0
		var verts := 0
		for mi: MeshInstance3D in mis:
			surf += mi.mesh.get_surface_count()
			for si in mi.mesh.get_surface_count():
				verts += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var n: int = maxi(m.members.size(), 1)
		print("[counts] %-14s mesh_instances=%d surfaces=%d verts=%d  per_member: mi=%.1f surf=%.1f verts=%d" % [id, mis.size(), surf, verts,
			float(mis.size()) / n, float(surf) / n, verts / n])
		m.free()
	var w := 0
	for id in Defs.UNITS:
		w += UnitModels.create_wreck(id).find_children("*", "MeshInstance3D", true, false).size()
	print("[counts] wreck mesh instances total=%d" % w)


func _add(id: String, pos: Vector3, yaw: float, speed: float = 0.0) -> UnitModel:
	var m := UnitModels.create(id, TEAM[_moving.size() % 2])
	m.position = pos
	m.rotation.y = yaw
	add_child(m)
	_moving.append([m, speed])
	return m


func _squad_layout(m: UnitModel) -> void:
	for i in m.members.size():
		m.members[i].position = Vector3(-(i / 3) * 2.6, 0, ((i % 3) - 1) * 2.6)


func _battle() -> void:
	var specs := [["cdf_mbt", Vector3(-14, 0, -6), 0.2], ["cdf_ifv", Vector3(-8, 0, 6), 0.1], ["cdf_rifle", Vector3(-4, 0, -2), 0.0],
		["cdf_rifle", Vector3(-6, 0, 12), 0.0], ["cdf_mrap", Vector3(-20, 0, 8), 0.0], ["pdb_militia", Vector3(14, 0, 0), PI],
		["pdb_technical", Vector3(18, 0, 10), PI + 0.4], ["pdb_tank", Vector3(22, 0, -8), PI], ["pdb_rpg", Vector3(10, 0, -10), PI],
		["hac_hound", Vector3(0, 0, 18), -1.2], ["cdf_heli", Vector3(-10, 14, -14), 0.3], ["hac_wasp", Vector3(6, 10, 8), 1.0]]
	for sp in specs:
		var m := _add(sp[0], sp[1], sp[2], 2.0)
		if Defs.unit(sp[0])["cat"] == Defs.CAT_INF:
			_squad_layout(m)
			_squads.append([m, [0, 1, 2][_squads.size() % 3]])
			m.rotation.y = sp[2]


var _stat_t := 0.0
var _us := 0


func _stats(delta: float, us: int) -> void:
	if not DevHarness.has_arg("stats"):
		return
	if _stat_t == 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_stat_t += delta
	_us += us
	if _stat_t > 2.5 and _stat_t - delta <= 2.5:
		_us = 0
		Engine.set_meta("f0", Engine.get_frames_drawn())
	if _stat_t > 4.5 and _stat_t - delta <= 4.5:
		var frames: int = Engine.get_frames_drawn() - int(Engine.get_meta("f0"))
		var mi := 0
		for n in find_children("*", "MeshInstance3D", true, false):
			mi += 1
		print("[stats] fps=%d draw_calls=%d objects=%d mesh_instances=%d anim_cpu_ms_per_frame=%.2f" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), mi, _us / 1000.0 / maxi(frames, 1)])


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_t += delta
	for e in _moving:
		var m: UnitModel = e[0]
		m.set_motion(e[1], delta)
		if m.turret:
			m.set_turret_yaw(sin(_t * 0.4) * 0.6)
	for s in _squads:
		var m: UnitModel = s[0]
		for i in m.members.size():
			m.set_member_state(i, s[1], delta)
	if int(_t * 10.0) % 15 == 0:
		for e in _moving:
			var m: UnitModel = e[0]
			if m.turret:
				m.fire_recoil(0)
	_stats(delta, Time.get_ticks_usec() - t0)

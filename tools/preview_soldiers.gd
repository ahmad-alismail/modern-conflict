extends Node3D
## Soldier / robot showcase. Args: --view=states|cdf|pdb|hac|hound|close|debug|crowd
##  states: one soldier per pose class (rows) x the five states (columns)
##  cdf/pdb/hac: every squad of that faction (rows) x five states (columns)

const STATES := ["idle", "move", "fire", "prone", "dead"]

var _cells: Array = []   # [UnitModel, state]
var _t := 0.0


func _ready() -> void:
	var view := DevHarness.arg("view", "states")
	if DevHarness.has_arg("debug"):
		UnitShaders.set_debug(true)
	match view:
		"states", "debug":
			_states()
			if view == "debug":
				UnitShaders.set_debug(true)
		"cdf", "pdb", "hac":
			_faction(view)
		"hound":
			for s in 5:
				var m := UnitModels.create("hac_hound", Color(0.25, 0.5, 0.95))
				add_child(m)
				for i in m.members.size():
					m.members[i].visible = i == 0
				m.members[0].position = Vector3(s * 2.0, 0, 0)
				_cells.append([m, s, 1])
			PreviewKit.setup(self, Vector3(4.0, 0.35, 0), 6.5, 14.0, 72.0)
		"close":
			_close()
		"crowd":
			_crowd()


func _states() -> void:
	var ids := ["cdf_rifle", "cdf_mg", "cdf_sniper", "pdb_rpg", "pdb_manpads", "pdb_hmg", "cdf_atgm", "cdf_mortar", "hac_operator"]
	var only := int(DevHarness.arg("row", "-1"))
	for r in ids.size():
		if only >= 0 and r != only:
			continue
		for s in 5:
			var m := UnitModels.create(ids[r], Color(0.25, 0.5, 0.95))
			add_child(m)
			for i in m.members.size():
				m.members[i].visible = i == 0
			m.members[0].position = Vector3(s * 3.0, 0, r * 2.6)
			_cells.append([m, s, 1])
	var f := DevHarness.arg("focus", "")
	if f != "":
		var p := f.split(",")
		PreviewKit.setup(self, Vector3(float(p[0]), 0.7, float(p[1])), float(p[2]) if p.size() > 2 else 6.0,
			float(p[3]) if p.size() > 3 else 12.0, float(p[4]) if p.size() > 4 else 90.0)
	else:
		PreviewKit.setup(self, Vector3(6, 0.5, 10.4), 27.0, 32.0, 90.0)


func _faction(f: String) -> void:
	var ids := []
	for id in Defs.units_of(f):
		if Defs.unit(id)["cat"] == Defs.CAT_INF:
			ids.append(id)
	_squads(ids, 1.3)
	PreviewKit.setup(self, Vector3(14, 0.5, ids.size() * 2.4), 34.0, 38.0, 90.0)


func _squads(ids: Array, spacing: float) -> void:
	for r in ids.size():
		for s in 5:
			var m := UnitModels.create(ids[r], [Color(0.25, 0.5, 0.95), Color(0.9, 0.3, 0.2)][r % 2])
			add_child(m)
			var n := m.members.size()
			for i in n:
				m.members[i].position = Vector3(s * 7.0 + (i % 3) * spacing, 0, r * 4.8 + (i / 3) * spacing)
			_cells.append([m, s, n])


func _close() -> void:
	var specs := [["cdf_rifle", 0, 0, 0], ["cdf_rifle", 2, 1, 1], ["pdb_militia", 0, 0, 2], ["pdb_militia", 1, 2, 3],
		["hac_operator", 2, 0, 4], ["pdb_militia", 0, 3, 5], ["pdb_militia", 0, 5, 6]]
	for sp in specs:
		var m := UnitModels.create(sp[0], Color(0.25, 0.5, 0.95))
		add_child(m)
		for i in m.members.size():
			m.members[i].visible = i == sp[2]
		m.members[sp[2]].position = Vector3(sp[3] * 1.6, 0, 0)
		_cells.append([m, sp[1], m.members.size()])
	var f := DevHarness.arg("focus", "")
	if f != "":
		var p := f.split(",")
		PreviewKit.setup(self, Vector3(float(p[0]), float(p[1]), 0), float(p[2]), 8.0, 70.0)
	else:
		PreviewKit.setup(self, Vector3(4.8, 1.0, 0), 8.0, 10.0, 75.0)


func _crowd() -> void:
	var ids := ["cdf_rifle", "pdb_militia", "hac_operator", "pdb_rpg", "cdf_mg", "hac_hound"]
	var k := 0
	for gx in 10:
		for gz in 8:
			var m := UnitModels.create(ids[k % ids.size()], Color(0.25, 0.5, 0.95))
			add_child(m)
			for i in m.members.size():
				m.members[i].position = Vector3(gx * 9.0 + (i % 3) * 2.5, 0, gz * 9.0 + (i / 3) * 2.5)
			_cells.append([m, k % 5, m.members.size()])
			k += 1
	PreviewKit.setup(self, Vector3(45, 0, 36), 80.0, 40.0, 90.0)


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
	var blend := float(DevHarness.arg("blend", "-1"))
	for c in _cells:
		var m: UnitModel = c[0]
		for i in m.members.size():
			if blend < 0.0:
				m.set_member_state(i, c[1], delta)
			elif _t <= delta * 1.5:
				m.set_member_state(i, 0, 10.0)      # settle in idle first
			elif _t < blend:
				m.set_member_state(i, c[1], delta)  # then freeze mid-transition
	_stats(delta, Time.get_ticks_usec() - t0)

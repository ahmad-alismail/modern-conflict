extends TestBase


static func _empty_map(cells: int = 80) -> MapDef:
	var m := MapDef.new(cells, cells)
	m.spawns = [{"team": 0, "rect": Rect2(4, 4, 20, 20)}, {"team": 1, "rect": Rect2(cells * 2 - 24, cells * 2 - 24, 20, 20)}]
	return m


static func _world(m: MapDef, placed0: Array, placed1: Array, seed_value: int = 1) -> SimWorld:
	var w := SimWorld.new()
	w.setup({"map": m, "seed": seed_value, "mode": "annihilation",
		"teams": [{"faction": "cdf", "placed": placed0, "reinforcements": []}, {"faction": "pdb", "placed": placed1, "reinforcements": []}]})
	return w


func test_city_generator_valid() -> void:
	var t0 := Time.get_ticks_msec()
	var m := CityGenerator.generate(7)
	var gen_ms := Time.get_ticks_msec() - t0
	check(m.buildings.size() > 120, "enough buildings: %d" % m.buildings.size())
	eq(m.objectives.size(), 5, "objectives")
	eq(m.spawns.size(), 2, "spawns")
	check(m.props.size() > 100, "props: %d" % m.props.size())
	t0 = Time.get_ticks_msec()
	var nav := NavGrid.new(m)
	var nav_ms := Time.get_ticks_msec() - t0
	print("    city: %d buildings, %d props, %d walls; gen %d ms, nav %d ms" % [m.buildings.size(), m.props.size(), m.walls.size(), gen_ms, nav_ms])
	var s0 := m.team_spawn(0).get_center()
	var s1 := m.team_spawn(1).get_center()
	for k in [Defs.MOVE_FOOT, Defs.MOVE_WHEELED, Defs.MOVE_TRACKED]:
		var p := nav.find_path(k, nav.nearest_open_point(k, s0), nav.nearest_open_point(k, s1))
		check(p.size() > 0 and p[p.size() - 1].distance_to(nav.nearest_open_point(k, s1)) < 4.0, "spawn-to-spawn path for class %d" % k)
	for o in m.objectives:
		var p := nav.find_path(Defs.MOVE_FOOT, s0, o["p"])
		check(p.size() > 0 and p[p.size() - 1].distance_to(o["p"]) < 10.0, "objective %s reachable on foot" % o["id"])


func test_map_roundtrip() -> void:
	var m := CityGenerator.generate(3)
	var m2 := MapDef.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	eq(m2.buildings.size(), m.buildings.size(), "buildings")
	eq(m2.terrain, m.terrain, "terrain")
	eq(m2.objectives.size(), m.objectives.size(), "objectives")


func test_los_blocked_by_building() -> void:
	var m := _empty_map()
	m.buildings.append({"id": 1, "c": Vector2(80, 80), "size": Vector2(12, 12), "rot": 0.0, "floors": 3, "style": 0, "color": 0, "seed": 1})
	var nav := NavGrid.new(m)
	check(not nav.los(Vector2(60, 80), 1.6, Vector2(100, 80), 1.6), "blocked through building")
	check(nav.los(Vector2(60, 60), 1.6, Vector2(100, 60), 1.6), "clear beside building")
	check(nav.los(Vector2(60, 80), 40.0, Vector2(100, 80), 1.0), "aircraft sees over building")
	check(not nav.is_open(Defs.MOVE_FOOT, Vector2(80, 80)), "building is solid")
	check(not nav.is_open(Defs.MOVE_TRACKED, Vector2(80, 87.5)), "vehicle clearance inflation")
	check(nav.is_open(Defs.MOVE_FOOT, Vector2(80, 87.5)), "foot can hug walls")
	eq(nav.cover_at(Vector2(80, 87.5)), 2, "heavy cover next to building")


func test_penetration_curve() -> void:
	check(Combat.p_pen(680, 720) < 0.35, "120mm vs MBT front is marginal")
	near(Combat.p_pen(680, 160), 1.0, 0.001, "120mm vs side")
	near(Combat.p_pen(3, 10), 0.0, 0.001, "rifle vs robot armor")
	near(Combat.p_pen(20, 6), 1.0, 0.001, "hmg vs technical")


func test_tank_beats_militia_in_open() -> void:
	var m := _empty_map()
	var w := _world(m, [{"def": "cdf_mbt", "p": Vector2(40, 80)}], [{"def": "pdb_militia", "p": Vector2(110, 80), "facing": PI}])
	var tank: SimUnit = w.team_units(0)[0]
	w.issue({"type": "attack_move", "team": 0, "ids": [tank.id], "pos": Vector2(120, 80)})
	for i in 1200:
		w.step()
		if not w.outcome.is_empty():
			break
	var mil: SimUnit = w.by_id[2]
	check(not mil.alive or mil.alive_members() <= 3 or mil.broken, "tank routs militia without AT (members left %d)" % mil.alive_members())
	eq(tank.hp(), tank.max_hp, "rifles cannot hurt the tank")


func test_rpg_team_kills_technical() -> void:
	var m := _empty_map()
	var w := _world(m, [{"def": "cdf_atgm", "p": Vector2(40, 80)}], [{"def": "pdb_technical", "p": Vector2(102, 80), "facing": PI}])
	for i in 1600:
		w.step()
		if not w.outcome.is_empty():
			break
	eq(w.outcome.get("winner", -1), 0, "ATGM team destroys technical at range")
	check(w.wrecks.size() == 1, "wreck left behind")


func test_move_and_garrison() -> void:
	var m := _empty_map()
	m.buildings.append({"id": 1, "c": Vector2(80, 80), "size": Vector2(12, 12), "rot": 0.0, "floors": 2, "style": 0, "color": 0, "seed": 1})
	var w := _world(m, [{"def": "cdf_rifle", "p": Vector2(30, 30)}], [{"def": "pdb_militia", "p": Vector2(150, 150)}])
	var u: SimUnit = w.team_units(0)[0]
	w.issue({"type": "garrison", "team": 0, "ids": [u.id], "bld": 0})
	for i in 600:
		w.step()
		if u.state == SimUnit.State.GARRISONED:
			break
	eq(u.state, SimUnit.State.GARRISONED, "squad entered building")
	w.issue({"type": "move", "team": 0, "ids": [u.id], "pos": Vector2(40, 140)})
	for i in 600:
		w.step()
	check(u.pos.distance_to(Vector2(40, 140)) < 3.0, "squad moved after leaving building (at %s)" % str(u.pos))


func _run_battle(seed_value: int) -> int:
	var m := CityGenerator.generate(11)
	var w := SimWorld.new()
	w.setup({"map": m, "seed": seed_value, "teams": [{"faction": "cdf"}, {"faction": "pdb"}]})
	var center := m.size_m() * 0.5
	for ti in 2:
		var ids := []
		for u in w.team_units(ti):
			ids.append(u.id)
		w.issue({"type": "attack_move", "team": ti, "ids": ids, "pos": center})
	for i in 1200:
		w.step()
	return w.state_hash()


func test_determinism() -> void:
	var t0 := Time.get_ticks_msec()
	var a := _run_battle(5)
	var ms := Time.get_ticks_msec() - t0
	var b := _run_battle(5)
	print("    1200 ticks full-army battle: %d ms" % ms)
	eq(a, b, "same seed + commands => same state")

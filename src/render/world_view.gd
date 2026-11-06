extends Node3D
## Presentation of a SimWorld: builds the static city, keeps a UnitView per unit,
## renders projectiles, wrecks, objectives and converts simulation events into
## effects and sounds. Respects fog of war for the local player's team.
class_name WorldView

const TEAM_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.42, 0.28), Color(0.4, 0.95, 0.5), Color(0.95, 0.85, 0.3)]
const TRACER_COLORS := {0: Color(1.0, 0.85, 0.45), 1: Color(1.0, 0.5, 0.3), 2: Color(0.5, 1.0, 0.6)}

var sim: SimWorld
var player_team := 0          # -1 = spectator (sees everything)
var fx: Effects
var audio: Node
var fog: FogOfWar
var terrain: TerrainBuilder
var unit_views: Dictionary = {}       # id -> UnitView
var building_nodes: Array = []        # index -> Node3D
var objective_nodes: Array = []
var _proj_nodes: Dictionary = {}      # proj id -> Node3D
var _corpses: Node3D
var _units_root: Node3D
var _mine_nodes: Array = []
var _shake_cb: Callable
var _sound_rate: Dictionary = {}
var camera_pos := Vector3.ZERO


func setup(world: SimWorld, p_team: int, p_fx: Effects, p_audio: Node) -> void:
	sim = world
	player_team = p_team
	fx = p_fx
	audio = p_audio
	var t0 := Time.get_ticks_msec()
	terrain = TerrainBuilder.new()
	add_child(terrain)
	terrain.build(sim.map)
	var t1 := Time.get_ticks_msec()
	var broot := Node3D.new()
	broot.name = "Buildings"
	add_child(broot)
	for i in sim.map.buildings.size():
		var b: Dictionary = sim.map.buildings[i]
		var n := BuildingBuilder.build(b)
		n.position = Vector3(b["c"].x, 0, b["c"].y)
		n.rotation.y = -b["rot"]
		broot.add_child(n)
		building_nodes.append(n)
	var t2 := Time.get_ticks_msec()
	add_child(PropBuilder.build_walls(sim.map.walls))
	add_child(PropBuilder.build_props(sim.map.props))
	var t3 := Time.get_ticks_msec()
	print("[WorldView] terrain %d ms, buildings %d ms (%d), props+walls %d ms" % [t1 - t0, t2 - t1, building_nodes.size(), t3 - t2])
	_corpses = Node3D.new()
	_corpses.name = "Corpses"
	add_child(_corpses)
	_units_root = Node3D.new()
	_units_root.name = "Units"
	add_child(_units_root)
	_build_objectives()
	fog = FogOfWar.new()
	add_child(fog)
	fog.setup(sim, player_team)
	for u in sim.units:
		_add_unit_view(u)
	# apply already-damaged state (e.g. loaded games)
	for i in sim.buildings.size():
		_apply_building_state(i)
	for w in sim.wrecks:
		_spawn_wreck_visual(w, false)


func team_color(team: int) -> Color:
	return TEAM_COLORS[team % TEAM_COLORS.size()]


func _add_unit_view(u: SimUnit) -> void:
	if unit_views.has(u.id) or not u.alive:
		return
	var v := UnitView.new()
	_units_root.add_child(v)
	v.setup(u, sim, team_color(u.team), _corpses)
	unit_views[u.id] = v
	if audio:
		v.start_loop(audio)


func _build_objectives() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/render/shaders/objective.gdshader")
	for o in sim.objectives:
		var root := Node3D.new()
		root.position = Vector3(o["p"].x, 0.12, o["p"].y)
		var disc := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.orientation = PlaneMesh.FACE_Y
		q.size = Vector2.ONE * o["r"] * 2.0
		disc.mesh = q
		disc.material_override = mat.duplicate()
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(disc)
		# flag pole with team-colored flag
		var kit := MeshKit.new()
		var pole_mat := MeshKit.mat(Color(0.55, 0.55, 0.55), 0.4, 0.8)
		kit.cylinder(pole_mat, MeshKit.xf_at(Vector3.ZERO), 0.07, 0.05, 9.0, 8, Color.WHITE)
		root.add_child(kit.to_instance())
		var flag := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(2.2, 1.3, 0.04)
		flag.mesh = fm
		flag.position = Vector3(1.15, 8.2, 0)
		var flag_mat := StandardMaterial3D.new()
		flag_mat.albedo_color = Color(0.85, 0.85, 0.85)
		flag_mat.emission_enabled = true
		flag_mat.emission = Color(0.3, 0.3, 0.3)
		flag.material_override = flag_mat
		root.add_child(flag)
		var label := Label3D.new()
		label.text = o["id"]
		label.font_size = 96
		label.pixel_size = 0.03
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 10.5, 0)
		label.outline_size = 24
		label.no_depth_test = true
		label.fixed_size = false
		root.add_child(label)
		add_child(root)
		objective_nodes.append({"root": root, "disc": disc, "flag": flag, "flag_mat": flag_mat})


# ======================================================================= sync =

func sync(alpha: float, delta: float) -> void:
	for u in sim.units:
		if u.alive and not unit_views.has(u.id):
			_add_unit_view(u)
	for id in unit_views:
		var v: UnitView = unit_views[id]
		var u := v.u
		var vis := player_team < 0 or u.team == player_team or (u.vis_mask & (1 << player_team)) != 0
		v.update_view(alpha, delta, vis)
	_sync_projectiles()
	_sync_objectives(delta)
	if fog:
		fog.update(delta)


func _sync_projectiles() -> void:
	var live := {}
	for p in sim.projectiles:
		live[p["id"]] = true
		var n: Node3D = _proj_nodes.get(p["id"])
		if n == null:
			n = fx.projectile(p["kind"])
			add_child(n)
			_proj_nodes[p["id"]] = n
		var pos := Combat.projectile_pos(p)
		var ahead := Combat.projectile_pos(p, 0.02)
		n.position = pos
		if ahead.distance_squared_to(pos) > 0.0001:
			n.look_at(ahead + (ahead - pos) * 0.01, Vector3.UP if absf((ahead - pos).normalized().y) < 0.99 else Vector3.RIGHT)
	for id in _proj_nodes.keys():
		if not live.has(id):
			var n: Node3D = _proj_nodes[id]
			_proj_nodes.erase(id)
			if fx.has_method("release_projectile"):
				fx.release_projectile(n)
			else:
				n.queue_free()


func _sync_objectives(delta: float) -> void:
	for i in sim.objectives.size():
		var o: Dictionary = sim.objectives[i]
		var on: Dictionary = objective_nodes[i]
		var col := Color(0.85, 0.85, 0.85)
		if o["owner"] >= 0:
			col = team_color(o["owner"])
		var prog: float = o["progress"]
		var prog_col := team_color(0) if prog > 0.0 else team_color(1)
		var dm: ShaderMaterial = on["disc"].material_override
		dm.set_shader_parameter("color", col)
		dm.set_shader_parameter("progress", absf(prog))
		dm.set_shader_parameter("progress_color", prog_col)
		dm.set_shader_parameter("contested", 1.0 if o.get("contested", false) else 0.0)
		var fm: StandardMaterial3D = on["flag_mat"]
		fm.albedo_color = col
		fm.emission = col * 0.35
		var flag: Node3D = on["flag"]
		flag.position.y = lerpf(1.2, 8.2, absf(prog) if o["owner"] < 0 else 1.0)
		flag.rotation.y += delta * 0.3


func set_paused(p: bool) -> void:
	fx.set_paused(p)


# ===================================================================== events =

func handle_events(events: Array) -> void:
	for e in events:
		match e["t"]:
			"shot": _on_shot(e)
			"launch": _on_launch(e)
			"impact": _on_impact(e)
			"destroyed": _on_destroyed(e)
			"armor_hit":
				var u: SimUnit = sim.by_id.get(e["u"])
				if u != null and _player_sees_point(u.pos):
					var p := Vector3(u.pos.x, 1.6, u.pos.y)
					fx.impact(p, "spark")
					_sound("metal_hit" if e["pen"] else "ricochet", p, -2.0)
			"bld_damaged":
				BuildingBuilder.apply_damage(building_nodes[e["b"]], 1)
			"bld_collapsed": _collapse_building(e["b"])
			"smoke":
				fx.smoke_cloud(Vector3(e["p"].x, 0, e["p"].y), e["r"], e["dur"])
				_sound("smoke_pop", Vector3(e["p"].x, 1, e["p"].y), -4.0)
			"jet": _spawn_jet(e)
			"mines": _refresh_mines()
			"spawn":
				var u: SimUnit = sim.by_id.get(e["u"])
				if u != null:
					_add_unit_view(u)


func _player_sees_point(p: Vector2) -> bool:
	return fog == null or fog.is_cell_visible(p)


func _unit_visible(u: SimUnit) -> bool:
	return player_team < 0 or u.team == player_team or (u.vis_mask & (1 << player_team)) != 0


func _on_shot(e: Dictionary) -> void:
	var u: SimUnit = sim.by_id.get(e["u"])
	var from: Vector3 = e["from"]
	var to: Vector3 = e["to"]
	var shooter_vis := u != null and _unit_visible(u)
	var target_vis := _player_sees_point(Vector2(to.x, to.z))
	if not shooter_vis and not target_vis:
		return
	var wid: String = e["w"]
	if u != null and not u.is_squad():
		var v: UnitView = unit_views.get(u.id)
		if v != null and v.model.visible:
			var slot := _slot_of(u, wid)
			var mp := v.muzzle_for_slot(slot)
			if mp != Vector3.INF:
				from = mp
			v.model.fire_recoil(slot)
	var dir := (to - from).normalized()
	var heavy := wid in ["hmg", "hmg_team", "autocannon30", "autocannon25", "heli_cannon"]
	if shooter_vis and _near_camera(from, 260.0):
		fx.muzzle_flash(from, dir, 1.6 if heavy else 0.8)
	var tracer_every := 1 if heavy or wid in ["lmg", "gpmg", "coax", "robot_mg"] else 3
	if (e.get("tgt", 0) + int(to.x * 10.0)) % tracer_every == 0:
		var col: Color = TRACER_COLORS.get(u.team if u else 0, Color(1, 0.8, 0.4))
		if wid in ["autocannon30", "autocannon25", "heli_cannon"]:
			col = Color(1.0, 0.6, 0.25)
		fx.tracer(from, to, col)
	elif not e["hit"] and target_vis and _near_camera(to, 160.0):
		fx.impact(to, "dirt" if to.y < 0.3 else "concrete")
	_sound(_weapon_sound(wid), from, 0.0)


func _slot_of(u: SimUnit, wid: String) -> int:
	for i in u.weapons.size():
		if u.weapons[i]["id"] == wid:
			return i
	return 0


func _near_camera(p: Vector3, d: float) -> bool:
	return camera_pos.distance_squared_to(p) < d * d * 4.0


func _weapon_sound(wid: String) -> String:
	match wid:
		"rifle", "smart_rifle": return "rifle"
		"ak": return "ak"
		"lmg", "gpmg", "coax", "robot_mg": return "lmg"
		"hmg", "hmg_team": return "hmg"
		"sniper", "dmr": return "sniper"
		"autocannon30", "autocannon25", "heli_cannon": return "autocannon"
		"cannon120", "cannon100", "recoilless": return "cannon"
		"rpg", "law", "heli_rockets": return "rocket_launch"
		"atgm", "ifv_atgm", "heli_atgm", "manpads", "ugv_missile", "ucav_missile": return "missile_launch"
		"mortar", "mrl": return "mortar_launch"
		"grenade", "drone_grenade": return "grenade"
	return "rifle"


func _sound(name: String, p: Vector3, vol: float) -> void:
	if audio == null:
		return
	audio.play(name, p, vol)


func _on_launch(e: Dictionary) -> void:
	var u: SimUnit = sim.by_id.get(e["u"])
	if u == null:
		return
	var from: Vector3 = e["from"]
	var vis := _unit_visible(u)
	if not u.is_squad():
		var v: UnitView = unit_views.get(u.id)
		if v != null and v.model.visible:
			var slot := _slot_of(u, e["w"])
			v.model.fire_recoil(slot)
			var mp := v.muzzle_for_slot(slot)
			if mp != Vector3.INF:
				from = mp
	if vis:
		var to: Vector3 = e["to"]
		var big: bool = e["kind"] == Defs.P_SHELL
		fx.muzzle_flash(from, (to - from).normalized(), 2.6 if big else 1.2)
		if big:
			fx.dust_burst(Vector3(from.x, 0.2, from.z), 1.0)
	if vis or _player_sees_point(Vector2(e["to"].x, e["to"].z)):
		_sound(_weapon_sound(e["w"]), from, 2.0)


func _on_impact(e: Dictionary) -> void:
	var p: Vector3 = e["p"]
	var splash: float = e["splash"]
	var visible := _player_sees_point(Vector2(p.x, p.z))
	var big: bool = e.get("big", false)
	if splash > 0.0:
		var size := clampf(splash / 4.5, 0.4, 3.2)
		if big:
			size = maxf(size, 1.8)
		fx.explosion(Vector3(p.x, maxf(p.y, 0.0) if p.y < 6.0 else p.y, p.z), size)
		var snd := "explosion_small" if size < 0.9 else ("explosion_medium" if size < 1.9 else "explosion_large")
		_sound(snd, p, 0.0 if visible else -6.0)
		if _shake_cb.is_valid():
			_shake_cb.call(size * 0.5, p)
	else:
		fx.impact(p, "metal" if e.get("veh", false) else "dirt")
		_sound("impact_bullet", p, -6.0)


func set_shake_callback(cb: Callable) -> void:
	_shake_cb = cb


func _on_destroyed(e: Dictionary) -> void:
	var v: UnitView = unit_views.get(e["u"])
	var u: SimUnit = sim.by_id.get(e["u"])
	if v == null or u == null:
		return
	if audio:
		v.stop_loop(audio)
	if u.is_squad():
		# squads leave their fallen in place; the view itself is freed
		for i in v.model.members.size():
			v.model.set_member_state(i, 4, 0.0)
		unit_views.erase(e["u"])
		v.queue_free()
		return
	var p := Vector3(u.pos.x, (u.alt if u.is_air() else 0.0), u.pos.y)
	var size := 1.6 if u.cat == Defs.CAT_VEH else 1.0
	if e.get("expended", false):
		size = 0.8
	fx.explosion(p if not u.is_air() else Vector3(p.x, maxf(p.y, 1.0), p.z), size)
	_sound("explosion_large" if size > 1.2 else "explosion_medium", p, 2.0)
	if _shake_cb.is_valid():
		_shake_cb.call(size * 0.7, p)
	if e.get("wreck", false):
		_spawn_wreck_visual(sim.wrecks[sim.wrecks.size() - 1], true)
	elif u.is_air() and not e.get("expended", false):
		fx.dust_burst(Vector3(u.pos.x, 0.3, u.pos.y), 0.6)
	unit_views.erase(e["u"])
	v.queue_free()


func _spawn_wreck_visual(w: Dictionary, burning: bool) -> void:
	var n := UnitModels.create_wreck(w["def"])
	n.position = Vector3(w["p"].x, 0, w["p"].y)
	n.rotation.y = -w["facing"]
	add_child(n)
	if burning:
		fx.fire(n.position + Vector3(0, 1.2, 0), w.get("burn", 40.0), 1.0)


func _collapse_building(bi: int) -> void:
	var b: Dictionary = sim.map.buildings[bi]
	var old: Node3D = building_nodes[bi]
	var ruin := BuildingBuilder.build_ruin(b)
	ruin.position = old.position
	ruin.rotation = old.rotation
	old.get_parent().add_child(ruin)
	old.queue_free()
	building_nodes[bi] = ruin
	var h := sim.map.building_height(b)
	fx.collapse(Vector3(b["c"].x, h * 0.4, b["c"].y), Vector3(b["size"].x, h, b["size"].y))
	_sound("collapse", Vector3(b["c"].x, 2, b["c"].y), 4.0)
	if _shake_cb.is_valid():
		_shake_cb.call(1.4, Vector3(b["c"].x, 0, b["c"].y))
	terrain.refresh_terrain()


func _apply_building_state(bi: int) -> void:
	var st: int = sim.buildings[bi]["state"]
	if st == 1:
		BuildingBuilder.apply_damage(building_nodes[bi], 1)
	elif st == 2:
		var b: Dictionary = sim.map.buildings[bi]
		var old: Node3D = building_nodes[bi]
		var ruin := BuildingBuilder.build_ruin(b)
		ruin.position = old.position
		ruin.rotation = old.rotation
		old.get_parent().add_child(ruin)
		old.queue_free()
		building_nodes[bi] = ruin


func _spawn_jet(e: Dictionary) -> void:
	var pos: Vector2 = e["pos"]
	var dir: Vector2 = e["dir"]
	var jet := Node3D.new()
	var kit := MeshKit.new()
	var m := MeshKit.mat(Color(0.5, 0.52, 0.55), 0.5, 0.4)
	kit.box(m, MeshKit.xf_at(Vector3.ZERO), Vector3(14.0, 1.6, 1.6), Color.WHITE)
	kit.box(m, MeshKit.xf_at(Vector3(-1.0, 0, 0)), Vector3(4.5, 0.25, 11.0), Color(0.9, 0.9, 0.9))
	kit.box(m, MeshKit.xf_at(Vector3(-6.0, 1.2, 0)), Vector3(2.5, 2.4, 0.2), Color(0.9, 0.9, 0.9))
	jet.add_child(kit.to_instance())
	add_child(jet)
	var eta: float = e["eta"]
	var start := pos - dir * 900.0
	var end := pos + dir * 900.0
	jet.position = Vector3(start.x, 120, start.y)
	jet.look_at(Vector3(end.x, 120, end.y), Vector3.UP)
	jet.rotate_object_local(Vector3.UP, PI * 0.5)
	jet.visible = false
	var tw := create_tween()
	tw.tween_interval(maxf(eta - 3.0, 0.0))
	tw.tween_callback(func():
		jet.visible = true
		_sound("jet_flyby", Vector3(pos.x, 80, pos.y), 4.0))
	tw.tween_property(jet, "position", Vector3(end.x, 140, end.y), 6.0)
	tw.tween_callback(jet.queue_free)


func _refresh_mines() -> void:
	for n in _mine_nodes:
		n.queue_free()
	_mine_nodes.clear()
	if player_team < 0:
		return
	var mm := BoxMesh.new()
	mm.size = Vector3(0.5, 0.12, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.3, 0.2)
	mm.material = mat
	for m in sim.mines:
		if m["team"] != player_team:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mm
		mi.position = Vector3(m["p"].x, 0.06, m["p"].y)
		add_child(mi)
		_mine_nodes.append(mi)

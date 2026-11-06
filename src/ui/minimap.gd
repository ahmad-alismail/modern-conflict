extends Control
## Tactical minimap: pre-rendered city plan, fog of war, objectives, visible units,
## camera frustum. Left click / drag moves the camera; right click orders a move.
class_name Minimap

var session: GameSession
var _base: ImageTexture
var _tex_rect: TextureRect
var _dragging := false
var _redraw_t := 0.0


func setup(s: GameSession) -> void:
	session = s
	custom_minimum_size = Vector2(250, 250)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_base = ImageTexture.create_from_image(render_plan(session.sim.map, session.sim))
	_tex_rect = TextureRect.new()
	_tex_rect.texture = _base
	_tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/ui/minimap.gdshader")
	mat.set_shader_parameter("fog_tex", session.view.fog.texture)
	mat.set_shader_parameter("fog_enabled", 1.0 if session.view.fog.enabled else 0.0)
	_tex_rect.material = mat
	add_child(_tex_rect)


## Static plan image of a map (also used by menus and the editor).
static func render_plan(m: MapDef, world: SimWorld = null) -> Image:
	var img := Image.create(m.width, m.height, false, Image.FORMAT_RGBA8)
	for y in m.height:
		for x in m.width:
			var c := Color(0.42, 0.37, 0.29)
			match m.terrain[y * m.width + x]:
				MapDef.T_ROAD: c = Color(0.2, 0.2, 0.21)
				MapDef.T_PAVED: c = Color(0.36, 0.34, 0.31)
				MapDef.T_GRASS: c = Color(0.25, 0.32, 0.17)
				MapDef.T_FIELD: c = Color(0.38, 0.37, 0.22)
				MapDef.T_RUBBLE: c = Color(0.33, 0.3, 0.27)
				MapDef.T_DIRT: c = Color(0.38, 0.33, 0.26)
				MapDef.T_WATER: c = Color(0.2, 0.3, 0.42)
			img.set_pixel(x, y, c)
	for bi in m.buildings.size():
		var b: Dictionary = m.buildings[bi]
		var collapsed: bool = world != null and world.buildings[bi]["state"] == 2
		var h := m.building_height(b)
		var v := clampf(0.55 + h / 60.0, 0.55, 0.85)
		var col := Color(v, v * 0.95, v * 0.86) if not collapsed else Color(0.33, 0.3, 0.27)
		if b["style"] == MapDef.S_MOSQUE:
			col = Color(0.75, 0.82, 0.8)
		for c in m.footprint_cells(b["c"], b["size"], b["rot"]):
			img.set_pixel(c.x, c.y, col)
	for w in m.walls:
		var a: Vector2 = w["a"]
		var bb: Vector2 = w["b"]
		var steps := int(a.distance_to(bb) / MapDef.CELL) + 1
		for s in steps + 1:
			var c := m.world_to_cell(a.lerp(bb, float(s) / steps))
			if m.in_bounds(c.x, c.y):
				img.set_pixel(c.x, c.y, Color(0.6, 0.55, 0.47))
	return img


func refresh_plan() -> void:
	_base.update(render_plan(session.sim.map, session.sim))


func _process(delta: float) -> void:
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.1
		queue_redraw()


func _to_map(p: Vector2) -> Vector2:
	return p / size * session.sim.map.size_m()


func _to_screen(p: Vector2) -> Vector2:
	return p / session.sim.map.size_m() * size


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.78, 0.68, 0.45, 0.6), false, 1.0)
	var sim := session.sim
	# objectives
	for o in sim.objectives:
		var c := _to_screen(o["p"])
		var col := Color(0.9, 0.9, 0.9) if o["owner"] < 0 else session.view.team_color(o["owner"])
		draw_circle(c, 7.0, Color(0, 0, 0, 0.5))
		draw_arc(c, 7.0, 0, TAU, 20, col, 2.0)
		draw_string(get_theme_default_font(), c + Vector2(-4, 4), o["id"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	# units
	var pt := session.player_team
	for u in sim.units:
		if not u.alive or u.state == SimUnit.State.EMBARKED:
			continue
		var vis: bool = pt < 0 or u.team == pt or (u.vis_mask & (1 << pt)) != 0
		if not vis:
			continue
		var c := _to_screen(u.pos)
		var col := session.view.team_color(u.team)
		if session.input and session.input.selected.has(u.id):
			col = Color(0.5, 1.0, 0.5)
		var r := 2.5 if u.is_squad() else 3.5
		if u.is_air():
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 1), c + Vector2(r + 1, r), c + Vector2(-r - 1, r)]), col)
		elif u.is_squad():
			draw_circle(c, r, col)
		else:
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col)
	# last known enemy positions
	if pt >= 0:
		var lk: Dictionary = sim.teams[pt]["last_known"]
		for id in lk:
			var c := _to_screen(lk[id]["p"])
			draw_arc(c, 3.0, 0, TAU, 8, Color(1, 0.4, 0.3, 0.6), 1.0)
	# camera view trapezoid
	var cam := session.cam
	var vs := get_viewport().get_visible_rect().size
	var pts := PackedVector2Array()
	for sp in [Vector2(0, 0), Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		var gp = cam.ground_point(sp)
		if gp == null:
			var far: Vector3 = cam.camera.project_ray_origin(sp) + cam.camera.project_ray_normal(sp) * 600.0
			gp = Vector3(far.x, 0, far.z)
		pts.append(_to_screen(Vector2(gp.x, gp.z)))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.7), 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_jump(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var units: Array = session.input.own_selected()
			if not units.is_empty():
				var ids := []
				for u in units:
					ids.append(u.id)
				session.issue({"type": "move", "ids": ids, "pos": _to_map(mb.position), "queue": mb.shift_pressed})
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_jump((event as InputEventMouseMotion).position)
		accept_event()


func _jump(p: Vector2) -> void:
	var m := _to_map(p)
	session.cam.look_at_point(Vector3(m.x, 0, m.y))

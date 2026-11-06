extends EditorTool
## Round eraser for buildings, props, walls, objectives and (optionally) roads.

var radius := 4.0
var flags := {"buildings": true, "props": true, "walls": true, "objectives": false, "roads": false}
var _active := false
var _hover := Vector2.ZERO


func _init() -> void:
	id = "eraser"
	title = "Eraser"
	hint = "Click or drag to erase what is under the circle · [ and ] change the size"


func build_options(box: VBoxContainer) -> void:
	box.add_child(EditorUI.row("Radius", EditorUI.slider(1.0, 20.0, 0.5, radius, func(v: float): radius = v, "%.1f m")))
	for k: String in flags:
		box.add_child(EditorUI.check(k.capitalize(), flags[k], func(v: bool): flags[k] = v))
	box.add_child(EditorUI.dim("Erasing roads removes their markings and turns road ground under the circle back to dirt."))


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	_active = true
	_erase(p)


func drag(p: Vector2) -> void:
	if _active:
		_erase(p)


func release(_p: Vector2) -> void:
	_active = false


func hover(p: Vector2) -> void:
	_hover = p


func key(ev: InputEventKey) -> bool:
	if ev.keycode == KEY_BRACKETLEFT or ev.keycode == KEY_BRACKETRIGHT:
		radius = clampf(radius + (1.0 if ev.keycode == KEY_BRACKETRIGHT else -1.0), 1.0, 20.0)
		ed.refresh_tool_options()
		return true
	return false


func _erase(p: Vector2) -> void:
	var m := ed.map
	var before := [m.buildings.size(), m.props.size(), m.walls.size(), m.objectives.size(), m.roads.size()]
	var keep_b := m.buildings.filter(func(b): return not (flags["buildings"] and building_contains(b, p, radius)))
	var keep_p := m.props.filter(func(pr): return not (flags["props"] and (pr["p"] as Vector2).distance_to(p) <= radius))
	var keep_w := m.walls.filter(func(w): return not (flags["walls"] and seg_dist(p, w["a"], w["b"]) <= radius))
	var keep_o := m.objectives.filter(func(o): return not (flags["objectives"] and (o["p"] as Vector2).distance_to(p) <= radius))
	var keep_r := m.roads.filter(func(r): return not (flags["roads"] and seg_dist(p, r["a"], r["b"]) <= radius))
	var terrain_hit := false
	if flags["roads"]:
		var c := m.world_to_cell(p)
		var rc := int(ceil(radius / MapDef.CELL))
		for y in range(c.y - rc, c.y + rc + 1):
			for x in range(c.x - rc, c.x + rc + 1):
				if m.in_bounds(x, y) and m.cell_center(Vector2i(x, y)).distance_to(p) <= radius:
					var t := m.terrain[y * m.width + x]
					if t == MapDef.T_ROAD or t == MapDef.T_PAVED:
						terrain_hit = true
	var after := [keep_b.size(), keep_p.size(), keep_w.size(), keep_o.size(), keep_r.size()]
	if after == before and not terrain_hit:
		return
	mutate()
	if not ed.selection.is_empty():
		ed.select({})
	m.buildings = keep_b
	m.props = keep_p
	m.walls = keep_w
	m.objectives = keep_o
	m.roads = keep_r
	if terrain_hit:
		var c := m.world_to_cell(p)
		var rc := int(ceil(radius / MapDef.CELL))
		for y in range(c.y - rc, c.y + rc + 1):
			for x in range(c.x - rc, c.x + rc + 1):
				if m.in_bounds(x, y) and m.cell_center(Vector2i(x, y)).distance_to(p) <= radius:
					var i := y * m.width + x
					if m.terrain[i] == MapDef.T_ROAD or m.terrain[i] == MapDef.T_PAVED:
						m.terrain[i] = MapDef.T_DIRT
	ed.changed()


func draw(ov: EditorOverlay) -> void:
	ov.ground_circle(_hover, radius, Color(1, 0.45, 0.35), Color(1, 0.4, 0.3, 0.12))

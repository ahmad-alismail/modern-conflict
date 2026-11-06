extends EditorTool
## Round terrain brush (sand, dirt, grass, field, paved, rubble, water, road).

const ORDER := [MapDef.T_SAND, MapDef.T_DIRT, MapDef.T_GRASS, MapDef.T_FIELD, MapDef.T_PAVED, MapDef.T_RUBBLE, MapDef.T_WATER, MapDef.T_ROAD]

var terrain := MapDef.T_GRASS
var radius := 4.0        # cells
var _last: Variant = null
var _hover := Vector2.ZERO


func _init() -> void:
	id = "terrain"
	title = "Terrain"
	hint = "Paint with the left mouse button · [ and ] change the brush size"


func build_options(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	var group := ButtonGroup.new()
	for t: int in ORDER:
		var b := Button.new()
		b.text = TERRAIN_NAMES[t]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = t == terrain
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): terrain = t)
		grid.add_child(b)
	box.add_child(grid)
	box.add_child(EditorUI.row("Brush", EditorUI.slider(1, 16, 1, radius, func(v: float): radius = v, "%.0f")))
	box.add_child(EditorUI.dim("Brush radius in cells (2 m). Water blocks all movement; road and paved ground are fastest for vehicles."))


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	_last = p
	_paint(p)


func drag(p: Vector2) -> void:
	if _last == null:
		return
	var a: Vector2 = _last
	var step := maxf(radius * MapDef.CELL * 0.4, 1.0)
	var n := int(a.distance_to(p) / step)
	for i in range(1, n + 1):
		_paint(a.lerp(p, float(i) / (n + 1)))
	_paint(p)
	_last = p


func release(_p: Vector2) -> void:
	_last = null


func hover(p: Vector2) -> void:
	_hover = p


func key(ev: InputEventKey) -> bool:
	if ev.keycode == KEY_BRACKETLEFT or ev.keycode == KEY_BRACKETRIGHT:
		radius = clampf(radius + (1.0 if ev.keycode == KEY_BRACKETRIGHT else -1.0), 1.0, 16.0)
		ed.refresh_tool_options()
		return true
	return false


func _paint(p: Vector2) -> void:
	var m := ed.map
	var c := m.world_to_cell(p)
	var r := int(ceil(radius))
	var changed := false
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if not m.in_bounds(x, y) or Vector2(x - c.x, y - c.y).length() > radius:
				continue
			if m.terrain[y * m.width + x] != terrain:
				if not changed:
					mutate()
					changed = true
				m.terrain[y * m.width + x] = terrain
	if changed:
		ed.changed()


func draw(ov: EditorOverlay) -> void:
	var col := Color(0.8, 1.0, 0.7) if terrain != MapDef.T_WATER else Color(0.5, 0.8, 1.0)
	ov.ground_circle(_hover, radius * MapDef.CELL, col, Color(col.r, col.g, col.b, 0.1))
	ov.text(_hover, TERRAIN_NAMES[terrain], col, 13, 0.5)

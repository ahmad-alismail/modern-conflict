extends EditorTool
## Click-drag wall segments (compound, low wall, HESCO, sandbags).

var kind := MapDef.W_COMPOUND
var _a: Variant = null
var _b := Vector2.ZERO
var _hover := Vector2.ZERO


func _init() -> void:
	id = "wall"
	title = "Wall"
	hint = "Drag to draw a wall segment · Shift = 45° steps · ends snap to other walls"


func build_options(box: VBoxContainer) -> void:
	box.add_child(EditorUI.row("Kind", EditorUI.option(WALL_NAMES, kind, func(i: int): kind = i)))
	box.add_child(EditorUI.dim("Compound 2.6 m and HESCO block everything. Low walls (1.1 m) and sandbags (0.9 m) give infantry heavy cover and stop vehicles."))


func _snapped(p: Vector2) -> Vector2:
	if _a != null and Input.is_key_pressed(KEY_SHIFT):
		return snap_angle(_a, p)
	var q := snap(p, 0.5)
	var best := 1.5
	for w in ed.map.walls:
		for e: Vector2 in [w["a"], w["b"]]:
			if e.distance_to(p) < best:
				best = e.distance_to(p)
				q = e
	return q


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	_a = _snapped(p)
	_b = _a


func drag(p: Vector2) -> void:
	if _a != null:
		_b = _snapped(p)


func release(_p: Vector2) -> void:
	if _a == null:
		return
	var a: Vector2 = _a
	_a = null
	if a.distance_to(_b) < 1.0:
		return
	mutate()
	ed.map.walls.append({"a": a, "b": _b, "h": MapDef.WALL_HEIGHT[kind], "kind": kind})
	ed.changed()


func hover(p: Vector2) -> void:
	_hover = _snapped(p)


func cancel() -> bool:
	if _a == null:
		return false
	_a = null
	return true


func draw(ov: EditorOverlay) -> void:
	var col := Color(1.0, 0.85, 0.6)
	if _a == null:
		ov.ground_circle(_hover, 0.6, col, col)
		return
	var h: float = MapDef.WALL_HEIGHT[kind]
	ov.ground_line(_a, _b, col, 3.0)
	ov.ground_line(_a, _b, col, 2.0, h)
	ov.text(((_a as Vector2) + _b) * 0.5, "%.1f m" % (_a as Vector2).distance_to(_b), col, 13, h + 1.0)

extends EditorTool
## Click points to draw a road (avenue / street / alley). Each segment paints
## road + sidewalk terrain (MapDef.paint_road) and is added to map.roads so the
## renderer draws markings. Endpoints snap to existing road ends.

const KINDS := [
	{"name": "Avenue", "w": 11.0, "walk": 2.5},
	{"name": "Street", "w": 7.0, "walk": 1.5},
	{"name": "Alley", "w": 4.0, "walk": 0.0},
]

var kind := 1
var clear_obstacles := true
var _pts: Array[Vector2] = []
var _hover := Vector2.ZERO


func _init() -> void:
	id = "road"
	title = "Road"
	hint = "Click to add points · Shift = 45° steps · right click / Enter ends the road"


func build_options(box: VBoxContainer) -> void:
	box.add_child(EditorUI.segmented(KINDS.map(func(k): return k["name"]), kind, func(i: int): kind = i))
	box.add_child(EditorUI.dim("Widths: avenue 11 m + 2.5 m sidewalks, street 7 m + 1.5 m, alley 4 m."))
	box.add_child(EditorUI.check("Clear buildings and props in the way", clear_obstacles, func(v: bool): clear_obstacles = v))


func deactivate() -> void:
	_pts.clear()


func _snapped(p: Vector2) -> Vector2:
	var q := snap(p)
	if not _pts.is_empty() and Input.is_key_pressed(KEY_SHIFT):
		return snap_angle(_pts[_pts.size() - 1], p)
	var best := 6.0
	for r in ed.map.roads:
		for e: Vector2 in [r["a"], r["b"]]:
			if e.distance_to(p) < best:
				best = e.distance_to(p)
				q = e
	return q


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	var q := _snapped(p)
	if not _pts.is_empty():
		var a := _pts[_pts.size() - 1]
		if a.distance_to(q) < 3.0:
			return
		_add_segment(a, q)
	_pts.append(q)


func _add_segment(a: Vector2, b: Vector2) -> void:
	var k: Dictionary = KINDS[kind]
	var w: float = k["w"]
	begin_gesture()
	mutate()
	var m := ed.map
	if clear_obstacles:
		var reach := w * 0.5 + 0.5
		m.buildings = m.buildings.filter(func(bl): return _rect_seg_dist(building_corners(bl), a, b) > reach)
		m.props = m.props.filter(func(pr): return seg_dist(pr["p"], a, b) > reach)
		m.walls = m.walls.filter(func(wl): return _seg_seg_dist(a, b, wl["a"], wl["b"]) > reach)
	m.paint_road(a, b, w, k["walk"])
	m.roads.append({"a": a, "b": b, "w": w, "kind": kind})
	ed.changed()


static func _seg_seg_dist(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var pts := Geometry2D.get_closest_points_between_segments(a, b, c, d)
	return pts[0].distance_to(pts[1])


static func _rect_seg_dist(poly: PackedVector2Array, a: Vector2, b: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		var c := poly[i]
		var d := poly[(i + 1) % poly.size()]
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
			return 0.0
		best = minf(best, _seg_seg_dist(a, b, c, d))
	return best


func hover(p: Vector2) -> void:
	_hover = _snapped(p)


func cancel() -> bool:
	if _pts.is_empty():
		return false
	_pts.clear()
	return true


func key(ev: InputEventKey) -> bool:
	if ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
		return cancel()
	return false


func draw(ov: EditorOverlay) -> void:
	var w: float = KINDS[kind]["w"]
	var col := Color(0.95, 0.95, 0.7)
	for i in range(1, _pts.size()):
		ov.ground_line(_pts[i - 1], _pts[i], col, 2.0)
	if _pts.is_empty():
		ov.ground_circle(_hover, w * 0.5, col, Color(col.r, col.g, col.b, 0.15))
		return
	var a := _pts[_pts.size() - 1]
	var d := (_hover - a)
	if d.length() > 0.5:
		var n := Vector2(-d.y, d.x).normalized() * w * 0.5
		ov.poly(PackedVector2Array([a + n, _hover + n, _hover - n, a - n]), col, Color(col.r, col.g, col.b, 0.18))
		ov.text((a + _hover) * 0.5, "%.0f m" % d.length(), col, 13, 1.0)
	ov.ground_circle(a, 1.0, col, col)

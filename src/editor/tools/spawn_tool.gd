extends EditorTool
## Drag a rectangle to set a team's deployment zone (replaces the old one).

var team := 0
var _a: Variant = null
var _b := Vector2.ZERO


func _init() -> void:
	id = "spawn"
	title = "Spawn zone"
	hint = "Drag a rectangle to set the deployment zone of the chosen team"


func build_options(box: VBoxContainer) -> void:
	box.add_child(EditorUI.segmented(["Blue (team 0)", "Red (team 1)"], team, func(i: int): team = i))
	box.add_child(EditorUI.dim("Units deploy inside this zone. Keep it on open ground near a map edge, with a route to every objective."))
	box.add_child(UITheme.button("Auto-place both zones and objectives", func(): ed.auto_zones(),
		"Pick the two most open opposite edges, carve streets if needed, and place objectives at junctions"))


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	_a = snap(p)
	_b = _a


func drag(p: Vector2) -> void:
	if _a != null:
		_b = snap(p)


func release(_p: Vector2) -> void:
	if _a == null:
		return
	var r := _rect()
	_a = null
	if r.size.x < 10.0 or r.size.y < 10.0:
		Events.notice.emit("Spawn zones need at least 10 × 10 m", "warn")
		return
	mutate()
	var m := ed.map
	m.spawns = m.spawns.filter(func(s): return int(s["team"]) != team)
	m.spawns.append({"team": team, "rect": r})
	m.spawns.sort_custom(func(x, y): return int(x["team"]) < int(y["team"]))
	ed.changed()


func cancel() -> bool:
	if _a == null:
		return false
	_a = null
	return true


func _rect() -> Rect2:
	var a: Vector2 = _a
	return Rect2(Vector2(minf(a.x, _b.x), minf(a.y, _b.y)), (_b - a).abs())


func draw(ov: EditorOverlay) -> void:
	if _a == null:
		return
	var col: Color = EditorOverlay.TEAM_COLORS[team]
	var r := _rect()
	ov.ground_rect(r, col, Color(col.r, col.g, col.b, 0.25), 3.0)
	ov.text(r.get_center(), "%.0f × %.0f m" % [r.size.x, r.size.y], col, 14)

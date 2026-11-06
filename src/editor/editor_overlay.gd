extends Control
## 2D overlay over the editor's 3D view: spawn zones, objectives, selection and
## the active tool's preview, drawn by projecting ground points through the
## camera (crisp at every zoom, no rebuilds). Never takes mouse input.
class_name EditorOverlay

const TEAM_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.42, 0.28)]
const SEL := Color(1.0, 0.86, 0.35)

var ed: MapEditor


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _cam() -> Camera3D:
	return ed.cam.camera if ed and ed.cam else null


## Screen position of a map point at height y, or null when behind the camera.
func to_screen(p: Vector2, y: float = 0.0) -> Variant:
	var cam := _cam()
	var v := Vector3(p.x, y, p.y)
	if cam == null or cam.is_position_behind(v):
		return null
	return cam.unproject_position(v)


func _project(pts: PackedVector2Array, y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		var s = to_screen(p, y)
		if s == null:
			return PackedVector2Array()
		out.append(s)
	return out


func poly(pts: PackedVector2Array, line: Color, fill: Color = Color(0, 0, 0, 0), width: float = 2.0, y: float = 0.05) -> void:
	var sp := _project(pts, y)
	if sp.size() < 2:
		return
	if fill.a > 0.0 and sp.size() >= 3:
		draw_colored_polygon(sp, fill)
	if line.a > 0.0:
		sp.append(sp[0])
		draw_polyline(sp, line, width, true)


func ground_rect(r: Rect2, line: Color, fill: Color = Color(0, 0, 0, 0), width: float = 2.0) -> void:
	poly(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), line, fill, width)


func ground_circle(c: Vector2, r: float, line: Color, fill: Color = Color(0, 0, 0, 0), width: float = 2.0) -> void:
	var pts := PackedVector2Array()
	var n := clampi(int(r * 1.5), 20, 64)
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	poly(pts, line, fill, width)


func ground_line(a: Vector2, b: Vector2, color: Color, width: float = 2.0, y: float = 0.05) -> void:
	var sa = to_screen(a, y)
	var sb = to_screen(b, y)
	if sa != null and sb != null:
		draw_line(sa, sb, color, width, true)


## Rotated footprint outline at height y.
func footprint(c: Vector2, size: Vector2, rot: float, line: Color, fill: Color = Color(0, 0, 0, 0), width: float = 2.0, y: float = 0.05) -> void:
	var h := size * 0.5
	var pts := PackedVector2Array()
	for k: Vector2 in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		pts.append(c + k.rotated(rot))
	poly(pts, line, fill, width, y)


## Wireframe box (building ghost / selection).
func box(c: Vector2, size: Vector2, rot: float, height: float, line: Color, fill: Color = Color(0, 0, 0, 0)) -> void:
	footprint(c, size, rot, line, fill, 2.0, 0.05)
	footprint(c, size, rot, line, Color(0, 0, 0, 0), 2.0, height)
	var h := size * 0.5
	for k: Vector2 in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		var p := c + k.rotated(rot)
		var s0 = to_screen(p, 0.05)
		var s1 = to_screen(p, height)
		if s0 != null and s1 != null:
			draw_line(s0, s1, line, 1.5, true)


func text(p: Vector2, s: String, color: Color, size: int = 14, y: float = 0.0) -> void:
	var sp = to_screen(p, y)
	if sp == null:
		return
	var font := get_theme_default_font()
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at: Vector2 = sp + Vector2(-w * 0.5, size * 0.35)
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.75))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw() -> void:
	if _cam() == null or ed.map == null:
		return
	var m := ed.map
	for s in m.spawns:
		var team: int = clampi(int(s["team"]), 0, 1)
		var col: Color = TEAM_COLORS[team]
		var r: Rect2 = s["rect"]
		ground_rect(r, col, Color(col.r, col.g, col.b, 0.14), 2.5)
		text(r.get_center(), "BLUE DEPLOY" if team == 0 else "RED DEPLOY", col, 15)
	for o in m.objectives:
		var p: Vector2 = o["p"]
		ground_circle(p, o["r"], Color(1, 0.92, 0.5, 0.95), Color(1, 0.9, 0.4, 0.08), 2.0)
		ground_circle(p, 1.2, Color(1, 0.92, 0.5), Color(1, 0.92, 0.5, 0.9), 1.0)
		text(p, "%s  %s" % [o["id"], o["name"]], Color(1, 0.94, 0.7), 14, 3.0)
	_draw_selection(m)
	if ed.tool:
		ed.tool.draw(self)


func _draw_selection(m: MapDef) -> void:
	var sel: Dictionary = ed.selection
	if sel.is_empty():
		return
	var i: int = sel["i"]
	match sel["kind"]:
		"building":
			var b: Dictionary = m.buildings[i]
			box(b["c"], b["size"] + Vector2(0.6, 0.6), b["rot"], m.building_height(b) + 0.5, SEL, Color(1, 0.86, 0.35, 0.12))
		"prop":
			var pr: Dictionary = m.props[i]
			var spec: Dictionary = MapDef.PROPS.get(pr["kind"], {"dims": Vector2.ONE})
			footprint(pr["p"], spec["dims"] * float(pr["s"]) + Vector2(0.8, 0.8), pr["rot"], SEL, Color(1, 0.86, 0.35, 0.2))
		"wall":
			var w: Dictionary = m.walls[i]
			ground_line(w["a"], w["b"], SEL, 5.0, float(w["h"]))
			ground_line(w["a"], w["b"], SEL, 3.0)
		"objective":
			var o: Dictionary = m.objectives[i]
			ground_circle(o["p"], o["r"], SEL, Color(1, 0.86, 0.35, 0.12), 3.5)
		"spawn":
			ground_rect(m.spawns[i]["rect"], SEL, Color(0, 0, 0, 0), 4.0)

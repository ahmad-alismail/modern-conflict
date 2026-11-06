extends RefCounted
## Base class of map editor tools (strategy pattern). The editor forwards mouse
## input already projected onto the ground (map meters) plus keys and wheel;
## tools mutate `ed.map` after `mutate()` (one undo snapshot per gesture) and
## call `ed.changed()`. Tools draw previews through the EditorOverlay.
class_name EditorTool

const STYLE_NAMES := ["Old quarter", "Apartment", "Shop / mixed", "Villa", "Mosque", "Industrial", "Unfinished", "Tower"]
const WALL_NAMES := ["Compound", "Low wall", "HESCO", "Sandbags"]
const TERRAIN_NAMES := ["Sand", "Dirt", "Grass", "Road", "Paved", "Water", "Field", "Rubble"]

var ed: MapEditor
var id := ""
var title := ""
var hint := ""
var _snapshotted := false


func setup(editor: MapEditor) -> EditorTool:
	ed = editor
	return self


# ---------------------------------------------------------------- overrides --

func activate() -> void:
	pass


func deactivate() -> void:
	pass


## Fill the tool-options panel.
func build_options(_box: VBoxContainer) -> void:
	pass


func press(_p: Vector2, _ev: InputEventMouseButton) -> void:
	pass


func drag(_p: Vector2) -> void:
	pass


func release(_p: Vector2) -> void:
	pass


func hover(_p: Vector2) -> void:
	pass


## Right click / Esc. Return true if something was cancelled.
func cancel() -> bool:
	return false


func key(_ev: InputEventKey) -> bool:
	return false


## Mouse wheel over the 3D view (dir = -1 up / +1 down). Return true to consume.
func wheel(_dir: float) -> bool:
	return false


## True while Q/E should rotate something instead of the camera.
func wants_qe() -> bool:
	return false


func draw(_ov: EditorOverlay) -> void:
	pass


func selection_changed() -> void:
	pass


# ------------------------------------------------------------------ helpers --

## Called by the editor when a mouse gesture starts.
func begin_gesture() -> void:
	_snapshotted = false


## Take the undo snapshot for this gesture right before its first change.
func mutate() -> void:
	if not _snapshotted:
		ed.begin_edit()
		_snapshotted = true


static func snap(p: Vector2, step: float = 1.0) -> Vector2:
	return Vector2(snappedf(p.x, step), snappedf(p.y, step))


## Constrain b to 45-degree steps around a.
static func snap_angle(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var ang := snappedf(d.angle(), PI / 4.0)
	return a + Vector2(cos(ang), sin(ang)) * d.length()


static func building_corners(b: Dictionary, grow: float = 0.0) -> PackedVector2Array:
	var c: Vector2 = b["c"]
	var h: Vector2 = b["size"] * 0.5 + Vector2(grow, grow)
	var rot: float = b["rot"]
	var out := PackedVector2Array()
	for k: Vector2 in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		out.append(c + k.rotated(rot))
	return out


static func building_contains(b: Dictionary, p: Vector2, grow: float = 0.0) -> bool:
	var local: Vector2 = (p - b["c"]).rotated(-float(b["rot"]))
	var h: Vector2 = b["size"] * 0.5 + Vector2(grow, grow)
	return absf(local.x) <= h.x and absf(local.y) <= h.y


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)


static func prop_contains(pr: Dictionary, p: Vector2, grow: float) -> bool:
	var spec: Dictionary = MapDef.PROPS.get(pr["kind"], {"dims": Vector2.ONE})
	var dims: Vector2 = spec["dims"] * float(pr["s"])
	var local: Vector2 = (p - pr["p"]).rotated(-float(pr["rot"]))
	return absf(local.x) <= dims.x * 0.5 + grow and absf(local.y) <= dims.y * 0.5 + grow


## Topmost object under p: {kind: objective|prop|wall|building|spawn, i} or {}.
static func pick(m: MapDef, p: Vector2) -> Dictionary:
	for i in m.objectives.size():
		if (m.objectives[i]["p"] as Vector2).distance_to(p) < 5.0:
			return {"kind": "objective", "i": i}
	for i in range(m.props.size() - 1, -1, -1):
		if prop_contains(m.props[i], p, 0.6):
			return {"kind": "prop", "i": i}
	for i in range(m.walls.size() - 1, -1, -1):
		if seg_dist(p, m.walls[i]["a"], m.walls[i]["b"]) < 1.0:
			return {"kind": "wall", "i": i}
	for i in range(m.buildings.size() - 1, -1, -1):
		if building_contains(m.buildings[i], p):
			return {"kind": "building", "i": i}
	for i in m.objectives.size():
		if (m.objectives[i]["p"] as Vector2).distance_to(p) < float(m.objectives[i]["r"]):
			return {"kind": "objective", "i": i}
	for i in m.spawns.size():
		if (m.spawns[i]["rect"] as Rect2).has_point(p):
			return {"kind": "spawn", "i": i}
	return {}


static func next_building_id(m: MapDef) -> int:
	var id := 0
	for b in m.buildings:
		id = maxi(id, int(b["id"]))
	return id + 1


## Property fields of the current selection (shared by Select and Objective tools).
func selection_fields(box: VBoxContainer) -> void:
	var sel: Dictionary = ed.selection
	if sel.is_empty():
		box.add_child(EditorUI.dim("Nothing selected. Click an object in the view."))
		return
	var kind: String = sel["kind"]
	var i: int = sel["i"]
	var m := ed.map
	var key := "%s%d:" % [kind, i]
	match kind:
		"building":
			var b: Dictionary = m.buildings[i]
			box.add_child(EditorUI.header("BUILDING #%d" % int(b["id"])))
			box.add_child(EditorUI.row("Style", EditorUI.option(STYLE_NAMES, b["style"], func(v: int):
				_set_field(key + "style", b, "style", v))))
			box.add_child(EditorUI.row("Floors", EditorUI.spin(1, 14, b["floors"], func(v: float):
				_set_field(key + "floors", b, "floors", int(v)))))
			box.add_child(EditorUI.row("Color", EditorUI.option(range(8).map(func(c): return "Tint %d" % (c + 1)), b["color"], func(v: int):
				_set_field(key + "color", b, "color", v))))
			var sz: Vector2 = b["size"]
			box.add_child(EditorUI.row("Width", EditorUI.spin(4, 120, sz.x, func(v: float):
				_set_field(key + "sx", b, "size", Vector2(v, (b["size"] as Vector2).y)), 0.5)))
			box.add_child(EditorUI.row("Depth", EditorUI.spin(4, 120, sz.y, func(v: float):
				_set_field(key + "sy", b, "size", Vector2((b["size"] as Vector2).x, v)), 0.5)))
			box.add_child(EditorUI.row("Rotation", EditorUI.spin(-180, 180, roundf(rad_to_deg(b["rot"])), func(v: float):
				_set_field(key + "rot", b, "rot", deg_to_rad(v)))))
			box.add_child(UITheme.button("New variation", func(): _set_field("", b, "seed", randi() % (1 << 30) + 1),
				"Same footprint, different facade details"))
		"prop":
			var pr: Dictionary = m.props[i]
			var kinds := MapDef.PROPS.keys()
			box.add_child(EditorUI.header("PROP"))
			box.add_child(EditorUI.row("Kind", EditorUI.option(kinds, kinds.find(pr["kind"]), func(v: int):
				_set_field(key + "kind", pr, "kind", kinds[v]))))
			box.add_child(EditorUI.row("Scale", EditorUI.slider(0.5, 2.0, 0.05, pr["s"], func(v: float):
				_set_field(key + "s", pr, "s", v))))
			box.add_child(EditorUI.row("Rotation", EditorUI.spin(-180, 180, roundf(rad_to_deg(pr["rot"])), func(v: float):
				_set_field(key + "rot", pr, "rot", deg_to_rad(v)))))
		"wall":
			var w: Dictionary = m.walls[i]
			box.add_child(EditorUI.header("WALL"))
			box.add_child(EditorUI.row("Kind", EditorUI.option(WALL_NAMES, w["kind"], func(v: int):
				ed.begin_edit(key + "kind")
				w["kind"] = v
				w["h"] = MapDef.WALL_HEIGHT[v]
				ed.changed())))
		"objective":
			var o: Dictionary = m.objectives[i]
			box.add_child(EditorUI.header("OBJECTIVE"))
			box.add_child(EditorUI.row("ID", EditorUI.line_edit(o["id"], func(t: String):
				_set_field(key + "id", o, "id", t.strip_edges().substr(0, 3)))))
			box.add_child(EditorUI.row("Name", EditorUI.line_edit(o["name"], func(t: String):
				_set_field(key + "name", o, "name", t))))
			box.add_child(EditorUI.row("Radius", EditorUI.slider(6.0, 40.0, 1.0, o["r"], func(v: float):
				_set_field(key + "r", o, "r", v), "%.0f m")))
		"spawn":
			var s: Dictionary = m.spawns[i]
			var r: Rect2 = s["rect"]
			box.add_child(EditorUI.header("SPAWN ZONE — %s" % ("BLUE (team 0)" if s["team"] == 0 else "RED (team 1)")))
			box.add_child(EditorUI.dim("%.0f × %.0f m. Drag to move; use the Spawn tool to redraw." % [r.size.x, r.size.y]))
	var del := UITheme.button("Delete", func(): ed.delete_selection(), "Delete (Del)")
	del.add_theme_color_override("font_color", UITheme.ALERT)
	box.add_child(del)


func _set_field(coalesce: String, d: Dictionary, field: String, value: Variant) -> void:
	if d.get(field) == value:
		return
	ed.begin_edit(coalesce)
	d[field] = value
	ed.changed()

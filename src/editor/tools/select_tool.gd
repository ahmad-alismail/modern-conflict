extends EditorTool
## Select, move (drag), rotate (Q/E) and delete buildings, props, walls,
## objectives and spawn zones; the options panel edits the selection.

var _box: VBoxContainer
var _from := Vector2.ZERO
var _orig: Variant = null
var _dragging := false
var _hover := {}


func _init() -> void:
	id = "select"
	title = "Select / Move"
	hint = "Click to select · drag to move · Q/E rotate · Del delete · Esc deselect"


func build_options(box: VBoxContainer) -> void:
	_box = box
	selection_changed()


func selection_changed() -> void:
	if _box == null or not is_instance_valid(_box):
		return
	for c in _box.get_children():
		c.queue_free()
	selection_fields(_box)


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	var hit := pick(ed.map, p)
	ed.select(hit)
	_dragging = not hit.is_empty()
	_from = p
	_orig = _position_of(hit)


func drag(p: Vector2) -> void:
	if not _dragging or ed.selection.is_empty():
		return
	var d := snap(p - _from, 0.5)
	if d == Vector2.ZERO and not _snapshotted:
		return
	mutate()
	var sel: Dictionary = ed.selection
	var i: int = sel["i"]
	var m := ed.map
	match sel["kind"]:
		"building": m.buildings[i]["c"] = (_orig as Vector2) + d
		"prop": m.props[i]["p"] = (_orig as Vector2) + d
		"objective": m.objectives[i]["p"] = (_orig as Vector2) + d
		"wall":
			m.walls[i]["a"] = _orig[0] + d
			m.walls[i]["b"] = _orig[1] + d
		"spawn":
			var r: Rect2 = _orig
			m.spawns[i]["rect"] = Rect2(r.position + d, r.size)
	ed.changed()


func release(_p: Vector2) -> void:
	_dragging = false


func hover(p: Vector2) -> void:
	_hover = pick(ed.map, p)


func cancel() -> bool:
	if ed.selection.is_empty():
		return false
	ed.select({})
	return true


func wants_qe() -> bool:
	return not ed.selection.is_empty() and ed.selection["kind"] in ["building", "prop"]


func key(ev: InputEventKey) -> bool:
	if ev.keycode == KEY_DELETE or ev.keycode == KEY_BACKSPACE:
		ed.delete_selection()
		return true
	if (ev.keycode == KEY_Q or ev.keycode == KEY_E) and wants_qe():
		var step := deg_to_rad(15.0 if not ev.shift_pressed else 90.0) * (1.0 if ev.keycode == KEY_E else -1.0)
		var sel: Dictionary = ed.selection
		var d: Dictionary = ed.map.buildings[sel["i"]] if sel["kind"] == "building" else ed.map.props[sel["i"]]
		ed.begin_edit("rotate%s%d" % [sel["kind"], sel["i"]])
		d["rot"] = wrapf(float(d["rot"]) + step, -PI, PI)
		ed.changed()
		selection_changed()
		return true
	return false


func _position_of(sel: Dictionary) -> Variant:
	if sel.is_empty():
		return null
	var i: int = sel["i"]
	var m := ed.map
	match sel["kind"]:
		"building": return m.buildings[i]["c"]
		"prop": return m.props[i]["p"]
		"objective": return m.objectives[i]["p"]
		"wall": return [m.walls[i]["a"], m.walls[i]["b"]]
		"spawn": return m.spawns[i]["rect"]
	return null


func draw(ov: EditorOverlay) -> void:
	if _hover.is_empty() or _hover == ed.selection:
		return
	var i: int = _hover["i"]
	var m := ed.map
	var col := Color(1, 1, 1, 0.6)
	match _hover["kind"]:
		"building":
			var b: Dictionary = m.buildings[i]
			ov.footprint(b["c"], b["size"] + Vector2(0.4, 0.4), b["rot"], col)
		"prop":
			var pr: Dictionary = m.props[i]
			ov.ground_circle(pr["p"], 1.2, col)
		"wall":
			ov.ground_line(m.walls[i]["a"], m.walls[i]["b"], col, 3.0)
		"objective":
			ov.ground_circle(m.objectives[i]["p"], m.objectives[i]["r"], col)
		"spawn":
			ov.ground_rect(m.spawns[i]["rect"], col)

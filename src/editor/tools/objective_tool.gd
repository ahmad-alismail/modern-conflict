extends EditorTool
## Click to place an objective, click-drag an existing one to move it; the
## panel edits the selected objective's id, name and radius.

const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var _box: VBoxContainer
var _drag := -1
var _hover := Vector2.ZERO


func _init() -> void:
	id = "objective"
	title = "Objective"
	hint = "Click to place an objective · drag one to move it · Del deletes the selected one"


func build_options(box: VBoxContainer) -> void:
	_box = box
	selection_changed()


func selection_changed() -> void:
	if _box == null or not is_instance_valid(_box):
		return
	for c in _box.get_children():
		c.queue_free()
	if not ed.selection.is_empty() and ed.selection["kind"] == "objective":
		selection_fields(_box)
	else:
		_box.add_child(EditorUI.dim("Objectives are captured by holding them; holding more than the enemy drains their tickets. 3–5 well-spread objectives at junctions play best."))


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	var m := ed.map
	for i in m.objectives.size():
		if (m.objectives[i]["p"] as Vector2).distance_to(p) < maxf(5.0, float(m.objectives[i]["r"]) * 0.4):
			_drag = i
			ed.select({"kind": "objective", "i": i})
			return
	mutate()
	var used := {}
	for o in m.objectives:
		used[o["id"]] = true
	var oid := "X"
	for ch in LETTERS:
		if not used.has(ch):
			oid = ch
			break
	m.objectives.append({"id": oid, "name": "Objective %s" % oid, "p": snap(p, 0.5), "r": 16.0})
	ed.changed()
	ed.select({"kind": "objective", "i": m.objectives.size() - 1})


func drag(p: Vector2) -> void:
	if _drag < 0 or _drag >= ed.map.objectives.size():
		return
	mutate()
	ed.map.objectives[_drag]["p"] = snap(p, 0.5)
	ed.changed()


func release(_p: Vector2) -> void:
	_drag = -1


func hover(p: Vector2) -> void:
	_hover = p


func key(ev: InputEventKey) -> bool:
	if (ev.keycode == KEY_DELETE or ev.keycode == KEY_BACKSPACE) and not ed.selection.is_empty():
		ed.delete_selection()
		return true
	return false


func cancel() -> bool:
	if ed.selection.is_empty():
		return false
	ed.select({})
	return true


func draw(ov: EditorOverlay) -> void:
	if _drag < 0:
		ov.ground_circle(_hover, 16.0, Color(1, 0.92, 0.5, 0.5))

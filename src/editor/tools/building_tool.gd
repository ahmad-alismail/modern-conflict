extends EditorTool
## Drag a rectangle to place a building (style, floors, color options).

var style := MapDef.S_APARTMENT
var floors := 4
var color := -1          # -1 = random tint
var _a: Variant = null
var _b := Vector2.ZERO
var _hover := Vector2.ZERO


func _init() -> void:
	id = "building"
	title = "Building"
	hint = "Drag a rectangle to place a building · Shift = square · right click cancels"


func build_options(box: VBoxContainer) -> void:
	box.add_child(EditorUI.row("Style", EditorUI.option(STYLE_NAMES, style, func(v: int):
		style = v
		if v == MapDef.S_MOSQUE:
			floors = 3)))
	box.add_child(EditorUI.row("Floors", EditorUI.spin(1, 14, floors, func(v: float): floors = int(v))))
	var tints := ["Random"]
	for i in 8:
		tints.append("Tint %d" % (i + 1))
	box.add_child(EditorUI.row("Color", EditorUI.option(tints, color + 1, func(v: int): color = v - 1)))
	box.add_child(EditorUI.dim("Each building gets its own facade variation. Select it afterwards to fine-tune size, rotation or style."))


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	_a = snap(p)
	_b = _a


func drag(p: Vector2) -> void:
	if _a == null:
		return
	_b = snap(p)
	if Input.is_key_pressed(KEY_SHIFT):
		var d := _b - (_a as Vector2)
		var s := maxf(absf(d.x), absf(d.y))
		_b = (_a as Vector2) + Vector2(signf(d.x) if d.x != 0.0 else 1.0, signf(d.y) if d.y != 0.0 else 1.0) * s


func release(_p: Vector2) -> void:
	if _a == null:
		return
	var r := _rect()
	_a = null
	if r.size.x < 4.0 or r.size.y < 4.0:
		Events.notice.emit("Buildings need at least 4 × 4 m", "warn")
		return
	mutate()
	var b := {"id": next_building_id(ed.map), "c": r.get_center(), "size": r.size, "rot": 0.0, "floors": floors,
		"style": style, "color": color if color >= 0 else randi() % 8, "seed": randi() % (1 << 30) + 1}
	ed.map.buildings.append(b)
	ed.changed()


func hover(p: Vector2) -> void:
	_hover = snap(p)


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
		ov.ground_circle(_hover, 0.8, Color(1, 1, 1, 0.8))
		return
	var r := _rect()
	var h := floors * (4.5 if style == MapDef.S_INDUSTRIAL else MapDef.FLOOR_H) + 1.0
	var ok := r.size.x >= 4.0 and r.size.y >= 4.0
	var col := Color(0.55, 0.9, 1.0) if ok else UITheme.ALERT
	ov.box(r.get_center(), r.size, 0.0, h, col, Color(col.r, col.g, col.b, 0.15))
	ov.text(r.get_center(), "%.0f × %.0f m · %d fl" % [r.size.x, r.size.y, floors], col, 14, h + 2.0)

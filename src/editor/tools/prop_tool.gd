extends EditorTool
## Place props (MapDef.PROPS kinds). Wheel or Q/E rotate, drag scatters a line.

var kind := "tree"
var rot := 0.0
var scale_f := 1.0
var random_rot := false
var _last: Variant = null
var _hover := Vector2.ZERO


func _init() -> void:
	id = "prop"
	title = "Prop"
	hint = "Click to place · drag to scatter · wheel or Q/E rotate (Ctrl+wheel zooms)"


func build_options(box: VBoxContainer) -> void:
	var kinds := MapDef.PROPS.keys()
	box.add_child(EditorUI.row("Kind", EditorUI.option(kinds, kinds.find(kind), func(i: int):
		kind = kinds[i]
		ed.refresh_tool_options())))
	box.add_child(EditorUI.row("Scale", EditorUI.slider(0.5, 2.0, 0.05, scale_f, func(v: float): scale_f = v)))
	box.add_child(EditorUI.check("Random rotation", random_rot, func(v: bool): random_rot = v))
	var spec: Dictionary = MapDef.PROPS[kind]
	box.add_child(EditorUI.dim("Vehicles, containers and barriers block vehicles; trees and bushes give light cover."))
	if int(spec["block"]) & 1:
		box.add_child(EditorUI.dim("This prop also blocks infantry."))


func wants_qe() -> bool:
	return true


func wheel(dir: float) -> bool:
	if Input.is_key_pressed(KEY_CTRL):
		return false
	rot = wrapf(rot + deg_to_rad(15.0) * dir, -PI, PI)
	return true


func key(ev: InputEventKey) -> bool:
	if ev.keycode == KEY_Q or ev.keycode == KEY_E:
		rot = wrapf(rot + deg_to_rad(15.0) * (1.0 if ev.keycode == KEY_E else -1.0), -PI, PI)
		return true
	return false


func press(p: Vector2, _ev: InputEventMouseButton) -> void:
	_place(p)
	_last = p


func drag(p: Vector2) -> void:
	if _last == null:
		return
	var dims: Vector2 = MapDef.PROPS[kind]["dims"] * scale_f
	if p.distance_to(_last) >= maxf(dims.x, dims.y) + 1.5:
		_place(p)
		_last = p


func release(_p: Vector2) -> void:
	_last = null


func hover(p: Vector2) -> void:
	_hover = p


func _place(p: Vector2) -> void:
	if not ed.map.in_bounds(ed.map.world_to_cell(p).x, ed.map.world_to_cell(p).y):
		return
	mutate()
	var r := randf_range(-PI, PI) if random_rot else rot
	ed.map.props.append({"kind": kind, "p": p, "rot": r, "s": scale_f})
	ed.changed()


func draw(ov: EditorOverlay) -> void:
	var dims: Vector2 = MapDef.PROPS[kind]["dims"] * scale_f
	var col := Color(0.7, 1.0, 0.75)
	ov.footprint(_hover, dims.max(Vector2(0.8, 0.8)), rot, col, Color(col.r, col.g, col.b, 0.25))
	ov.ground_line(_hover, _hover + Vector2(cos(rot), sin(rot)) * maxf(dims.x * 0.5 + 1.0, 1.5), col, 2.0)
	ov.text(_hover, "%s  %d°" % [kind, roundi(rad_to_deg(rot))], col, 13, 2.5)

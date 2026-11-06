extends Node
## Editor self-test: drives every map editor tool programmatically (as the mouse
## handler would), checks the map after each step, then leaves the editor open
## with a selection for a screenshot.
##   tools/gd.sh shot editor_tools.png 14 --preview=editor_tools

var ed: MapEditor
var _fails := 0


func _ready() -> void:
	ed = MapEditor.new()
	add_child(ed)
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print("  %s %s" % ["PASS" if cond else "FAIL", msg])


func _tool(i: int) -> EditorTool:
	ed.set_tool(i)
	return ed.tool


func _gesture(t: EditorTool, a: Vector2, b: Vector2 = Vector2.INF) -> void:
	t.begin_gesture()
	t.press(a, InputEventMouseButton.new())
	if b != Vector2.INF:
		for k in range(1, 6):
			t.drag(a.lerp(b, k / 5.0))
		t.release(b)
	else:
		t.release(a)


func _run() -> void:
	print("[editor self-test]")
	ed._new_map(160)
	_check(ed.map.width == 160 and ed.map.buildings.is_empty(), "new 160-cell map")
	# building
	var t := _tool(1)
	t.set("style", MapDef.S_SHOP)
	t.set("floors", 5)
	_gesture(t, Vector2(100, 100), Vector2(124, 116))
	_check(ed.map.buildings.size() == 1 and ed.map.buildings[0]["size"] == Vector2(24, 16) and ed.map.buildings[0]["floors"] == 5, "building placed by drag (24 x 16, 5 floors)")
	# road: click points, right click ends
	t = _tool(2)
	for p: Vector2 in [Vector2(20, 60), Vector2(300, 60), Vector2(300, 250)]:
		_gesture(t, p)
	t.cancel()
	var c := ed.map.world_to_cell(Vector2(150, 60))
	_check(ed.map.roads.size() == 2 and ed.map.get_terrain(c.x, c.y) == MapDef.T_ROAD, "road polyline painted (2 segments)")
	# terrain brush
	t = _tool(3)
	t.set("terrain", MapDef.T_WATER)
	t.set("radius", 5.0)
	_gesture(t, Vector2(200, 160), Vector2(240, 180))
	var water := 0
	for v in ed.map.terrain:
		if v == MapDef.T_WATER:
			water += 1
	_check(water > 60, "terrain brush stroke painted water (%d cells)" % water)
	# prop with wheel rotation
	t = _tool(4)
	t.set("kind", "car")
	t.wheel(1.0)
	t.wheel(1.0)
	_gesture(t, Vector2(150, 64))
	_check(ed.map.props.size() == 1 and absf(float(ed.map.props[0]["rot"]) - deg_to_rad(30)) < 0.01, "prop placed with wheel rotation 30 deg")
	# wall
	t = _tool(5)
	_gesture(t, Vector2(60, 120), Vector2(90, 120))
	_check(ed.map.walls.size() == 1, "wall segment drawn")
	# spawns
	t = _tool(6)
	t.set("team", 0)
	_gesture(t, Vector2(6, 90), Vector2(40, 210))
	t.set("team", 1)
	_gesture(t, Vector2(280, 90), Vector2(314, 210))
	_check(ed.map.spawns.size() == 2, "two spawn zones")
	# objectives
	t = _tool(7)
	_gesture(t, Vector2(200, 62))
	_gesture(t, Vector2(250, 120))
	_check(ed.map.objectives.size() == 2 and ed.map.objectives[1]["id"] == "B", "objectives A and B placed")
	var fields := VBoxContainer.new()
	ed.tool.selection_fields(fields)
	_check(fields.get_child_count() >= 4, "objective property fields built")
	fields.free()
	# select, move, rotate, field edit
	t = _tool(0)
	_gesture(t, Vector2(110, 108), Vector2(130, 108))
	var b: Dictionary = ed.map.buildings[0]
	_check(ed.selection.get("kind", "") == "building" and (b["c"] as Vector2).is_equal_approx(Vector2(132, 108)), "building selected and moved 20 m")
	var q := InputEventKey.new()
	q.keycode = KEY_E
	q.pressed = true
	t.key(q)
	_check(absf(float(ed.map.buildings[0]["rot"]) - deg_to_rad(15)) < 0.01, "E rotates the selection 15 deg")
	# eraser (props only)
	t = _tool(8)
	_gesture(t, Vector2(150, 64))
	_check(ed.map.props.is_empty() and ed.map.buildings.size() == 1, "eraser removed the car, kept the building")
	# undo / redo
	ed.undo()
	_check(ed.map.props.size() == 1, "undo restores the car")
	ed.redo()
	_check(ed.map.props.is_empty(), "redo erases it again")
	for k in 60:
		ed.undo()
	_check(ed.map.width == 240 and ed._undo.is_empty(), "undo back to the starting map")
	for k in 60:
		ed.redo()
	_check(ed.map.width == 160 and ed.map.objectives.size() == 2, "redo replays everything")
	# validation
	var res := MapValidator.validate(ed.map)
	for r: Dictionary in res:
		print("    [%s] %s" % [r["level"], r["text"]])
	_check(not MapValidator.has_errors(res), "hand-made map validates")
	# save / load round trip
	var path := "user://maps/_editor_selftest.json"
	DirAccess.make_dir_recursive_absolute("user://maps")
	_check(ed.map.save_json(path) == OK, "saved")
	var loaded := MapDef.load_json(path)
	_check(loaded != null and loaded.buildings.size() == 1 and loaded.objectives.size() == 2, "loaded back")
	DirAccess.remove_absolute(path)
	# auto zones on a generated city
	ed._generate(11, 0.3, 160)
	ed.auto_zones()
	_check(ed.map.spawns.size() == 2 and ed.map.objectives.size() >= 3, "auto-placed spawns and %d objectives on a generated city" % ed.map.objectives.size())
	_check(not MapValidator.has_errors(MapValidator.validate(ed.map)), "auto-zoned city validates")
	_input_routing()
	print("[editor self-test] %d failures" % _fails)
	# leave a nice state for the screenshot: imported town, building tool ghost-free, a selection
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://tools/test_images/old_town_plan.png"))
	ed.set_map(ImageImporter.analyze(img, {"size": 240, "seed": 7}))
	ed.set_tool(0)
	var best := 0
	for i in ed.map.buildings.size():
		if (ed.map.buildings[i]["c"] as Vector2).distance_to(Vector2(250, 250)) < (ed.map.buildings[best]["c"] as Vector2).distance_to(Vector2(250, 250)):
			best = i
	ed.select({"kind": "building", "i": best})
	var bc: Vector2 = ed.map.buildings[best]["c"]
	ed.cam.setup(Rect2(Vector2.ZERO, ed.map.size_m()), Vector3(bc.x, 0, bc.y), deg_to_rad(-70), 110.0)


## Real input path: events pushed into the viewport reach the tool through the
## editor's input sink (ahead of the camera), not via direct method calls.
func _input_routing() -> void:
	var vp := get_viewport()
	var center := vp.get_visible_rect().size * 0.5
	ed.set_tool(1)
	var before := ed.map.buildings.size()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = center
	vp.push_input(down, true)
	var mv := InputEventMouseMotion.new()
	mv.position = center + Vector2(90, 60)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(mv, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = center + Vector2(90, 60)
	vp.push_input(up, true)
	_check(ed.map.buildings.size() == before + 1, "mouse drag in the 3D view places a building (input routing)")
	ed.set_tool(4)
	var prop_tool: EditorTool = ed.tool
	var rot0: float = prop_tool.get("rot")
	var dist0: float = ed.cam.get("_t_dist")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = center
	vp.push_input(wheel, true)
	_check(absf(float(prop_tool.get("rot")) - rot0) > 0.01 and is_equal_approx(float(ed.cam.get("_t_dist")), dist0), "wheel rotates the prop instead of zooming")
	ed.set_tool(0)
	vp.push_input(wheel, true)
	_check(float(ed.cam.get("_t_dist")) < dist0, "wheel zooms the camera with other tools")

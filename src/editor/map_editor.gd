extends Node
## Map editor screen: 3D view of the map (debounced, layer-wise rebuilds), a tool
## panel (select, building, road, terrain, prop, wall, spawn, objective, eraser),
## undo/redo snapshots, new / generate / import / save / load, a validation panel
## and Test Play. Dev args: --editor-gen=<seed> --editor-map=<path>
## --editor-import=<image path> [--editor-import-mode=plan|sketch|photo]
## [--editor-import-apply] --editor-tool=<id> --editor-cam=x,z,dist[,yaw_deg]
## --editor-select=<building index> --editor-testplay.
class_name MapEditor

const TOOL_SCRIPTS := [
	preload("res://src/editor/tools/select_tool.gd"),
	preload("res://src/editor/tools/building_tool.gd"),
	preload("res://src/editor/tools/road_tool.gd"),
	preload("res://src/editor/tools/terrain_tool.gd"),
	preload("res://src/editor/tools/prop_tool.gd"),
	preload("res://src/editor/tools/wall_tool.gd"),
	preload("res://src/editor/tools/spawn_tool.gd"),
	preload("res://src/editor/tools/objective_tool.gd"),
	preload("res://src/editor/tools/eraser_tool.gd"),
]
const MAPS_DIR := "user://maps"
const AUTOSAVE := "user://editor_autosave.json"
const UNDO_CAP := 50
const REBUILD_DELAY_MS := 300
const SIZES := [160, 240, 320]
const PANEL_W := 290.0

var map: MapDef
var cam: CameraRig
var env: EnvironmentRig
var scene: EditorScene
var overlay: EditorOverlay
var tool: EditorTool
var tools: Array[EditorTool] = []
## {kind: building|prop|wall|objective|spawn, i: int} or {}
var selection := {}

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _edit_key := ""
var _edit_ms := 0
var _rebuild_at := -1
var _unsaved := false
var _mouse_down := false
var _last_ground := Vector2.ZERO
var _ui: Control
var _name_edit: LineEdit
var _tool_buttons: Array[Button] = []
var _options: VBoxContainer
var _options_title: Label
var _status: Label
var _cursor_label: Label
var _plan_rect: TextureRect
var _stats_label: Label
var _val_box: VBoxContainer
var _val_title: Label
var _val_task := -1
var _val_pending := false
var _val_out: Array = []
var _val_results: Array = []
var _modal: Control
var _import: ImportDialog
var _file_dialog: FileDialog


class _InputSink extends Node:
	## Added after the camera so it sees unhandled input first (reverse tree order).
	var handler: Callable

	func _unhandled_input(event: InputEvent) -> void:
		handler.call(event)


func _ready() -> void:
	env = EnvironmentRig.new()
	add_child(env)
	env.set_conditions("day", "clear")
	scene = EditorScene.new()
	add_child(scene)
	cam = CameraRig.new()
	add_child(cam)
	var sink := _InputSink.new()
	sink.handler = _viewport_input
	add_child(sink)
	_build_ui()
	for s: GDScript in TOOL_SCRIPTS:
		var t: EditorTool = s.new()
		tools.append(t.setup(self))
	set_tool(0)
	_initial_map()


func _exit_tree() -> void:
	if _val_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_val_task)
		_val_task = -1


# =================================================================== map ====

func _initial_map() -> void:
	var m: MapDef = null
	var path := DevHarness.arg("editor-map")
	var gen := DevHarness.arg("editor-gen")
	if path != "":
		m = MapDef.load_json(path)
	elif gen != "":
		m = CityGenerator.generate(int(gen), {"war_damage": 0.25})
	elif FileAccess.file_exists(AUTOSAVE):
		m = MapDef.load_json(AUTOSAVE)
	if m == null:
		m = CityGenerator.generate(randi() % 9999 + 1, {"war_damage": 0.25})
	_use_map(m)
	_unsaved = false
	var tool_id := DevHarness.arg("editor-tool")
	for i in tools.size():
		if tools[i].id == tool_id:
			set_tool(i)
	var sel := DevHarness.arg("editor-select")
	if sel != "" and int(sel) < map.buildings.size():
		set_tool(0)
		select({"kind": "building", "i": int(sel)})
	var imp := DevHarness.arg("editor-import")
	if imp != "":
		_open_import(imp)
		if _import:
			var mode := ["plan", "sketch", "photo"].find(DevHarness.arg("editor-import-mode", "plan"))
			_import.set_mode(maxi(mode, 0))
			if DevHarness.has_arg("editor-import-apply"):
				_import.create_now()
	if DevHarness.has_arg("editor-testplay"):
		_test_play.call_deferred()
	var cam_arg := DevHarness.arg("editor-cam")
	if cam_arg != "":
		var v := cam_arg.split(",")
		if v.size() >= 3:
			var yaw := deg_to_rad(float(v[3])) if v.size() >= 4 else -PI * 0.5
			cam.setup(Rect2(Vector2.ZERO, map.size_m()), Vector3(float(v[0]), 0, float(v[1])), yaw, float(v[2]))


## Replace the edited map without an undo step (startup / internal).
func _use_map(m: MapDef, reset_camera: bool = true) -> void:
	map = m
	selection = {}
	scene.clear()
	scene.sync(map)
	var t: Dictionary = scene.last_ms
	print("[MapEditor] full build %.0f ms (terrain %.0f, %d buildings %.0f, props+walls %.0f)" % [t["total"], t["terrain"], t["built"], t["buildings"], t["props"]])
	_name_edit.text = map.name
	if reset_camera:
		var s := map.size_m()
		cam.setup(Rect2(Vector2.ZERO, s), Vector3(s.x * 0.5, 0, s.y * 0.5), -PI * 0.5, minf(CameraRig.MAX_DIST, s.x * 0.62))
	_after_rebuild()
	if tool:
		tool.selection_changed()


## Replace the map as an undoable edit (new, generate, import, load).
func set_map(m: MapDef) -> void:
	begin_edit()
	_use_map(m, true)
	_unsaved = true
	_update_title()


func _snapshot() -> Dictionary:
	return {"w": map.width, "h": map.height, "terrain": map.terrain.duplicate(), "buildings": map.buildings.duplicate(true),
		"walls": map.walls.duplicate(true), "props": map.props.duplicate(true), "roads": map.roads.duplicate(true),
		"spawns": map.spawns.duplicate(true), "objectives": map.objectives.duplicate(true), "districts": map.districts.duplicate(true),
		"name": map.name, "description": map.description, "seed": map.map_seed}


func _restore(s: Dictionary) -> void:
	var resized: bool = s["w"] != map.width or s["h"] != map.height
	map.width = s["w"]
	map.height = s["h"]
	map.terrain = s["terrain"]
	map.buildings = s["buildings"]
	map.walls = s["walls"]
	map.props = s["props"]
	map.roads = s["roads"]
	map.spawns = s["spawns"]
	map.objectives = s["objectives"]
	map.districts = s["districts"]
	map.name = s["name"]
	map.description = s["description"]
	map.map_seed = s["seed"]
	_name_edit.text = map.name
	if resized:
		var sz := map.size_m()
		cam.setup(Rect2(Vector2.ZERO, sz), Vector3(sz.x * 0.5, 0, sz.y * 0.5), cam.yaw, cam.dist)


## Push an undo snapshot of the current state. Edits sharing a non-empty
## `coalesce` key within 1.5 s (slider drags, typing) form one undo step.
func begin_edit(coalesce: String = "") -> void:
	var now := Time.get_ticks_msec()
	if coalesce != "" and coalesce == _edit_key and now - _edit_ms < 1500:
		_edit_ms = now
		return
	_edit_key = coalesce
	_edit_ms = now
	_undo.append(_snapshot())
	if _undo.size() > UNDO_CAP:
		_undo.pop_front()
	_redo.clear()


## Notify that the map changed: schedules the debounced 3D rebuild.
func changed() -> void:
	_unsaved = true
	_rebuild_at = Time.get_ticks_msec() + REBUILD_DELAY_MS
	_update_title()


func undo() -> void:
	if _undo.is_empty():
		Events.notice.emit("Nothing to undo", "info")
		return
	_redo.append(_snapshot())
	_restore(_undo.pop_back())
	_edit_key = ""
	select({})
	changed()


func redo() -> void:
	if _redo.is_empty():
		Events.notice.emit("Nothing to redo", "info")
		return
	_undo.append(_snapshot())
	_restore(_redo.pop_back())
	_edit_key = ""
	select({})
	changed()


func select(sel: Dictionary) -> void:
	selection = sel
	if tool:
		tool.selection_changed()


func delete_selection() -> void:
	if selection.is_empty():
		return
	begin_edit()
	var i: int = selection["i"]
	match selection["kind"]:
		"building": map.buildings.remove_at(i)
		"prop": map.props.remove_at(i)
		"wall": map.walls.remove_at(i)
		"objective": map.objectives.remove_at(i)
		"spawn": map.spawns.remove_at(i)
	select({})
	changed()


## Spawns on the most open opposite edges, connectivity carving, objectives.
func auto_zones() -> void:
	begin_edit()
	map.spawns.clear()
	map.objectives.clear()
	var rep := ImageImporter.make_playable(map, {"seed": map.map_seed, "zones": true, "props": false})
	select({})
	changed()
	var carved: int = rep["carved"]
	Events.notice.emit("Placed 2 spawn zones and %d objectives%s" % [map.objectives.size(),
		"" if carved == 0 else " · carved %d street%s to connect them" % [carved, "s" if carved > 1 else ""]], "good")


func _process(_delta: float) -> void:
	# Q/E rotate the tool's object instead of the camera while it wants them
	cam.input_enabled = not (tool.wants_qe() and (Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E)))
	if _mouse_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_down = false
		tool.release(_last_ground)
	if _rebuild_at > 0 and _mouse_down:
		scene.sync(map, false)   # live building moves / deletes while dragging
	elif _rebuild_at > 0 and Time.get_ticks_msec() >= _rebuild_at:
		_rebuild_at = -1
		scene.sync(map)
		_after_rebuild()
		var t: Dictionary = scene.last_ms
		print("[MapEditor] rebuild %.0f ms (terrain %.0f, buildings %.0f / %d new, props+walls %.0f)" % [t["total"], t["terrain"], t["buildings"], t["built"], t["props"]])
	if _val_task >= 0 and WorkerThreadPool.is_task_completed(_val_task):
		WorkerThreadPool.wait_for_task_completion(_val_task)
		_val_task = -1
		if _val_out.size() > 0:
			_show_validation(_val_out[0])
		if _val_pending:
			_validate_async()


func _after_rebuild() -> void:
	_plan_rect.texture = ImageTexture.create_from_image(EditorUI.plan_image(map))
	_stats_label.text = "%d × %d cells (%d m)\n%d buildings · %d props · %d walls · %d road segments" % [
		map.width, map.height, int(map.size_m().x), map.buildings.size(), map.props.size(), map.walls.size(), map.roads.size()]
	_validate_async()


# ============================================================== validation ==

func _validate_async() -> void:
	if _val_task >= 0:
		_val_pending = true
		return
	_val_pending = false
	_val_title.text = "VALIDATION  ·  checking…"
	var copy := MapDef.from_dict(map.to_dict())
	var out: Array = []
	_val_out = out
	_val_task = WorkerThreadPool.add_task(func(): out.append(MapValidator.validate(copy)))


func _show_validation(results: Array) -> void:
	_val_results = results
	for c in _val_box.get_children():
		c.queue_free()
	var errors := 0
	var warns := 0
	for r: Dictionary in results:
		var col := UITheme.GOOD
		match r["level"]:
			MapValidator.LV_ERROR:
				col = UITheme.ALERT
				errors += 1
			MapValidator.LV_WARN:
				col = UITheme.WARN
				warns += 1
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.color = col
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var dwrap := MarginContainer.new()
		dwrap.add_theme_constant_override("margin_top", 5)
		dwrap.add_child(dot)
		h.add_child(dwrap)
		var l := UITheme.label(r["text"], 13, UITheme.TEXT if r["level"] == MapValidator.LV_OK else col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(PANEL_W - 60, 0)
		h.add_child(l)
		_val_box.add_child(h)
	if errors > 0:
		_val_title.text = "VALIDATION  ·  %d problem%s" % [errors, "" if errors == 1 else "s"]
	elif warns > 0:
		_val_title.text = "VALIDATION  ·  playable, %d warning%s" % [warns, "" if warns == 1 else "s"]
	else:
		_val_title.text = "VALIDATION  ·  ready to play"


# ================================================================== input ===

func _ground(screen: Vector2) -> Variant:
	var g = cam.ground_point(screen)
	if g == null:
		return null
	var s := map.size_m()
	return Vector2(clampf(g.x, 0.0, s.x), clampf(g.z, 0.0, s.y))


func _viewport_input(event: InputEvent) -> void:
	if _modal or _import:
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_close_modal()
			_close_import()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed and tool.wheel(-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0):
				get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var gp = _ground(mb.position)
			if mb.pressed and gp != null:
				_mouse_down = true
				_last_ground = gp
				tool.begin_gesture()
				tool.press(gp, mb)
			elif not mb.pressed and _mouse_down:
				_mouse_down = false
				tool.release(gp if gp != null else _last_ground)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			tool.cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var gp = _ground((event as InputEventMouseMotion).position)
		if gp == null:
			return
		_last_ground = gp
		tool.hover(gp)
		if _mouse_down:
			tool.drag(gp)
		var c := map.world_to_cell(gp)
		_cursor_label.text = "%.0f m, %.0f m  ·  %s" % [gp.x, gp.y, EditorTool.TERRAIN_NAMES[map.get_terrain(c.x, c.y)]]
	elif event is InputEventKey and (event as InputEventKey).pressed:
		if _shortcut(event as InputEventKey):
			get_viewport().set_input_as_handled()


func _shortcut(k: InputEventKey) -> bool:
	if k.ctrl_pressed:
		match k.keycode:
			KEY_Z:
				if k.shift_pressed:
					redo()
				else:
					undo()
				return true
			KEY_Y:
				redo()
				return true
			KEY_S:
				_save()
				return true
		return false
	if k.keycode == KEY_ESCAPE:
		tool.cancel()
		return true
	if not k.echo and k.keycode >= KEY_1 and k.keycode <= KEY_9:
		set_tool(k.keycode - KEY_1)
		return true
	return tool.key(k)


# ==================================================================== tools ==

func set_tool(i: int) -> void:
	if i < 0 or i >= tools.size():
		return
	if tool:
		tool.deactivate()
	tool = tools[i]
	tool.activate()
	_tool_buttons[i].button_pressed = true
	_options_title.text = tool.title.to_upper()
	_status.text = tool.hint
	refresh_tool_options()


func refresh_tool_options() -> void:
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	tool.build_options(_options)


# ===================================================================== files ==

func _map_path(name: String) -> String:
	var f := name.strip_edges().validate_filename().replace(" ", "_")
	return "%s/%s.json" % [MAPS_DIR, f if f != "" else "untitled"]


func _save() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm == "":
		nm = "Untitled"
		_name_edit.text = nm
	map.name = nm
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	var path := _map_path(nm)
	var existed := FileAccess.file_exists(path)
	var err := map.save_json(path)
	if err != OK:
		Events.notice.emit("Could not save: %s" % error_string(err), "alert")
		return
	_unsaved = false
	_update_title()
	var results := MapValidator.validate(map)
	_show_validation(results)
	var msg := "%s %s" % ["Updated" if existed else "Saved", path.get_file()]
	if MapValidator.has_errors(results):
		Events.notice.emit(msg + " · not playable yet, see validation", "warn")
	else:
		Events.notice.emit(msg + " · playable from Skirmish", "good")


func _autosave() -> void:
	map.name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else map.name
	map.save_json(AUTOSAVE)


func _load(path: String) -> void:
	var m := MapDef.load_json(path)
	if m == null:
		Events.notice.emit("Could not read " + path.get_file(), "alert")
		return
	set_map(m)
	_unsaved = false
	_update_title()
	Events.notice.emit("Loaded " + m.name, "good")


func _new_map(n: int) -> void:
	var m := MapDef.new(n, n)
	m.name = "New Map"
	m.map_seed = randi() % 99999 + 1
	var noise := FastNoiseLite.new()
	noise.seed = m.map_seed
	noise.frequency = 0.035
	for y in n:
		for x in n:
			m.terrain[y * n + x] = MapDef.T_DIRT if noise.get_noise_2d(x, y) > 0.15 else MapDef.T_SAND
	set_map(m)


func _generate(seed_v: int, war: float, n: int) -> void:
	var t0 := Time.get_ticks_msec()
	set_map(CityGenerator.generate(seed_v, {"size": n, "war_damage": war}))
	Events.notice.emit("Generated %s (%d ms)" % [map.name, Time.get_ticks_msec() - t0], "good")


func _test_play() -> void:
	var results := MapValidator.validate(map)
	_show_validation(results)
	if not MapValidator.has_errors(results):
		_start_game()
		return
	var lines := []
	for r: Dictionary in results:
		if r["level"] == MapValidator.LV_ERROR:
			lines.append("• " + r["text"])
	var body := EditorUI.dim("This map has problems:\n%s\n\nPlay anyway?" % "\n".join(lines), 14)
	body.custom_minimum_size = Vector2(440, 0)
	_show_modal("TEST PLAY", body, [["Cancel", _close_modal], ["Play anyway", _start_game]])


func _start_game() -> void:
	_autosave()
	var cfg := GameConfig.skirmish("cdf", "pdb", "medium", map.map_seed, {"map": MapDef.from_dict(map.to_dict())})
	Events.navigate.emit("game", cfg)


func _back() -> void:
	_autosave()
	Events.navigate.emit("menu", {})


# ============================================================ import flow ===

func _browse_image() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		_file_dialog.title = "Choose a plan, drawing or map image"
		_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Images"])
		_file_dialog.file_selected.connect(_open_import)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


func _open_import(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		Events.notice.emit("Could not load image: " + path.get_file(), "alert")
		return
	if _import == null:
		_import = ImportDialog.new()
		_ui.add_child(_import)
		_import.browse_requested.connect(_browse_image)
		_import.cancelled.connect(_close_import)
		_import.accepted.connect(func(m: MapDef):
			_close_import()
			set_map(m)
			Events.notice.emit("Imported %s · review and edit the details" % m.name, "good"))
	_import.set_image(img, path)


func _close_import() -> void:
	if _import:
		_import.queue_free()
		_import = null


# ======================================================================= UI ==

func _update_title() -> void:
	if _name_edit:
		_name_edit.modulate = Color(1, 0.92, 0.75) if _unsaved else Color.WHITE


func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, o_r: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = o_r
	c.offset_bottom = ob


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.get_theme()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	overlay = EditorOverlay.new()
	overlay.ed = self
	_ui.add_child(overlay)
	_build_top_bar()
	_build_left_panel()
	_build_right_panel()
	var bottom := EditorUI.panel()
	_place(bottom, 0, 1, 1, 1, 8, -40, -8, -6)
	var bh := HBoxContainer.new()
	_status = UITheme.label("", 13, UITheme.TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	bh.add_child(_status)
	bh.add_child(UITheme.label("MMB rotate · Shift+MMB pan · wheel zoom · WASD move · Ctrl+Z / Ctrl+Y undo / redo  ", 12, UITheme.TEXT_DIM))
	_cursor_label = UITheme.label("", 13, UITheme.TEXT)
	_cursor_label.custom_minimum_size = Vector2(230, 0)
	_cursor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bh.add_child(_cursor_label)
	bottom.add_child(bh)
	_ui.add_child(bottom)


func _build_top_bar() -> void:
	var top := EditorUI.panel()
	_place(top, 0, 0, 1, 0, 8, 8, -8, 56)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	top.add_child(h)
	h.add_child(UITheme.label("MAP EDITOR", 22, UITheme.ACCENT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	h.add_child(gap)
	_name_edit = EditorUI.line_edit("", func(t: String):
		map.name = t
		_unsaved = true
		_update_title(), "Map name")
	_name_edit.custom_minimum_size = Vector2(230, 0)
	_name_edit.tooltip_text = "Map name (also the file name in user://maps)"
	h.add_child(_name_edit)
	var items := [
		["Save", _save, "Save to user://maps/<name>.json (Ctrl+S); saved maps appear in Skirmish"],
		["Load", _load_dialog, "Open a saved map"],
		["New", _new_dialog, "Start an empty map"],
		["Generate city", _generate_dialog, "Procedural city from a seed"],
		["Import image", _import_pressed, "Build a map from a plan, drawing or map screenshot"],
		["|", null, ""],
		["Undo", undo, "Ctrl+Z"],
		["Redo", redo, "Ctrl+Y"],
	]
	for it: Array in items:
		if it[0] == "|":
			var s := VSeparator.new()
			h.add_child(s)
			continue
		h.add_child(UITheme.button(it[0], it[1], it[2]))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var play := UITheme.button("Test Play", _test_play, "Validate, then start a skirmish on this map")
	play.add_theme_color_override("font_color", UITheme.GOOD)
	h.add_child(play)
	h.add_child(UITheme.button("Back to menu", _back, "Your work is kept and restored next time"))
	_ui.add_child(top)


func _build_left_panel() -> void:
	var left := EditorUI.panel()
	_place(left, 0, 0, 0, 1, 8, 64, 8 + PANEL_W, -48)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	left.add_child(v)
	v.add_child(EditorUI.header("TOOLS"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	var names := ["Select", "Building", "Road", "Terrain", "Prop", "Wall", "Spawn zone", "Objective", "Eraser"]
	for i in names.size():
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, names[i]]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(set_tool.bind(i))
		grid.add_child(b)
		_tool_buttons.append(b)
	v.add_child(grid)
	v.add_child(EditorUI.sep())
	_options_title = EditorUI.header("")
	v.add_child(_options_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 7)
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_options)
	v.add_child(scroll)
	_ui.add_child(left)


func _build_right_panel() -> void:
	var right := EditorUI.panel()
	_place(right, 1, 0, 1, 1, -8 - PANEL_W, 64, -8, -48)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	right.add_child(v)
	v.add_child(EditorUI.header("MAP"))
	_stats_label = UITheme.label("", 13, UITheme.TEXT_DIM)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stats_label)
	_plan_rect = TextureRect.new()
	_plan_rect.custom_minimum_size = Vector2(PANEL_W - 24, PANEL_W - 24)
	_plan_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plan_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_plan_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_plan_rect.tooltip_text = "Click to move the camera"
	_plan_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_plan_rect.gui_input.connect(_plan_input)
	v.add_child(_plan_rect)
	v.add_child(EditorUI.sep())
	var vh := HBoxContainer.new()
	_val_title = EditorUI.header("VALIDATION")
	_val_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vh.add_child(_val_title)
	vh.add_child(UITheme.button("Re-check", _validate_async, "Run the playability checks now"))
	v.add_child(vh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_val_box = VBoxContainer.new()
	_val_box.add_theme_constant_override("separation", 5)
	scroll.add_child(_val_box)
	v.add_child(scroll)
	v.add_child(UITheme.button("Auto-place spawns & objectives", auto_zones,
		"Spawn zones on the two most open opposite edges, streets carved if needed, objectives at junctions"))
	_ui.add_child(right)


func _plan_input(event: InputEvent) -> void:
	var drag := event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if not (drag or click):
		return
	var sz := _plan_rect.size
	var side := minf(sz.x, sz.y)
	var off := (sz - Vector2(side, side)) * 0.5
	var local: Vector2 = (event as InputEventMouse).position - off
	var p := local / side * map.size_m()
	cam.look_at_point(Vector3(clampf(p.x, 0, map.size_m().x), 0, clampf(p.y, 0, map.size_m().y)))


# ================================================================= dialogs ===

func _show_modal(title: String, content: Control, buttons: Array) -> void:
	_close_modal()
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_modal())
	_modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(center)
	var panel := EditorUI.panel(Vector2(420, 0))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UITheme.label(title, 20, UITheme.ACCENT))
	v.add_child(content)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	for b: Array in buttons:
		var cb: Callable = b[1]
		row.add_child(UITheme.button(b[0], func():
			if cb != _close_modal:
				_close_modal()
			cb.call()))
	v.add_child(row)
	_ui.add_child(_modal)


func _close_modal() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null


func _new_dialog() -> void:
	var size_i := [1]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(EditorUI.dim("An empty map of open ground. Paint roads, place buildings and zones by hand, or use Auto-place for spawns and objectives."))
	v.add_child(EditorUI.row("Size", EditorUI.segmented(SIZES.map(func(s): return "%d (%d m)" % [s, s * 2]), 1, func(i: int): size_i[0] = i)))
	_show_modal("NEW MAP", v, [["Cancel", _close_modal], ["Create", func(): _new_map(SIZES[size_i[0]])]])


func _generate_dialog() -> void:
	var st := {"seed": randi() % 9999 + 1, "war": 0.25, "size": 1}
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var seed_row := HBoxContainer.new()
	var spin := EditorUI.spin(1, 99999, st["seed"], func(x: float): st["seed"] = int(x))
	seed_row.add_child(spin)
	seed_row.add_child(UITheme.button("Random", func(): spin.value = randi() % 99999 + 1))
	v.add_child(EditorUI.row("Seed", seed_row))
	v.add_child(EditorUI.row("War damage", EditorUI.slider(0.0, 0.8, 0.05, st["war"], func(x: float): st["war"] = x)))
	v.add_child(EditorUI.row("Size", EditorUI.segmented(SIZES.map(func(s): return "%d m" % (s * 2)), 1, func(i: int): st["size"] = i)))
	v.add_child(EditorUI.dim("Replaces the current map (undo restores it). The result stays fully editable."))
	_show_modal("GENERATE CITY", v, [["Cancel", _close_modal], ["Generate", func(): _generate(st["seed"], st["war"], SIZES[st["size"]])]])


func _load_dialog() -> void:
	var files := SaveSystem.list(MAPS_DIR, ".json")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	if files.is_empty():
		v.add_child(EditorUI.dim("No saved maps yet. Maps you save appear here and in the Skirmish setup.", 14))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, mini(files.size(), 9) * 40 + 4)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for f: String in files:
		var stamp := Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(f)).replace("T", " ").substr(0, 16)
		var b := UITheme.button("%s     %s" % [f.get_file().get_basename(), stamp], func():
			_close_modal()
			_load(f))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 36)
		list.add_child(b)
	if not files.is_empty():
		v.add_child(scroll)
	_show_modal("LOAD MAP", v, [["Close", _close_modal]])


func _import_pressed() -> void:
	_browse_image()

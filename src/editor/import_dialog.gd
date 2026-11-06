extends Control
## Image import dialog: interpretation mode, per-class thresholds and layout
## parameters with a live preview (source image next to the interpreted plan).
## Analysis runs on a worker thread, debounced, so sliders stay responsive.
class_name ImportDialog

signal accepted(map: MapDef)
signal browse_requested
signal cancelled

const SIZES := [160, 240, 320]
const MODE_LABELS := ["Color plan", "Sketch", "Screenshot"]
const LEGENDS := [
	"Legend: gray or white = roads · dark gray, black or brown = buildings · green = parks and fields · blue = water · any other color = open ground.",
	"Dark pencil or ink marks = buildings, paper = open ground. Closed outlines are filled, gaps between marks become streets. Blue / green colored pencil = water / vegetation.",
	"Heuristics: light low-saturation gray = road, green = vegetation, blue = water, mid and dark gray blocks = buildings, warm sandy colors = open ground. Tune the thresholds until the plan matches.",
]

var params := ImageImporter.default_params()
var result: MapDef
var _src: Image
var _prep: Image
var _prep_size := 0
var _task := -1
var _task_out: Array = []
var _dirty := false
var _debounce := 0.0
var _src_rect: TextureRect
var _out_rect: TextureRect
var _stats: Label
var _legend: Label
var _file_label: Label
var _thresholds: VBoxContainer
var _create: Button
var _busy: Label
var _name_edit: LineEdit
var _mode_buttons: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := EditorUI.panel(Vector2(1240, 780))
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UITheme.label("IMPORT MAP FROM IMAGE", 24, UITheme.ACCENT))
	_file_label = UITheme.label("", 13, UITheme.TEXT_DIM)
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_label.clip_text = true
	head.add_child(_file_label)
	head.add_child(UITheme.button("Choose image…", func(): browse_requested.emit(), "PNG, JPG, WEBP or BMP: a plan, a drawing or a map screenshot"))
	root.add_child(head)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_params())
	body.add_child(_build_preview())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.alignment = BoxContainer.ALIGNMENT_END
	_busy = UITheme.label("", 13, UITheme.WARN)
	_busy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_busy)
	foot.add_child(UITheme.button("Cancel", func(): cancelled.emit()))
	_create = UITheme.button("Create map", create_now, "Open the result in the editor for review")
	_create.custom_minimum_size = Vector2(190, 38)
	_create.add_theme_font_size_override("font_size", 17)
	foot.add_child(_create)
	root.add_child(foot)
	_rebuild_thresholds()


func _build_params() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(EditorUI.header("INTERPRET AS"))
	_mode_buttons = EditorUI.segmented(MODE_LABELS, params["mode"], func(i: int):
		params["mode"] = i
		_rebuild_thresholds()
		_schedule())
	v.add_child(_mode_buttons)
	_legend = EditorUI.dim("")
	_legend.custom_minimum_size = Vector2(360, 0)
	v.add_child(_legend)
	v.add_child(EditorUI.header("THRESHOLDS"))
	_thresholds = VBoxContainer.new()
	_thresholds.add_theme_constant_override("separation", 5)
	v.add_child(_thresholds)
	v.add_child(EditorUI.header("LAYOUT"))
	v.add_child(EditorUI.row("Map size", EditorUI.segmented(SIZES.map(func(s): return "%d m" % (s * 2)), SIZES.find(params["size"]), func(i: int):
		params["size"] = SIZES[i]
		_schedule()), 120))
	v.add_child(_slider_row("Min building", "min_building", 4.0, 16.0, 0.5, "%.1f m"))
	v.add_child(_slider_row("Max lot size", "max_lot", 12.0, 60.0, 1.0, "%.0f m"))
	var floors := HBoxContainer.new()
	floors.add_theme_constant_override("separation", 6)
	floors.add_child(EditorUI.spin(1, 12, params["floors_min"], func(x: float):
		params["floors_min"] = int(x)
		_schedule()))
	floors.add_child(UITheme.label("to", 13, UITheme.TEXT_DIM))
	floors.add_child(EditorUI.spin(1, 14, params["floors_max"], func(x: float):
		params["floors_max"] = int(x)
		_schedule()))
	v.add_child(EditorUI.row("Floors", floors, 120))
	v.add_child(_slider_row("War damage", "war_damage", 0.0, 0.8, 0.05, "%.2f"))
	var seed_row := HBoxContainer.new()
	var seed_spin := EditorUI.spin(1, 99999, params["seed"], func(x: float):
		params["seed"] = int(x)
		_schedule())
	seed_row.add_child(seed_spin)
	seed_row.add_child(UITheme.button("Random", func(): seed_spin.value = randi() % 99999 + 1, "New styles, floors and colors"))
	v.add_child(EditorUI.row("Seed", seed_row, 120))
	v.add_child(EditorUI.check("Auto-place spawns and objectives", params["auto_zones"], func(on: bool):
		params["auto_zones"] = on
		_schedule()))
	v.add_child(EditorUI.check("Street props (lamps, parked cars, wrecks)", params["props"], func(on: bool):
		params["props"] = on
		_schedule()))
	_name_edit = EditorUI.line_edit(params["name"], func(t: String): params["name"] = t)
	v.add_child(EditorUI.row("Map name", _name_edit, 120))
	return scroll


func _slider_row(label: String, key: String, lo: float, hi: float, step: float, fmt: String = "%.2f") -> Control:
	return EditorUI.row(label, EditorUI.slider(lo, hi, step, float(params[key]), func(x: float):
		params[key] = x
		_schedule(), fmt), 120)


func _rebuild_thresholds() -> void:
	for c in _thresholds.get_children():
		c.queue_free()
	var mode: int = params["mode"]
	_legend.text = LEGENDS[mode]
	match mode:
		ImageImporter.MODE_PLAN:
			_thresholds.add_child(_slider_row("Building dark", "building_dark", 0.1, 0.7, 0.01))
			_thresholds.add_child(_slider_row("Gray max sat.", "road_sat", 0.05, 0.5, 0.01))
			_thresholds.add_child(EditorUI.check("Pure white is open ground (not road)", params["white_open"], func(on: bool):
				params["white_open"] = on
				_schedule()))
		ImageImporter.MODE_SKETCH:
			_thresholds.add_child(_slider_row("Ink darkness", "ink", 0.1, 0.9, 0.01))
			_thresholds.add_child(EditorUI.check("Invert (light marks on dark paper)", params["invert"], func(on: bool):
				params["invert"] = on
				_schedule()))
			_thresholds.add_child(EditorUI.check("Fill closed outlines", params["fill_outlines"], func(on: bool):
				params["fill_outlines"] = on
				_schedule()))
			_thresholds.add_child(EditorUI.check("Gaps between marks become streets", params["gap_streets"], func(on: bool):
				params["gap_streets"] = on
				_schedule()))
		_:
			_thresholds.add_child(_slider_row("Road brightness", "road_light", 0.3, 0.95, 0.01))
			_thresholds.add_child(_slider_row("Gray max sat.", "road_sat", 0.05, 0.5, 0.01))
			_thresholds.add_child(_slider_row("Building dark", "building_dark", 0.1, 0.7, 0.01))
	_thresholds.add_child(_slider_row("Vegetation", "veg", 0.0, 1.0, 0.02))
	_thresholds.add_child(_slider_row("Water", "water", 0.0, 1.0, 0.02))
	var smooth: int = params["smooth"]
	if smooth < 0:
		smooth = [0, 1, 2][mode]
	_thresholds.add_child(EditorUI.row("Smoothing", EditorUI.slider(0, 3, 1, smooth, func(x: float):
		params["smooth"] = int(x)
		_schedule(), "%.0f"), 120))


func _build_preview() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	for i in 2:
		var col := VBoxContainer.new()
		col.add_child(EditorUI.header("SOURCE IMAGE" if i == 0 else "INTERPRETED PLAN"))
		var frame := PanelContainer.new()
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(390, 390)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if i == 0 else CanvasItem.TEXTURE_FILTER_NEAREST
		frame.add_child(tr)
		col.add_child(frame)
		row.add_child(col)
		if i == 0:
			_src_rect = tr
		else:
			_out_rect = tr
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 10)
	legend.alignment = BoxContainer.ALIGNMENT_END
	for it: Array in [["Road", Color(0.2, 0.2, 0.21)], ["Sidewalk", Color(0.36, 0.34, 0.31)], ["Building", Color(0.75, 0.72, 0.65)],
			["Park", Color(0.25, 0.32, 0.17)], ["Field", Color(0.38, 0.37, 0.22)], ["Water", Color(0.2, 0.3, 0.42)],
			["Spawn", Color(0.35, 0.6, 1.0)], ["Objective", Color(1, 0.9, 0.3)]]:
		var sw := ColorRect.new()
		sw.color = it[1]
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(sw)
		legend.add_child(UITheme.label(it[0], 12, UITheme.TEXT_DIM))
	v.add_child(legend)
	_stats = UITheme.label("Choose an image to start.", 14, UITheme.TEXT)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stats)
	v.add_child(EditorUI.dim("Everything stays editable: after creating the map you can move, restyle or delete buildings, redraw roads, repaint ground and adjust spawns and objectives."))
	return v


## Show an image (resets the cached downscale) and analyze it.
func set_image(img: Image, path: String) -> void:
	_src = img
	_prep = null
	_prep_size = 0
	_file_label.text = "%s  ·  %d × %d px" % [path.get_file(), img.get_width(), img.get_height()]
	var base := path.get_file().get_basename().replace("_", " ").replace("-", " ").strip_edges()
	if base != "":
		params["name"] = base.capitalize()
		_name_edit.text = params["name"]
	_schedule(0.0)


func set_mode(mode: int) -> void:
	params["mode"] = mode
	(_mode_buttons.get_child(mode) as Button).button_pressed = true
	_rebuild_thresholds()
	_schedule()


func _schedule(delay: float = 0.15) -> void:
	_dirty = true
	_debounce = delay


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply(_task_out)
	_debounce -= delta
	if _dirty and _debounce <= 0.0 and _task < 0 and _src != null:
		_start()
	_busy.text = "Analyzing…" if _task >= 0 or _dirty else ""
	_create.disabled = _src == null


func _ensure_prepared() -> void:
	var size: int = params["size"]
	if _prep == null or _prep_size != size:
		_prep = ImageImporter.prepare(_src, size)
		_prep_size = size
		_src_rect.texture = ImageTexture.create_from_image(_prep)


func _start() -> void:
	_dirty = false
	_ensure_prepared()
	var img := _prep
	var p := params.duplicate()
	var out: Array = []
	_task_out = out
	_task = WorkerThreadPool.add_task(func():
		var t0 := Time.get_ticks_msec()
		var m := ImageImporter.analyze(img, p)
		var plan := EditorUI.plan_image(m)
		out.append_array([m, plan, Time.get_ticks_msec() - t0]))


func _apply(out: Array) -> void:
	if out.size() < 3:
		return
	result = out[0]
	_out_rect.texture = ImageTexture.create_from_image(out[1])
	var water := 0
	var road := 0
	for t in result.terrain:
		if t == MapDef.T_WATER:
			water += 1
		elif t == MapDef.T_ROAD:
			road += 1
	var cells := float(result.width * result.height)
	_stats.text = "%d buildings · %d road segments (%.0f%% road) · %.0f%% water · %d props · %d spawn zones · %d objectives  —  %d ms" % [
		result.buildings.size(), result.roads.size(), road / cells * 100.0, water / cells * 100.0, result.props.size(),
		result.spawns.size(), result.objectives.size(), out[2]]


## Finish any pending analysis synchronously and hand the map to the editor.
func create_now() -> void:
	if _src == null:
		return
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply(_task_out)
	if _dirty or result == null:
		_dirty = false
		_ensure_prepared()
		result = ImageImporter.analyze(_prep, params)
	accepted.emit(result)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

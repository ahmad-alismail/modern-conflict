extends RefCounted
## Small widget factory for the map editor panels (UITheme look).
class_name EditorUI


static func header(text: String) -> Label:
	var l := UITheme.label(text, 13, UITheme.ACCENT)
	l.add_theme_constant_override("outline_size", 0)
	return l


static func dim(text: String, size: int = 12) -> Label:
	var l := UITheme.label(text, size, UITheme.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Label on the left, control filling the rest.
static func row(label: String, ctl: Control, label_w: float = 78.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := UITheme.label(label, 13, UITheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(label_w, 0)
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	return h


static func option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for it in items:
		o.add_item(str(it))
	o.select(clampi(selected, 0, items.size() - 1))
	o.item_selected.connect(cb)
	return o


## Slider with a live value label. cb(value: float) fires while dragging.
static func slider(min_v: float, max_v: float, step: float, value: float, cb: Callable, fmt: String = "%.2f") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(80, 18)
	var l := UITheme.label(fmt % value, 12, UITheme.TEXT)
	l.custom_minimum_size = Vector2(40, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float):
		l.text = fmt % v
		cb.call(v))
	h.add_child(s)
	h.add_child(l)
	return h


static func spin(min_v: float, max_v: float, value: float, cb: Callable, step: float = 1.0) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(cb)
	return s


static func check(text: String, value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 13)
	c.toggled.connect(cb)
	return c


static func line_edit(text: String, cb: Callable, placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.text_submitted.connect(func(_t: String): e.release_focus())
	e.text_changed.connect(cb)
	return e


## Row of toggle buttons acting as a radio group. cb(index: int).
static func segmented(items: Array, selected: int, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for i in items.size():
		var b := Button.new()
		b.text = str(items[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = i == selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): cb.call(i))
		h.add_child(b)
	return h


static func sep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 8)
	return s


## Dark translucent panel with padding.
static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## Plan image of a map (Minimap.render_plan) with spawn zones and objectives.
## Thread-safe: only touches the Image it creates.
static func plan_image(m: MapDef) -> Image:
	var img := Minimap.render_plan(m)
	for sp in m.spawns:
		var r: Rect2 = sp["rect"]
		var col := Color(0.35, 0.6, 1.0) if sp["team"] == 0 else Color(1.0, 0.42, 0.28)
		var c0 := m.world_to_cell(r.position)
		var c1 := m.world_to_cell(r.end)
		for y in range(maxi(c0.y, 0), mini(c1.y + 1, m.height)):
			for x in range(maxi(c0.x, 0), mini(c1.x + 1, m.width)):
				var edge := x == c0.x or x == c1.x or y == c0.y or y == c1.y
				img.set_pixel(x, y, col if edge else img.get_pixel(x, y).lerp(col, 0.25))
	for o in m.objectives:
		var c := m.world_to_cell(o["p"])
		var rc := int(float(o["r"]) / MapDef.CELL)
		for a in 64:
			var q := c + Vector2i(Vector2(cos(TAU * a / 64.0), sin(TAU * a / 64.0)) * rc)
			if m.in_bounds(q.x, q.y):
				img.set_pixel(q.x, q.y, Color(1, 0.9, 0.3))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if m.in_bounds(c.x + dx, c.y + dy):
					img.set_pixel(c.x + dx, c.y + dy, Color(1, 0.9, 0.3))
	return img

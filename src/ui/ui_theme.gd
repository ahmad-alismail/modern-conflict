extends RefCounted
## Shared UI look: dark translucent military panels with a sand accent.
class_name UITheme

const BG := Color(0.07, 0.08, 0.075, 0.88)
const BG_SOLID := Color(0.09, 0.1, 0.095, 0.97)
const PANEL_BORDER := Color(0.78, 0.68, 0.45, 0.35)
const ACCENT := Color(0.86, 0.74, 0.46)
const TEXT := Color(0.92, 0.91, 0.86)
const TEXT_DIM := Color(0.65, 0.65, 0.6)
const GOOD := Color(0.45, 0.9, 0.5)
const WARN := Color(1.0, 0.75, 0.3)
const ALERT := Color(1.0, 0.38, 0.3)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 15
	var panel := _box(BG, PANEL_BORDER, 1, 4)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	var bn := _box(Color(0.16, 0.17, 0.15, 0.95), Color(0.78, 0.68, 0.45, 0.25), 1, 3)
	var bh := _box(Color(0.24, 0.24, 0.2, 0.98), ACCENT, 1, 3)
	var bp := _box(Color(0.32, 0.29, 0.2, 1.0), ACCENT, 1, 3)
	var bd := _box(Color(0.1, 0.1, 0.1, 0.8), Color(0.3, 0.3, 0.3, 0.3), 1, 3)
	for s in [bn, bh, bp, bd]:
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 5
		s.content_margin_bottom = 5
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_stylebox("normal", "OptionButton", bn)
	t.set_stylebox("hover", "OptionButton", bh)
	t.set_stylebox("pressed", "OptionButton", bp)
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	var le := _box(Color(0.05, 0.05, 0.05, 0.9), Color(0.78, 0.68, 0.45, 0.3), 1, 3)
	le.content_margin_left = 8
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _box(Color(0.05, 0.05, 0.05, 0.95), ACCENT, 1, 3))
	var pb_bg := _box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 0, 2)
	var pb_fg := _box(GOOD, Color(0, 0, 0, 0), 0, 2)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)
	t.set_stylebox("panel", "TooltipPanel", _box(BG_SOLID, ACCENT, 1, 3))
	t.set_stylebox("panel", "PopupMenu", _box(BG_SOLID, PANEL_BORDER, 1, 3))
	t.set_stylebox("slider", "HSlider", _box(Color(0, 0, 0, 0.6), Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("tab_selected", "TabContainer", _box(Color(0.24, 0.24, 0.2, 0.98), ACCENT, 1, 3))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(0.12, 0.12, 0.11, 0.95), PANEL_BORDER, 1, 3))
	t.set_stylebox("panel", "TabContainer", panel)
	_theme = t
	return t


static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


static func bar(color: Color, height: float = 8.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.max_value = 1.0
	p.step = 0.0
	var fg := _box(color, Color(0, 0, 0, 0), 0, 2)
	p.add_theme_stylebox_override("fill", fg)
	return p

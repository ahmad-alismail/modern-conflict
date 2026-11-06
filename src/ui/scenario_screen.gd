extends PanelContainer
## Mission selection: briefing, forces and objectives for each fictional scenario.
class_name ScenarioScreen

var _brief: RichTextLabel
var _diff: OptionButton
var _sel := 0


func _ready() -> void:
	UITheme.place(self, Control.PRESET_CENTER_RIGHT, Vector2(-860, -330), Vector2(820, 660))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	vb.add_child(UITheme.label("SCENARIOS", 26, UITheme.ACCENT))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(260, 0)
	hb.add_child(list)
	var all := Scenarios.all()
	for i in all.size():
		var b := UITheme.button(all[i]["title"], func(): _select(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(250, 40)
		list.add_child(b)
	_brief = RichTextLabel.new()
	_brief.bbcode_enabled = true
	_brief.custom_minimum_size = Vector2(500, 520)
	_brief.add_theme_font_size_override("normal_font_size", 14)
	hb.add_child(_brief)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 12)
	vb.add_child(bottom)
	bottom.add_child(UITheme.label("Difficulty", 14, UITheme.TEXT_DIM))
	_diff = OptionButton.new()
	for d in ["Easy", "Medium", "Hard"]:
		_diff.add_item(d)
	_diff.select(1)
	bottom.add_child(_diff)
	bottom.add_child(UITheme.button("Back", queue_free))
	var start := UITheme.button("Start Mission", func():
		Events.navigate.emit("game", Scenarios.build(Scenarios.all()[_sel]["id"], ["easy", "medium", "hard"][_diff.selected])))
	start.custom_minimum_size = Vector2(200, 40)
	bottom.add_child(start)
	_select(0)


func _select(i: int) -> void:
	_sel = i
	var s: Dictionary = Scenarios.all()[i]
	_brief.text = "[font_size=22][color=#dbbd75]%s[/color][/font_size]\n[color=#a0a09a]%s[/color]\n\n%s\n\n[color=#dbbd75]Objectives[/color]\n%s\n\n[color=#dbbd75]Your forces[/color]\n%s" % [
		s["title"], s["subtitle"], s["briefing"], s["objectives_text"], s["forces_text"]]

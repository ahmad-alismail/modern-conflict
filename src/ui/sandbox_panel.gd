extends PanelContainer
## Sandbox controls: place any unit for either side, toggle the AI, change the
## time of day and weather live, remove units and switch which side you command.
class_name SandboxPanel

var session: GameSession
var _team := 0
var _faction := 0
var _list: VBoxContainer
var _team_btn: Button
var _ai_btn: Button
var _ctl_btn: Button
var _tod := 0
var _wx := 0

const TODS := ["day", "dawn", "dusk", "night"]
const WEATHERS := ["clear", "haze", "dust", "rain"]


func setup(s: GameSession) -> void:
	session = s
	UITheme.place(self, Control.PRESET_TOP_RIGHT, Vector2(-250, 96), Vector2(240, 0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	add_child(vb)
	vb.add_child(UITheme.label("SANDBOX", 16, UITheme.ACCENT))
	_team_btn = UITheme.button("", _toggle_team, "Which side new units join")
	vb.add_child(_team_btn)
	var fac := OptionButton.new()
	for f in Defs.FACTION_ORDER:
		fac.add_item(Defs.FACTIONS[f]["short"] + " — " + Defs.FACTIONS[f]["kind"])
	fac.item_selected.connect(func(i): _faction = i; _fill())
	vb.add_child(fac)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(230, 300)
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_ai_btn = UITheme.button("", _toggle_ai, "Let the classic AI command the red side")
	vb.add_child(_ai_btn)
	_ctl_btn = UITheme.button("", _toggle_control, "Switch which side you command")
	vb.add_child(_ctl_btn)
	vb.add_child(UITheme.button("Time of day ▸", func():
		_tod = (_tod + 1) % TODS.size()
		session.set_conditions(TODS[_tod], WEATHERS[_wx])
		session.hud.notice("Time: " + TODS[_tod])))
	vb.add_child(UITheme.button("Weather ▸", func():
		_wx = (_wx + 1) % WEATHERS.size()
		session.set_conditions(TODS[_tod], WEATHERS[_wx])
		session.hud.notice("Weather: " + WEATHERS[_wx])))
	vb.add_child(UITheme.button("Remove selected", func():
		session.issue({"type": "despawn", "ids": session.input.selected.duplicate()})))
	vb.add_child(UITheme.button("Toggle fog of war", func():
		session.view.fog.set_enabled(not session.view.fog.enabled)))
	_refresh()
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var fid: String = Defs.FACTION_ORDER[_faction]
	for id in Defs.units_of(fid):
		var d := Defs.unit(id)
		var b := UITheme.button(d["name"], func(): session.input.set_mode("spawn:%s:%d" % [id, _team]), d.get("role", ""))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		_list.add_child(b)


func _refresh() -> void:
	_team_btn.text = "Placing for: %s" % ("BLUE" if _team == 0 else "RED")
	_team_btn.add_theme_color_override("font_color", session.view.team_color(_team))
	_ai_btn.text = "Red AI: %s" % ("ON" if session.ai_enabled[1] else "OFF")
	_ctl_btn.text = "You command: %s" % ("BLUE" if session.player_team == 0 else "RED")


func _toggle_team() -> void:
	_team = 1 - _team
	_refresh()


func _toggle_ai() -> void:
	session.set_ai_enabled(1, not session.ai_enabled[1])
	_refresh()


func _toggle_control() -> void:
	session.switch_control(1 - session.player_team)
	_refresh()

extends PanelContainer
## Battle setup for Skirmish, AI vs AI and Sandbox: factions, commanders,
## difficulty, map (generated or custom), conditions and victory settings.
class_name SetupScreen

var kind := "skirmish"
var _f0: OptionButton
var _f1: OptionButton
var _c0: OptionButton
var _c1: OptionButton
var _map_opt: OptionButton
var _seed: SpinBox
var _tod: OptionButton
var _weather: OptionButton
var _war: HSlider
var _tickets: OptionButton
var _limit: OptionButton
var _preview: TextureRect
var _desc0: Label
var _desc1: Label
var _custom_maps: Array = []

const DIFFS := ["easy", "medium", "hard"]


func _init(p_kind: String) -> void:
	kind = p_kind


func _ready() -> void:
	UITheme.place(self, Control.PRESET_CENTER_RIGHT, Vector2(-820, -290), Vector2(780, 580))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	var titles := {"skirmish": "SKIRMISH", "aivai": "AI VS AI", "sandbox": "SANDBOX"}
	vb.add_child(UITheme.label(titles[kind], 26, UITheme.ACCENT))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	vb.add_child(cols)
	var left := GridContainer.new()
	left.columns = 2
	left.add_theme_constant_override("h_separation", 12)
	left.add_theme_constant_override("v_separation", 8)
	left.custom_minimum_size = Vector2(450, 0)
	cols.add_child(left)
	var right := VBoxContainer.new()
	cols.add_child(right)

	_f0 = _faction_opt(0)
	_f1 = _faction_opt(1)
	_row(left, "Blue side" if kind != "skirmish" else "Your faction", _f0)
	_desc0 = _desc_label()
	_row(left, "", _desc0)
	_row(left, "Red side" if kind != "skirmish" else "Enemy faction", _f1)
	_desc1 = _desc_label()
	_row(left, "", _desc1)
	_f0.item_selected.connect(func(_i): _update_desc())
	_f1.item_selected.connect(func(_i): _update_desc())
	if kind == "aivai":
		_c0 = _commander_opt()
		_row(left, "Blue commander", _c0)
	_c1 = _commander_opt() if kind == "aivai" else _difficulty_opt()
	_row(left, "Red commander" if kind == "aivai" else "Difficulty", _c1)
	_map_opt = OptionButton.new()
	_map_opt.add_item("Generated city")
	_custom_maps = SaveSystem.list("user://maps", ".json")
	for p in _custom_maps:
		_map_opt.add_item("Custom: " + p.get_file().get_basename())
	_map_opt.item_selected.connect(func(_i): _update_preview())
	_row(left, "Map", _map_opt)
	var seed_row := HBoxContainer.new()
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 99999
	_seed.value = randi() % 9999 + 1
	_seed.value_changed.connect(func(_v): _update_preview())
	seed_row.add_child(_seed)
	seed_row.add_child(UITheme.button("Random", func(): _seed.value = randi() % 9999 + 1))
	_row(left, "City seed", seed_row)
	_war = HSlider.new()
	_war.min_value = 0.0
	_war.max_value = 0.8
	_war.step = 0.05
	_war.value = 0.3
	_war.custom_minimum_size = Vector2(200, 20)
	_war.drag_ended.connect(func(_c): _update_preview())
	_row(left, "Prior war damage", _war)
	_tod = _opt(["Day", "Dawn", "Dusk", "Night"])
	_row(left, "Time of day", _tod)
	_weather = _opt(["Clear", "Haze", "Dust storm", "Rain"])
	_row(left, "Weather", _weather)
	_tickets = _opt(["300 (short)", "500 (standard)", "800 (long)"])
	_tickets.select(1)
	_row(left, "Tickets", _tickets)
	_limit = _opt(["None", "15 min", "30 min", "45 min"])
	_row(left, "Time limit", _limit)

	right.add_child(UITheme.label("Map preview", 13, UITheme.TEXT_DIM))
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(270, 270)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(_preview)
	var legend := UITheme.label("Blue deploys west, Red deploys east.\nCapture objectives A–E to drain enemy tickets;\nunit losses also cost tickets.", 12, UITheme.TEXT_DIM)
	right.add_child(legend)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(bottom)
	bottom.add_child(UITheme.button("Back", queue_free))
	var start := UITheme.button("Start Battle", _start)
	start.custom_minimum_size = Vector2(200, 40)
	start.add_theme_font_size_override("font_size", 18)
	bottom.add_child(start)
	_f1.select(1)
	_update_desc()
	_update_preview()


func _row(grid: GridContainer, label: String, ctl: Control) -> void:
	grid.add_child(UITheme.label(label, 14, UITheme.TEXT_DIM))
	grid.add_child(ctl)


func _opt(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.custom_minimum_size = Vector2(240, 0)
	return o


func _faction_opt(sel: int) -> OptionButton:
	var o := OptionButton.new()
	for f in Defs.FACTION_ORDER:
		o.add_item("%s (%s)" % [Defs.FACTIONS[f]["name"], Defs.FACTIONS[f]["kind"]])
	o.select(sel)
	o.custom_minimum_size = Vector2(300, 0)
	return o


func _difficulty_opt() -> OptionButton:
	var o := _opt(["Easy", "Medium", "Hard"])
	o.select(1)
	return o


func _commander_opt() -> OptionButton:
	var items := ["Classic AI — Easy", "Classic AI — Medium", "Classic AI — Hard"]
	if Settings.get_value("llm", "enabled"):
		items.append("LLM Commander (%s)" % Settings.get_value("llm", "provider"))
	var o := _opt(items)
	o.select(1)
	return o


func _desc_label() -> Label:
	var l := UITheme.label("", 12, UITheme.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _update_desc() -> void:
	_desc0.text = Defs.FACTIONS[Defs.FACTION_ORDER[_f0.selected]]["desc"]
	_desc1.text = Defs.FACTIONS[Defs.FACTION_ORDER[_f1.selected]]["desc"]


func _current_map() -> MapDef:
	if _map_opt.selected > 0:
		return MapDef.load_json(_custom_maps[_map_opt.selected - 1])
	return CityGenerator.generate(int(_seed.value), {"war_damage": _war.value})


func _update_preview() -> void:
	var m := _current_map()
	if m == null:
		return
	var img := Minimap.render_plan(m)
	for s in m.spawns:
		var r: Rect2 = s["rect"]
		var col := Color(0.35, 0.6, 1.0) if s["team"] == 0 else Color(1.0, 0.42, 0.28)
		var c0 := m.world_to_cell(r.position)
		var c1 := m.world_to_cell(r.end)
		for y in range(maxi(c0.y, 0), mini(c1.y, m.height)):
			for x in [maxi(c0.x, 0), mini(c1.x, m.width - 1)]:
				img.set_pixel(x, y, col)
	for o in m.objectives:
		var c := m.world_to_cell(o["p"])
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if m.in_bounds(c.x + dx, c.y + dy):
					img.set_pixel(c.x + dx, c.y + dy, Color(1, 0.9, 0.3))
	_preview.texture = ImageTexture.create_from_image(img)


func _commander_cfg(o: OptionButton) -> Dictionary:
	if o.selected >= 3:
		return {"controller": "llm"}
	return {"controller": "ai", "difficulty": DIFFS[o.selected]}


func _start() -> void:
	var f0: String = Defs.FACTION_ORDER[_f0.selected]
	var f1: String = Defs.FACTION_ORDER[_f1.selected]
	var opts := {
		"war_damage": _war.value,
		"tod": ["day", "dawn", "dusk", "night"][_tod.selected],
		"weather": ["clear", "haze", "dust", "rain"][_weather.selected],
		"tickets": [300, 500, 800][_tickets.selected],
		"time_limit": [0.0, 900.0, 1800.0, 2700.0][_limit.selected],
	}
	if _map_opt.selected > 0:
		opts["map"] = _current_map()
	var cfg: Dictionary
	match kind:
		"aivai":
			cfg = GameConfig.ai_vs_ai(f0, f1, _commander_cfg(_c0), _commander_cfg(_c1), int(_seed.value), opts)
		"sandbox":
			cfg = GameConfig.skirmish(f0, f1, DIFFS[_c1.selected], int(_seed.value), opts)
			cfg["mode"] = "sandbox"
			cfg["sandbox"] = true
			cfg["victory"] = "none"
			for t in cfg["teams"]:
				t["forces"] = []
				t["reinforcements"] = []
			cfg["teams"][1]["controller"] = "ai"
		_:
			cfg = GameConfig.skirmish(f0, f1, DIFFS[_c1.selected], int(_seed.value), opts)
	Events.navigate.emit("game", cfg)

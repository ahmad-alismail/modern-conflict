extends PanelContainer
## Pre-battle army composition for both sides: any number of each unit from the
## side's own faction roster, plus support-strike charges. Presets fill a side in
## one click. Emits `applied` with one {units, support} dict per side.
class_name ForceBuilder

signal applied(sides: Array)

const MAX_PER_TYPE := 25
const MAX_CHARGES := 9
const WARN_UNITS := 50

var _factions: Array = []
var _titles: Array = []
var _state: Array = [{}, {}]          # per side: {"units": {id: n}, "support": {power: n}}
var _count_labels: Array = [{}, {}]   # per side: key -> Label
var _summary: Array = []


## factions: [f0, f1]; titles: ["Your forces", "Enemy forces"]; current: [state or null, ...]
func setup(factions: Array, titles: Array, current: Array) -> void:
	_factions = factions
	_titles = titles
	for i in 2:
		_state[i] = current[i].duplicate(true) if current[i] != null else ForcePresets.get_preset(factions[i], "Default")
	_build()


func _build() -> void:
	UITheme.place(self, Control.PRESET_CENTER, Vector2(-770, -450), Vector2(1540, 900))
	add_theme_stylebox_override("panel", UITheme._box(UITheme.BG_SOLID, UITheme.PANEL_BORDER, 1, 4))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	vb.add_child(UITheme.label("FORCE BUILDER", 26, UITheme.ACCENT))
	var help := UITheme.label("Choose each side's army before the battle. Click + / − (Shift-click for 5). Air power comes from aircraft units and from support strikes called in during the battle.", 13, UITheme.TEXT_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.custom_minimum_size = Vector2(1480, 0)
	vb.add_child(help)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)
	for i in 2:
		cols.add_child(_side_column(i))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 12)
	vb.add_child(bottom)
	bottom.add_child(UITheme.button("Cancel", queue_free))
	var ok := UITheme.button("Apply", _apply)
	ok.custom_minimum_size = Vector2(180, 38)
	bottom.add_child(ok)
	for i in 2:
		_refresh(i)


func _side_column(i: int) -> Control:
	var fid: String = _factions[i]
	var fac: Dictionary = Defs.FACTIONS[fid]
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(735, 0)
	col.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_child(UITheme.label(_titles[i] + ":  ", 18, UITheme.TEXT))
	head.add_child(UITheme.label(fac["name"], 18, fac["color"]))
	col.add_child(head)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	prow.add_child(UITheme.label("Preset", 14, UITheme.TEXT_DIM))
	var preset := OptionButton.new()
	preset.custom_minimum_size = Vector2(260, 0)
	for n in ForcePresets.names(fid):
		preset.add_item(n)
	preset.item_selected.connect(func(idx: int):
		_state[i] = ForcePresets.get_preset(fid, preset.get_item_text(idx))
		_refresh(i))
	prow.add_child(preset)
	prow.add_child(UITheme.button("Clear", func():
		_state[i] = {"units": {}, "support": {}}
		_refresh(i)))
	col.add_child(prow)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(735, 660)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var groups := [["INFANTRY", Defs.CAT_INF], ["VEHICLES", Defs.CAT_VEH], ["AIRCRAFT & DRONES", Defs.CAT_AIR]]
	for g in groups:
		var ids := Defs.units_of(fid).filter(func(id): return Defs.unit(id)["cat"] == g[1])
		if ids.is_empty():
			continue
		list.add_child(UITheme.label(g[0], 13, UITheme.ACCENT))
		for id in ids:
			var d := Defs.unit(id)
			list.add_child(_row(i, "u:" + id, d["name"], _unit_tooltip(d)))
	list.add_child(UITheme.label("SUPPORT STRIKES (charges)", 13, UITheme.ACCENT))
	for pw in fac.get("support_options", fac["support"].keys()):
		var sd: Dictionary = Defs.SUPPORT[pw]
		list.add_child(_row(i, "s:" + pw, sd["name"], sd["desc"]))
	var sum := UITheme.label("", 14, UITheme.TEXT)
	col.add_child(sum)
	_summary.append(sum)
	return col


func _unit_tooltip(d: Dictionary) -> String:
	var weapons := []
	for wid in d["loadout"]:
		var wn: String = Defs.weapon(wid)["name"]
		if not weapons.has(wn):
			weapons.append(wn)
	var armor := "none" if d["armor"][0] <= 0 else "%d front / %d side / %d rear" % [d["armor"][0], d["armor"][1], d["armor"][2]]
	return "%s\nWeapons: %s\nArmor: %s · Sight %d m · Speed %d km/h" % [d.get("role", ""), ", ".join(weapons) if weapons.size() > 0 else "none",
		armor, int(d["sight"]), int(d["speed"] * 3.6)]


func _row(i: int, key: String, title: String, tip: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var name := UITheme.label(title, 14)
	name.custom_minimum_size = Vector2(430, 0)
	name.tooltip_text = tip
	name.mouse_filter = Control.MOUSE_FILTER_STOP
	hb.add_child(name)
	var minus := UITheme.button("−", func(): _change(i, key, -1))
	minus.custom_minimum_size = Vector2(40, 30)
	hb.add_child(minus)
	var count := UITheme.label("0", 16, UITheme.TEXT)
	count.custom_minimum_size = Vector2(44, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(count)
	var plus := UITheme.button("+", func(): _change(i, key, 1))
	plus.custom_minimum_size = Vector2(40, 30)
	hb.add_child(plus)
	_count_labels[i][key] = count
	return hb


func _change(i: int, key: String, delta: int) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		delta *= 5
	var bucket := "units" if key.begins_with("u:") else "support"
	var id := key.substr(2)
	var cap := MAX_PER_TYPE if bucket == "units" else MAX_CHARGES
	var dict: Dictionary = _state[i][bucket]
	dict[id] = clampi(int(dict.get(id, 0)) + delta, 0, cap)
	if dict[id] == 0:
		dict.erase(id)
	_refresh(i)


func _refresh(i: int) -> void:
	var units := 0
	var charges := 0
	for key in _count_labels[i]:
		var bucket := "units" if String(key).begins_with("u:") else "support"
		var n: int = int(_state[i][bucket].get(String(key).substr(2), 0))
		var lbl: Label = _count_labels[i][key]
		lbl.text = str(n)
		lbl.add_theme_color_override("font_color", UITheme.TEXT if n > 0 else UITheme.TEXT_DIM)
		if bucket == "units":
			units += n
		else:
			charges += n
	var text := "%d units · %d strike charges" % [units, charges]
	var col := UITheme.TEXT
	if units == 0:
		text += "  —  needs at least one unit"
		col = UITheme.ALERT
	elif units > WARN_UNITS:
		text += "  —  very large armies may lower performance"
		col = UITheme.WARN
	_summary[i].text = text
	_summary[i].add_theme_color_override("font_color", col)


func _apply() -> void:
	for i in 2:
		if _state[i]["units"].is_empty():
			Events.notice.emit("Each side needs at least one unit", "alert")
			return
	applied.emit(_state.duplicate(true))
	queue_free()


## Short human summary of a side's composition for the setup screen.
static func describe(state: Dictionary) -> String:
	var n := 0
	var veh := 0
	var air := 0
	for id in state["units"]:
		var c: int = state["units"][id]
		n += c
		match int(Defs.unit(id)["cat"]):
			Defs.CAT_VEH: veh += c
			Defs.CAT_AIR: air += c
	var charges := 0
	for k in state["support"]:
		charges += int(state["support"][k])
	return "%d units (%d vehicles, %d aircraft) · %d strikes" % [n, veh, air, charges]

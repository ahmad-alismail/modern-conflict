extends CanvasLayer
## In-game HUD: top bar (tickets, objectives, clock, speed, pause), minimap,
## selection panel, command card with support powers, message log, tactical
## pause banner, unit health overlay, pause menu and end-of-battle screen.
class_name Hud

var session: GameSession
var root: Control
var overlay: UnitOverlay
var minimap: Minimap
var _tickets: Array = []          # ProgressBar per team
var _ticket_labels: Array = []
var _obj_chips: Array = []
var _clock: Label
var _speed_label: Label
var _pause_banner: PanelContainer
var _sel_panel: PanelContainer
var _sel_box: VBoxContainer
var _cmd_grid: GridContainer
var _support_box: HBoxContainer
var _log: VBoxContainer
var _notice: Label
var _menu: Control
var _end: Control
var _mode_label: Label
var _refresh_t := 0.0
var _support_buttons: Dictionary = {}
var _reinforce_btn: Button
var _llm_panel: PanelContainer
var _llm_label: RichTextLabel
var _fps: Label


func setup(s: GameSession) -> void:
	session = s
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	overlay = UnitOverlay.new()
	overlay.setup(session)
	root.add_child(overlay)
	_build_top_bar()
	_build_bottom()
	_build_log()
	_build_pause_banner()
	_notice = UITheme.label("", 20, UITheme.ACCENT)
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.position = Vector2(-200, 110)
	_notice.size = Vector2(400, 30)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notice)
	_mode_label = UITheme.label("", 16, UITheme.WARN)
	_mode_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_mode_label.position = Vector2(-250, -250)
	_mode_label.size = Vector2(500, 24)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_mode_label)
	session.input.selection_changed.connect(func(_ids): _rebuild_selection())
	session.input.mode_changed.connect(_on_mode_changed)
	_rebuild_selection()
	on_speed_changed(session.speed)
	var has_llm := false
	for t in session.config["teams"]:
		has_llm = has_llm or t.get("controller", "") == "llm"
	if has_llm:
		_build_spectator_panel()
	_fps = UITheme.label("", 12, UITheme.TEXT_DIM)
	_fps.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fps.position = Vector2(10, 8)
	root.add_child(_fps)
	if session.replay.is_empty() and session.sim.tick == 0 and not DevHarness.has_arg("no-briefing"):
		show_briefing()


# ================================================================== layout ===

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.position = Vector2(-430, 6)
	bar.custom_minimum_size = Vector2(860, 0)
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	bar.add_child(hb)
	for ti in 2:
		var t: Dictionary = session.sim.teams[ti]
		var vb := VBoxContainer.new()
		vb.custom_minimum_size = Vector2(190, 0)
		var name := UITheme.label("%s%s" % [Defs.FACTIONS[t["faction"]]["short"], "  (You)" if ti == session.player_team else ""], 14, session.view.team_color(ti))
		vb.add_child(name)
		var pb := UITheme.bar(session.view.team_color(ti), 10)
		vb.add_child(pb)
		var lbl := UITheme.label("", 12, UITheme.TEXT_DIM)
		vb.add_child(lbl)
		_tickets.append(pb)
		_ticket_labels.append(lbl)
		if ti == 0:
			hb.add_child(vb)
		else:
			# objectives in the middle
			var mid := HBoxContainer.new()
			mid.add_theme_constant_override("separation", 6)
			mid.alignment = BoxContainer.ALIGNMENT_CENTER
			mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for o in session.sim.objectives:
				var chip := PanelContainer.new()
				chip.custom_minimum_size = Vector2(34, 34)
				chip.tooltip_text = o["name"]
				var l := UITheme.label(o["id"], 16)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				chip.add_child(l)
				chip.gui_input.connect(func(ev):
					if ev is InputEventMouseButton and ev.pressed:
						session.cam.look_at_point(Vector3(o["p"].x, 0, o["p"].y)))
				mid.add_child(chip)
				_obj_chips.append(chip)
			var center := VBoxContainer.new()
			center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			center.add_child(mid)
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			_clock = UITheme.label("00:00", 14)
			row.add_child(_clock)
			row.add_child(UITheme.label("   ", 12))
			for sp in [["II", 0.0], ["½", 0.5], ["1×", 1.0], ["2×", 2.0], ["4×", 4.0]]:
				var b := UITheme.button(sp[0], func():
					if sp[1] == 0.0:
						session.toggle_pause()
					else:
						if session.paused:
							session.set_paused(false)
						session.set_speed(sp[1]), "Pause (Space)" if sp[1] == 0.0 else "Game speed (+/-)")
				b.custom_minimum_size = Vector2(34, 0)
				b.add_theme_font_size_override("font_size", 12)
				row.add_child(b)
			_speed_label = UITheme.label("", 12, UITheme.ACCENT)
			row.add_child(_speed_label)
			var menu_b := UITheme.button("Menu", toggle_menu, "Esc")
			menu_b.add_theme_font_size_override("font_size", 12)
			row.add_child(menu_b)
			center.add_child(row)
			hb.add_child(center)
			hb.add_child(vb)
			name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			pb.fill_mode = ProgressBar.FILL_END_TO_BEGIN


func _build_bottom() -> void:
	var mm_panel := PanelContainer.new()
	mm_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mm_panel.position = Vector2(8, -278)
	root.add_child(mm_panel)
	minimap = Minimap.new()
	minimap.setup(session)
	mm_panel.add_child(minimap)

	_sel_panel = PanelContainer.new()
	_sel_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sel_panel.position = Vector2(-330, -178)
	_sel_panel.custom_minimum_size = Vector2(560, 170)
	root.add_child(_sel_panel)
	_sel_box = VBoxContainer.new()
	_sel_panel.add_child(_sel_box)

	var cmd := PanelContainer.new()
	cmd.visible = session.player_team >= 0
	cmd.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cmd.position = Vector2(-372, -238)
	cmd.custom_minimum_size = Vector2(364, 230)
	root.add_child(cmd)
	var vb := VBoxContainer.new()
	cmd.add_child(vb)
	vb.add_child(UITheme.label("ORDERS", 12, UITheme.TEXT_DIM))
	_cmd_grid = GridContainer.new()
	_cmd_grid.columns = 3
	vb.add_child(_cmd_grid)
	var orders := [
		["Attack-Move [T]", func(): session.input.set_mode("attack_move"), "Move and engage enemies on the way. Shortcut: Alt+right-click."],
		["Stop [X]", func(): session.input.order_simple("stop"), "Cancel all orders."],
		["Hold [H]", func(): session.input._key(_fake_key(KEY_H)), "Toggle hold position."],
		["Exit Bldg [G]", func(): session.input.order_simple("ungarrison"), "Leave the building."],
		["Unload [U]", func(): session.input.order_simple("unload"), "Unload passengers."],
		["Smoke [C]", func(): session.input.order_smoke(), "Smoke screen: vehicles pop smoke, infantry throw it."],
		["Retreat [R]", func(): session.input.order_simple("retreat"), "Fall back to the deployment zone at speed."],
		["Stance [V]", func(): session.input.cycle_stance(), "Fire at will / Return fire / Hold fire."],
		["Follow [F]", func(): session.input.toggle_follow(), "Cinematic follow camera."],
	]
	for o in orders:
		var b := UITheme.button(o[0], o[1], o[2])
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(112, 28)
		_cmd_grid.add_child(b)
	vb.add_child(UITheme.label("SUPPORT", 12, UITheme.TEXT_DIM))
	_support_box = HBoxContainer.new()
	vb.add_child(_support_box)
	_reinforce_btn = UITheme.button("", func(): session.issue({"type": "reinforce"}), "Call the next reinforcement wave [F5]")
	_reinforce_btn.add_theme_font_size_override("font_size", 12)
	vb.add_child(_reinforce_btn)
	rebuild_support()


## (Re)build the support-power buttons for the commanded team (sandbox can switch sides).
func rebuild_support() -> void:
	for c in _support_box.get_children():
		c.queue_free()
	_support_buttons.clear()
	_reinforce_btn.visible = session.player_team >= 0
	if session.player_team < 0:
		return
	var team: Dictionary = session.sim.teams[session.player_team]
	var keys: Array = team["support"].keys()
	for i in keys.size():
		var k: String = keys[i]
		var b := UITheme.button("", func(): session.input.set_mode("support:" + k), "%s [F%d]\n%s" % [Defs.SUPPORT[k]["name"], i + 1, Defs.SUPPORT[k]["desc"]])
		b.add_theme_font_size_override("font_size", 11)
		b.custom_minimum_size = Vector2(84, 40)
		_support_box.add_child(b)
		_support_buttons[k] = b


func _fake_key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


func _build_log() -> void:
	_log = VBoxContainer.new()
	_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log.position = Vector2(12, -470)
	_log.custom_minimum_size = Vector2(420, 180)
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_log)


func _build_pause_banner() -> void:
	_pause_banner = PanelContainer.new()
	_pause_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pause_banner.position = Vector2(-260, 78)
	_pause_banner.custom_minimum_size = Vector2(520, 0)
	var l := UITheme.label("TACTICAL PAUSE  —  issue orders, they execute on resume  [Space]", 15, UITheme.WARN)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_banner.add_child(l)
	_pause_banner.visible = false
	_pause_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pause_banner)


func _build_spectator_panel() -> void:
	_llm_panel = PanelContainer.new()
	_llm_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_llm_panel.position = Vector2(-420, 100)
	_llm_panel.custom_minimum_size = Vector2(410, 260)
	_llm_label = RichTextLabel.new()
	_llm_label.bbcode_enabled = true
	_llm_label.scroll_following = true
	_llm_label.custom_minimum_size = Vector2(390, 240)
	_llm_label.add_theme_font_size_override("normal_font_size", 13)
	_llm_panel.add_child(_llm_label)
	_llm_label.text = "[color=#d9bd75]COMMANDER FEED[/color]\n"
	root.add_child(_llm_panel)


func commander_log(team: int, text: String) -> void:
	if _llm_label == null:
		return
	# a human player must not read the enemy commander's plans; status lines are fine
	if session.player_team >= 0 and team != session.player_team and not text.begins_with("LLM"):
		return
	var col := session.view.team_color(team).to_html(false)
	_llm_label.append_text("[color=#%s]%s:[/color] %s\n" % [col, session.sim.teams[team]["name"], text])


# ================================================================= updates ===

func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.2
		_refresh_top()
		_refresh_selection_values()
		_refresh_support()
	_fps.text = ("%d FPS" % Engine.get_frames_per_second()) if Settings.get_value("graphics", "show_fps") else ""
	_pause_banner.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 250.0) if _pause_banner.visible else 1.0


func _refresh_top() -> void:
	var sim := session.sim
	for ti in 2:
		var t: Dictionary = sim.teams[ti]
		var start := float(session.config.get("tickets", 500))
		_tickets[ti].value = clampf(t["tickets"] / start, 0.0, 1.0)
		var alive := sim.team_units(ti).size()
		_ticket_labels[ti].text = "%d tickets · %d units" % [maxi(0, int(t["tickets"])), alive] if sim.mode == "vp" else "%d units" % alive
	for i in sim.objectives.size():
		var o: Dictionary = sim.objectives[i]
		var chip: PanelContainer = _obj_chips[i]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		var base := Color(0.2, 0.2, 0.2, 0.9) if o["owner"] < 0 else session.view.team_color(o["owner"]).darkened(0.35)
		sb.bg_color = base
		sb.border_color = Color(1, 0.85, 0.2) if o.get("contested", false) else Color(0, 0, 0, 0.6)
		sb.set_border_width_all(2)
		chip.add_theme_stylebox_override("panel", sb)
		chip.tooltip_text = "%s — %s" % [o["name"], "neutral" if o["owner"] < 0 else sim.teams[o["owner"]]["name"]]
	var t := int(sim.time)
	var lim := ""
	if sim.time_limit > 0.0:
		var rem := int(maxf(sim.time_limit - sim.time, 0.0))
		lim = "  (%02d:%02d left)" % [rem / 60, rem % 60]
	_clock.text = "%02d:%02d%s" % [t / 60, t % 60, lim]


func _refresh_support() -> void:
	if session.player_team < 0:
		return
	var team: Dictionary = session.sim.teams[session.player_team]
	for k in _support_buttons:
		if not team["support"].has(k):
			continue
		var s: Dictionary = team["support"][k]
		var b: Button = _support_buttons[k]
		var name: String = Defs.SUPPORT[k]["name"]
		var short := name.split(" ")[0]
		if s["cd"] > 0.0:
			b.text = "%s\n%ds" % [short, int(ceil(s["cd"]))]
		else:
			b.text = "%s\n×%d" % [short, s["charges"]]
		b.disabled = s["charges"] <= 0 or s["cd"] > 0.0
	if _reinforce_btn:
		var waves: int = team["waves"].size()
		_reinforce_btn.disabled = waves == 0 or team["wave_cd"] > 0.0
		_reinforce_btn.text = "Reinforcements: %d waves left%s" % [waves, ("  (%ds)" % int(ceil(team["wave_cd"]))) if team["wave_cd"] > 0.0 else ""]


func _rebuild_selection() -> void:
	for c in _sel_box.get_children():
		c.queue_free()
	var ids: Array = session.input.selected
	if ids.is_empty():
		_sel_box.add_child(UITheme.label("No units selected", 14, UITheme.TEXT_DIM))
		var hint := UITheme.label("Left-click / drag to select · Right-click to order · Hold right + drag to pan · Space = tactical pause\nRight-click building = garrison · Alt+right-click = attack-move · Ctrl+right-click = area fire", 12, UITheme.TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		_sel_box.add_child(hint)
		return
	if ids.size() == 1:
		_build_single(session.sim.by_id.get(ids[0]))
	else:
		_build_multi(ids)


func _build_single(u: SimUnit) -> void:
	if u == null:
		return
	var head := HBoxContainer.new()
	var title := UITheme.label(u.def["name"], 18, UITheme.ACCENT)
	head.add_child(title)
	var fac := UITheme.label("   " + Defs.FACTIONS[u.def["faction"]]["kind"], 12, UITheme.TEXT_DIM)
	head.add_child(fac)
	_sel_box.add_child(head)
	var role := UITheme.label(u.def.get("role", ""), 12, UITheme.TEXT_DIM)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD
	_sel_box.add_child(role)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	_sel_box.add_child(grid)
	var hp_l := UITheme.label("Health", 12)
	hp_l.name = "hp_l"
	grid.add_child(hp_l)
	var hp := UITheme.bar(UITheme.GOOD, 10)
	hp.name = "hp"
	hp.custom_minimum_size = Vector2(300, 10)
	grid.add_child(hp)
	if u.is_squad() and not u.is_robot():
		grid.add_child(UITheme.label("Morale", 12))
		var mo := UITheme.bar(Color(0.4, 0.7, 1.0), 8)
		mo.name = "morale"
		grid.add_child(mo)
		grid.add_child(UITheme.label("Suppression", 12))
		var su := UITheme.bar(UITheme.WARN, 8)
		su.name = "supp"
		grid.add_child(su)
	grid.add_child(UITheme.label("Ammo", 12))
	var am := UITheme.bar(Color(0.85, 0.8, 0.5), 8)
	am.name = "ammo"
	grid.add_child(am)
	var status := UITheme.label("", 13, UITheme.WARN)
	status.name = "status"
	_sel_box.add_child(status)
	var weapons := UITheme.label("", 12, UITheme.TEXT_DIM)
	weapons.name = "weapons"
	weapons.autowrap_mode = TextServer.AUTOWRAP_WORD
	_sel_box.add_child(weapons)
	_refresh_selection_values()


func _build_multi(ids: Array) -> void:
	_sel_box.add_child(UITheme.label("%d units selected" % ids.size(), 14, UITheme.ACCENT))
	var flow := HFlowContainer.new()
	_sel_box.add_child(flow)
	for id in ids:
		var u: SimUnit = session.sim.by_id.get(id)
		if u == null:
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = _abbrev(u.def["name"])
		b.tooltip_text = u.def["name"]
		b.custom_minimum_size = Vector2(62, 34)
		b.add_theme_font_size_override("font_size", 11)
		var frac := u.hp_frac()
		b.add_theme_color_override("font_color", UITheme.GOOD.lerp(UITheme.ALERT, 1.0 - frac))
		b.pressed.connect(func(): session.input.set_selection([id]))
		flow.add_child(b)


static func _abbrev(name: String) -> String:
	var parts := name.split(" ")
	if parts.size() == 1:
		return name.substr(0, 6)
	var s := ""
	for p in parts:
		s += p.substr(0, 3 if parts.size() == 2 else 2)
	return s.substr(0, 7)


func _refresh_selection_values() -> void:
	var ids: Array = session.input.selected
	if ids.size() != 1:
		return
	var u: SimUnit = session.sim.by_id.get(ids[0])
	if u == null or not u.alive:
		session.input.set_selection([])
		return
	var hp: ProgressBar = _sel_box.find_child("hp", true, false)
	if hp == null:
		return
	hp.value = u.hp_frac()
	var hp_l: Label = _sel_box.find_child("hp_l", true, false)
	if u.is_squad():
		hp_l.text = "Men %d/%d" % [u.alive_members(), u.members_hp.size()] if not u.is_robot() else "Units %d/%d" % [u.alive_members(), u.members_hp.size()]
	else:
		hp_l.text = "Health %d%%" % int(u.hp_frac() * 100)
	var mo: ProgressBar = _sel_box.find_child("morale", true, false)
	if mo:
		mo.value = u.morale / 100.0
	var su: ProgressBar = _sel_box.find_child("supp", true, false)
	if su:
		su.value = u.suppression / 100.0
	var am: ProgressBar = _sel_box.find_child("ammo", true, false)
	am.value = u.total_ammo_frac()
	var flags := []
	if u.team != session.player_team and session.player_team >= 0:
		flags.append("ENEMY")
	if u.broken: flags.append("BROKEN — falling back")
	elif u.pinned: flags.append("PINNED")
	if u.state == SimUnit.State.GARRISONED: flags.append("In building")
	if u.state == SimUnit.State.EMBARKED: flags.append("Embarked")
	if u.mobility >= 2: flags.append("IMMOBILIZED")
	elif u.mobility == 1: flags.append("Engine damaged")
	if u.firepower >= 2: flags.append("Main weapon destroyed")
	if u.burn_t > 0.0: flags.append("ON FIRE")
	if u.shaken_t > 0.0: flags.append("Crew stunned")
	if u.jammed_t > 0.0: flags.append("JAMMED")
	if not u.linked: flags.append("No network link (-accuracy)")
	if u.hold_pos: flags.append("Holding")
	if u.stance != 0: flags.append(["", "Return fire", "Hold fire"][u.stance])
	if u.cargo.size() > 0: flags.append("Carrying %d squad(s)" % u.cargo.size())
	if u.smoke_charges > 0: flags.append("Smoke ×%d" % u.smoke_charges)
	if u.kills > 0: flags.append("Kills: %d" % u.kills)
	var o := u.current_order()
	if not o.is_empty():
		flags.append("Order: %s" % String(o["o"]).replace("_", " "))
	(_sel_box.find_child("status", true, false) as Label).text = "  ·  ".join(flags)
	var wl := []
	for ws in u.weapons:
		if ws["holders"] <= 0:
			continue
		var cnt := (" ×%d" % ws["holders"]) if ws["holders"] > 1 else ""
		wl.append("%s%s (%d/%d)" % [ws["def"]["name"], cnt, ws["ammo"], ws["ammo_max"]])
	(_sel_box.find_child("weapons", true, false) as Label).text = "Weapons: " + ", ".join(wl) if wl.size() > 0 else "Unarmed"


# ================================================================== events ===

func handle_events(events: Array) -> void:
	var refresh_map := false
	for e in events:
		match e["t"]:
			"message":
				var team: int = e.get("team", -1)
				if team < 0 or team == session.player_team or session.player_team < 0:
					_add_log(e["text"], e.get("kind", "info"))
			"bld_collapsed":
				refresh_map = true
			"rejected":
				if e.get("team", -1) == session.player_team:
					notice(e.get("text", "Order not possible"))
			"spotted":
				if e["team"] == session.player_team and Settings.get_value("gameplay", "pause_on_contact") and not session.paused:
					session.set_paused(true)
					notice("Contact! Auto-paused")
	if refresh_map:
		minimap.refresh_plan()


func _add_log(text: String, kind: String) -> void:
	var col := UITheme.TEXT
	match kind:
		"good": col = UITheme.GOOD
		"warn": col = UITheme.WARN
		"alert": col = UITheme.ALERT
	var l := UITheme.label("%s  %s" % [_time_str(), text], 13, col)
	_log.add_child(l)
	while _log.get_child_count() > 7:
		_log.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func _time_str() -> String:
	var t := int(session.sim.time)
	return "[%02d:%02d]" % [t / 60, t % 60]


func notice(text: String) -> void:
	_notice.text = text
	_notice.modulate.a = 1.0
	var tw := _notice.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_notice, "modulate:a", 0.0, 0.6)


func on_pause_changed(p: bool) -> void:
	_pause_banner.visible = p


func on_speed_changed(s: float) -> void:
	if _speed_label:
		_speed_label.text = " %s× " % str(s)


func _on_mode_changed(m: String) -> void:
	match m:
		"": _mode_label.text = ""
		"attack_move": _mode_label.text = "ATTACK-MOVE: left-click destination (right-click to cancel)"
		"smoke": _mode_label.text = "SMOKE: left-click where to throw smoke"
		"attack_ground": _mode_label.text = "AREA FIRE: left-click target area"
		_:
			if m.begins_with("spawn:"):
				_mode_label.text = "PLACE %s: left-click to place, right-click to stop" % Defs.unit(m.split(":")[1])["name"].to_upper()
			elif m.begins_with("support:"):
				_mode_label.text = "%s: left-click target (right-click to cancel)" % Defs.SUPPORT[m.substr(8)]["name"].to_upper()


# ============================================================ menus/screens ===

func toggle_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
		return
	_menu = PanelContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.position = Vector2(-160, -180)
	_menu.custom_minimum_size = Vector2(320, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_menu.add_child(vb)
	vb.add_child(UITheme.label("BATTLE MENU", 20, UITheme.ACCENT))
	vb.add_child(UITheme.button("Resume", toggle_menu))
	if session.replay.is_empty():
		vb.add_child(UITheme.button("Save Game", func():
			var path := SaveSystem.save_session(session)
			notice("Saved: " + path.get_file())
			toggle_menu()))
	vb.add_child(UITheme.button("Settings", func():
		var s := SettingsMenu.new()
		root.add_child(s)
		toggle_menu()))
	vb.add_child(UITheme.button("Controls", func():
		toggle_menu()
		show_controls()))
	vb.add_child(UITheme.button("Toggle Fog of War view", func():
		session.view.fog.set_enabled(not session.view.fog.enabled)
		toggle_menu()))
	vb.add_child(UITheme.button("Quit to Main Menu", session.quit_to_menu))
	root.add_child(_menu)


## Mission/battle briefing shown at the start; the battle waits (paused) until dismissed.
func show_briefing() -> void:
	var cfg: Dictionary = session.config
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-330, -230)
	panel.custom_minimum_size = Vector2(660, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var sim := session.sim
	var title: String = cfg.get("title", "")
	if title == "":
		title = {"skirmish": "SKIRMISH", "aivai": "AI VS AI", "sandbox": "SANDBOX"}.get(cfg.get("mode", ""), "BATTLE")
	vb.add_child(UITheme.label(title, 26, UITheme.ACCENT))
	var env: Dictionary = cfg.get("env", {})
	vb.add_child(UITheme.label("%s · %s · %s" % [sim.map.name, String(env.get("tod", "day")).capitalize(), String(env.get("weather", "clear")).capitalize()], 14, UITheme.TEXT_DIM))
	var text := String(cfg.get("briefing", ""))
	if text == "":
		var pt := maxi(session.player_team, 0)
		text = "%s against %s. Capture objectives A–E to drain enemy tickets; every unit you lose costs tickets too." % [sim.teams[pt]["name"], sim.teams[1 - pt]["name"]]
		if cfg.get("sandbox", false):
			text = "Place units for either side from the panel on the right, set conditions and watch the simulation. No victory conditions."
		elif session.player_team < 0:
			text = "Two commanders fight it out. You are an observer: move the camera freely, select units to inspect them, change game speed."
	var body := UITheme.label(text, 15)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size = Vector2(620, 0)
	vb.add_child(body)
	if session.player_team >= 0:
		var fac: Dictionary = Defs.FACTIONS[sim.teams[session.player_team]["faction"]]
		var f := UITheme.label("Your force: %s — %s" % [fac["name"], fac["desc"]], 13, UITheme.TEXT_DIM)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD
		f.custom_minimum_size = Vector2(620, 0)
		vb.add_child(f)
	var tip := UITheme.label("Tip: press Space at any time for TACTICAL PAUSE. Give orders while paused; they execute when you resume.", 13, UITheme.WARN)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip.custom_minimum_size = Vector2(620, 0)
	vb.add_child(tip)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(UITheme.button("Controls", show_controls))
	var go := UITheme.button("Begin", func():
		panel.queue_free()
		session.set_paused(false))
	go.custom_minimum_size = Vector2(160, 38)
	hb.add_child(go)
	vb.add_child(hb)
	root.add_child(panel)
	session.set_paused(true)
	_pause_banner.visible = false


func show_controls() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-360, -290)
	panel.custom_minimum_size = Vector2(720, 0)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(UITheme.label("CONTROLS", 22, UITheme.ACCENT))
	var rows := [
		["Camera", "Hold right mouse + drag: pan · WASD / arrows / screen edge: pan · Mouse wheel: zoom (low zoom = cinematic) · Q/E or middle-drag: rotate · F: follow unit"],
		["Selection", "Left-click: select · Drag: box select · Shift: add/remove · Double-click / Ctrl+click: all of type on screen · Ctrl+1-9: assign group · 1-9: select group (double tap: center)"],
		["Orders", "Right-click: move / attack enemy / garrison building / board transport · Alt+right-click: attack-move · Ctrl+right-click: area fire (mortars) · Shift: queue orders"],
		["Commands", "T attack-move · X stop · H hold position · G leave building · U unload · C smoke · R retreat · V stance · Tab next idle unit · Home center"],
		["Support", "F1–F4: support powers (then click target) · F5: reinforcements"],
		["Time", "Space: tactical pause · + / -: game speed · Esc: menu / cancel"],
		["Tactics", "Infantry in buildings are hard to hit. Tanks fear close-range anti-tank teams. Suppressed troops get pinned and may break. Vehicles are weakest from the sides and rear. Smoke blocks line of sight."],
	]
	for r in rows:
		var hb := HBoxContainer.new()
		var k := UITheme.label(r[0], 14, UITheme.ACCENT)
		k.custom_minimum_size = Vector2(110, 0)
		hb.add_child(k)
		var v := UITheme.label(r[1], 13)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.custom_minimum_size = Vector2(580, 0)
		hb.add_child(v)
		vb.add_child(hb)
	vb.add_child(UITheme.button("Close", panel.queue_free))
	root.add_child(panel)


func show_end_screen(outcome: Dictionary) -> void:
	_end = PanelContainer.new()
	_end.set_anchors_preset(Control.PRESET_CENTER)
	_end.position = Vector2(-260, -200)
	_end.custom_minimum_size = Vector2(520, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_end.add_child(vb)
	var pt: int = outcome["player_team"]
	var title := "BATTLE OVER"
	var col := UITheme.ACCENT
	if pt >= 0:
		title = "VICTORY" if outcome["winner"] == pt else "DEFEAT"
		col = UITheme.GOOD if outcome["winner"] == pt else UITheme.ALERT
	else:
		title = "%s WINS" % session.sim.teams[outcome["winner"]]["name"].to_upper()
	vb.add_child(UITheme.label(title, 40, col))
	vb.add_child(UITheme.label(outcome["reason"], 16))
	var t := int(outcome["time"])
	vb.add_child(UITheme.label("Duration %02d:%02d" % [t / 60, t % 60], 14, UITheme.TEXT_DIM))
	for ti in 2:
		var st: Dictionary = outcome["stats"][ti]
		vb.add_child(UITheme.label("%s — units lost: %d · enemy units destroyed: %d" % [session.sim.teams[ti]["name"], st["lost"], st["killed"]], 14, session.view.team_color(ti)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	hb.add_child(UITheme.button("Save Replay", func():
		var path := SaveSystem.save_replay(outcome["replay"])
		notice("Replay saved: " + path.get_file())))
	hb.add_child(UITheme.button("Keep Watching", func(): _end.queue_free()))
	hb.add_child(UITheme.button("Main Menu", session.quit_to_menu))
	root.add_child(_end)
	if session.audio:
		session.audio.play_ui("ui_alert")

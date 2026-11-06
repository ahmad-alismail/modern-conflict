extends Control
## Screen-space overlay: health/member bars and status icons above units,
## the drag-selection box and a hover tooltip.
class_name UnitOverlay

var session: GameSession


func setup(s: GameSession) -> void:
	session = s
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := session.cam.camera
	var input: PlayerInput = session.input
	var always: bool = Settings.get_value("gameplay", "always_show_health")
	var font := get_theme_default_font()
	var vp := get_viewport_rect()
	for v in session.view.unit_views.values():
		var u: SimUnit = v.u
		if not u.alive or not v.model.visible:
			continue
		var sel: bool = input.selected.has(u.id)
		var hov: bool = input.hovered_unit == u.id
		var hurt := u.hp_frac() < 0.999
		var status := u.pinned or u.broken or u.mobility >= 2 or u.jammed_t > 0.0
		if not (sel or hov or always or hurt or status):
			continue
		var top: float = v.model.top_height() + (u.alt if u.is_air() else 0.0) + 0.6
		var wp := Vector3(u.pos.x, top, u.pos.y)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if not vp.grow(40).has_point(sp):
			continue
		var dist := cam.global_position.distance_to(wp)
		var w := clampf(900.0 / dist, 22.0, 54.0)
		var own := u.team == session.player_team or session.player_team < 0
		var base_col := session.view.team_color(u.team)
		var x0 := sp.x - w * 0.5
		var y0 := sp.y
		draw_rect(Rect2(x0 - 1, y0 - 1, w + 2, 6), Color(0, 0, 0, 0.6))
		if u.is_squad():
			var n := u.members_hp.size()
			var seg := w / n
			for i in n:
				var f: float = clampf(u.members_hp[i] / u.max_hp, 0.0, 1.0)
				var c := Color(0.35, 0.95, 0.45) if f > 0.5 else (Color(1, 0.8, 0.3) if f > 0.0 else Color(0.25, 0.25, 0.25))
				draw_rect(Rect2(x0 + i * seg + 0.5, y0, (seg - 1.0) * maxf(f, 0.0001 if f > 0.0 else 1.0), 4), c if f > 0.0 else c)
		else:
			var f := u.hp_frac()
			var c := Color(0.35, 0.95, 0.45).lerp(Color(1, 0.3, 0.25), 1.0 - f)
			draw_rect(Rect2(x0, y0, w * f, 4), c)
		# team marker
		draw_rect(Rect2(x0 - 5, y0 - 1, 3, 6), base_col)
		if u.is_squad() and not u.is_robot() and (sel or u.suppression > 15.0):
			draw_rect(Rect2(x0, y0 + 6, w * u.suppression / 100.0, 2), Color(1, 0.75, 0.3, 0.9))
		var icon := ""
		var icol := UITheme.WARN
		if u.broken:
			icon = "RETREAT"
			icol = UITheme.ALERT
		elif u.pinned:
			icon = "PINNED"
		elif u.mobility >= 2:
			icon = "IMMOBILE"
		elif u.jammed_t > 0.0:
			icon = "JAMMED"
		elif u.burn_t > 0.0:
			icon = "BURNING"
			icol = UITheme.ALERT
		if icon != "":
			draw_string(font, Vector2(x0, y0 - 4), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, icol)
		if hov and not sel:
			var txt: String = u.def["name"] + ("" if own else "  (enemy)")
			draw_string(font, Vector2(x0, y0 - (16 if icon != "" else 4)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT)
	# garrisoned buildings: show occupant count
	if session.player_team >= 0:
		for bi in session.sim.buildings.size():
			var g: Array = session.sim.buildings[bi]["garrison"]
			if g.is_empty():
				continue
			var gu: SimUnit = session.sim.by_id.get(g[0])
			if gu == null or (gu.team != session.player_team and (gu.vis_mask & (1 << session.player_team)) == 0):
				continue
			var b: Dictionary = session.sim.map.buildings[bi]
			var wp := Vector3(b["c"].x, session.sim.map.building_height(b) + 1.5, b["c"].y)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			var col := session.view.team_color(gu.team)
			draw_rect(Rect2(sp.x - 14, sp.y - 9, 28, 18), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(sp.x - 14, sp.y - 9, 28, 18), col, false, 1.5)
			draw_string(font, Vector2(sp.x - 9, sp.y + 5), "▣%d" % g.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# selection box
	if input.dragging and input.box_rect.size.length() > 2.0:
		draw_rect(input.box_rect, Color(0.4, 1.0, 0.5, 0.12))
		draw_rect(input.box_rect, Color(0.4, 1.0, 0.5, 0.8), false, 1.0)
	# building hover hint for garrison
	if input.hovered_building >= 0 and input.hovered_unit < 0:
		var mp := get_viewport().get_mouse_position()
		var cap := session.sim.building_capacity(input.hovered_building)
		var occ: int = session.sim.buildings[input.hovered_building]["garrison"].size()
		draw_string(font, mp + Vector2(16, 0), "Garrison (%d/%d)" % [occ, cap], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.85, 1.0))

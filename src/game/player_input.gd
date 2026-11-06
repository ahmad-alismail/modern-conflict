extends Node3D
## Player command input: unit selection (click, box, double-click, control groups),
## context-sensitive orders (move / attack / garrison / board), targeting modes
## (attack-move, smoke, area fire, support powers), hotkeys, and order feedback
## (destination markers and planned paths, especially useful during tactical pause).
class_name PlayerInput

signal selection_changed(ids: Array)
signal mode_changed(mode: String)

const CLICK_DRAG := 6.0

var session: GameSession
var selected: Array = []           # unit ids
var groups: Dictionary = {}        # digit -> Array of ids
var mode := ""                     # "", "attack_move", "smoke", "attack_ground", "support:<power>"
var hovered_unit := -1
var hovered_building := -1
var drag_start := Vector2.ZERO
var dragging := false
var box_rect := Rect2()
var _lmb_down := false
var _last_click_ms := 0
var _last_group_key := -1
var _last_group_ms := 0
var _paths: MeshInstance3D
var _imesh: ImmediateMesh
var _markers: Array = []
var _hover_timer := 0.0


func setup(s: GameSession) -> void:
	session = s
	process_mode = Node.PROCESS_MODE_ALWAYS
	_imesh = ImmediateMesh.new()
	_paths = MeshInstance3D.new()
	_paths.mesh = _imesh
	_paths.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	_paths.material_override = m
	add_child(_paths)


func sim() -> SimWorld:
	return session.sim


func set_mode(m: String) -> void:
	mode = m
	mode_changed.emit(m)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if m != "" else Input.CURSOR_ARROW)


func set_selection(ids: Array) -> void:
	for id in selected:
		var v: UnitView = session.view.unit_views.get(id)
		if v:
			v.set_ring(false, Color.WHITE)
	selected = []
	for id in ids:
		var u: SimUnit = sim().by_id.get(id)
		if u != null and u.alive and (u.team == session.player_team or session.player_team < 0):
			selected.append(id)
	if selected.is_empty() and ids.size() == 1:
		# allow inspecting a single visible enemy (no orders)
		var u: SimUnit = sim().by_id.get(ids[0])
		if u != null and u.alive and session.view._unit_visible(u):
			selected.append(ids[0])
	_refresh_rings()
	selection_changed.emit(selected)


func _refresh_rings() -> void:
	for id in selected:
		var v: UnitView = session.view.unit_views.get(id)
		var u: SimUnit = sim().by_id.get(id)
		if v and u:
			v.set_ring(true, _rel_color(u))


func _rel_color(u: SimUnit) -> Color:
	if session.player_team < 0:
		return session.view.team_color(u.team)
	return Color(0.35, 1.0, 0.45) if u.team == session.player_team else Color(1.0, 0.3, 0.25)


func own_selected() -> Array:
	var out := []
	for id in selected:
		var u: SimUnit = sim().by_id.get(id)
		if u != null and u.alive and u.team == session.player_team:
			out.append(u)
	return out


# ==================================================================== input ===

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_lmb_down = true
				drag_start = mb.position
				dragging = false
			elif _lmb_down:
				_lmb_down = false
				if dragging:
					_box_select(mb.shift_pressed)
				else:
					_left_click(mb.position, mb.shift_pressed, mb.ctrl_pressed)
				dragging = false
				box_rect = Rect2()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != "":
				set_mode("")
			else:
				_right_click(mb.position, mb.shift_pressed, mb.ctrl_pressed, mb.alt_pressed)
	elif event is InputEventMouseMotion:
		if _lmb_down and (event as InputEventMouseMotion).position.distance_to(drag_start) > CLICK_DRAG and mode == "":
			dragging = true
			var p := (event as InputEventMouseMotion).position
			box_rect = Rect2(drag_start, p - drag_start).abs()
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)


func _key(k: InputEventKey) -> void:
	var code := k.keycode
	if code >= KEY_0 and code <= KEY_9:
		var digit := code - KEY_0
		if k.ctrl_pressed:
			groups[digit] = selected.duplicate()
			session.hud.notice("Group %d assigned" % digit)
		else:
			var ids: Array = groups.get(digit, [])
			var now := Time.get_ticks_msec()
			if _last_group_key == digit and now - _last_group_ms < 350:
				_center_on_selection()
			_last_group_key = digit
			_last_group_ms = now
			if k.shift_pressed:
				var merged := selected.duplicate()
				for id in ids:
					if not merged.has(id):
						merged.append(id)
				set_selection(merged)
			else:
				set_selection(ids)
		get_viewport().set_input_as_handled()
		return
	match code:
		KEY_SPACE:
			session.toggle_pause()
		KEY_EQUAL, KEY_KP_ADD:
			session.step_speed(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			session.step_speed(-1)
		KEY_ESCAPE:
			if mode != "":
				set_mode("")
			elif not selected.is_empty():
				set_selection([])
			else:
				session.hud.toggle_menu()
		KEY_T:
			if not own_selected().is_empty():
				set_mode("attack_move")
		KEY_X:
			order_simple("stop")
		KEY_H:
			var any_hold := false
			for u in own_selected():
				any_hold = any_hold or u.hold_pos
			_issue({"type": "hold", "ids": selected.duplicate(), "value": not any_hold})
			session.hud.notice("Hold position %s" % ("off" if any_hold else "on"))
		KEY_G:
			order_simple("ungarrison")
		KEY_U:
			order_simple("unload")
		KEY_R:
			order_simple("retreat")
		KEY_C:
			order_smoke()
		KEY_V:
			cycle_stance()
		KEY_F:
			toggle_follow()
		KEY_HOME:
			_center_on_selection()
		KEY_F1, KEY_F2, KEY_F3, KEY_F4:
			var powers: Array = sim().teams[maxi(session.player_team, 0)]["support"].keys()
			var i := code - KEY_F1
			if session.player_team >= 0 and i < powers.size():
				set_mode("support:" + powers[i])
		KEY_F5:
			if session.player_team >= 0:
				session.issue({"type": "reinforce"})
		KEY_TAB:
			_select_idle()


func _issue(cmd: Dictionary) -> void:
	if session.player_team < 0:
		return
	session.issue(cmd)


func order_simple(type: String) -> void:
	var ids := []
	for u in own_selected():
		ids.append(u.id)
	if ids.is_empty():
		return
	_issue({"type": type, "ids": ids})
	if session.audio:
		session.audio.play_ui("ui_order")


func order_smoke() -> void:
	var inf := false
	var veh_ids := []
	for u in own_selected():
		if u.smoke_charges <= 0:
			continue
		if u.cat == Defs.CAT_VEH:
			veh_ids.append(u.id)
		else:
			inf = true
	if not veh_ids.is_empty():
		_issue({"type": "smoke", "ids": veh_ids})
	if inf:
		set_mode("smoke")
	elif veh_ids.is_empty():
		session.hud.notice("No smoke available")


func cycle_stance() -> void:
	var units := own_selected()
	if units.is_empty():
		return
	var s: int = (units[0].stance + 1) % 3
	var ids := []
	for u in units:
		ids.append(u.id)
	_issue({"type": "stance", "ids": ids, "value": s})
	session.hud.notice("Stance: %s" % ["Fire at will", "Return fire", "Hold fire"][s])


func toggle_follow() -> void:
	if session.cam.is_following():
		session.cam.follow(null)
		return
	if selected.is_empty():
		return
	var v: UnitView = session.view.unit_views.get(selected[0])
	if v:
		session.cam.follow(v)
		session.cam._t_dist = minf(session.cam._t_dist, 26.0)


func _center_on_selection() -> void:
	if selected.is_empty():
		return
	var c := Vector2.ZERO
	var n := 0
	for id in selected:
		var u: SimUnit = sim().by_id.get(id)
		if u != null and u.alive:
			c += u.pos
			n += 1
	if n > 0:
		c /= n
		session.cam.look_at_point(Vector3(c.x, 0, c.y))


func _select_idle() -> void:
	for u in sim().team_units(session.player_team):
		if u.orders.is_empty() and u.state == SimUnit.State.IDLE and not selected.has(u.id):
			set_selection([u.id])
			_center_on_selection()
			return


# =================================================================== clicks ===

func _left_click(pos: Vector2, shift: bool, ctrl: bool) -> void:
	if mode != "":
		_targeting_click(pos, shift)
		return
	var id := pick_unit(pos)
	var now := Time.get_ticks_msec()
	var dbl := now - _last_click_ms < 320
	_last_click_ms = now
	if id < 0:
		if not shift:
			set_selection([])
		return
	var u: SimUnit = sim().by_id[id]
	if (dbl or ctrl) and u.team == session.player_team:
		var same := []
		for v in session.view.unit_views.values():
			if v.u.def_id == u.def_id and v.u.team == u.team and _on_screen(v.u):
				same.append(v.u.id)
		set_selection(same)
		return
	if shift:
		var s := selected.duplicate()
		if s.has(id):
			s.erase(id)
		else:
			s.append(id)
		set_selection(s)
	else:
		set_selection([id])
	if session.audio:
		session.audio.play_ui("ui_select")


func _box_select(shift: bool) -> void:
	var ids := selected.duplicate() if shift else []
	var cam := session.cam.camera
	for v in session.view.unit_views.values():
		var u: SimUnit = v.u
		if u.team != session.player_team and session.player_team >= 0:
			continue
		if not u.is_active() and u.state != SimUnit.State.GARRISONED:
			continue
		var wp := Vector3(u.pos.x, u.alt + 0.8, u.pos.y)
		if cam.is_position_behind(wp):
			continue
		if box_rect.has_point(cam.unproject_position(wp)) and not ids.has(u.id):
			ids.append(u.id)
	set_selection(ids)
	if session.audio and not ids.is_empty():
		session.audio.play_ui("ui_select")


func _on_screen(u: SimUnit) -> bool:
	var cam := session.cam.camera
	var wp := Vector3(u.pos.x, 1, u.pos.y)
	if cam.is_position_behind(wp):
		return false
	return get_viewport().get_visible_rect().has_point(cam.unproject_position(wp))


func _right_click(pos: Vector2, shift: bool, ctrl: bool, alt: bool) -> void:
	var units := own_selected()
	if units.is_empty():
		return
	var ids := []
	for u in units:
		ids.append(u.id)
	var target := pick_unit(pos)
	var gp = session.cam.ground_point(pos)
	if target >= 0:
		var t: SimUnit = sim().by_id[target]
		if t.team != session.player_team:
			_issue({"type": "attack", "ids": ids, "target": target, "queue": shift})
			_marker(Vector3(t.pos.x, 0.1, t.pos.y), Color(1, 0.3, 0.2))
			_ack()
			return
		if t.def.get("transport", 0) > 0:
			var riders := []
			for u in units:
				if u.is_squad() and u.def.get("garrison", false) and u.id != t.id:
					riders.append(u.id)
			if not riders.is_empty():
				_issue({"type": "board", "ids": riders, "target": target, "queue": shift})
				_marker(Vector3(t.pos.x, 0.1, t.pos.y), Color(0.4, 0.8, 1.0))
				_ack()
				return
	var bi := pick_building(pos)
	if bi >= 0 and not ctrl:
		var garrisoners := []
		var others := []
		for u in units:
			if u.def.get("garrison", false) and u.is_squad():
				garrisoners.append(u.id)
			else:
				others.append(u.id)
		if not garrisoners.is_empty():
			_issue({"type": "garrison", "ids": garrisoners, "bld": bi, "queue": shift})
			var c: Vector2 = sim().map.buildings[bi]["c"]
			_marker(Vector3(c.x, 0.1, c.y), Color(0.4, 0.8, 1.0))
			if not others.is_empty():
				_issue({"type": "move", "ids": others, "pos": sim().building_entry_point(bi, units[0].pos), "queue": shift})
			_ack()
			return
	if gp == null:
		return
	var p := Vector2(gp.x, gp.z)
	if ctrl and _has_indirect(units):
		_issue({"type": "attack_ground", "ids": ids, "pos": p, "queue": shift})
		_marker(Vector3(p.x, 0.1, p.y), Color(1.0, 0.6, 0.2))
	else:
		_issue({"type": "attack_move" if alt else "move", "ids": ids, "pos": p, "queue": shift})
		_marker(Vector3(p.x, 0.1, p.y), Color(1.0, 0.5, 0.3) if alt else Color(0.4, 1.0, 0.5))
	_ack()


func _has_indirect(units: Array) -> bool:
	for u in units:
		for ws in u.weapons:
			if ws["def"].get("indirect", false):
				return true
	return false


func _targeting_click(pos: Vector2, shift: bool) -> void:
	var gp = session.cam.ground_point(pos)
	if gp == null:
		return
	var p := Vector2(gp.x, gp.z)
	var ids := []
	for u in own_selected():
		ids.append(u.id)
	if mode == "attack_move":
		_issue({"type": "attack_move", "ids": ids, "pos": p, "queue": shift})
		_marker(Vector3(p.x, 0.1, p.y), Color(1.0, 0.5, 0.3))
	elif mode == "smoke":
		var inf := []
		for u in own_selected():
			if u.cat == Defs.CAT_INF and u.smoke_charges > 0:
				inf.append(u.id)
		_issue({"type": "smoke", "ids": inf, "pos": p})
	elif mode == "attack_ground":
		_issue({"type": "attack_ground", "ids": ids, "pos": p, "queue": shift})
	elif mode.begins_with("spawn:"):
		var parts := mode.split(":")
		session.issue({"type": "spawn", "def": parts[1], "spawn_team": int(parts[2]), "pos": p})
		return
	elif mode.begins_with("support:"):
		var power := mode.substr(8)
		var dir := session.cam.forward_2d()
		session.issue({"type": "support", "power": power, "pos": p, "dir": dir})
		_marker(Vector3(p.x, 0.1, p.y), Color(1.0, 0.85, 0.2), Defs.SUPPORT[power]["radius"])
	_ack()
	if not shift:
		set_mode("")


func _ack() -> void:
	if session.audio:
		session.audio.play_ui("ui_order")


# ================================================================== picking ===

func pick_unit(pos: Vector2) -> int:
	var cam := session.cam.camera
	var best := -1
	var best_d := 1e9
	for v in session.view.unit_views.values():
		var u: SimUnit = v.u
		if not u.alive or not v.model.visible:
			continue
		var wp := Vector3(u.pos.x, (u.alt if u.is_air() else 0.0) + 0.8, u.pos.y)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var r_world: float = u.def["radius"] * (1.0 if u.is_squad() else 0.8)
		var edge := cam.unproject_position(wp + cam.global_transform.basis.x * r_world)
		var r_px := maxf(sp.distance_to(edge), 14.0)
		var d := sp.distance_to(pos)
		if d < r_px and d < best_d:
			best_d = d
			best = u.id
	return best


## Ray test against building boxes (handles clicks on walls, not just the ground).
func pick_building(pos: Vector2) -> int:
	var cam := session.cam.camera
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	var best := -1
	var best_t := 1e9
	var m := sim().map
	for i in m.buildings.size():
		if sim().buildings[i]["state"] == 2:
			continue
		var b: Dictionary = m.buildings[i]
		var h := m.building_height(b)
		var half: Vector2 = b["size"] * 0.5
		var c: Vector2 = b["c"]
		var aabb := AABB(Vector3(c.x - half.x, 0, c.y - half.y), Vector3(half.x * 2.0, h, half.y * 2.0))
		var hit = aabb.intersects_ray(o, d)
		if hit != null:
			var t: float = (hit as Vector3).distance_to(o)
			if t < best_t:
				best_t = t
				best = i
	return best


# ================================================================ feedback ====

func _marker(p: Vector3, col: Color, radius: float = 2.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2.ONE
	mi.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/render/shaders/ring.gdshader")
	mat.set_shader_parameter("color", col)
	mat.render_priority = 10
	mi.material_override = mat
	mi.position = p
	mi.scale = Vector3.ONE * radius * 2.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.6, 0.6)
	tw.parallel().tween_method(func(a: float): mat.set_shader_parameter("color", Color(col.r, col.g, col.b, a)), 1.0, 0.0, 0.6)
	tw.tween_callback(mi.queue_free)


func _process(delta: float) -> void:
	_hover_timer -= delta
	if _hover_timer <= 0.0:
		_hover_timer = 0.06
		_update_hover()
	_draw_paths()


func _update_hover() -> void:
	var mp := get_viewport().get_mouse_position()
	var id := pick_unit(mp)
	if id != hovered_unit:
		var old: UnitView = session.view.unit_views.get(hovered_unit)
		if old:
			old.set_hover(false, Color.WHITE)
		hovered_unit = id
		var nv: UnitView = session.view.unit_views.get(id)
		if nv:
			nv.set_hover(true, _rel_color(nv.u))
	hovered_building = pick_building(mp) if id < 0 and not own_selected().is_empty() else -1


func _draw_paths() -> void:
	_imesh.clear_surfaces()
	var units := own_selected()
	if units.is_empty():
		return
	var any := false
	for u in units:
		if u.path.size() == 0 and u.orders.size() <= 1:
			continue
		if not any:
			_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
			any = true
		var col := Color(0.4, 1.0, 0.5, 0.75) if not u.attack_move else Color(1.0, 0.55, 0.3, 0.75)
		var prev := Vector3(u.pos.x, 0.25, u.pos.y)
		for i in range(u.path_i, u.path.size()):
			var p := Vector3(u.path[i].x, 0.25, u.path[i].y)
			_imesh.surface_set_color(col)
			_imesh.surface_add_vertex(prev)
			_imesh.surface_set_color(col)
			_imesh.surface_add_vertex(p)
			prev = p
		# queued orders
		for k in range(1, u.orders.size()):
			var o: Dictionary = u.orders[k]
			if o.has("pos"):
				var p := Vector3(o["pos"].x, 0.25, o["pos"].y)
				_imesh.surface_set_color(Color(1, 1, 0.5, 0.5))
				_imesh.surface_add_vertex(prev)
				_imesh.surface_set_color(Color(1, 1, 0.5, 0.5))
				_imesh.surface_add_vertex(p)
				prev = p
	if any:
		_imesh.surface_end()

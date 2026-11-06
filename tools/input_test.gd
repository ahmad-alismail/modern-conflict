extends Node
## Dev harness (--input-test): drives PlayerInput with synthetic mouse/keyboard events
## and prints PASS/FAIL lines, then quits.

var session: GameSession
var _t := 0.0
var _step := 0
var _results: Array = []
var _focus_before := Vector3.ZERO
var _cmds_before := 0


func _process(delta: float) -> void:
	_t += delta
	match _step:
		0:
			if _t > 2.0:
				_box_select()
				_step = 1
		1:
			if _t > 2.6:
				_check(session.input.selected.size() > 0, "box select picked %d units" % session.input.selected.size())
				_key(KEY_SPACE)
				_step = 2
		2:
			if _t > 3.0:
				_check(session.paused, "space toggles tactical pause")
				var target := get_viewport().get_visible_rect().size * Vector2(0.5, 0.35)
				_click(target, MOUSE_BUTTON_RIGHT)
				_step = 3
		3:
			if _t > 3.6:
				var ordered := 0
				for id in session.input.selected:
					var u: SimUnit = session.sim.by_id.get(id)
					if u != null and not u.orders.is_empty():
						ordered += 1
				_check(ordered == 0, "orders wait during pause (applied on resume)")
				_check(session.sim.pending.size() > 0, "order queued while paused (%d pending)" % session.sim.pending.size())
				_key(KEY_SPACE)
				_step = 4
		4:
			if _t > 4.6:
				var moving := 0
				for id in session.input.selected:
					var u: SimUnit = session.sim.by_id.get(id)
					if u != null and (u.state == SimUnit.State.MOVING or not u.orders.is_empty()):
						moving += 1
				_check(moving > 0, "units execute the order after resume (%d moving)" % moving)
				_key(KEY_EQUAL)
				_step = 5
		5:
			if _t > 5.0:
				_check(session.speed > 1.0, "speed up hotkey (speed %s)" % session.speed)
				_key(KEY_X)
				_step = 6
		6:
			if _t > 5.6:
				# hold right mouse + drag: camera pans, no order is issued
				_focus_before = session.cam._t_focus
				_cmds_before = session.sim.command_log.size() + session.sim.pending.size()
				var c := get_viewport().get_visible_rect().size * 0.5
				_mouse(c, MOUSE_BUTTON_RIGHT, true)
				for k in range(1, 11):
					var mm := InputEventMouseMotion.new()
					mm.position = c + Vector2(k * 25.0, k * 8.0)
					mm.global_position = mm.position
					mm.button_mask = MOUSE_BUTTON_MASK_RIGHT
					Input.parse_input_event(mm)
				_mouse(c + Vector2(250, 80), MOUSE_BUTTON_RIGHT, false)
				_step = 7
		7:
			if _t > 6.2:
				var moved: float = session.cam._t_focus.distance_to(_focus_before)
				_check(moved > 5.0, "right-drag pans the camera (%.1f m)" % moved)
				var cmds := session.sim.command_log.size() + session.sim.pending.size()
				_check(cmds == _cmds_before, "right-drag does not issue an order")
				_step = 8
		8:
			if _t > 6.6:
				print("[input-test] done: %d checks, %d failed" % [_results.size(), _results.count(false)])
				get_tree().quit()


func _check(ok: bool, msg: String) -> void:
	_results.append(ok)
	print("[input-test] %s %s" % ["PASS" if ok else "FAIL", msg])


func _box_select() -> void:
	var cam := session.cam.camera
	var pts := []
	for u in session.sim.team_units(session.player_team):
		pts.append(cam.unproject_position(Vector3(u.pos.x, 0.8, u.pos.y)))
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	r = r.grow(20)
	_mouse(r.position, MOUSE_BUTTON_LEFT, true)
	var mm := InputEventMouseMotion.new()
	mm.position = r.end
	mm.global_position = r.end
	Input.parse_input_event(mm)
	_mouse(r.end, MOUSE_BUTTON_LEFT, false)


func _click(p: Vector2, button: MouseButton) -> void:
	_mouse(p, button, true)
	_mouse(p, button, false)


func _mouse(p: Vector2, button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)

extends Node3D
## RTS camera: pan (WASD / arrows / edge scroll / middle-drag), rotate (Q/E, Alt+middle-drag),
## zoom to cursor that pitches smoothly from a strategic top-down view to a low cinematic
## angle, unit follow mode, and screen shake. Runs on real time (unaffected by pause).
class_name CameraRig

signal view_changed(distance: float)

const MIN_DIST := 9.0
const MAX_DIST := 320.0

var camera: Camera3D
var bounds := Rect2(0, 0, 480, 480)
var focus := Vector3(240, 0, 240)
var yaw := deg_to_rad(-90.0)
var dist := 140.0
var _t_focus := focus
var _t_yaw := yaw
var _t_dist := dist
var _follow: Node3D
var _drag_rotate := false
var _drag_pan := false
var _last_mouse := Vector2.ZERO
## Right-button drag pans ("grab the map"). A right click without dragging stays an order;
## PlayerInput checks `rmb_dragged` on release to tell the two apart.
var rmb_dragged := false
var _rmb_down := false
var _rmb_start := Vector2.ZERO
var _rmb_last := Vector2.ZERO
const RMB_DRAG_PX := 6.0
var _shake := 0.0
var _shake_t := 0.0
var _last_us := 0
var input_enabled := true
## Optional Callable(Vector2) -> float giving obstacle height at a map point (camera rises over roofs).
var height_query: Callable
var _lift := 0.0
var cinematic := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.near = 0.3
	camera.far = 3500.0
	add_child(camera)
	camera.current = true
	_last_us = Time.get_ticks_usec()
	_apply()


func setup(map_bounds: Rect2, start: Vector3, start_yaw: float, start_dist: float = 140.0) -> void:
	bounds = map_bounds
	focus = start
	_t_focus = start
	yaw = start_yaw
	_t_yaw = start_yaw
	dist = start_dist
	_t_dist = start_dist
	_apply()


func pitch_for(d: float) -> float:
	var t := clampf((d - MIN_DIST) / (MAX_DIST - MIN_DIST), 0.0, 1.0)
	return deg_to_rad(lerpf(9.0, 62.0, pow(t, 0.5)))


func look_at_point(p: Vector3, d: float = -1.0) -> void:
	_follow = null
	_t_focus = Vector3(p.x, 0, p.z)
	if d > 0.0:
		_t_dist = clampf(d, MIN_DIST, MAX_DIST)


func follow(n: Node3D) -> void:
	_follow = n


func is_following() -> bool:
	return _follow != null and is_instance_valid(_follow)


func shake(strength: float, at: Vector3) -> void:
	var d := at.distance_to(camera.global_position)
	var s := strength * clampf(1.0 - d / 260.0, 0.0, 1.0)
	_shake = maxf(_shake, s)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				if Settings.get_value("gameplay", "invert_zoom"):
					dir = -dir
				_zoom(dir * mb.factor if mb.factor > 0.0 else dir, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rmb_down = true
				rmb_dragged = false
				_rmb_start = mb.position
				_rmb_last = mb.position
			else:
				_rmb_down = false
				if rmb_dragged:
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_rotate = mb.pressed and not mb.shift_pressed
			_drag_pan = mb.pressed and mb.shift_pressed
			_last_mouse = mb.position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rmb_down:
			if not rmb_dragged and mm.position.distance_to(_rmb_start) > RMB_DRAG_PX:
				rmb_dragged = true
				_follow = null
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			if rmb_dragged:
				_grab_pan(_rmb_last, mm.position)
				_rmb_last = mm.position
			return
		if _drag_rotate:
			_t_yaw -= mm.relative.x * 0.006 * float(Settings.get_value("gameplay", "rotate_speed"))
			_t_dist = clampf(_t_dist * (1.0 + mm.relative.y * 0.004), MIN_DIST, MAX_DIST)
		elif _drag_pan:
			var right := Vector3(cos(yaw + PI * 0.5), 0, sin(yaw + PI * 0.5))
			var fwd := Vector3(cos(yaw), 0, sin(yaw))
			_t_focus -= (right * mm.relative.x - fwd * mm.relative.y) * dist * 0.0018
			_follow = null
	elif event is InputEventMagnifyGesture:
		_zoom((1.0 - (event as InputEventMagnifyGesture).factor) * 4.0, get_viewport().get_mouse_position())


## Move the camera so the ground point under `from` ends up under `to` (map follows the cursor).
func _grab_pan(from: Vector2, to: Vector2) -> void:
	var a = ground_point(from)
	var b = ground_point(to)
	if a == null or b == null:
		return
	var d: Vector3 = a - b
	d.y = 0.0
	_t_focus += d
	focus += d
	_apply()


func _zoom(amount: float, mouse: Vector2) -> void:
	var before = ground_point(mouse)
	var nd := clampf(_t_dist * pow(1.15, amount), MIN_DIST, MAX_DIST)
	if before != null and not is_following():
		# zoom toward the cursor
		var k := 1.0 - nd / _t_dist
		var bp: Vector3 = before
		_t_focus += (Vector3(bp.x, 0, bp.z) - _t_focus) * k * 0.9
	_t_dist = nd


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.1)
	_last_us = now
	if input_enabled:
		_keyboard(dt)
	if is_following():
		_t_focus = Vector3(_follow.global_position.x, 0, _follow.global_position.z)
	_t_focus.x = clampf(_t_focus.x, bounds.position.x, bounds.end.x)
	_t_focus.z = clampf(_t_focus.z, bounds.position.y, bounds.end.y)
	var k := 1.0 - exp(-dt * 10.0)
	focus = focus.lerp(_t_focus, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	dist = lerpf(dist, _t_dist, 1.0 - exp(-dt * 8.0))
	_shake_t += dt
	_shake = maxf(0.0, _shake - dt * 2.5)
	_apply()


func _keyboard(dt: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1
	if (Input.is_key_pressed(KEY_S) and not Input.is_key_pressed(KEY_CTRL)) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Settings.get_value("gameplay", "edge_scroll") and DisplayServer.window_is_focused():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		var edge := 6.0
		if mp.x >= 0 and mp.y >= 0 and mp.x <= vs.x and mp.y <= vs.y:
			if mp.x < edge: move.x -= 1
			if mp.x > vs.x - edge: move.x += 1
			if mp.y < edge: move.y += 1
			if mp.y > vs.y - edge: move.y -= 1
	if move != Vector2.ZERO:
		_follow = null
		var speed := (30.0 + dist * 1.3) * float(Settings.get_value("gameplay", "scroll_speed"))
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= 2.0
		var fwd := Vector3(cos(yaw), 0, sin(yaw))
		var right := Vector3(cos(yaw + PI * 0.5), 0, sin(yaw + PI * 0.5))
		_t_focus += (fwd * move.y + right * move.x).normalized() * speed * dt
	var rs := 1.6 * float(Settings.get_value("gameplay", "rotate_speed"))
	if Input.is_key_pressed(KEY_Q):
		_t_yaw += rs * dt
	if Input.is_key_pressed(KEY_E):
		_t_yaw -= rs * dt
	if Input.is_key_pressed(KEY_PAGEUP):
		_t_dist = clampf(_t_dist * (1.0 - dt * 1.5), MIN_DIST, MAX_DIST)
	if Input.is_key_pressed(KEY_PAGEDOWN):
		_t_dist = clampf(_t_dist * (1.0 + dt * 1.5), MIN_DIST, MAX_DIST)


func _apply() -> void:
	if camera == null:
		return
	var pitch := pitch_for(dist)
	# camera sits behind the focus point (opposite to the yaw "forward" direction)
	var back := Vector3(-cos(yaw) * cos(pitch), sin(pitch), -sin(yaw) * cos(pitch))
	var look_at_pt := focus + Vector3(0, lerpf(1.2, 0.0, clampf(dist / 60.0, 0.0, 1.0)), 0)
	var pos := look_at_pt + back * dist
	if _shake > 0.0:
		pos += Vector3(sin(_shake_t * 61.0), sin(_shake_t * 47.0 + 1.3), cos(_shake_t * 53.0)) * _shake * 0.6
	if height_query.is_valid():
		var h := 0.0
		for off in [Vector2.ZERO, Vector2(2.5, 0), Vector2(-2.5, 0), Vector2(0, 2.5), Vector2(0, -2.5)]:
			h = maxf(h, float(height_query.call(Vector2(pos.x, pos.z) + off)))
		_lift = lerpf(_lift, maxf(0.0, h + 2.5 - pos.y), 0.25)
		pos.y += _lift
	pos.y = maxf(pos.y, 1.5)
	camera.look_at_from_position(pos, look_at_pt, Vector3.UP)
	view_changed.emit(dist)


## Ground-plane intersection under a screen position (null if none).
func ground_point(screen: Vector2) -> Variant:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return null
	var t := -o.y / d.y
	if t < 0.0:
		return null
	return o + d * t


func forward_2d() -> Vector2:
	return Vector2(cos(yaw), sin(yaw))

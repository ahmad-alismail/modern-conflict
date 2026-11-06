extends Node
## Player-side fog of war: per-cell viewshed computed with radial ray marching
## against the building/wall height grid (so buildings cast real vision shadows),
## with explored memory, smoothed over time and uploaded as a texture that a
## full-screen post pass (fog_post.gdshader) and the minimap use.
class_name FogOfWar

const CELL := 4.0
const UNEXPLORED := 0.16
const EXPLORED := 0.5
const UPDATE_DT := 0.2

var sim: SimWorld
var team := 0
var enabled := true
var gw := 0
var gh := 0
var display := PackedFloat32Array()
var explored := PackedByteArray()
var visible_now := PackedByteArray()
var image: Image
var texture: ImageTexture
var _timer := 0.0
var _smooth_acc := 0.0
var _post: MeshInstance3D


func setup(world: SimWorld, p_team: int) -> void:
	sim = world
	team = p_team
	enabled = team >= 0
	var size := sim.map.size_m()
	gw = int(ceil(size.x / CELL))
	gh = int(ceil(size.y / CELL))
	display.resize(gw * gh)
	display.fill(UNEXPLORED if enabled else 1.0)
	explored.resize(gw * gh)
	visible_now.resize(gw * gh)
	image = Image.create(gw, gh, false, Image.FORMAT_L8)
	image.fill(Color(display[0], display[0], display[0]))
	texture = ImageTexture.create_from_image(image)
	_recompute()
	for i in display.size():
		display[i] = 1.0 if visible_now[i] else (EXPLORED if explored[i] else UNEXPLORED)
	_upload()


## Attach the full-screen fog pass to the active camera.
func attach_to_camera(cam: Camera3D) -> void:
	_post = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	_post.mesh = q
	_post.extra_cull_margin = 16384.0
	_post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/render/shaders/fog_post.gdshader")
	mat.set_shader_parameter("fog_tex", texture)
	mat.set_shader_parameter("map_size", sim.map.size_m())
	mat.set_shader_parameter("texel", 1.0 / gw)
	_post.material_override = mat
	_post.visible = enabled
	cam.add_child(_post)


func set_enabled(on: bool) -> void:
	enabled = on and team >= 0
	if _post:
		_post.visible = enabled


func update(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_DT
		_recompute()
	_smooth_acc += delta
	if _smooth_acc < 1.0 / 30.0:
		return
	var k := 1.0 - exp(-_smooth_acc * 6.0)
	_smooth_acc = 0.0
	for i in display.size():
		var t := 1.0 if visible_now[i] else (EXPLORED if explored[i] else UNEXPLORED)
		display[i] += (t - display[i]) * k
	_upload()


func _upload() -> void:
	var data := PackedByteArray()
	data.resize(display.size())
	for i in display.size():
		data[i] = int(clampf(display[i], 0.0, 1.0) * 255.0)
	image.set_data(gw, gh, false, Image.FORMAT_L8, data)
	texture.update(image)


func is_cell_visible(p: Vector2) -> bool:
	if not enabled:
		return true
	var cx := clampi(int(p.x / CELL), 0, gw - 1)
	var cy := clampi(int(p.y / CELL), 0, gh - 1)
	return visible_now[cy * gw + cx] != 0


func _recompute() -> void:
	visible_now.fill(0)
	for u in sim.units:
		if u.team != team or not u.is_active():
			continue
		if u.is_air() and u.jammed_t > 0.0:
			continue
		var r: float = u.def["sight"] * sim.sight_mult(u)
		if u.has_special("sensor_mast") and u.stationary_t > 3.0:
			r = 175.0 * sim.sight_mult(u)
		_stamp(u.pos if u.garrison_bld < 0 else u.pos, sim.garrison_eye(u), r, u.garrison_bld)
	for rv in sim.reveals:
		if rv["team"] == team:
			_stamp_circle(rv["p"], rv["r"])


func _stamp_circle(c: Vector2, r: float) -> void:
	var cr := int(ceil(r / CELL))
	var cx := int(c.x / CELL)
	var cy := int(c.y / CELL)
	for y in range(maxi(cy - cr, 0), mini(cy + cr + 1, gh)):
		for x in range(maxi(cx - cr, 0), mini(cx + cr + 1, gw)):
			if Vector2((x + 0.5) * CELL, (y + 0.5) * CELL).distance_to(c) <= r:
				var i := y * gw + x
				visible_now[i] = 1
				explored[i] = 1


## Radial viewshed: march rays outward tracking the steepest obstacle slope.
func _stamp(origin: Vector2, eye: float, r: float, own_bld: int) -> void:
	var nav := sim.nav
	var rays := clampi(int(r / CELL * 6.5), 32, 220)
	var step := CELL * 0.5
	var steps := int(r / step)
	var ocx := int(origin.x / CELL)
	var ocy := int(origin.y / CELL)
	if ocx >= 0 and ocy >= 0 and ocx < gw and ocy < gh:
		visible_now[ocy * gw + ocx] = 1
		explored[ocy * gw + ocx] = 1
	var mapw := nav.w
	var maph := nav.h
	var ncell := nav.cell
	for k in rays:
		var a := TAU * k / rays
		var dx := cos(a) * step
		var dy := sin(a) * step
		var max_slope := -INF
		var x := origin.x
		var y := origin.y
		for s in range(1, steps + 1):
			x += dx
			y += dy
			var nx := int(x / ncell)
			var ny := int(y / ncell)
			if nx < 0 or ny < 0 or nx >= mapw or ny >= maph:
				break
			var dist := s * step
			var ni := ny * mapw + nx
			var oh: float = nav.height[ni]
			if own_bld >= 0 and nav.bld[ni] == own_bld:
				oh = 0.0
			var target_slope := (1.0 - eye) / dist
			var cx := int(x / CELL)
			var cy := int(y / CELL)
			if target_slope >= max_slope or (oh > 0.0 and (oh - eye) / dist >= max_slope):
				var ci := cy * gw + cx
				if cx < gw and cy < gh:
					visible_now[ci] = 1
					explored[ci] = 1
			if oh > 0.0:
				var sl := (oh - eye) / dist
				if sl > max_slope:
					max_slope = sl
				if oh > eye + 30.0:
					break

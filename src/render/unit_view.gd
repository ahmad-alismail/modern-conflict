extends Node3D
## Visual representation of one SimUnit: interpolates sim state between ticks,
## animates squad members around the formation (fallen soldiers stay where they fell),
## hides units the player's team cannot see, and shows a selection ring.
class_name UnitView

var u: SimUnit
var world: SimWorld
var model: UnitModel
var ring: MeshInstance3D
var selected := false
var hovered := false
var corpse_root: Node3D
var _member_pos: Array[Vector3] = []
var _member_yaw: PackedFloat32Array = PackedFloat32Array()
var _dead: PackedByteArray = PackedByteArray()
var _fade := 1.0
var _bank := 0.0
var _loop_player: Node
var _deployed := false

static var _ring_mesh: QuadMesh


func setup(unit: SimUnit, sim: SimWorld, color: Color, corpses: Node3D) -> void:
	u = unit
	world = sim
	corpse_root = corpses
	model = UnitModels.create(u.def_id, color)
	add_child(model)
	var n := model.members.size()
	_member_pos.resize(n)
	_member_yaw.resize(n)
	_dead.resize(n)
	for i in n:
		var off := u.member_offset(i).rotated(-u.facing)
		_member_pos[i] = Vector3(off.x, 0, off.y)
		model.members[i].position = _member_pos[i]
	ring = MeshInstance3D.new()
	ring.mesh = _get_ring_mesh()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r: float = u.def["radius"] + (1.2 if u.is_squad() else 0.6)
	ring.scale = Vector3(r * 2.0, 1, r * 2.0)
	ring.position.y = 0.08
	ring.visible = false
	var rm := ShaderMaterial.new()
	rm.shader = preload("res://src/render/shaders/ring.gdshader")
	rm.render_priority = 10
	ring.material_override = rm
	add_child(ring)
	_place(1.0)


static func _get_ring_mesh() -> QuadMesh:
	if _ring_mesh == null:
		_ring_mesh = QuadMesh.new()
		_ring_mesh.size = Vector2.ONE
		_ring_mesh.orientation = PlaneMesh.FACE_Y
	return _ring_mesh


func set_ring(sel: bool, color: Color) -> void:
	selected = sel
	ring.visible = sel or hovered
	(ring.material_override as ShaderMaterial).set_shader_parameter("color", color)


func set_hover(h: bool, color: Color) -> void:
	hovered = h
	ring.visible = selected or hovered
	if not selected:
		(ring.material_override as ShaderMaterial).set_shader_parameter("color", color * Color(1, 1, 1, 0.5))


func start_loop(audio: Node) -> void:
	if not audio.has_method("play_loop") or u.is_squad():
		return
	var snd := "engine_truck_loop"
	if u.move_class == Defs.MOVE_TRACKED:
		snd = "engine_tank_loop"
	if u.is_air():
		snd = "heli_loop" if u.def.get("air_kind", "") == "heli" else ("jet_flyby" if u.def.get("air_kind", "") == "plane" else "drone_loop")
	if snd == "jet_flyby":
		snd = "drone_loop"
	_loop_player = audio.play_loop(snd, self, -8.0 if not u.is_air() else -4.0)


func stop_loop(audio: Node) -> void:
	if _loop_player and audio.has_method("stop_loop"):
		audio.stop_loop(_loop_player)
	_loop_player = null


## visible_to_player: whether the local player's team can currently see this unit.
func update_view(alpha: float, delta: float, visible_to_player: bool) -> void:
	var hidden_state := u.state == SimUnit.State.GARRISONED or u.state == SimUnit.State.EMBARKED
	var target_fade := 1.0 if visible_to_player and not hidden_state else 0.0
	_fade = move_toward(_fade, target_fade, delta * 4.0)
	model.visible = _fade > 0.02
	if not model.visible:
		return
	_place(alpha)
	model.set_motion(u.cur_speed, delta)
	if u.def.get("turret", 0.0) > 0.0:
		var t := lerp_angle(u.prev_turret, u.turret, alpha)
		var f := lerp_angle(u.prev_facing, u.facing, alpha)
		model.set_turret_yaw(angle_difference(f, t))
	if u.has_special("sensor_mast"):
		var dep := u.stationary_t > 3.0
		if dep != _deployed:
			_deployed = dep
			model.set_deployed(dep)
	if u.is_squad():
		_update_members(delta)


func _place(alpha: float) -> void:
	var p := u.prev_pos.lerp(u.pos, alpha)
	var f := lerp_angle(u.prev_facing, u.facing, alpha)
	var h := 0.0
	if u.is_air():
		h = lerpf(u.prev_alt, u.alt, alpha)
	position = Vector3(p.x, h, p.y)
	rotation.y = -f
	if u.is_air():
		# bank into turns, pitch forward with speed
		var turn := angle_difference(u.prev_facing, u.facing) / SimWorld.DT
		_bank = lerpf(_bank, clampf(turn * 0.35, -0.6, 0.6), 0.1)
		model.rotation = Vector3(_bank, 0, -clampf(u.cur_speed / maxf(u.def["speed"], 1.0), 0.0, 1.0) * 0.18)


func _update_members(delta: float) -> void:
	var firing := u.fired_t < 0.7
	var moving := u.is_moving()
	var aim = _aim_local() if (firing or u.engaging) else null
	for i in model.members.size():
		var node := model.members[i]
		if u.members_hp[i] <= 0.0:
			if _dead[i] == 0:
				_dead[i] = 1
				_drop_corpse(i)
			model.set_member_state(i, 4, delta)
			continue
		var off := u.member_offset(i).rotated(-u.facing)
		var target := Vector3(off.x, 0, off.y)
		var k := 1.0 - exp(-delta * (2.2 if moving else 3.5))
		_member_pos[i] = _member_pos[i].lerp(target, k)
		node.position = _member_pos[i]
		var state := 0
		if u.pinned:
			state = 3
		elif moving:
			state = 1
		elif firing:
			state = 2
		var want_yaw := 0.0
		if aim != null and not moving:
			want_yaw = aim
		_member_yaw[i] = lerp_angle(_member_yaw[i], want_yaw, 1.0 - exp(-delta * 6.0))
		node.rotation.y = -_member_yaw[i]
		model.set_member_state(i, state, delta)


## Angle of the current target relative to the squad facing, or null.
func _aim_local() -> Variant:
	for ws in u.weapons:
		if ws["target"] >= 0:
			var t: SimUnit = world.by_id.get(ws["target"])
			if t != null and t.alive:
				return angle_difference(u.facing, (t.pos - u.pos).angle())
	return null


## Move a fallen member out of the squad so the body stays on the ground.
func _drop_corpse(i: int) -> void:
	var node := model.members[i]
	if corpse_root == null or not is_instance_valid(node):
		return
	var xf := node.global_transform
	node.get_parent().remove_child(node)
	corpse_root.add_child(node)
	node.global_transform = xf


func muzzle_for_slot(slot: int) -> Vector3:
	if u.is_squad():
		return Vector3.INF
	return model.muzzle_world(slot)

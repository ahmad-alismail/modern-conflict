extends Node3D
## Runtime visual of one unit (see docs/CONTRACTS.md §2). Built by UnitModels.
##
## Squads: each member is a caller-positioned Node3D holding one MeshInstance3D whose
## pose is evaluated on the GPU. This node only blends state weights and advances the
## gait phase / clock, then pushes two instance uniforms per changed member.
## Vehicles / aircraft: hull + optional turret node; wheels, rotors and barrel recoil
## are animated in the vehicle shader through per-instance uniforms (anim, recoil).
class_name UnitModel

const ST_IDLE := 0
const ST_MOVE := 1
const ST_FIRE := 2
const ST_PRONE := 3
const ST_DEAD := 4

var members: Array[Node3D] = []
var turret: Node3D
var _height := 2.0

# --- squad state (per member) ---
var _mi: Array[MeshInstance3D] = []
var _w := PackedFloat32Array()        # 4 weights per member: idle, move, fire, prone
var _phase := PackedFloat32Array()
var _clock := PackedFloat32Array()
var _imp := PackedFloat32Array()      # recoil impulse from fire_recoil()
var _fall := PackedFloat32Array()     # < 0 alive, else death blend progress 0..1
var _settled := PackedByteArray()
var _fire_phase := PackedFloat32Array()   # clock value at which the procedural burst cadence starts
var _member_weapon := PackedStringArray()
var _slot_members: Array = []         # weapon slot -> Array[int] member indices
var _gait_len := 2.3                  # meters travelled per gait cycle
var _gait_max := 1.8                  # cycles per second cap
var _speed := -1.0
var _default_speed := 3.4
var _auto_recoil := true

# --- vehicle state ---
var _hull: MeshInstance3D
var _anim_mis: Array[MeshInstance3D] = []
var _recoil_mis: Array[MeshInstance3D] = []
var _has_wheels := false
var _roll := 0.0
var _spin := 0.0
var _spin_rate := 0.0
var _recoil := Vector4.ZERO
var _muzzles: Array = []              # per slot: {node: Node3D, pts: PackedVector3Array, i: int}
var _mast: Array[Node3D] = []
var _mast_h := PackedFloat32Array()   # extension per section at full deploy
var _mast_spin: Node3D
var _deploy := 0.0
var _deploy_target := 0.0


func _ready() -> void:
	process_priority = 100
	_update_processing()


func _notification(what: int) -> void:
	# Bodies may outlive this model (the caller moves fallen members to a corpse layer):
	# make sure anyone still falling ends up lying on the ground.
	if what == NOTIFICATION_PREDELETE:
		for i in _mi.size():
			if _fall[i] >= 0.0 and _fall[i] < 1.0 and is_instance_valid(_mi[i]):
				_fall[i] = 1.0
				_mi[i].set_instance_shader_parameter(&"pw", Vector4.ZERO)
				_mi[i].set_instance_shader_parameter(&"pd", Vector4(1.0, _phase[i], _clock[i], 0.0))


# ================================================================== squads ===

func _add_member(holder: Node3D, mi: MeshInstance3D, weapon: String) -> void:
	holder.add_child(mi)
	add_child(holder)
	members.append(holder)
	_mi.append(mi)
	_member_weapon.append(weapon)
	_w.append_array([1.0, 0.0, 0.0, 0.0])
	_phase.append(randf() * TAU)
	_clock.append(randf() * 10.0)
	_imp.append(0.0)
	_fall.append(-1.0)
	_settled.append(0)
	var c: Vector4 = mi.get_instance_shader_parameter(&"cfg")
	_fire_phase.append(fposmod(-c.y * 0.37 - 0.12, maxf(c.w, 0.01)))


func set_member_state(i: int, state: int, delta: float) -> void:
	if i < 0 or i >= _mi.size():
		return
	var mi := _mi[i]
	var b := i * 4
	if _fall[i] >= 0.0 or state == ST_DEAD:
		if _fall[i] >= 1.0:
			return
		_fall[i] = minf(maxf(_fall[i], 0.0) + delta / 0.8, 1.0)
		var d := _fall[i] * _fall[i]
		var k := 1.0 - d
		mi.set_instance_shader_parameter(&"pw", Vector4(_w[b] * k, _w[b + 1] * k, _w[b + 2] * k, _w[b + 3] * k))
		mi.set_instance_shader_parameter(&"pd", Vector4(d, _phase[i], _clock[i], 0.0))
		return
	if state == ST_FIRE and _w[b + 2] < 0.05:
		_clock[i] = _fire_phase[i]   # first procedural kick lands just after the shot that triggered firing
	_clock[i] += delta
	var dirty := false
	if _settled[i] == 0 or _w[b + state] < 1.0:
		var k := 1.0 - exp(-9.0 * delta)
		var err := 0.0
		for s in 4:
			var t := 1.0 if s == state else 0.0
			_w[b + s] += (t - _w[b + s]) * k
			err = maxf(err, absf(t - _w[b + s]))
		if err < 0.002:
			for s in 4:
				_w[b + s] = 1.0 if s == state else 0.0
			_settled[i] = 1
		else:
			_settled[i] = 0
		dirty = true
	if _w[b + 1] > 0.001:
		var spd := _speed if _speed >= 0.0 else _default_speed
		_phase[i] = fmod(_phase[i] + TAU * minf(maxf(spd, 1.2) / _gait_len, _gait_max) * delta, TAU * 64.0)
		dirty = true
	if _imp[i] > 0.0:
		_imp[i] = maxf(_imp[i] - delta * 5.0, 0.0)
		dirty = true
	if state == ST_FIRE:
		dirty = true
	if dirty:
		mi.set_instance_shader_parameter(&"pw", Vector4(_w[b], _w[b + 1], _w[b + 2], _w[b + 3]))
		mi.set_instance_shader_parameter(&"pd", Vector4(0.0, _phase[i], _clock[i], _imp[i]))


# ================================================================ vehicles ===

func set_turret_yaw(local_yaw: float) -> void:
	if turret:
		turret.rotation.y = -local_yaw


func set_motion(speed: float, delta: float) -> void:
	_speed = absf(speed)
	if _has_wheels and absf(speed) > 0.0001:
		_roll += speed * delta
		_push_anim()


func muzzle_world(slot: int) -> Vector3:
	if slot >= 0 and slot < _muzzles.size():
		var mz: Dictionary = _muzzles[slot]
		var pts: PackedVector3Array = mz["pts"]
		var n: Node3D = mz["node"]
		return n.global_transform * pts[int(mz["i"]) % pts.size()]
	if not _mi.is_empty():
		var idx := _first_alive_holder(slot)
		if idx >= 0:
			return members[idx].global_transform * SoldierRig.muzzle_local(_member_weapon[idx])
	return global_transform * Vector3(0, _height * 0.7, 0)


func _first_alive_holder(slot: int) -> int:
	var cands: Array = _slot_members[slot] if slot >= 0 and slot < _slot_members.size() else range(_mi.size())
	for idx in cands:
		if _fall[idx] < 0.0:
			return idx
	return cands[0] if not cands.is_empty() else -1


func fire_recoil(slot: int) -> void:
	if not _mi.is_empty():
		if slot < 0 or slot >= _slot_members.size():
			return
		if _auto_recoil:
			# real fire events arrive: switch members from the procedural burst cadence to events
			_auto_recoil = false
			for mi in _mi:
				var c: Vector4 = mi.get_instance_shader_parameter(&"cfg")
				c.w = 0.0
				mi.set_instance_shader_parameter(&"cfg", c)
		for idx in _slot_members[slot]:
			if _fall[idx] < 0.0:
				_imp[idx] = 1.0
		return
	if slot >= 0 and slot < 4:
		_recoil[slot] = 1.0
		_push_recoil()
	if slot >= 0 and slot < _muzzles.size():
		var mz: Dictionary = _muzzles[slot]
		mz["i"] = int(mz["i"]) + 1
	_update_processing()


func set_deployed(on: bool) -> void:
	if _mast.is_empty():
		return
	_deploy_target = 1.0 if on else 0.0
	_update_processing()


func top_height() -> float:
	if not _mast.is_empty():
		return _height + _deploy * 9.5
	return _height


func _update_processing() -> void:
	if not is_inside_tree():
		return
	var need := _spin_rate != 0.0 or _recoil != Vector4.ZERO or (not _mast.is_empty() and (_deploy != _deploy_target or _deploy > 0.0))
	set_process(need)


func _process(delta: float) -> void:
	var anim_dirty := false
	if _spin_rate != 0.0:
		_spin = fmod(_spin + _spin_rate * delta, TAU * 1000.0)
		anim_dirty = true
	if _recoil != Vector4.ZERO:
		for s in 4:
			_recoil[s] = maxf(_recoil[s] - delta * 2.2, 0.0)
		_push_recoil()
	if not _mast.is_empty():
		if _deploy != _deploy_target:
			_deploy = move_toward(_deploy, _deploy_target, delta / 4.0)
			var e := smoothstep(0.0, 1.0, _deploy)
			for k in _mast.size():
				_mast[k].position.y = _mast_h[k] * e
		if _mast_spin and _deploy > 0.95:
			_mast_spin.rotation.y += delta * 0.8
	if anim_dirty:
		_push_anim()
	if _spin_rate == 0.0 and _recoil == Vector4.ZERO and (_mast.is_empty() or (_deploy == _deploy_target and _deploy == 0.0)):
		set_process(false)


func _push_anim() -> void:
	var v := Vector4(_roll, _spin, 0, 0)
	for mi in _anim_mis:
		mi.set_instance_shader_parameter(&"anim", v)


func _push_recoil() -> void:
	for mi in _recoil_mis:
		mi.set_instance_shader_parameter(&"recoil", _recoil)

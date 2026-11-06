extends RefCounted
## Factory for unit visuals (see docs/CONTRACTS.md §2).
## Squads -> SoldierRig / HoundRig members; vehicles and aircraft -> VehicleBuilder specs
## (meshes cached per def + paint variant, shared by every instance).
class_name UnitModels

static var _counter := 0


static func create(def_id: String, team_color: Color) -> UnitModel:
	var def := Defs.unit(def_id)
	var m := UnitModel.new()
	m.name = def_id
	_counter += 1
	var seed0 := absi(hash(def_id)) % 997 + _counter * 17
	var team_lin := team_color.srgb_to_linear()
	if def["cat"] == Defs.CAT_INF:
		_build_squad(m, def_id, def, team_lin, seed0)
	else:
		_build_vehicle(m, def_id, def, team_lin, seed0)
	return m


static func _build_squad(m: UnitModel, def_id: String, def: Dictionary, team_lin: Color, seed0: int) -> void:
	var loadout: Array = def["loadout"]
	var faction: String = def["faction"]
	var robot := def_id == "hac_hound"
	var slots := {}
	for i in int(def["members"]):
		var wid: String = loadout[i % loadout.size()]
		if not slots.has(wid):
			slots[wid] = m._slot_members.size()
			m._slot_members.append([])
		m._slot_members[slots[wid]].append(i)
		var holder := Node3D.new()
		holder.name = "M%d" % i
		var mi: MeshInstance3D
		if robot:
			mi = HoundRig.make_member(team_lin, seed0 + i * 7)
		else:
			mi = SoldierRig.make_member(faction, wid, team_lin, seed0 + i * 7)
		m._add_member(holder, mi, wid)
	if robot:
		m._gait_len = 1.2
		m._gait_max = 3.4
		m._default_speed = float(def["speed"])
		m._height = 1.1
	else:
		m._default_speed = float(def["speed"])
		m._height = 2.0


static func _build_vehicle(m: UnitModel, def_id: String, def: Dictionary, team_lin: Color, seed0: int) -> void:
	var spec := VehicleBuilder.spec(def_id, seed0 % VehicleBuilder.variant_count(def_id))
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = spec["hull"]
	hull.set_instance_shader_parameter(&"team_color", team_lin)
	if spec.has("aabb"):
		hull.custom_aabb = spec["aabb"]
	m.add_child(hull)
	m._hull = hull
	m._anim_mis.append(hull)
	m._recoil_mis.append(hull)
	m._has_wheels = spec.get("wheels", false)
	m._spin_rate = spec.get("spin_rate", 0.0)
	m._height = spec["height"]
	var tnode: Node3D = null
	if spec.get("turret") != null:
		tnode = Node3D.new()
		tnode.name = "Turret"
		tnode.position = spec["turret_pos"]
		var tmi := MeshInstance3D.new()
		tmi.mesh = spec["turret"]
		tmi.set_instance_shader_parameter(&"team_color", team_lin)
		tnode.add_child(tmi)
		m.add_child(tnode)
		m.turret = tnode
		m._recoil_mis.append(tmi)
	for mz: Dictionary in spec["muzzles"]:
		var node: Node3D = tnode if mz.get("on_turret", false) and tnode else m
		m._muzzles.append({"node": node, "pts": mz["pts"], "i": 0})
	if spec.has("mast"):
		_build_mast(m, spec["mast"], team_lin)


static func _build_mast(m: UnitModel, mast: Dictionary, team_lin: Color) -> void:
	var parent: Node3D = m
	var base := Node3D.new()
	base.position = mast["pos"]
	m.add_child(base)
	parent = base
	var meshes: Array = mast["sections"]
	var ext: PackedFloat32Array = mast["ext"]
	for k in meshes.size():
		var sec := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[k]
		mi.set_instance_shader_parameter(&"team_color", team_lin)
		sec.add_child(mi)
		parent.add_child(sec)
		m._mast.append(sec)
		m._mast_h.append(ext[k])
		parent = sec
	var head := Node3D.new()
	var hmi := MeshInstance3D.new()
	hmi.mesh = mast["head"]
	hmi.set_instance_shader_parameter(&"team_color", team_lin)
	head.position.y = mast["head_y"]
	head.add_child(hmi)
	parent.add_child(head)
	m._mast_spin = head


static func create_wreck(def_id: String) -> Node3D:
	var def := Defs.unit(def_id)
	var n := Node3D.new()
	n.name = def_id + "_wreck"
	if def["cat"] == Defs.CAT_INF:
		return n
	var w := VehicleBuilder.wreck(def_id)
	var hull := MeshInstance3D.new()
	hull.mesh = w["hull"]
	n.add_child(hull)
	if w.get("turret") != null:
		var t := MeshInstance3D.new()
		t.mesh = w["turret"]
		t.transform = w["turret_xf"]
		n.add_child(t)
	return n

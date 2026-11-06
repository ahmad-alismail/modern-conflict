extends RefCounted
## Procedural Syrian / Middle-Eastern urban architecture (docs/CONTRACTS.md §1).
## Each building is two MeshInstance3Ds sharing one uber-shader material
## (EnvMaterials): the main mass (walls with real window recesses, glazing, shutters,
## balconies, doors, shopfronts, kiosks) and a small-clutter mesh (water tanks, dishes,
## AC units, grilles, rebar, railings posts) hidden beyond DETAIL_RANGE.
## Geometry is built by EnvBld/EnvStyles/EnvLandmarks with the fast EnvGeo accumulator.
class_name BuildingBuilder

const DETAIL_RANGE := 260.0
const _META_DEF := "env_bdef"
const _META_DMG := "env_damage"
const _META_PART := "env_part"


static func build(b: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = "Building%d" % int(b.get("id", 0))
	n.set_meta(_META_DEF, b)
	_populate(n, b, 0)
	return n


static func build_ruin(b: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = "Ruin%d" % int(b.get("id", 0))
	var c := EnvBld.new(b, 0)
	EnvLandmarks.ruin(c)
	_attach(n, c, 0)
	return n


## level 0 = intact, 1 = damaged (holes, soot, broken parapets and glass), 2+ = heavier.
## Rebuilds the node's own meshes deterministically; other children are left alone.
static func apply_damage(node: Node3D, level: int) -> void:
	if node == null:
		return
	var b: Variant = node.get_meta(_META_DEF, null)
	if typeof(b) != TYPE_DICTIONARY:
		for ch in node.get_children():
			if ch is GeometryInstance3D:
				(ch as GeometryInstance3D).set_instance_shader_parameter("scorch", 0.8 if level > 0 else 0.0)
		return
	if int(node.get_meta(_META_DMG, 0)) == level:
		return
	for ch in node.get_children():
		if ch.has_meta(_META_PART):
			node.remove_child(ch)
			ch.queue_free()
	_populate(node, b, level)


static func _populate(n: Node3D, b: Dictionary, level: int) -> void:
	var c := EnvBld.new(b, level)
	EnvStyles.build(c)
	_attach(n, c, level)
	n.set_meta(_META_DMG, level)


static func _attach(n: Node3D, c: EnvBld, level: int) -> void:
	var mat := EnvMaterials.building()
	var scorch := clampf(0.55 + 0.2 * level, 0.0, 1.0) if level > 0 else 0.0
	var mi := c.g.to_instance(mat)
	mi.name = "Main"
	mi.set_meta(_META_PART, true)
	if level > 0:
		mi.set_instance_shader_parameter("scorch", scorch)
	n.add_child(mi)
	if not c.dt.is_empty():
		var di := c.dt.to_instance(mat)
		di.name = "Detail"
		di.visibility_range_end = DETAIL_RANGE
		di.visibility_range_end_margin = 20.0
		di.set_meta(_META_PART, true)
		if level > 0:
			di.set_instance_shader_parameter("scorch", scorch)
		n.add_child(di)

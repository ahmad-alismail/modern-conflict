extends RefCounted
## Street props and walls (docs/CONTRACTS.md §1).
## Props: one MultiMeshInstance3D per kind (meshes from EnvProps, cached), per-instance
## tint + variation in custom data, transform = yaw -rot, uniform scale s.
## Walls: merged per 96 m map chunk (a few meshes, each spatially compact for culling).
class_name PropBuilder

const WALL_CHUNK := 96.0
## Kinds that are radially symmetric get a deterministic extra yaw for variety.
const FREE_YAW := ["palm", "tree", "bush", "rubble", "tires", "barrels", "tank_trap"]


static func build_props(props: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Props"
	var by_kind: Dictionary = {}
	for p in props:
		var kind: String = p["kind"]
		if not MapDef.PROPS.has(kind):
			continue
		if not by_kind.has(kind):
			by_kind[kind] = []
		(by_kind[kind] as Array).append(p)
	var kinds := by_kind.keys()
	kinds.sort()
	for kind in kinds:
		var list: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = EnvProps.mesh(kind)
		mm.instance_count = list.size()
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var free_yaw: bool = kind in FREE_YAW
		for i in list.size():
			var p: Dictionary = list[i]
			var pos: Vector2 = p["p"]
			var rng := Rng.new(int(pos.x * 97.0) * 7919 + int(pos.y * 89.0) * 104729 + kind.length())
			var yaw: float = -float(p["rot"])
			if free_yaw:
				yaw += rng.range_f(0.0, TAU)
			var s: float = p.get("s", 1.0)
			var bas := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
			var t := EnvProps.tint(kind, rng)
			var k := i * 16
			buf[k] = bas.x.x; buf[k + 1] = bas.y.x; buf[k + 2] = bas.z.x; buf[k + 3] = pos.x
			buf[k + 4] = bas.x.y; buf[k + 5] = bas.y.y; buf[k + 6] = bas.z.y; buf[k + 7] = 0.0
			buf[k + 8] = bas.x.z; buf[k + 9] = bas.y.z; buf[k + 10] = bas.z.z; buf[k + 11] = pos.y
			buf[k + 12] = t.r; buf[k + 13] = t.g; buf[k + 14] = t.b; buf[k + 15] = rng.next_float()
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Props_" + kind
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mmi)
	return root


static func build_walls(walls: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Walls"
	var chunks: Dictionary = {}
	for w in walls:
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		if a.distance_to(b) < 0.05:
			continue
		var mid := (a + b) * 0.5
		var key := Vector2i(int(floor(mid.x / WALL_CHUNK)), int(floor(mid.y / WALL_CHUNK)))
		var g: EnvGeo = chunks.get(key)
		if g == null:
			g = EnvGeo.new()
			chunks[key] = g
		EnvWalls.wall(g, a, b, float(w.get("h", 2.0)), int(w.get("kind", MapDef.W_COMPOUND)))
	var mat := EnvMaterials.building()
	for key in chunks:
		var g: EnvGeo = chunks[key]
		var mi := g.to_instance(mat)
		mi.name = "Walls_%d_%d" % [key.x, key.y]
		root.add_child(mi)
	return root

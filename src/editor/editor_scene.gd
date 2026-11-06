extends Node3D
## 3D view of the map being edited. `sync(map)` rebuilds only the layers whose
## content changed (terrain + road markings, walls, props); buildings are pooled
## by their geometry key so moving or rotating one never rebuilds its mesh.
class_name EditorScene

var _terrain: TerrainBuilder
var _terrain_key := 0
var _water: MeshInstance3D
var _buildings: Node3D
var _pool := {}            # geometry key -> Array[Node3D]
var _walls: Node3D
var _walls_key := 0
var _props: Node3D
var _props_key := 0
## Timings (ms) of the last sync, for the status bar / logs.
var last_ms := {}


func _ready() -> void:
	_buildings = Node3D.new()
	_buildings.name = "Buildings"
	add_child(_buildings)


static func _bkey(b: Dictionary) -> int:
	return hash([b["size"], b["floors"], b["style"], b["color"], b["seed"]])


## heavy = false only updates buildings (cheap enough to run every frame while
## the user drags); terrain, walls and props wait for the debounced full sync.
func sync(m: MapDef, heavy: bool = true) -> void:
	var t0 := Time.get_ticks_usec()
	var tk := hash([m.width, m.height, m.map_seed, m.terrain, m.roads]) if heavy else _terrain_key
	if heavy and (tk != _terrain_key or _terrain == null):
		_terrain_key = tk
		if _terrain:
			_terrain.queue_free()
		_terrain = TerrainBuilder.new()
		_terrain.name = "Terrain"
		add_child(_terrain)
		_terrain.build(m)
		_build_water(m)
	var t1 := Time.get_ticks_usec()
	var built := 0
	var next := {}
	for b in m.buildings:
		var k := _bkey(b)
		var n: Node3D = null
		var free_list: Array = _pool.get(k, [])
		if not free_list.is_empty():
			n = free_list.pop_back()
		else:
			n = BuildingBuilder.build(b)
			_buildings.add_child(n)
			built += 1
		n.position = Vector3(b["c"].x, 0, b["c"].y)
		n.rotation.y = -float(b["rot"])
		if not next.has(k):
			next[k] = []
		next[k].append(n)
	for k in _pool:
		for n: Node3D in _pool[k]:
			n.queue_free()
	_pool = next
	var t2 := Time.get_ticks_usec()
	if not heavy:
		return
	var wk := hash(m.walls)
	if wk != _walls_key or _walls == null:
		_walls_key = wk
		if _walls:
			_walls.queue_free()
		_walls = PropBuilder.build_walls(m.walls)
		add_child(_walls)
	var pk := hash(m.props)
	if pk != _props_key or _props == null:
		_props_key = pk
		if _props:
			_props.queue_free()
		_props = PropBuilder.build_props(m.props)
		add_child(_props)
	var t3 := Time.get_ticks_usec()
	last_ms = {"terrain": (t1 - t0) / 1000.0, "buildings": (t2 - t1) / 1000.0, "built": built, "props": (t3 - t2) / 1000.0,
		"total": (t3 - t0) / 1000.0}


## Water surface over T_WATER cells (the terrain splat has no water channel),
## one quad per horizontal run of water cells.
func _build_water(m: MapDef) -> void:
	if _water:
		_water.queue_free()
		_water = null
	var verts := PackedVector3Array()
	var c := MapDef.CELL
	for y in m.height:
		var x := 0
		while x < m.width:
			if m.terrain[y * m.width + x] != MapDef.T_WATER:
				x += 1
				continue
			var x1 := x
			while x1 + 1 < m.width and m.terrain[y * m.width + x1 + 1] == MapDef.T_WATER:
				x1 += 1
			var a := Vector3(x * c, 0.06, y * c)
			var b := Vector3((x1 + 1) * c, 0.06, y * c)
			var d := Vector3((x1 + 1) * c, 0.06, (y + 1) * c)
			var e := Vector3(x * c, 0.06, (y + 1) * c)
			verts.append_array([a, b, d, a, d, e])
			x = x1 + 1
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.27, 0.33)
	mat.roughness = 0.18
	mat.metallic = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = mesh
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)


## Drop every cached layer (e.g. after loading a different map).
func clear() -> void:
	_terrain_key = 0
	_walls_key = 0
	_props_key = 0
	for k in _pool:
		for n: Node3D in _pool[k]:
			n.queue_free()
	_pool.clear()

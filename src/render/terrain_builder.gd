extends Node3D
## Ground rendering: a splat shader fed by the map's terrain grid (roads, paving,
## vegetation, rubble) plus a high-resolution road-marking mask, extended far past
## the playable area, with distant outskirts silhouettes for the horizon.
class_name TerrainBuilder

const MARK_RES := 2048
const MARGIN := 900.0

var map: MapDef
var _splat_img: Image
var _splat_tex: ImageTexture
var _mat: ShaderMaterial


func build(m: MapDef) -> void:
	map = m
	_splat_img = Image.create(m.width, m.height, false, Image.FORMAT_RGBA8)
	for y in m.height:
		for x in m.width:
			_splat_img.set_pixel(x, y, _splat_color(m.terrain[y * m.width + x]))
	_splat_tex = ImageTexture.create_from_image(_splat_img)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/render/shaders/terrain.gdshader")
	_mat.set_shader_parameter("terrain_map", _splat_tex)
	_mat.set_shader_parameter("marks_map", _build_marks())
	_mat.set_shader_parameter("noise_a", _noise_tex(1, 0.012, 6))
	_mat.set_shader_parameter("noise_b", _noise_tex(2, 0.05, 3))
	_mat.set_shader_parameter("map_size", m.size_m())
	var size := m.size_m()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size + Vector2.ONE * MARGIN * 2.0
	pm.subdivide_width = 64
	pm.subdivide_depth = 64
	ground.mesh = pm
	ground.position = Vector3(size.x * 0.5, 0, size.y * 0.5)
	ground.material_override = _mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	_build_water()
	_build_outskirts()


static func _splat_color(t: int) -> Color:
	match t:
		MapDef.T_ROAD: return Color(1, 0, 0, 0)
		MapDef.T_PAVED: return Color(0, 1, 0, 0)
		MapDef.T_GRASS: return Color(0, 0, 1, 0)
		MapDef.T_FIELD: return Color(0, 0, 0.5, 0)
		MapDef.T_RUBBLE: return Color(0, 0, 0, 1)
		MapDef.T_DIRT: return Color(0, 0, 0.12, 0)
		MapDef.T_WATER: return Color(0, 0, 0.12, 0.35)   # muddy banks under the water surface
		_: return Color(0, 0, 0, 0)


## Refresh splat texture after runtime terrain changes (building collapse -> rubble).
func refresh_terrain() -> void:
	for y in map.height:
		for x in map.width:
			if map.terrain[y * map.width + x] == MapDef.T_RUBBLE:
				_splat_img.set_pixel(x, y, Color(0, 0, 0, 1))
	_splat_tex.update(_splat_img)


func _noise_tex(seed_value: int, freq: float, octaves: int) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = octaves
	t.noise = n
	return t


## Road paint and curb lines rasterized at ~0.23 m per pixel.
## R = white paint, G = yellow paint, B = darkening (curbs, cracks, oil).
func _build_marks() -> ImageTexture:
	var img := Image.create(MARK_RES, MARK_RES, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var size := map.size_m()
	var s := MARK_RES / size.x
	var rng := Rng.new(map.map_seed + 77)
	for r in map.roads:
		var a: Vector2 = r["a"]
		var b: Vector2 = r["b"]
		var w: float = r["w"]
		var kind: int = r["kind"]
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var length := a.distance_to(b)
		if kind == 2:
			continue
		# curbs: dark line at road edges
		_line(img, a + nrm * w * 0.5, b + nrm * w * 0.5, s, 0.22, Color(0, 0, 0.6, 1), 0.0, 0.0)
		_line(img, a - nrm * w * 0.5, b - nrm * w * 0.5, s, 0.22, Color(0, 0, 0.6, 1), 0.0, 0.0)
		if kind == 0:
			# double center line + dashed lane lines
			_line(img, a + nrm * 0.12, b + nrm * 0.12, s, 0.12, Color(0, 1, 0, 1), 0.0, 0.0)
			_line(img, a - nrm * 0.12, b - nrm * 0.12, s, 0.12, Color(0, 1, 0, 1), 0.0, 0.0)
			_line(img, a + nrm * w * 0.25, b + nrm * w * 0.25, s, 0.12, Color(1, 0, 0, 1), 3.0, 4.0)
			_line(img, a - nrm * w * 0.25, b - nrm * w * 0.25, s, 0.12, Color(1, 0, 0, 1), 3.0, 4.0)
			_line(img, a + nrm * (w * 0.5 - 0.35), b + nrm * (w * 0.5 - 0.35), s, 0.12, Color(1, 0, 0, 1), 0.0, 0.0)
			_line(img, a - nrm * (w * 0.5 - 0.35), b - nrm * (w * 0.5 - 0.35), s, 0.12, Color(1, 0, 0, 1), 0.0, 0.0)
		else:
			_line(img, a, b, s, 0.1, Color(1, 0, 0, 1), 2.0, 5.0)
		# oil stains / patches along the road
		var t := rng.range_f(0, 20)
		while t < length:
			var p := a + dir * t + nrm * rng.range_f(-w * 0.35, w * 0.35)
			_blot(img, p, s, rng.range_f(0.6, 1.8), Color(0, 0, rng.range_f(0.25, 0.5), 1))
			t += rng.range_f(8, 30)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _line(img: Image, a: Vector2, b: Vector2, s: float, width_m: float, col: Color, dash: float, gap: float) -> void:
	var length := a.distance_to(b)
	var step := 0.5 / s
	var hw := maxi(1, int(round(width_m * s * 0.5)))
	var t := 0.0
	var period := dash + gap
	while t <= length:
		if period <= 0.0 or fmod(t, period) < dash:
			var p := a.lerp(b, t / maxf(length, 0.001)) * s
			img.fill_rect(Rect2i(int(p.x) - hw + 1, int(p.y) - hw + 1, hw * 2 - 1, hw * 2 - 1), col)
		t += step


func _blot(img: Image, p: Vector2, s: float, r_m: float, col: Color) -> void:
	var c := p * s
	var r := int(r_m * s)
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var d := sqrt(float(ox * ox + oy * oy)) / maxf(r, 1)
			if d > 1.0:
				continue
			var x := int(c.x) + ox
			var y := int(c.y) + oy
			if x >= 0 and y >= 0 and x < MARK_RES and y < MARK_RES:
				var e := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(e.r, e.g, maxf(e.b, col.b * (1.0 - d)), 1))


## Water surface over T_WATER cells (canals, ponds, rivers from the editor / importer).
func _build_water() -> void:
	var kit := MeshKit.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/render/shaders/water.gdshader")
	mat.set_shader_parameter("noise_tex", _noise_tex(9, 0.03, 3))
	var c := MapDef.CELL
	var any := false
	for y in map.height:
		var x := 0
		while x < map.width:
			if map.terrain[y * map.width + x] != MapDef.T_WATER:
				x += 1
				continue
			var x0 := x
			while x < map.width and map.terrain[y * map.width + x] == MapDef.T_WATER:
				x += 1
			var a := Vector3(x0 * c, 0.06, y * c)
			var b := Vector3(x * c, 0.06, y * c)
			kit.quad(mat, Vector3(a.x, a.y, a.z + c), Vector3(b.x, b.y, b.z + c), b, a)
			any = true
	if any:
		var mi := kit.to_instance(false)
		mi.name = "Water"
		add_child(mi)


## Low-detail city silhouettes beyond the playable edge so the horizon reads as a city.
func _build_outskirts() -> void:
	var size := map.size_m()
	var rng := Rng.new(map.map_seed + 991)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.74, 0.64)
	mat.roughness = 0.95
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var attempts := 0
	while xfs.size() < 900 and attempts < 6000:
		attempts += 1
		var p := Vector2(rng.range_f(-MARGIN * 0.8, size.x + MARGIN * 0.8), rng.range_f(-MARGIN * 0.8, size.y + MARGIN * 0.8))
		var edge_d := maxf(maxf(-p.x, p.x - size.x), maxf(-p.y, p.y - size.y))
		# only on the horizon: the band right outside the map stays open ground
		if edge_d < 220.0 or rng.next_float() > 1.3 - edge_d / MARGIN:
			continue
		var w := rng.range_f(8, 22)
		var d := rng.range_f(8, 22)
		var h := rng.range_f(4, 9) + (rng.range_f(0, 14) if rng.chance(0.15) else 0.0)
		xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, d)), Vector3(p.x, h * 0.5, p.y)))
		var v := rng.range_f(0.85, 1.05)
		cols.append(Color(v, v * rng.range_f(0.95, 1.0), v * rng.range_f(0.88, 0.97)))
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

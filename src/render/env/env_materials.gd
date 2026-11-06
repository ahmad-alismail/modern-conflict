extends RefCounted
## Shared environment materials: one uber-shader (env_surface.gdshader) with two
## ShaderMaterial instances, buildings/walls and instanced props, plus the procedural
## seamless noise textures it samples. Created once and shared by every mesh, so the
## whole city batches into a handful of pipelines.
class_name EnvMaterials

const SHADER := preload("res://src/render/env/env_surface.gdshader")

static var _building: ShaderMaterial
static var _props: ShaderMaterial
static var _noise_a: ImageTexture
static var _noise_b: ImageTexture


## Material for buildings, walls and roof details (flag bit = pattern variant).
static func building() -> ShaderMaterial:
	if _building == null:
		_building = _make(false)
	return _building


## Material for MultiMesh props (flag bit = multiply by INSTANCE_CUSTOM.rgb tint).
static func props() -> ShaderMaterial:
	if _props == null:
		_props = _make(true)
	return _props


## Optional night hook: 0 by day, about 1 at night. Lights a share of windows (warm and
## fluorescent) and the street-lamp heads through emission. Costs nothing when 0.
static func set_night_lights(amount: float) -> void:
	building().set_shader_parameter("night_lights", amount)
	props().set_shader_parameter("night_lights", amount)


static func _make(props_mode: bool) -> ShaderMaterial:
	_ensure_noise()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("noise_a", _noise_a)
	m.set_shader_parameter("noise_b", _noise_b)
	m.set_shader_parameter("props_mode", props_mode)
	return m


static func _ensure_noise() -> void:
	if _noise_a != null:
		return
	var fa := FastNoiseLite.new()
	fa.seed = 1337
	fa.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fa.frequency = 0.012
	fa.fractal_type = FastNoiseLite.FRACTAL_FBM
	fa.fractal_octaves = 5
	_noise_a = _tex(fa)
	var fb := FastNoiseLite.new()
	fb.seed = 4242
	fb.noise_type = FastNoiseLite.TYPE_CELLULAR
	fb.frequency = 0.03
	fb.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	fb.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	fb.fractal_type = FastNoiseLite.FRACTAL_FBM
	fb.fractal_octaves = 3
	_noise_b = _tex(fb)


static func _tex(n: FastNoiseLite) -> ImageTexture:
	var img := n.get_seamless_image(256, 256)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

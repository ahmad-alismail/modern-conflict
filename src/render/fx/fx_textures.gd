extends RefCounted
## Procedural textures for battlefield effects, generated once per process and cached.
## Smoke, fire and muzzle shapes are analytic in the shaders and erode with `noise()`;
## sparks/tracers/flashes are fully analytic. Craters get an albedo + normal pair.
class_name FxTextures

const CRATER_SIZE := 256

static var _noise: Texture2D
static var _crater: Texture2D
static var _crater_normal: Texture2D


## Tileable fractal noise (L8, mipmapped) used to break up smoke puffs and flames.
static func noise() -> Texture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = 7
		n.frequency = 0.012
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 5
		n.fractal_gain = 0.55
		var img := n.get_seamless_image(256, 256, false, false, 0.15, true)
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise


static func crater() -> Texture2D:
	if _crater == null:
		_build_crater()
	return _crater


static func crater_normal() -> Texture2D:
	if _crater_normal == null:
		_build_crater()
	return _crater_normal


## Blast crater: soot-black bowl, raised dirt rim, streaky scorched ejecta fading out.
static func _build_crater() -> void:
	var s := CRATER_SIZE
	var coarse := _noise_bytes(s, 0.022, 11)
	var fine := _noise_bytes(s, 0.09, 23)
	var height := PackedFloat32Array()
	height.resize(s * s)
	var rgba := PackedByteArray()
	rgba.resize(s * s * 4)
	var inv := 2.0 / s
	for y in s:
		var dy := (y + 0.5) * inv - 1.0
		for x in s:
			var i := y * s + x
			var dx := (x + 0.5) * inv - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var n := coarse[i] / 255.0
			var g := fine[i] / 255.0
			var rj := r * (1.0 + (n - 0.5) * 0.4)
			var bowl := rj / 0.4
			var h := -0.5 * (1.0 - bowl * bowl) if rj < 0.4 else 0.0
			var rim := (rj - 0.42) / 0.1
			h += 0.32 * exp(-rim * rim)
			h += (g - 0.5) * 0.14 * (1.0 - smoothstep(0.55, 0.95, rj))
			height[i] = h
			var rays := 0.5 + 0.5 * sin(atan2(dy, dx) * 7.0 + n * 5.0)
			var scorch := 1.0 - smoothstep(0.32, 0.95, rj + (rays - 0.5) * 0.16 * rj)
			var soot := 1.0 - smoothstep(0.18, 0.46, rj)
			var dirt := exp(-rim * rim * 0.6)
			var cr := lerpf(lerpf(0.13, 0.25, dirt), 0.045, soot) * (0.8 + 0.4 * g)
			var cg := lerpf(lerpf(0.11, 0.2, dirt), 0.04, soot) * (0.8 + 0.4 * g)
			var cb := lerpf(lerpf(0.095, 0.15, dirt), 0.035, soot) * (0.8 + 0.4 * g)
			var a := clampf(scorch * (0.8 + 0.25 * g) + soot * 0.3, 0.0, 1.0)
			var o := i * 4
			rgba[o] = int(clampf(cr, 0.0, 1.0) * 255.0)
			rgba[o + 1] = int(clampf(cg, 0.0, 1.0) * 255.0)
			rgba[o + 2] = int(clampf(cb, 0.0, 1.0) * 255.0)
			rgba[o + 3] = int(a * 255.0)
	var img := Image.create_from_data(s, s, false, Image.FORMAT_RGBA8, rgba)
	img.generate_mipmaps()
	_crater = ImageTexture.create_from_image(img)

	var nrm := PackedByteArray()
	nrm.resize(s * s * 4)
	var strength := 22.0
	for y in s:
		var y0 := maxi(y - 1, 0) * s
		var y1 := mini(y + 1, s - 1) * s
		for x in s:
			var x0 := maxi(x - 1, 0)
			var x1 := mini(x + 1, s - 1)
			var hx := (height[y * s + x1] - height[y * s + x0]) * strength
			var hy := (height[y1 + x] - height[y0 + x]) * strength
			var v := Vector3(-hx, hy, 1.0).normalized()
			var o := (y * s + x) * 4
			nrm[o] = int((v.x * 0.5 + 0.5) * 255.0)
			nrm[o + 1] = int((v.y * 0.5 + 0.5) * 255.0)
			nrm[o + 2] = int((v.z * 0.5 + 0.5) * 255.0)
			nrm[o + 3] = 255
	var nimg := Image.create_from_data(s, s, false, Image.FORMAT_RGBA8, nrm)
	nimg.generate_mipmaps()
	_crater_normal = ImageTexture.create_from_image(nimg)


static func _noise_bytes(size: int, freq: float, seed: int) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	var img := n.get_image(size, size)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	return img.get_data()

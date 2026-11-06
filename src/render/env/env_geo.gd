extends RefCounted
## Fast procedural geometry accumulator for environment art (buildings, props, walls).
## Everything is emitted as quads (4 vertices; triangles are degenerate quads) into packed
## arrays from pre-built unit templates transformed natively, about 30x faster than
## SurfaceTool for the tens of thousands of small parts a city needs. A whole building is
## one surface drawn with the shared uber-shader (EnvMaterials): the surface type travels
## in vertex-color alpha (see `c()`), the tint in RGB (sRGB, converted in the shader).
## Winding: quads passed as a, b, c, d are counter-clockwise seen from the front.
class_name EnvGeo

# surface types (decoded by env_surface.gdshader)
const PLASTER := 0
const STONE := 1
const CONCRETE := 2
const CORRUGATED := 3
const SHUTTER := 4
const GLASS := 5
const VOID := 6
const METAL := 7
const WOOD := 8
const FABRIC := 9
const RUBBLE := 10
const FOLIAGE := 11
const RUST := 12
const ROOF := 13
const BARK := 14
const MESH := 15
## Variant bit: buildings use it for pattern variants, props for "apply instance tint".
const FLAG := 16

# box face bits (local axes)
const PX := 1
const NX := 2
const PY := 4
const NY := 8
const PZ := 16
const NZ := 32
const ALL := 63
const NO_BOTTOM := 55
const SIDES := 51

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var _scr := PackedColorArray()

static var _box_tpl: Dictionary = {}
static var _tpl: Dictionary = {}
static var _idx := PackedInt32Array()

# face table: bit, normal, u (right), v (up) with u x v = normal
static var _faces: Array = [
	[PX, Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[NX, Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[PY, Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[NY, Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[PZ, Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[NZ, Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]


## Encode a tint + surface type (+ FLAG) into a vertex color.
static func c(rgb: Color, surface: int) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, surface / 31.0)


func is_empty() -> bool:
	return verts.is_empty()


func _push_col(col: Color, n: int) -> void:
	if _scr.size() != n:
		_scr.resize(n)
	_scr.fill(col)
	cols.append_array(_scr)


# ------------------------------------------------------------------ primitives -

## Quad from 4 corners, counter-clockwise seen from the front (flat normal).
func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color) -> void:
	var n := (b - a).cross(cc - a)
	if n.length_squared() < 1e-12:
		n = (cc - a).cross(d - a)
		if n.length_squared() < 1e-12:
			n = Vector3.UP
	verts.append(a); verts.append(d); verts.append(cc); verts.append(b)
	norms.append(n); norms.append(n); norms.append(n); norms.append(n)
	_push_col(col, 4)


## Quad with per-corner colors (gradients: grime, soot, fades).
func quad4(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, ca: Color, cb: Color, ccc: Color, cd: Color) -> void:
	var n := (b - a).cross(cc - a)
	verts.append(a); verts.append(d); verts.append(cc); verts.append(b)
	norms.append(n); norms.append(n); norms.append(n); norms.append(n)
	cols.append(ca); cols.append(cd); cols.append(ccc); cols.append(cb)


## Double-sided quad (thin leaves, cloth, signs seen from both sides).
func quad2(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color) -> void:
	quad(a, b, cc, d, col)
	quad(a, d, cc, b, col)


func tri(a: Vector3, b: Vector3, cc: Vector3, col: Color) -> void:
	quad(a, b, cc, cc, col)


## Convex planar polygon (counter-clockwise seen from the front), emitted as a fan.
func poly(pts: PackedVector3Array, col: Color) -> void:
	var n := pts.size()
	var i := 1
	while i + 2 < n:
		quad(pts[0], pts[i], pts[i + 1], pts[i + 2], col)
		i += 2
	if i + 1 < n:
		quad(pts[0], pts[i], pts[i + 1], pts[i + 1], col)


## Axis-aligned box (center, full size). mask: face bits (PX, NX, PY, NY, PZ, NZ).
func box(center: Vector3, size: Vector3, col: Color, mask: int = NO_BOTTOM) -> void:
	var t: Array = _box(mask)
	var tv: PackedVector3Array = t[0]
	verts.append_array(Transform3D(Basis.from_scale(size), center) * tv)
	norms.append_array(t[1])
	_push_col(col, tv.size())


## Axis-aligned box from min/max corners.
func boxmm(lo: Vector3, hi: Vector3, col: Color, mask: int = NO_BOTTOM) -> void:
	box((lo + hi) * 0.5, (hi - lo).abs(), col, mask)


## Oriented box: xf.basis must be a pure rotation; size is applied in local space.
func obox(xf: Transform3D, size: Vector3, col: Color, mask: int = NO_BOTTOM) -> void:
	var t: Array = _box(mask)
	var tv: PackedVector3Array = t[0]
	verts.append_array(Transform3D(xf.basis * Basis.from_scale(size), xf.origin) * tv)
	norms.append_array(Transform3D(xf.basis, Vector3.ZERO) * (t[1] as PackedVector3Array))
	_push_col(col, tv.size())


## Box between two points (beams, bars, rebar, wires) with square section `w` x `h`.
func beam(a: Vector3, b: Vector3, w: float, h: float, col: Color, mask: int = ALL) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return
	var fwd := d / len
	var up := Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT
	var side := fwd.cross(up).normalized()
	up = side.cross(fwd).normalized()
	var bas := Basis(fwd, up, side)
	obox(Transform3D(bas, (a + b) * 0.5), Vector3(len, h, w), col, mask)


## Hexahedron from 8 corners: bottom 0..3 = (x-z-, x+z-, x+z+, x-z+), top 4..7 likewise.
func hexa(p: Array, col: Color, mask: int = NO_BOTTOM) -> void:
	if mask & PY: quad(p[4], p[7], p[6], p[5], col)
	if mask & NY: quad(p[0], p[1], p[2], p[3], col)
	if mask & PX: quad(p[1], p[5], p[6], p[2], col)
	if mask & NX: quad(p[0], p[3], p[7], p[4], col)
	if mask & PZ: quad(p[3], p[2], p[6], p[7], col)
	if mask & NZ: quad(p[0], p[4], p[5], p[1], col)


## Frustum-like box: bottom size (bx, bz), top size (tx, tz), height h, top offset (ox, oz).
func taper(base: Vector3, bx: float, bz: float, tx: float, tz: float, h: float, col: Color,
		mask: int = NO_BOTTOM, ox: float = 0.0, oz: float = 0.0, yaw: float = 0.0) -> void:
	var bas := Basis(Vector3.UP, yaw)
	var p := [
		Vector3(-bx, 0, -bz) * 0.5, Vector3(bx, 0, -bz) * 0.5, Vector3(bx, 0, bz) * 0.5, Vector3(-bx, 0, bz) * 0.5,
		Vector3(-tx * 0.5 + ox, h, -tz * 0.5 + oz), Vector3(tx * 0.5 + ox, h, -tz * 0.5 + oz),
		Vector3(tx * 0.5 + ox, h, tz * 0.5 + oz), Vector3(-tx * 0.5 + ox, h, tz * 0.5 + oz)]
	for i in 8:
		p[i] = base + bas * (p[i] as Vector3)
	hexa(p, col, mask)


## Cylinder / cone frustum along local +Y (radius r at the base, r_top at the top;
## r_top < 0 means same as r). caps: 1 top, 2 bottom. Smooth radial normals.
func cyl(base: Vector3, r: float, h: float, col: Color, seg: int = 8, caps: int = 1, r_top: float = -1.0,
		bas: Basis = Basis.IDENTITY) -> void:
	var k := 1.0 if r_top < 0.0 else r_top / maxf(r, 1e-4)
	var kq := snappedf(clampf(k, 0.0, 4.0), 0.05)
	var key := "c%d_%d_%d" % [seg, int(kq * 20.0 + 0.5), caps]
	var t: Array = _tpl.get(key, [])
	if t.is_empty():
		t = _make_cyl(seg, kq, caps)
		_tpl[key] = t
	_stamp(t, Transform3D(bas * Basis.from_scale(Vector3(r, h, r)), base), col)


## Ellipsoid (or upper hemisphere) with radii `rad`, smooth normals.
func sphere(center: Vector3, rad: Vector3, col: Color, rings: int = 6, seg: int = 8, hemi: bool = false,
		bas: Basis = Basis.IDENTITY) -> void:
	var key := "s%d_%d_%d" % [rings, seg, 1 if hemi else 0]
	var t: Array = _tpl.get(key, [])
	if t.is_empty():
		t = _make_sphere(rings, seg, hemi)
		_tpl[key] = t
	_stamp(t, Transform3D(bas * Basis.from_scale(rad), center), col)


## Stamp a cached template: verts by xf, normals by the inverse-transpose basis.
func _stamp(t: Array, xf: Transform3D, col: Color) -> void:
	var tv: PackedVector3Array = t[0]
	verts.append_array(xf * tv)
	norms.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (t[1] as PackedVector3Array))
	_push_col(col, tv.size())


# ------------------------------------------------------------------ templates --

static func _box(mask: int) -> Array:
	var t: Array = _box_tpl.get(mask, [])
	if not t.is_empty():
		return t
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	for f in _faces:
		if not (mask & int(f[0])):
			continue
		var nn: Vector3 = f[1]
		var u: Vector3 = f[2] * 0.5
		var w: Vector3 = f[3] * 0.5
		var cc := nn * 0.5
		# clockwise from the front, matching the quad index pattern (0,1,2)(0,2,3)
		v.append(cc - u - w); v.append(cc - u + w); v.append(cc + u + w); v.append(cc + u - w)
		for i in 4:
			n.append(nn)
	t = [v, n]
	_box_tpl[mask] = t
	return t


## Template quad with explicit per-vertex normals, corners counter-clockwise from the front.
static func _tq(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, cc: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	v.append(a); v.append(d); v.append(cc); v.append(b)
	n.append(na); n.append(nd); n.append(nc); n.append(nb)


static func _make_cyl(seg: int, k: float, caps: int) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var slope := 1.0 - k   # radial drop per unit height -> normal tilt
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		var b0 := d0
		var b1 := d1
		var t0 := d0 * k + Vector3.UP
		var t1 := d1 * k + Vector3.UP
		# seen from outside, increasing angle goes to the left
		_tq(v, n, b1, b0, t0, t1, n1, n0, n0, n1)
	if caps & 1 and k > 0.001:
		_cap(v, n, seg, k, 1.0, Vector3.UP)
	if caps & 2:
		_cap(v, n, seg, 1.0, 0.0, Vector3.DOWN)
	return [v, n]


static func _cap(v: PackedVector3Array, n: PackedVector3Array, seg: int, r: float, y: float, nn: Vector3) -> void:
	var c := Vector3(0, y, 0)
	var i := 0
	while i < seg:
		var p0 := Vector3(cos(TAU * i / seg), 0, sin(TAU * i / seg)) * r + c
		var p1 := Vector3(cos(TAU * (i + 1) / seg), 0, sin(TAU * (i + 1) / seg)) * r + c
		var p2 := Vector3(cos(TAU * (i + 2) / seg), 0, sin(TAU * (i + 2) / seg)) * r + c
		if i + 1 >= seg:
			p2 = p1
		# counter-clockwise from above = decreasing angle (angle runs +X toward +Z)
		if nn.y > 0.0:
			_tq(v, n, c, p2, p1, p0, nn, nn, nn, nn)
		else:
			_tq(v, n, c, p0, p1, p2, nn, nn, nn, nn)
		i += 2


static func _make_sphere(rings: int, seg: int, hemi: bool) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var rmax := rings / 2 if hemi else rings
	for r in rmax:
		var th0 := PI * r / rings
		var th1 := PI * (r + 1) / rings
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var p00 := Vector3(sin(th0) * cos(a0), cos(th0), sin(th0) * sin(a0))
			var p01 := Vector3(sin(th0) * cos(a1), cos(th0), sin(th0) * sin(a1))
			var p10 := Vector3(sin(th1) * cos(a0), cos(th1), sin(th1) * sin(a0))
			var p11 := Vector3(sin(th1) * cos(a1), cos(th1), sin(th1) * sin(a1))
			# from outside: lower ring (th1) is bottom, increasing angle is to the left
			_tq(v, n, p11, p10, p00, p01, p11, p10, p00, p01)
	return [v, n]


# ------------------------------------------------------------------ output -----

static func _ensure_idx(nq: int) -> void:
	var have := _idx.size() / 6
	if have >= nq:
		return
	var want := maxi(nq, maxi(have * 2, 16384))
	_idx.resize(want * 6)
	for q in range(have, want):
		var b := q * 4
		var k := q * 6
		_idx[k] = b
		_idx[k + 1] = b + 1
		_idx[k + 2] = b + 2
		_idx[k + 3] = b
		_idx[k + 4] = b + 2
		_idx[k + 5] = b + 3


## Add this geometry as one surface of `am` (created if null) using material `mat`.
func commit(mat: Material, am: ArrayMesh = null) -> ArrayMesh:
	if am == null:
		am = ArrayMesh.new()
	if verts.is_empty():
		return am
	var nq := verts.size() / 4
	_ensure_idx(nq)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = _idx.slice(0, nq * 6)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(am.get_surface_count() - 1, mat)
	return am


func to_instance(mat: Material, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

extends RefCounted
## Indexed geometry builder for unit models. Unlike MeshKit it carries the extra
## per-vertex channels the unit shaders need:
##   COLOR    albedo tint (authored in sRGB, stored linear); alpha = 1 - dirt
##   UV       meters (patterns, tread / track scrolling)
##   UV2      x = material code (UnitShaders.M_*), y = bone (soldier rigs) or anim mode (vehicles)
##   CUSTOM0  vehicles: pivot xyz + mode parameter (wheel radius, spin rate, recoil slot)
## Every primitive takes a Transform3D; faces are oriented automatically (outward
## from the primitive's center), so callers never have to think about winding.
class_name UnitMesh

var code := 0          # material code for following primitives
var tag := 0           # bone index or animation mode
var custom := Color(0, 0, 0, 0)
var dirt := 0.0        # constant dirt amount 0..1
var dirt_h := 0.0      # > 0: extra height-based dirt below this model-space height
var y_base := 0.0      # model-space height of this mesh's origin (for dirt_h on turrets)
var base := Transform3D.IDENTITY   # applied to every primitive (sub-assemblies)

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _cu := PackedFloat32Array()
var _idx := PackedInt32Array()


func is_empty() -> bool:
	return _v.is_empty()


func vertex_count() -> int:
	return _v.size()


## Sets code/tag (and optionally the custom channel) for the next primitives.
func use(p_code: int, p_tag: int = -1, p_custom: Variant = null) -> UnitMesh:
	code = p_code
	if p_tag >= 0:
		tag = p_tag
	if p_custom != null:
		custom = p_custom
	return self


func _vert(p: Vector3, n: Vector3, col: Color, uv: Vector2) -> int:
	var wp := base * p
	_v.append(wp)
	_n.append((base.basis * n).normalized())
	var d := dirt
	if dirt_h > 0.0:
		d = clampf(d + clampf((dirt_h - (wp.y + y_base)) / dirt_h, 0.0, 1.0) * 0.75, 0.0, 1.0)
	col.a = 1.0 - d
	_c.append(col)
	_uv.append(uv)
	_uv2.append(Vector2(code, tag))
	_cu.append(custom.r); _cu.append(custom.g); _cu.append(custom.b); _cu.append(custom.a)
	return _v.size() - 1


static func lin(col: Color) -> Color:
	var c := col.srgb_to_linear()
	c.a = col.a
	return c


## Emits a planar convex polygon (fan) with a flat normal facing `out_dir`.
func _poly(pts: Array, out_dir: Vector3, col: Color, uvs: Array = []) -> void:
	var n := Vector3.ZERO
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var flip := n.dot(out_dir) < 0.0
	if flip:
		n = -n
	var i0 := _v.size()
	for i in pts.size():
		var uv: Vector2 = uvs[i] if i < uvs.size() else Vector2.ZERO
		_vert(pts[i], n, col, uv)
	for i in range(1, pts.size() - 1):
		# Godot front faces are clockwise: for CCW (around n) a,b,c emit a,c,b.
		if flip:
			_idx.append(i0); _idx.append(i0 + i); _idx.append(i0 + i + 1)
		else:
			_idx.append(i0); _idx.append(i0 + i + 1); _idx.append(i0 + i)


## Planar UVs (meters) for a face, projected on the two axes most orthogonal to its normal.
static func _uvs_for(pts: Array, n: Vector3) -> Array:
	var a := n.abs()
	var out := []
	for p: Vector3 in pts:
		if a.x >= a.y and a.x >= a.z:
			out.append(Vector2(p.z, -p.y))
		elif a.y >= a.z:
			out.append(Vector2(p.x, p.z))
		else:
			out.append(Vector2(p.x, -p.y))
	return out


## Convex polygon given in local coords of xf, oriented away from `center` (local).
func face(xf: Transform3D, pts: Array, col: Color, center: Vector3 = Vector3.ZERO) -> void:
	var w := []
	var c := Vector3.ZERO
	for p in pts:
		w.append(xf * p)
		c += p
	c /= pts.size()
	var out := xf.basis * (c - center)
	_poly(w, out, lin(col), _uvs_for(w, out))


## Box centered at xf.origin. faces: 1 +X, 2 -X, 4 +Y, 8 -Y, 16 +Z, 32 -Z.
func box(xf: Transform3D, size: Vector3, col: Color, faces: int = 63) -> void:
	var h := size * 0.5
	var lc := lin(col)
	var defs := [
		[1, Vector3(1, 0, 0), [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)]],
		[2, Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[4, Vector3(0, 1, 0), [Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[8, Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[16, Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[32, Vector3(0, 0, -1), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)]],
	]
	for d in defs:
		if faces & int(d[0]):
			var w := []
			for p: Vector3 in d[2]:
				w.append(xf * p)
			var out: Vector3 = xf.basis * d[1]
			_poly(w, out, lc, _uvs_for(w, out))


## Box with all 12 edges chamfered by `b` (reads much better under light than a plain box).
func bbox(xf: Transform3D, size: Vector3, b: float, col: Color) -> void:
	if size.length() < 0.17 or b < 0.004:
		box(xf, size, col)   # bevel would be sub-centimetre: save ~70 vertices
		return
	var h := size * 0.5
	b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.95)
	var lc := lin(col)
	var P := {}
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var k := Vector3i(sx, sy, sz)
				P[k] = [
					xf * Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b)),
					xf * Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b)),
					xf * Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)]
	var ctr := xf.origin
	# main faces
	for axis in 3:
		for s in [-1, 1]:
			var pts := []
			for a in [-1, 1]:
				for c in ([-1, 1] if a == -1 else [1, -1]):
					var k := Vector3i.ZERO
					k[axis] = s
					k[(axis + 1) % 3] = a
					k[(axis + 2) % 3] = c
					pts.append(P[k][axis])
			_emit_out(pts, ctr, lc)
	# edges
	for axis in 3:
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		for s1 in [-1, 1]:
			for s2 in [-1, 1]:
				var pts := []
				for s0 in [-1, 1]:
					var k := Vector3i.ZERO
					k[axis] = s0
					k[a1] = s1
					k[a2] = s2
					pts.append(P[k][a1])
					pts.append(P[k][a2])
				_emit_out([pts[0], pts[1], pts[3], pts[2]], ctr, lc)
	# corners
	for k in P:
		_emit_out(P[k], ctr, lc)


func _emit_out(w: Array, ctr: Vector3, lc: Color) -> void:
	var c := Vector3.ZERO
	for p in w:
		c += p
	c /= w.size()
	var out := c - ctr
	_poly(w, out, lc, _uvs_for(w, out))


## Extrudes a 2D profile (XY plane, any simple polygon) along local Z, centered.
func prism(xf: Transform3D, profile: PackedVector2Array, depth: float, col: Color, caps: bool = true) -> void:
	var lc := lin(col)
	var hz := depth * 0.5
	var n := profile.size()
	var area := 0.0
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var ccw := area > 0.0
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var e := b - a
		var on := Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
		var w := [xf * Vector3(a.x, a.y, -hz), xf * Vector3(b.x, b.y, -hz), xf * Vector3(b.x, b.y, hz), xf * Vector3(a.x, a.y, hz)]
		var out := xf.basis * Vector3(on.x, on.y, 0)
		var len := e.length()
		_poly(w, out, lc, [Vector2(0, -hz), Vector2(len, -hz), Vector2(len, hz), Vector2(0, hz)])
	if caps:
		var tri := Geometry2D.triangulate_polygon(profile)
		for s: float in [-1.0, 1.0]:
			var out := xf.basis * Vector3(0, 0, s)
			var nrm := out.normalized()
			var i0 := _v.size()
			for p in profile:
				_vert(xf * Vector3(p.x, p.y, hz * s), nrm, lc, p)
			for t in range(0, tri.size(), 3):
				var A := xf * Vector3(profile[tri[t]].x, profile[tri[t]].y, hz * s)
				var B := xf * Vector3(profile[tri[t + 1]].x, profile[tri[t + 1]].y, hz * s)
				var C := xf * Vector3(profile[tri[t + 2]].x, profile[tri[t + 2]].y, hz * s)
				if (B - A).cross(C - A).dot(nrm) > 0.0:
					_idx.append(i0 + tri[t]); _idx.append(i0 + tri[t + 2]); _idx.append(i0 + tri[t + 1])
				else:
					_idx.append(i0 + tri[t]); _idx.append(i0 + tri[t + 1]); _idx.append(i0 + tri[t + 2])


## Frustum between two convex polygons in the XZ plane (same vertex count) at heights y0 < y1.
func loft(xf: Transform3D, bottom: PackedVector2Array, y0: float, top: PackedVector2Array, y1: float, col: Color,
		cap_bottom: bool = true, cap_top: bool = true) -> void:
	var lc := lin(col)
	var n := bottom.size()
	var cb := Vector2.ZERO
	var ct := Vector2.ZERO
	for i in n:
		cb += bottom[i]
		ct += top[i]
	cb /= n
	ct /= n
	var ctr := xf * Vector3((cb.x + ct.x) * 0.5, (y0 + y1) * 0.5, (cb.y + ct.y) * 0.5)
	for i in n:
		var j := (i + 1) % n
		var w := [xf * Vector3(bottom[i].x, y0, bottom[i].y), xf * Vector3(bottom[j].x, y0, bottom[j].y),
			xf * Vector3(top[j].x, y1, top[j].y), xf * Vector3(top[i].x, y1, top[i].y)]
		_emit_out(w, ctr, lc)
	if cap_bottom:
		var w := []
		for p in bottom:
			w.append(xf * Vector3(p.x, y0, p.y))
		_poly(w, xf.basis * Vector3.DOWN, lc, _uvs_for(w, Vector3.UP))
	if cap_top:
		var w := []
		for p in top:
			w.append(xf * Vector3(p.x, y1, p.y))
		_poly(w, xf.basis * Vector3.UP, lc, _uvs_for(w, Vector3.UP))


## Smooth cylinder / cone frustum along local +Y from xf.origin. UV.x = arc length (m), UV.y = height.
func cyl(xf: Transform3D, r0: float, r1: float, h: float, seg: int, col: Color, caps: bool = true, phase: float = 0.0) -> void:
	var lc := lin(col)
	var circ := TAU * maxf(r0, r1)
	var slope := (r0 - r1) / maxf(h, 0.0001)
	var i0 := _v.size()
	var nb := xf.basis.inverse().transposed()
	for i in seg + 1:
		var a := TAU * i / seg + phase
		var d := Vector3(cos(a), 0, sin(a))
		var nl := (nb * Vector3(d.x, slope, d.z)).normalized()
		var u := circ * i / seg
		_vert(xf * (d * r0), nl, lc, Vector2(u, 0))
		_vert(xf * (d * r1 + Vector3(0, h, 0)), nl, lc, Vector2(u, h))
	for i in seg:
		var b0 := i0 + i * 2
		var t0 := b0 + 1
		var b1 := b0 + 2
		var t1 := b0 + 3
		# outward normal: emit clockwise seen from outside
		_idx.append(b0); _idx.append(b1); _idx.append(t1)
		_idx.append(b0); _idx.append(t1); _idx.append(t0)
	if caps:
		for top in [false, true]:
			var r := r1 if top else r0
			if r < 0.001:
				continue
			var pts := []
			for i in seg:
				var a := TAU * i / seg + phase
				pts.append(xf * Vector3(cos(a) * r, h if top else 0.0, sin(a) * r))
			var out := xf.basis * (Vector3.UP if top else Vector3.DOWN)
			_poly(pts, out, lc, _uvs_for(pts, out.normalized()))


## Cylinder between two points (local to base).
func tube(a: Vector3, b: Vector3, r0: float, r1: float, seg: int, col: Color, caps: bool = true) -> void:
	cyl(xf_from_to(a, b), r0, r1, a.distance_to(b), seg, col, caps)


## Basis with +Y along (b - a), origin a.
static func xf_from_to(a: Vector3, b: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), a)


## Smooth (optionally half) UV sphere; xf may be non-uniformly scaled (ellipsoids).
func sphere(xf: Transform3D, r: float, rings: int, seg: int, col: Color, half: bool = false) -> void:
	var lc := lin(col)
	var nb := xf.basis.inverse().transposed()
	var ring_max := rings / 2 if half else rings
	var i0 := _v.size()
	for ri in ring_max + 1:
		var v := PI * ri / rings
		for si in seg + 1:
			var u := TAU * si / seg
			var d := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
			_vert(xf * (d * r), (nb * d).normalized(), lc, Vector2(float(si) / seg * TAU * r, v * r))
	for ri in ring_max:
		for si in seg:
			var a := i0 + ri * (seg + 1) + si
			var b := a + 1
			var c := a + seg + 1
			var d := c + 1
			_idx.append(a); _idx.append(d); _idx.append(b)
			_idx.append(a); _idx.append(c); _idx.append(d)
	if half:
		var pts := []
		for si in seg:
			var u := TAU * si / seg
			pts.append(xf * (Vector3(cos(u), 0, sin(u)) * r))
		_poly(pts, xf.basis * Vector3.DOWN, lc, _uvs_for(pts, Vector3.UP))


## Thin double-sided quad (blades, fins, flags). Points in local coords of base.
func dquad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var lc := lin(col)
	var n := (b - a).cross(c - a)
	_poly([a, b, c, d], n, lc, _uvs_for([a, b, c, d], n.normalized()))
	_poly([a, b, c, d], -n, lc, _uvs_for([a, b, c, d], n.normalized()))


## Arbitrary triangle strip loop extruded across Z (used for track belts):
## `loop` is a closed polyline in XY; UV.x = arc length (scrolls with motion).
func belt(loop: PackedVector2Array, z0: float, z1: float, thick: float, col: Color) -> void:
	var lc := lin(col)
	var n := loop.size()
	var area := 0.0
	for i in n:
		area += loop[i].x * loop[(i + 1) % n].y - loop[(i + 1) % n].x * loop[i].y
	var ccw := area > 0.0
	var s := 0.0
	for i in n:
		var a := loop[i]
		var b := loop[(i + 1) % n]
		var e := b - a
		var len := e.length()
		if len < 1e-5:
			continue
		var on := (Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)).normalized()
		var ai := a - on * thick
		var bi := b - on * thick
		# outer tread surface
		_poly([Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)],
			Vector3(on.x, on.y, 0), lc, [Vector2(s, 0), Vector2(s + len, 0), Vector2(s + len, z1 - z0), Vector2(s, z1 - z0)])
		# inner surface
		_poly([Vector3(ai.x, ai.y, z0), Vector3(bi.x, bi.y, z0), Vector3(bi.x, bi.y, z1), Vector3(ai.x, ai.y, z1)],
			Vector3(-on.x, -on.y, 0), lc, [Vector2(s, 0), Vector2(s + len, 0), Vector2(s + len, z1 - z0), Vector2(s, z1 - z0)])
		# side walls
		for z in [z0, z1]:
			_poly([Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(bi.x, bi.y, z), Vector3(ai.x, ai.y, z)],
				Vector3(0, 0, signf(z - (z0 + z1) * 0.5)), lc, [Vector2(s, 0), Vector2(s + len, 0), Vector2(s + len, 0.1), Vector2(s, 0.1)])
		s += len


## Appends another builder's geometry (keeps its attributes), transformed.
func append(other: UnitMesh, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var off := _v.size()
	var nb := xf.basis.inverse().transposed()
	for i in other._v.size():
		_v.append(xf * other._v[i])
		_n.append((nb * other._n[i]).normalized())
	_c.append_array(other._c)
	_uv.append_array(other._uv)
	_uv2.append_array(other._uv2)
	_cu.append_array(other._cu)
	for i in other._idx:
		_idx.append(i + off)


## Rewrites every vertex's material code (and clears animation tags): used for wrecks.
func recode(p_code: int) -> void:
	for i in _uv2.size():
		_uv2[i] = Vector2(p_code, 0)


## Translates all vertices (e.g. lowering a wreck onto its rims).
func shift(off: Vector3) -> void:
	for i in _v.size():
		_v[i] += off


func arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_TEX_UV2] = _uv2
	arr[Mesh.ARRAY_CUSTOM0] = _cu
	arr[Mesh.ARRAY_INDEX] = _idx
	return arr


## Adds this geometry as a surface of `am` (created when null). Returns the mesh.
func commit(mat: Material, am: ArrayMesh = null) -> ArrayMesh:
	if am == null:
		am = ArrayMesh.new()
	if _v.is_empty():
		return am
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(), [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	am.surface_set_material(am.get_surface_count() - 1, mat)
	return am


static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(scale), pos)

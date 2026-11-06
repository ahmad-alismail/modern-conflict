extends RefCounted
## Procedural geometry accumulator. Geometry is grouped per material into one
## surface each, so a complex building/vehicle becomes a single ArrayMesh with a
## handful of surfaces (few draw calls). Vertex colors carry per-part tint, so
## one material can serve many colors (materials should enable vertex_color_use_as_albedo).
## UVs are in meters (world-scale tiling) unless stated otherwise.
class_name MeshKit

var _sts: Dictionary = {}     # material -> SurfaceTool
var _order: Array = []


func _st(mat: Material) -> SurfaceTool:
	var st: SurfaceTool = _sts.get(mat)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mat)
		_sts[mat] = st
		_order.append(mat)
	return st


func is_empty() -> bool:
	return _sts.is_empty()


## Quad from 4 corners (counter-clockwise when seen from the front; emitted with
## Godot's clockwise front-face winding).
func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color = Color.WHITE,
		uv_a := Vector2(0, 1), uv_b := Vector2(1, 1), uv_c := Vector2(1, 0), uv_d := Vector2(0, 0)) -> void:
	var st := _st(mat)
	var n := (b - a).cross(c - a).normalized()
	st.set_color(color)
	st.set_normal(n)
	st.set_uv(uv_a); st.add_vertex(a)
	st.set_uv(uv_c); st.add_vertex(c)
	st.set_uv(uv_b); st.add_vertex(b)
	st.set_uv(uv_a); st.add_vertex(a)
	st.set_uv(uv_d); st.add_vertex(d)
	st.set_uv(uv_c); st.add_vertex(c)


## Axis-aligned (in xf space) box centered at xf.origin with full size `size`.
## faces bitmask: 1 +X, 2 -X, 4 +Y, 8 -Y, 16 +Z, 32 -Z (default all but bottom).
func box(mat: Material, xf: Transform3D, size: Vector3, color: Color = Color.WHITE, faces: int = 55, uv_scale: float = 1.0) -> void:
	var h := size * 0.5
	var p := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var w := []
	for v in p:
		w.append(xf * v)
	var sx := size.x * uv_scale
	var sy := size.y * uv_scale
	var sz := size.z * uv_scale
	if faces & 16: # +Z
		quad(mat, w[4], w[5], w[6], w[7], color, Vector2(0, sy), Vector2(sx, sy), Vector2(sx, 0), Vector2(0, 0))
	if faces & 32: # -Z
		quad(mat, w[1], w[0], w[3], w[2], color, Vector2(0, sy), Vector2(sx, sy), Vector2(sx, 0), Vector2(0, 0))
	if faces & 1: # +X
		quad(mat, w[5], w[1], w[2], w[6], color, Vector2(0, sy), Vector2(sz, sy), Vector2(sz, 0), Vector2(0, 0))
	if faces & 2: # -X
		quad(mat, w[0], w[4], w[7], w[3], color, Vector2(0, sy), Vector2(sz, sy), Vector2(sz, 0), Vector2(0, 0))
	if faces & 4: # +Y
		quad(mat, w[7], w[6], w[2], w[3], color, Vector2(0, sz), Vector2(sx, sz), Vector2(sx, 0), Vector2(0, 0))
	if faces & 8: # -Y
		quad(mat, w[0], w[1], w[5], w[4], color, Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sz), Vector2(0, sz))


## Cylinder / cone frustum along local +Y, base centered at xf.origin.
func cylinder(mat: Material, xf: Transform3D, r_bottom: float, r_top: float, height: float, segments: int = 10,
		color: Color = Color.WHITE, caps: bool = true) -> void:
	var st := _st(mat)
	st.set_color(color)
	var circ := TAU * maxf(r_bottom, r_top)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := xf * (d0 * r_bottom)
		var b1 := xf * (d1 * r_bottom)
		var t0 := xf * (d0 * r_top + Vector3(0, height, 0))
		var t1 := xf * (d1 * r_top + Vector3(0, height, 0))
		var n0 := (xf.basis * d0).normalized()
		var n1 := (xf.basis * d1).normalized()
		var u0 := circ * i / segments
		var u1 := circ * (i + 1) / segments
		st.set_normal(n0); st.set_uv(Vector2(u0, height)); st.add_vertex(b0)
		st.set_normal(n1); st.set_uv(Vector2(u1, height)); st.add_vertex(b1)
		st.set_normal(n1); st.set_uv(Vector2(u1, 0)); st.add_vertex(t1)
		st.set_normal(n0); st.set_uv(Vector2(u0, height)); st.add_vertex(b0)
		st.set_normal(n1); st.set_uv(Vector2(u1, 0)); st.add_vertex(t1)
		st.set_normal(n0); st.set_uv(Vector2(u0, 0)); st.add_vertex(t0)
		if caps:
			var up := (xf.basis * Vector3.UP).normalized()
			var ct := xf * Vector3(0, height, 0)
			if r_top > 0.001:
				st.set_normal(up); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(ct)
				st.set_normal(up); st.add_vertex(t0)
				st.set_normal(up); st.add_vertex(t1)
			var cb := xf.origin
			if r_bottom > 0.001:
				st.set_normal(-up); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(cb)
				st.set_normal(-up); st.add_vertex(b1)
				st.set_normal(-up); st.add_vertex(b0)


## UV sphere (or hemisphere when `half`), centered at xf.origin.
func sphere(mat: Material, xf: Transform3D, radius: float, rings: int = 6, segments: int = 10,
		color: Color = Color.WHITE, half: bool = false) -> void:
	var st := _st(mat)
	st.set_color(color)
	var ring_max := rings if not half else rings / 2
	for r in ring_max:
		var v0 := PI * r / rings
		var v1 := PI * (r + 1) / rings
		for s in segments:
			var u0 := TAU * s / segments
			var u1 := TAU * (s + 1) / segments
			var pts := [_sph(v0, u0), _sph(v0, u1), _sph(v1, u1), _sph(v1, u0)]
			var idx := [0, 2, 1, 0, 3, 2]
			for k in idx:
				var d: Vector3 = pts[k]
				st.set_normal((xf.basis * d).normalized())
				st.set_uv(Vector2(float(s) / segments, float(r) / rings))
				st.add_vertex(xf * (d * radius))


static func _sph(v: float, u: float) -> Vector3:
	return Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))


## Append an existing mesh (all surfaces use `mat`) with a transform.
func mesh(mat: Material, m: Mesh, xf: Transform3D) -> void:
	var st := _st(mat)
	for s in m.get_surface_count():
		st.append_from(m, s, xf)


func commit(shadows: bool = true) -> ArrayMesh:
	var am := ArrayMesh.new()
	for mat in _order:
		var st: SurfaceTool = _sts[mat]
		st.generate_tangents()
		st.commit(am)
	return am


## Convenience: commit into a MeshInstance3D.
func to_instance(cast_shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func xf_at(pos: Vector3, yaw: float = 0.0, scale: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos)


## Standard PBR material using vertex color as albedo tint.
static func mat(color: Color = Color.WHITE, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	return m

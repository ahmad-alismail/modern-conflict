extends RefCounted
## Reusable vehicle components built into a UnitMesh: wheels, tank running gear with
## scrolling track belts, recoiling barrels, machine guns, smoke dischargers, lights,
## antennas, fuel drums, rotors. Wheels/rotors/barrels are tagged with the vehicle
## shader's animation modes so they move without extra nodes.
class_name VehicleParts

const S = preload("res://src/render/units/unit_shaders.gd")

const BLACK := Color(0.07, 0.07, 0.075)
const GUNMETAL := Color(0.16, 0.16, 0.16)
const RUBBER := Color(0.08, 0.08, 0.08)
const GLASS := Color(0.10, 0.14, 0.16)
const CYAN := Color(0.12, 0.85, 1.0)


static func x(p: Vector3, r: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return UnitMesh.xf(p, r, s)


## Transform whose +Y axis points along +Z (cylinders across the vehicle: wheels, axles).
static func xz(p: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p)


## Transform whose +Y axis points along +X (cylinders along the vehicle: barrels, drums).
static func xx(p: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.FORWARD, PI * 0.5), p)


static func recoil_custom(slot: int, stroke: float) -> Color:
	return Color(0, 0, 0, slot + clampf(stroke, 0.0, 1.9) * 0.5)


## Cylinder along Z between z_a and z_b (any order) centered on (cx, cy).
static func zcyl(m: UnitMesh, cx: float, cy: float, z_a: float, z_b: float, r_a: float, r_b: float, seg: int, col: Color, caps: bool = true) -> void:
	if z_b < z_a:
		var t := z_a
		z_a = z_b
		z_b = t
		var tr := r_a
		r_a = r_b
		r_b = tr
	m.cyl(xz(Vector3(cx, cy, z_a)), r_a, r_b, z_b - z_a, seg, col, caps)


## Road wheel / tyre spinning about Z through `c` (outer face toward sign(c.z)).
static func wheel(m: UnitMesh, c: Vector3, r: float, w: float, rim: Color, wreck: bool, style: int = 0) -> void:
	var cb := m.base * c
	var cust := Color(cb.x, cb.y, cb.z, r)
	var sd := signf(c.z) if c.z != 0.0 else 1.0
	var zo := c.z + sd * w * 0.5
	if not wreck:
		m.use(S.M_RUBBER, S.A_ROLL, cust)
		zcyl(m, c.x, c.y, c.z - w * 0.5, c.z + w * 0.5, r, r, 18, RUBBER)
		zcyl(m, c.x, c.y, zo - sd * 0.01, zo + sd * 0.012, r * 0.86, r * 0.8, 18, RUBBER.lightened(0.04))
	m.use(S.M_PAINT if style == 0 else S.M_METAL, S.A_ROLL, cust)
	zcyl(m, c.x, c.y, zo - sd * 0.05, zo + sd * 0.02, r * 0.62, r * 0.6, 14, rim)
	zcyl(m, c.x, c.y, zo, zo + sd * 0.07, r * 0.26, r * 0.2, 8, rim.darkened(0.25))
	if not wreck:
		for k in 6:
			var a := TAU * k / 6.0
			m.box(x(Vector3(c.x + cos(a) * r * 0.4, c.y + sin(a) * r * 0.4, zo + sd * 0.03)), Vector3(0.04, 0.04, 0.03), GUNMETAL)
	m.use(S.M_PAINT, S.A_NONE, Color(0, 0, 0, 0))


## Tank road wheel: rubber tyre + steel disc (+ starfish ribs for older designs).
static func road_wheel(m: UnitMesh, c: Vector3, r: float, w: float, col: Color, starfish: bool, wreck: bool) -> void:
	var cb := m.base * c
	var cust := Color(cb.x, cb.y, cb.z, r)
	var sd := signf(c.z)
	var zo := c.z + sd * w * 0.5
	if not wreck:
		m.use(S.M_RUBBER, S.A_ROLL, cust)
		zcyl(m, c.x, c.y, c.z - w * 0.5, c.z + w * 0.5, r, r, 16, RUBBER)
	m.use(S.M_PAINT, S.A_ROLL, cust)
	zcyl(m, c.x, c.y, c.z - w * 0.5 - 0.006, zo + sd * 0.006, r * 0.84, r * 0.84, 16, col)
	zcyl(m, c.x, c.y, zo, zo + sd * 0.06, r * 0.36, r * 0.3, 10, col.darkened(0.15))
	if starfish and not wreck:
		for k in 5:
			var a := TAU * k / 5.0
			m.box(x(Vector3(c.x + cos(a) * r * 0.52, c.y + sin(a) * r * 0.52, zo + sd * 0.015), Vector3(0, 0, rad_to_deg(a))), Vector3(r * 0.6, 0.07, 0.04), col.darkened(0.12))
	elif not wreck:
		for k in 8:
			var a := TAU * k / 8.0
			m.box(x(Vector3(c.x + cos(a) * r * 0.2, c.y + sin(a) * r * 0.2, zo + sd * 0.065)), Vector3(0.03, 0.03, 0.02), GUNMETAL)
	m.use(S.M_PAINT, S.A_NONE, Color(0, 0, 0, 0))


## Drive sprocket with teeth.
static func sprocket(m: UnitMesh, c: Vector3, r: float, w: float, col: Color, wreck: bool) -> void:
	var cb := m.base * c
	var cust := Color(cb.x, cb.y, cb.z, r)
	var sd := signf(c.z)
	m.use(S.M_METAL, S.A_ROLL, cust)
	zcyl(m, c.x, c.y, c.z - w * 0.5, c.z + w * 0.5, r * 0.82, r * 0.82, 14, col)
	if not wreck:
		for k in 12:
			var a := TAU * k / 12.0
			m.box(x(Vector3(c.x + cos(a) * r * 0.9, c.y + sin(a) * r * 0.9, c.z), Vector3(0, 0, rad_to_deg(a))), Vector3(0.12, 0.07, w * 0.7), col.darkened(0.2))
	zcyl(m, c.x, c.y, c.z + sd * w * 0.5, c.z + sd * (w * 0.5 + 0.08), r * 0.35, r * 0.25, 10, col.darkened(0.3))
	m.use(S.M_PAINT, S.A_NONE, Color(0, 0, 0, 0))


## Full running gear for one side: road wheels, sprocket (rear), idler (front) and a
## track belt (convex hull around the wheels) whose texture scrolls with motion.
static func running_gear(m: UnitMesh, z: float, w: float, wheels_x: Array, r: float, wy: float,
		spr: Vector3, idl: Vector3, wheel_col: Color, track_col: Color, starfish: bool, wreck: bool, thick: float = 0.07) -> void:
	for wx in wheels_x:
		road_wheel(m, Vector3(wx, wy, z), r, w * 0.82, wheel_col, starfish, wreck)
	sprocket(m, Vector3(spr.x, spr.y, z), spr.z, w * 0.7, wheel_col.darkened(0.2), wreck)
	road_wheel(m, Vector3(idl.x, idl.y, z), idl.z, w * 0.7, wheel_col, starfish, wreck)
	var pts := PackedVector2Array()
	var circles := [[spr.x, spr.y, spr.z], [idl.x, idl.y, idl.z]]
	for wx in wheels_x:
		circles.append([wx, wy, r])
	for c in circles:
		for k in 28:
			var a := TAU * k / 28.0
			pts.append(Vector2(c[0] + cos(a) * (c[2] + thick), c[1] + sin(a) * (c[2] + thick)))
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	var area := 0.0
	for i in hull.size():
		area += hull[i].x * hull[(i + 1) % hull.size()].y - hull[(i + 1) % hull.size()].x * hull[i].y
	if area < 0.0:
		hull.reverse()
	m.use(S.M_TRACK, S.A_NONE, Color(0, 0, 0, 0))
	m.belt(hull, z - w * 0.5, z + w * 0.5, thick, track_col)
	m.use(S.M_PAINT)


## Gun tube along +X from `a` with optional sleeve sections; tagged for recoil.
## sections: Array of [length, radius] from breech to muzzle.
static func barrel(m: UnitMesh, a: Vector3, sections: Array, col: Color, slot: int, stroke: float, seg: int = 12) -> Vector3:
	m.use(S.M_PAINT, S.A_RECOIL, recoil_custom(slot, stroke))
	var p := a
	for s in sections:
		var l: float = s[0]
		var r0: float = s[1]
		var r1: float = s[2] if s.size() > 2 else r0
		m.cyl(xx(p), r0, r1, l, seg, col)
		p += Vector3(l, 0, 0)
	m.use(S.M_PAINT, S.A_NONE, Color(0, 0, 0, 0))
	return p


## M2-style heavy machine gun along +X; origin at the cradle pivot. Returns the muzzle.
static func hmg(m: UnitMesh, o: Vector3, slot: int, col: Color = GUNMETAL) -> Vector3:
	m.use(S.M_WEAPON, S.A_RECOIL, recoil_custom(slot, 0.06))
	m.bbox(x(o + Vector3(-0.05, 0.05, 0)), Vector3(0.62, 0.17, 0.16), 0.02, col)
	m.cyl(xx(o + Vector3(0.26, 0.06, 0)), 0.045, 0.045, 0.42, 10, col)
	m.cyl(xx(o + Vector3(0.68, 0.06, 0)), 0.022, 0.02, 0.62, 8, col)
	m.cyl(xx(o + Vector3(1.26, 0.06, 0)), 0.03, 0.03, 0.08, 8, col)
	for zz: float in [-0.06, 0.06]:
		m.tube(o + Vector3(-0.38, -0.02, zz), o + Vector3(-0.38, 0.1, zz), 0.014, 0.014, 6, col)
	m.use(S.M_WEAPON, S.A_NONE, Color(0, 0, 0, 0))
	m.bbox(x(o + Vector3(-0.02, -0.02, -0.17)), Vector3(0.28, 0.18, 0.12), 0.015, Color(0.30, 0.33, 0.22))
	m.box(x(o + Vector3(0, -0.12, 0)), Vector3(0.12, 0.12, 0.1), col)
	m.use(S.M_PAINT)
	return o + Vector3(1.34, 0.06, 0)


## Cluster of smoke grenade dischargers pointing outward along `dir_yaw` (deg).
static func smoke(m: UnitMesh, o: Vector3, yaw: float, rows: int, cols: int, col: Color) -> void:
	m.use(S.M_PAINT)
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	m.bbox(Transform3D(b, o), Vector3(0.2, rows * 0.1 + 0.04, cols * 0.1 + 0.04), 0.02, col)
	for i in rows:
		for j in cols:
			var p := o + b * Vector3(0.08, (i - (rows - 1) * 0.5) * 0.1, (j - (cols - 1) * 0.5) * 0.1)
			var dir := (b * Vector3(1, 0.45, 0)).normalized()
			m.tube(p, p + dir * 0.2, 0.038, 0.038, 8, col.darkened(0.15))
			m.use(S.M_PAINT)


static func antenna(m: UnitMesh, base: Vector3, h: float) -> void:
	m.use(S.M_WEAPON)
	m.cyl(x(base), 0.035, 0.03, 0.08, 6, BLACK)
	m.tube(base, base + Vector3(-0.08, h, 0), 0.008, 0.004, 4, BLACK, false)
	m.use(S.M_PAINT)


static func headlight(m: UnitMesh, p: Vector3, r: float = 0.07, face: Vector3 = Vector3.RIGHT) -> void:
	m.use(S.M_METAL)
	var b := Basis(Vector3.FORWARD, PI * 0.5) if face == Vector3.RIGHT else Basis(Vector3.FORWARD, -PI * 0.5)
	m.cyl(Transform3D(b, p - face * 0.04), r * 1.15, r * 1.1, 0.05, 10, GUNMETAL)
	m.use(S.M_GLASS)
	m.cyl(Transform3D(b, p + face * 0.008), r, r * 0.95, 0.012, 10, Color(0.55, 0.55, 0.5))
	m.use(S.M_PAINT)


## 200 l drum lying along Z (axis across) or X.
static func drum(m: UnitMesh, c: Vector3, along_z: bool, col: Color) -> void:
	m.use(S.M_RUST)
	var t := xz(c - Vector3(0, 0, 0.44)) if along_z else xx(c - Vector3(0.44, 0, 0))
	m.cyl(t, 0.29, 0.29, 0.88, 14, col)
	for k: float in [0.28, 0.6]:
		var tk := xz(c - Vector3(0, 0, 0.44 - k)) if along_z else xx(c - Vector3(0.44 - k, 0, 0))
		m.cyl(tk, 0.3, 0.3, 0.03, 14, col.darkened(0.15), false)
	m.use(S.M_PAINT)


static func jerrycan(m: UnitMesh, c: Vector3, col: Color) -> void:
	m.bbox(x(c), Vector3(0.17, 0.46, 0.33), 0.03, col)
	m.box(x(c + Vector3(0, 0.25, 0.06)), Vector3(0.05, 0.05, 0.12), col.darkened(0.2))


## Octagonal-section body lofted along X through stations [x, half_width, y_bottom, y_top, chamfer].
static func loft_x(m: UnitMesh, stations: Array, col: Color, cap_front: bool = true, cap_back: bool = true) -> void:
	for i in stations.size() - 1:
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		var sa := _sec(a)
		var sb := _sec(b)
		var ca := Vector3(a[0], (a[2] + a[3]) * 0.5, 0)
		var cb := Vector3(b[0], (b[2] + b[3]) * 0.5, 0)
		var ctr := (ca + cb) * 0.5
		for k in sa.size():
			var k2 := (k + 1) % sa.size()
			var quad := [sa[k], sa[k2], sb[k2], sb[k]]
			if (sa[k] - sa[k2]).length() < 0.0005 and (sb[k] - sb[k2]).length() < 0.0005:
				continue
			m.face(Transform3D.IDENTITY, quad, col, ctr)
		if i == 0 and cap_back:
			m.face(Transform3D.IDENTITY, sa, col, ca + Vector3(1, 0, 0))
		if i == stations.size() - 2 and cap_front:
			m.face(Transform3D.IDENTITY, sb, col, cb - Vector3(1, 0, 0))


static func _sec(s: Array) -> Array:
	var px: float = s[0]
	var w: float = maxf(s[1], 0.001)
	var yb: float = s[2]
	var yt: float = s[3]
	var c: float = minf(s[4], minf(w, (yt - yb) * 0.5) * 0.95)
	return [Vector3(px, yb + c, w), Vector3(px, yt - c, w), Vector3(px, yt, w - c), Vector3(px, yt, -w + c),
		Vector3(px, yt - c, -w), Vector3(px, yb + c, -w), Vector3(px, yb, -w + c), Vector3(px, yb, w - c)]


## Rotor blades spinning about the local axis through `hub` (mode = S.A_SPIN_*).
static func rotor(m: UnitMesh, hub: Vector3, axis_mode: int, blades: int, r: float, chord: float, rate: float, col: Color, thick: float = 0.04, phase: float = 0.0) -> void:
	var hb := m.base * hub
	m.use(S.M_PAINT, axis_mode, Color(hb.x, hb.y, hb.z, rate))
	for k in blades:
		var a := phase + TAU * k / blades
		var t: Transform3D
		match axis_mode:
			S.A_SPIN_Y:
				t = Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(6)), hub + Basis(Vector3.UP, a) * Vector3(r * 0.53, 0, 0))
				m.box(t, Vector3(r * 0.92, thick, chord), col)
			S.A_SPIN_Z:
				t = Transform3D(Basis(Vector3.BACK, a), hub + Basis(Vector3.BACK, a) * Vector3(0, r * 0.53, 0))
				m.box(t, Vector3(chord, r * 0.92, thick), col)
			S.A_SPIN_X:
				t = Transform3D(Basis(Vector3.RIGHT, a), hub + Basis(Vector3.RIGHT, a) * Vector3(0, r * 0.53, 0))
				m.box(t, Vector3(thick, r * 0.92, chord), col)
	m.use(S.M_PAINT, S.A_NONE, Color(0, 0, 0, 0))


## Translucent blur disc (separate surface) for a rotor.
static func disc(d: UnitMesh, hub: Vector3, axis_mode: int, r: float) -> void:
	var b := Basis.IDENTITY
	if axis_mode == S.A_SPIN_Z:
		b = Basis(Vector3.RIGHT, PI * 0.5)
	elif axis_mode == S.A_SPIN_X:
		b = Basis(Vector3.BACK, PI * 0.5)
	var pts := []
	var uvs := []
	for k in 32:
		var a := TAU * k / 32.0
		pts.append(hub + b * Vector3(cos(a) * r, 0, sin(a) * r))
		uvs.append(Vector2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))
	d._poly(pts, b * Vector3.UP, Color.WHITE, uvs)

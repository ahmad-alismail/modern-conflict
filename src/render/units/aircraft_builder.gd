extends RefCounted
## Aircraft models (origin at the airframe center, facing +X). Rotors and props spin in
## the vehicle shader (A_SPIN_* about a per-vertex hub), with translucent blur discs on a
## second surface. The chin gun of the Kestrel is the turret.
class_name AircraftBuilder

const S = preload("res://src/render/units/unit_shaders.gd")
const P = preload("res://src/render/units/vehicle_parts.gd")

const KESTREL := Color(0.62, 0.57, 0.45)
const HAC_G := Color(0.31, 0.32, 0.345)
const HAC_D := Color(0.17, 0.175, 0.19)
const CARBON := Color(0.06, 0.06, 0.065)


static func _x(p: Vector3, r: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return UnitMesh.xf(p, r, s)


static func build(def_id: String, c: VehicleBuilder.Ctx) -> void:
	match def_id:
		"cdf_heli": _heli(c)
		"hac_recon": _quad(c)
		"hac_fpv": _fpv(c)
		"hac_wasp": _wasp(c)
		"hac_ucav": _ucav(c)


# ================================================================= Kestrel ===

static func _heli_body(m: UnitMesh, c: VehicleBuilder.Ctx, col: Color) -> void:
	m.use(S.M_VCAMO)
	P.loft_x(m, [[-8.0, 0.15, 0.55, 0.85, 0.05], [-4.0, 0.28, 0.25, 0.95, 0.1], [-2.2, 0.55, -0.55, 1.0, 0.2],
		[1.2, 0.62, -0.75, 1.05, 0.22], [2.6, 0.55, -0.75, 0.62, 0.2], [4.6, 0.45, -0.65, 0.25, 0.16], [5.5, 0.28, -0.48, 0.0, 0.12]], col)
	m.use(S.M_GLASS)
	P.loft_x(m, [[1.1, 0.5, 0.55, 1.05, 0.15], [1.45, 0.48, 0.55, 1.3, 0.24], [2.7, 0.46, 0.5, 1.28, 0.24], [3.0, 0.44, 0.35, 0.95, 0.22],
		[4.4, 0.4, 0.15, 0.9, 0.2], [4.95, 0.3, 0.05, 0.42, 0.12]], Color(0.12, 0.15, 0.17))
	m.use(S.M_VCAMO)
	for s: float in [-1.0, 1.0]:
		m.cyl(P.xx(Vector3(-1.9, 0.82, s * 0.78)), 0.34, 0.37, 2.8, 12, col)
		m.use(S.M_PAINT)
		m.cyl(P.xx(Vector3(0.88, 0.82, s * 0.78)), 0.3, 0.3, 0.03, 12, P.BLACK)
		m.cyl(P.xx(Vector3(-2.05, 0.82, s * 0.78)), 0.26, 0.32, 0.16, 10, Color(0.1, 0.09, 0.08))
		m.use(S.M_VCAMO)
		m.prism(Transform3D(Basis(Vector3.RIGHT, s * deg_to_rad(84)), Vector3(0.25, 0.15, s * 1.45)), VehicleBuilder._pv([-0.35, -0.95, 0.75, -0.95, 0.75, 0.95, -0.25, 0.95]), 0.12, col)
	m.prism(_x(Vector3(0, 0, 0)), VehicleBuilder._pv([-8.65, 0.55, -7.55, 0.7, -8.0, 2.45, -8.65, 2.55]), 0.13, col)
	m.box(_x(Vector3(-8.15, 0.62, 0)), Vector3(0.75, 0.06, 2.5), col)
	m.use(S.M_TEAM)
	for s: float in [-1.0, 1.0]:
		m.box(_x(Vector3(-5.2, 0.62, s * 0.26)), Vector3(0.9, 0.18, 0.02), Color.WHITE)
	m.use(S.M_PAINT)
	m.sphere(_x(Vector3(5.62, -0.38, 0)), 0.36, 8, 12, Color(0.2, 0.2, 0.19))
	m.use(S.M_GLASS)
	m.box(_x(Vector3(5.95, -0.38, 0)), Vector3(0.04, 0.2, 0.3), Color(0.1, 0.12, 0.2))
	m.use(S.M_PAINT)


static func _heli(c: VehicleBuilder.Ctx) -> void:
	var h := c.h
	var col := KESTREL
	var dk := Color(0.18, 0.18, 0.17)
	c.height = 2.4
	c.spin_rate = 15.0
	_heli_body(h, c, col)
	# canopy frames
	h.use(S.M_PAINT)
	for xk: float in [1.45, 2.85, 4.4]:
		h.box(_x(Vector3(xk, 0.95, 0)), Vector3(0.05, 0.5, 0.94), dk)
	# stores: rocket pods (inner) and missile racks (outer)
	var rk := []
	var ms := []
	for s: float in [-1.0, 1.0]:
		h.use(S.M_PAINT)
		h.box(_x(Vector3(0.3, -0.05, s * 1.3)), Vector3(0.5, 0.2, 0.08), dk)
		h.box(_x(Vector3(0.3, -0.05, s * 2.15)), Vector3(0.5, 0.2, 0.08), dk)
		h.cyl(P.xx(Vector3(-0.55, -0.32, s * 1.3)), 0.21, 0.21, 1.6, 12, Color(0.36, 0.38, 0.3))
		h.sphere(_x(Vector3(-0.55, -0.32, s * 1.3), Vector3.ZERO, Vector3(0.5, 1, 1)), 0.21, 6, 12, Color(0.36, 0.38, 0.3))
		h.use(S.M_WEAPON)
		h.cyl(P.xx(Vector3(1.04, -0.32, s * 1.3)), 0.19, 0.19, 0.02, 12, P.BLACK)
		rk.append(Vector3(1.1, -0.32, s * 1.3))
		h.use(S.M_PAINT)
		h.box(_x(Vector3(0.3, -0.18, s * 2.15)), Vector3(1.2, 0.06, 0.5), dk)
		for yy: float in [-0.3, -0.52]:
			for zz: float in [-0.13, 0.13]:
				var p := Vector3(-0.55, yy, s * 2.15 + zz)
				h.use(S.M_WEAPON)
				h.cyl(P.xx(p), 0.085, 0.085, 1.45, 8, Color(0.25, 0.26, 0.22))
				h.cyl(P.xx(p + Vector3(1.45, 0, 0)), 0.085, 0.01, 0.2, 8, Color(0.25, 0.26, 0.22))
				ms.append(p + Vector3(1.65, 0, 0))
	c.muzzle(1, rk, false)
	c.muzzle(2, ms, false)
	# gear, antennas, mast-mounted radar
	h.use(S.M_PAINT)
	for s: float in [-1.0, 1.0]:
		h.tube(Vector3(1.6, -0.6, s * 0.5), Vector3(1.4, -1.15, s * 0.88), 0.05, 0.05, 6, dk)
		P.wheel(h, Vector3(1.4, -1.22, s * 0.9), 0.24, 0.16, Color(0.3, 0.3, 0.3), c.wreck)
	h.tube(Vector3(-7.0, 0.55, 0), Vector3(-7.1, 0.25, 0), 0.03, 0.03, 4, dk)
	h.cyl(_x(Vector3(0.2, 1.0, 0)), 0.14, 0.12, 0.5, 10, dk)
	h.sphere(_x(Vector3(0.2, 2.05, 0), Vector3.ZERO, Vector3(1, 0.55, 1)), 0.42, 8, 12, col.darkened(0.1))
	h.cyl(_x(Vector3(0.2, 1.65, 0)), 0.08, 0.08, 0.4, 8, dk)
	P.antenna(h, Vector3(-3.0, 0.98, 0), 0.6)
	# rotors
	h.use(S.M_PAINT, S.A_SPIN_Y, Color(0.2, 1.55, 0, 1.0))
	h.cyl(_x(Vector3(0.2, 1.48, 0)), 0.32, 0.28, 0.16, 10, dk)
	P.rotor(h, Vector3(0.2, 1.56, 0), S.A_SPIN_Y, 5, 7.2, 0.52, 1.0, Color(0.16, 0.16, 0.15), 0.05)
	P.disc(c.d, Vector3(0.2, 1.58, 0), S.A_SPIN_Y, 7.3)
	h.use(S.M_PAINT, S.A_SPIN_Z, Color(-8.25, 2.0, -0.12, -4.2))
	h.cyl(P.xz(Vector3(-8.25, 2.0, -0.2)), 0.12, 0.12, 0.12, 8, dk)
	P.rotor(h, Vector3(-8.25, 2.0, -0.17), S.A_SPIN_Z, 4, 1.45, 0.22, -4.2, Color(0.16, 0.16, 0.15), 0.03)
	P.disc(c.d, Vector3(-8.25, 2.0, -0.17), S.A_SPIN_Z, 1.48)
	# chin gun turret
	c.turret_at(Vector3(3.55, -0.82, 0))
	var t := c.t
	t.dirt_h = 0.0
	t.use(S.M_PAINT)
	t.cyl(_x(Vector3(0, -0.05, 0)), 0.2, 0.22, 0.12, 10, dk)
	t.bbox(_x(Vector3(0.15, -0.18, 0)), Vector3(0.55, 0.18, 0.22), 0.04, dk)
	var mz := P.barrel(t, Vector3(0.4, -0.2, 0), [[1.2, 0.035], [0.08, 0.045]], P.GUNMETAL, 0, 0.08, 8)
	c.muzzle(0, [mz], true)


# =============================================================== Small drones ===

static func _quad(c: VehicleBuilder.Ctx) -> void:
	var h := c.h
	h.base = Transform3D(Basis().scaled(Vector3.ONE * 1.3), Vector3.ZERO)
	c.height = 0.5
	c.spin_rate = 15.0
	h.use(S.M_PAINT)
	h.bbox(_x(Vector3(0, 0, 0)), Vector3(0.42, 0.12, 0.28), 0.04, HAC_G)
	h.bbox(_x(Vector3(-0.02, 0.07, 0)), Vector3(0.3, 0.05, 0.2), 0.02, HAC_D)
	var k := 0
	for a: float in [45.0, 135.0, 225.0, 315.0]:
		var r := deg_to_rad(a)
		var dir := Vector3(cos(r), 0, sin(r))
		h.use(S.M_PAINT)
		h.box(Transform3D(Basis(Vector3.UP, -r), dir * 0.27), Vector3(0.44, 0.035, 0.045), HAC_D)
		var tip := dir * 0.5
		h.cyl(_x(tip - Vector3(0, 0.03, 0)), 0.045, 0.04, 0.07, 10, HAC_D)
		h.use(S.M_EMIT)
		h.box(_x(tip + Vector3(0, -0.04, 0)), Vector3(0.03, 0.01, 0.03), P.CYAN if a < 180.0 else Color(1.0, 0.15, 0.1))
		var rate := 3.0 if k % 2 == 0 else -3.0
		P.rotor(h, tip + Vector3(0, 0.055, 0), S.A_SPIN_Y, 2, 0.21, 0.04, rate, CARBON, 0.008, r)
		P.disc(c.d, (tip + Vector3(0, 0.06, 0)) * 1.3, S.A_SPIN_Y, 0.21 * 1.3)
		h.use(S.M_PAINT)
		h.tube(tip * 0.7, tip * 0.7 + Vector3(0, -0.16, 0), 0.008, 0.008, 4, CARBON)
		k += 1
	h.sphere(_x(Vector3(0.14, -0.1, 0)), 0.065, 6, 10, HAC_D)
	h.use(S.M_GLASS)
	h.sphere(_x(Vector3(0.19, -0.1, 0)), 0.03, 4, 8, Color(0.05, 0.08, 0.12))
	h.use(S.M_TEAM)
	h.box(_x(Vector3(-0.1, 0.1, 0)), Vector3(0.12, 0.004, 0.06), Color.WHITE)
	h.base = Transform3D.IDENTITY


static func _fpv(c: VehicleBuilder.Ctx) -> void:
	var h := c.h
	h.base = Transform3D(Basis().scaled(Vector3.ONE * 1.5), Vector3.ZERO)
	c.height = 0.4
	c.spin_rate = 15.0
	h.use(S.M_PAINT)
	h.bbox(_x(Vector3(0, 0, 0)), Vector3(0.12, 0.04, 0.07), 0.01, CARBON)
	h.bbox(_x(Vector3(-0.01, 0.04, 0)), Vector3(0.13, 0.045, 0.06), 0.012, Color(0.15, 0.15, 0.17))
	h.use(S.M_CLOTH)
	h.box(_x(Vector3(-0.01, 0.065, 0)), Vector3(0.015, 0.008, 0.065), Color(0.7, 0.1, 0.1))
	h.use(S.M_PAINT)
	var k := 0
	for a: float in [40.0, 140.0, 220.0, 320.0]:
		var r := deg_to_rad(a)
		var dir := Vector3(cos(r), 0, sin(r))
		h.box(Transform3D(Basis(Vector3.UP, -r), dir * 0.07), Vector3(0.15, 0.012, 0.022), CARBON)
		var tip := dir * 0.14
		h.cyl(_x(tip - Vector3(0, 0.005, 0)), 0.016, 0.016, 0.025, 8, Color(0.2, 0.2, 0.22))
		P.rotor(h, tip + Vector3(0, 0.025, 0), S.A_SPIN_Y, 3, 0.065, 0.02, 4.0 if k % 2 == 0 else -4.0, Color(0.1, 0.5, 0.7), 0.004, r)
		P.disc(c.d, (tip + Vector3(0, 0.03, 0)) * 1.5, S.A_SPIN_Y, 0.068 * 1.5)
		h.use(S.M_PAINT)
		k += 1
	h.bbox(_x(Vector3(0.07, 0.015, 0), Vector3(0, 0, 25)), Vector3(0.03, 0.03, 0.03), 0.006, CARBON)
	h.use(S.M_GLASS)
	h.box(_x(Vector3(0.086, 0.022, 0), Vector3(0, 0, 25)), Vector3(0.004, 0.015, 0.015), Color(0.1, 0.1, 0.2))
	h.use(S.M_WEAPON)
	var ol := Color(0.30, 0.33, 0.22)
	h.cyl(P.xx(Vector3(-0.08, -0.05, 0)), 0.028, 0.028, 0.14, 8, ol)
	h.cyl(P.xx(Vector3(0.06, -0.05, 0)), 0.028, 0.042, 0.06, 8, ol)
	h.cyl(P.xx(Vector3(0.12, -0.05, 0)), 0.042, 0.005, 0.09, 8, ol)
	h.box(_x(Vector3(0.0, -0.025, 0)), Vector3(0.03, 0.02, 0.07), CARBON)
	h.tube(Vector3(-0.06, 0.03, -0.02), Vector3(-0.11, 0.09, -0.03), 0.003, 0.003, 4, CARBON, false)
	h.tube(Vector3(-0.06, 0.03, 0.02), Vector3(-0.11, 0.09, 0.03), 0.003, 0.003, 4, CARBON, false)
	h.use(S.M_EMIT)
	h.box(_x(Vector3(-0.066, 0.0, 0)), Vector3(0.004, 0.01, 0.03), P.CYAN)
	h.use(S.M_TEAM)
	h.box(_x(Vector3(-0.01, 0.0, 0.036)), Vector3(0.06, 0.012, 0.003), Color.WHITE)
	h.base = Transform3D.IDENTITY
	c.muzzle(0, [Vector3(0.32, -0.075, 0)], false)


static func _wasp(c: VehicleBuilder.Ctx) -> void:
	var h := c.h
	c.height = 0.5
	c.spin_rate = 15.0
	h.use(S.M_PAINT)
	h.cyl(_x(Vector3(0, -0.06, 0)), 0.22, 0.22, 0.13, 6, HAC_G)
	h.sphere(_x(Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), 0.18, 6, 10, HAC_D, true)
	for k in 6:
		var r := deg_to_rad(30.0 + k * 60.0)
		var dir := Vector3(cos(r), 0, sin(r))
		h.use(S.M_PAINT)
		h.box(Transform3D(Basis(Vector3.UP, -r), dir * 0.45), Vector3(0.5, 0.04, 0.05), HAC_D)
		var tip := dir * 0.7
		h.cyl(_x(tip - Vector3(0, 0.04, 0)), 0.05, 0.045, 0.08, 10, HAC_D)
		h.use(S.M_EMIT)
		if k % 3 == 0:
			h.box(_x(tip + Vector3(0, -0.05, 0)), Vector3(0.03, 0.012, 0.03), P.CYAN)
		P.rotor(h, tip + Vector3(0, 0.06, 0), S.A_SPIN_Y, 2, 0.27, 0.05, 3.0 if k % 2 == 0 else -3.0, CARBON, 0.01, r)
		P.disc(c.d, tip + Vector3(0, 0.065, 0), S.A_SPIN_Y, 0.27)
	h.use(S.M_WEAPON)
	h.cyl(_x(Vector3(0, -0.36, 0)), 0.12, 0.12, 0.28, 8, Color(0.22, 0.23, 0.2))
	for k in 6:
		var r := TAU * k / 6.0
		h.sphere(_x(Vector3(cos(r) * 0.075, -0.37, sin(r) * 0.075)), 0.035, 4, 6, Color(0.30, 0.33, 0.22))
	h.box(_x(Vector3(0, -0.1, 0)), Vector3(0.1, 0.12, 0.1), HAC_D)
	h.use(S.M_PAINT)
	for s: float in [-1.0, 1.0]:
		h.tube(Vector3(0.0, -0.12, s * 0.15), Vector3(0.0, -0.42, s * 0.25), 0.012, 0.012, 4, CARBON)
		h.tube(Vector3(-0.25, -0.42, s * 0.25), Vector3(0.25, -0.42, s * 0.25), 0.012, 0.012, 4, CARBON)
	h.use(S.M_TEAM)
	h.box(_x(Vector3(0.0, 0.0, 0.22)), Vector3(0.14, 0.03, 0.004), Color.WHITE)
	c.muzzle(0, [Vector3(0, -0.5, 0)], false)


static func _ucav(c: VehicleBuilder.Ctx) -> void:
	var h := c.h
	var g := Color(0.34, 0.35, 0.38)
	var gd := HAC_D
	c.height = 1.2
	c.spin_rate = 15.0
	h.use(S.M_PAINT)
	P.loft_x(h, [[-4.4, 0.12, -0.05, 0.18, 0.05], [-3.4, 0.28, -0.25, 0.32, 0.1], [-0.5, 0.42, -0.42, 0.42, 0.16],
		[1.6, 0.45, -0.45, 0.62, 0.18], [2.8, 0.42, -0.42, 0.66, 0.2], [3.5, 0.3, -0.3, 0.42, 0.15], [3.9, 0.1, -0.1, 0.1, 0.05]], g)
	for s: float in [-1.0, 1.0]:
		h.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.15, 0)), VehicleBuilder._pv([0.6, s * 0.3, 0.55, s * 5.1, 0.12, s * 5.1, -0.28, s * 0.3]), 0.1, g)
		var ty := Vector3(0, 0.707, s * 0.707)
		var tb := Basis(Vector3.RIGHT, ty, Vector3.RIGHT.cross(ty))
		h.prism(Transform3D(tb, Vector3(0, 0.12, 0)), VehicleBuilder._pv([-3.35, 0.1, -3.95, 1.75, -4.4, 1.75, -4.4, 0.1]), 0.06, g)
		h.use(S.M_EMIT)
		h.box(_x(Vector3(0.3, 0.15, s * 5.1)), Vector3(0.12, 0.03, 0.03), P.CYAN if s > 0 else Color(1.0, 0.15, 0.1))
		h.use(S.M_PAINT)
	h.prism(_x(Vector3.ZERO), VehicleBuilder._pv([-3.5, -0.1, -4.2, -0.75, -4.45, -0.7, -4.35, -0.05]), 0.05, g)
	h.sphere(_x(Vector3(2.9, -0.48, 0)), 0.22, 8, 12, gd)
	h.use(S.M_GLASS)
	h.sphere(_x(Vector3(3.08, -0.5, 0)), 0.09, 6, 10, Color(0.05, 0.07, 0.12))
	h.use(S.M_TEAM)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(-2.2, 0.15, s * 0.3)), Vector3(0.8, 0.12, 0.02), Color.WHITE)
	var pts := []
	for zz: float in [1.7, 2.7]:
		for s: float in [-1.0, 1.0]:
			h.use(S.M_PAINT)
			h.box(_x(Vector3(0.2, 0.0, s * zz)), Vector3(0.6, 0.2, 0.06), gd)
			h.use(S.M_WEAPON)
			var p := Vector3(-0.55, -0.18, s * zz)
			h.cyl(P.xx(p), 0.085, 0.085, 1.4, 8, Color(0.55, 0.56, 0.52))
			h.cyl(P.xx(p + Vector3(1.4, 0, 0)), 0.085, 0.012, 0.22, 8, Color(0.55, 0.56, 0.52))
			pts.append(p + Vector3(1.65, 0, 0))
	c.muzzle(0, pts, false)
	h.use(S.M_PAINT)
	h.cyl(P.xx(Vector3(-4.6, 0.06, 0)), 0.08, 0.12, 0.2, 8, gd)
	P.rotor(h, Vector3(-4.62, 0.06, 0), S.A_SPIN_X, 3, 1.1, 0.16, 3.0, Color(0.12, 0.12, 0.12), 0.04)
	P.disc(c.d, Vector3(-4.62, 0.06, 0), S.A_SPIN_X, 1.12)


# ================================================================== wrecks ===

static func build_wreck(def_id: String, c: VehicleBuilder.Ctx) -> void:
	var h := c.h
	c.height = 1.5
	match def_id:
		"cdf_heli":
			h.base = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(14)), Vector3(0, 0.8, 0))
			_heli_body(h, c, KESTREL)
			h.base = Transform3D(Basis(Vector3.UP, deg_to_rad(25)) * Basis(Vector3.RIGHT, deg_to_rad(-20)), Vector3(-3.0, 0.5, 1.5))
			h.use(S.M_PAINT)
			h.box(_x(Vector3(1.5, 0, 0), Vector3(0, 0, 4)), Vector3(4.5, 0.06, 0.5), Color(0.2, 0.2, 0.2))
			h.base = Transform3D(Basis(Vector3.UP, deg_to_rad(-70)), Vector3(1.0, 0.1, -2.5))
			h.box(_x(Vector3(1.6, 0, 0), Vector3(0, 0, -3)), Vector3(3.6, 0.06, 0.5), Color(0.2, 0.2, 0.2))
			h.base = Transform3D.IDENTITY
		"hac_ucav":
			h.base = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8)), Vector3(0, 0.42, 0))
			P.loft_x(h, [[-4.4, 0.12, -0.05, 0.18, 0.05], [-0.5, 0.42, -0.42, 0.42, 0.16], [2.8, 0.42, -0.42, 0.66, 0.2], [3.9, 0.1, -0.1, 0.1, 0.05]], HAC_G)
			h.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.15, 0)), VehicleBuilder._pv([0.6, 0.3, 0.55, 5.1, 0.12, 5.1, -0.28, 0.3]), 0.1, HAC_G)
			h.base = Transform3D(Basis(Vector3.UP, deg_to_rad(-30)), Vector3(-1.0, 0.06, -3.5))
			h.box(_x(Vector3.ZERO), Vector3(0.7, 0.1, 3.6), HAC_G)
			h.base = Transform3D.IDENTITY
		_:
			var s := 1.6 if def_id == "hac_wasp" else 1.0
			h.base = Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3.ONE * s), Vector3(0, 0.06, 0))
			h.use(S.M_PAINT)
			h.bbox(_x(Vector3.ZERO), Vector3(0.42, 0.12, 0.28), 0.04, HAC_G)
			h.box(_x(Vector3(0.3, -0.03, 0.2), Vector3(0, 40, 0)), Vector3(0.44, 0.035, 0.045), HAC_D)
			h.box(_x(Vector3(-0.35, -0.03, 0.05), Vector3(0, -70, 8)), Vector3(0.4, 0.035, 0.045), HAC_D)
			h.base = Transform3D.IDENTITY

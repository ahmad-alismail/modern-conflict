extends RefCounted
## Vehicle and aircraft model specs. Each def (+ paint variant) is built once into
## shared meshes: a hull mesh (opaque surface + optional translucent rotor-disc surface)
## and an optional turret mesh, plus muzzle points per loadout slot.
## Wrecks reuse the same builders with details skipped and every surface charred.
## Models face +X, origin at the ground center (aircraft: airframe center), right = +Z.
class_name VehicleBuilder

const S = preload("res://src/render/units/unit_shaders.gd")
const P = preload("res://src/render/units/vehicle_parts.gd")

const CDF_TAN := Color(0.74, 0.64, 0.47)
const CDF_DARK := Color(0.30, 0.28, 0.24)
const PDB_OLIVE := Color(0.43, 0.44, 0.30)
const HAC_GRAPHITE := Color(0.31, 0.32, 0.345)
const HAC_DARK := Color(0.17, 0.175, 0.19)
const TRACK := Color(0.30, 0.29, 0.27)
const CANVAS := Color(0.47, 0.44, 0.33)
const PICKUP_PAINT := [Color(0.88, 0.88, 0.85), Color(0.78, 0.70, 0.55), Color(0.56, 0.33, 0.21)]

static var _cache := {}


## Per-build accumulator handed to every builder function.
class Ctx:
	extends RefCounted
	var h := UnitMesh.new()        # hull, model space
	var t := UnitMesh.new()        # turret, turret space (origin at turret_pos)
	var d := UnitMesh.new()        # translucent rotor discs, model space
	var turret_pos := Vector3.ZERO
	var has_turret := false
	var muzzles: Array = []
	var wreck := false
	var variant := 0
	var height := 2.0
	var spin_rate := 0.0
	var wheels := false
	var extra := {}

	func muzzle(slot: int, pts: Array, on_turret: bool) -> void:
		while muzzles.size() <= slot:
			muzzles.append({"pts": PackedVector3Array([Vector3(0, height * 0.7, 0)]), "on_turret": false})
		muzzles[slot] = {"pts": PackedVector3Array(pts), "on_turret": on_turret}

	func turret_at(p: Vector3) -> void:
		turret_pos = p
		has_turret = true
		t.dirt_h = h.dirt_h
		t.y_base = p.y

	## Detail parts are skipped on wrecks.
	func detail() -> bool:
		return not wreck


static func variant_count(def_id: String) -> int:
	return 3 if def_id in ["pdb_technical", "pdb_spg", "pdb_mrl"] else 1


static func spec(def_id: String, variant: int) -> Dictionary:
	var key := "%s/%d" % [def_id, variant]
	if _cache.has(key):
		return _cache[key]
	var c := Ctx.new()
	c.variant = variant
	_build(def_id, c)
	var mat := S.vehicle_material()
	var hull := c.h.commit(mat)
	if not c.d.is_empty():
		c.d.commit(S.disc_material(), hull)
	var s := {"hull": hull, "height": c.height, "spin_rate": c.spin_rate, "wheels": c.wheels, "muzzles": c.muzzles}
	if c.has_turret:
		s["turret"] = c.t.commit(mat)
		s["turret_pos"] = c.turret_pos
	for k in c.extra:
		s[k] = c.extra[k]
	_cache[key] = s
	return s


static func wreck(def_id: String) -> Dictionary:
	var key := "wreck/" + def_id
	if _cache.has(key):
		return _cache[key]
	var c := Ctx.new()
	c.wreck = true
	var def := Defs.unit(def_id)
	if def["cat"] == Defs.CAT_AIR:
		AircraftBuilder.build_wreck(def_id, c)
	else:
		_build(def_id, c)
		if c.wheels:
			c.h.shift(Vector3(0, -0.18, 0))
	c.h.recode(S.M_CHAR)
	c.t.recode(S.M_CHAR)
	var mat := S.vehicle_material()
	var s := {"hull": c.h.commit(mat)}
	if c.has_turret:
		s["turret"] = c.t.commit(mat)
		var yaw := deg_to_rad(28.0 + float(absi(hash(def_id)) % 30))
		s["turret_xf"] = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, deg_to_rad(-4.0)) * Basis(Vector3.RIGHT, deg_to_rad(3.0)),
			c.turret_pos + Vector3(-0.15, -0.06 - (0.18 if c.wheels else 0.0), 0.12))
	_cache[key] = s
	return s


static func _build(def_id: String, c: Ctx) -> void:
	var def := Defs.unit(def_id)
	if def["cat"] == Defs.CAT_AIR:
		AircraftBuilder.build(def_id, c)
		return
	c.h.dirt_h = 1.4
	match def_id:
		"cdf_mbt": _mbt(c)
		"pdb_tank": _relic(c)
		"cdf_ifv": _ifv(c)
		"cdf_mrap": _mrap(c)
		"cdf_supply": _supply(c)
		"pdb_technical", "pdb_spg", "pdb_mrl": _pickup(c, def_id)
		"hac_ugv_gun", "hac_ugv_atgm": _ugv(c, def_id == "hac_ugv_atgm")
		"hac_ew": _ew(c)
		"hac_mast": _mast_truck(c)
		_:
			c.h.use(S.M_PAINT)
			c.h.bbox(P.x(Vector3(0, 1.0, 0)), Vector3(4, 1.6, 2.2), 0.1, CDF_TAN)


static func _pv(f: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, f.size(), 2):
		out.append(Vector2(f[i], f[i + 1]))
	return out


static func _x(p: Vector3, r: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return UnitMesh.xf(p, r, s)


## Prism extruded along X (profile given as (z, y) pairs).
static func _prism_x(m: UnitMesh, x0: float, x1: float, zy: Array, col: Color) -> void:
	m.prism(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3((x0 + x1) * 0.5, 0, 0)), _pv(zy), x1 - x0, col)


static func _glass_quad(m: UnitMesh, pts: Array, out: Vector3) -> void:
	m.use(S.M_GLASS)
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var shifted := []
	for p in pts:
		shifted.append(p + out.normalized() * 0.012)
	m.face(Transform3D.IDENTITY, shifted, P.GLASS, c - out)
	m.use(S.M_PAINT)


## Team-colour ID panel (both sides) on a hull/turret side face.
static func _team_panels(m: UnitMesh, c: Vector3, size: Vector3) -> void:
	m.use(S.M_TEAM)
	for s: float in [-1.0, 1.0]:
		m.box(_x(Vector3(c.x, c.y, c.z * s)), size, Color.WHITE)
	m.use(S.M_PAINT)


# ============================================================ Sentinel MBT ===

static func _mbt(c: Ctx) -> void:
	var h := c.h
	var tan := CDF_TAN
	var dk := CDF_DARK
	c.height = 3.1
	h.use(S.M_PAINT)
	h.prism(_x(Vector3.ZERO), _pv([-3.65, 0.42, 3.3, 0.42, 3.85, 1.05, -3.75, 1.05]), 2.3, tan.darkened(0.08))
	h.prism(_x(Vector3.ZERO), _pv([-3.85, 1.05, 3.95, 1.05, 3.95, 1.22, 1.45, 1.72, -3.0, 1.74, -3.85, 1.62]), 3.66, tan)
	var wx := []
	for i in 7:
		wx.append(-2.75 + i * 0.9)
	for z: float in [-1.48, 1.48]:
		P.running_gear(h, z, 0.64, wx, 0.33, 0.40, Vector3(-3.45, 0.62, 0.33), Vector3(3.35, 0.58, 0.30), tan.darkened(0.12), TRACK, false, c.wreck)
	h.use(S.M_PAINT)
	for s: float in [-1.0, 1.0]:
		h.prism(_x(Vector3(0, 0, s * 1.86)), _pv([-3.7, 0.62, 3.35, 0.62, 3.78, 0.95, 3.78, 1.22, -3.7, 1.22]), 0.08, tan)
		if c.detail():
			for i in 7:
				h.box(_x(Vector3(-2.9 + i * 0.95, 0.93, s * 1.902)), Vector3(0.025, 0.56, 0.01), tan.darkened(0.25))
			P.headlight(h, Vector3(3.97, 1.14, s * 1.42), 0.06)
			h.box(_x(Vector3(3.93, 1.14, s * 1.24)), Vector3(0.06, 0.18, 0.03), dk)
			h.box(_x(Vector3(3.97, 1.08, s * 0.8)), Vector3(0.06, 0.1, 0.1), dk)
			h.box(_x(Vector3(-3.86, 1.48, s * 1.55)), Vector3(0.03, 0.08, 0.14), Color(0.5, 0.08, 0.06))
		h.box(_x(Vector3(3.55, 1.235, s * 1.5)), Vector3(0.55, 0.03, 0.7), tan)
	if c.detail():
		h.use(S.M_PAINT)
		h.cyl(_x(Vector3(2.05, 1.6, 0)), 0.34, 0.34, 0.06, 12, tan.darkened(0.1))
		h.use(S.M_GLASS)
		h.box(_x(Vector3(2.4, 1.6, 0), Vector3(0, 0, -11)), Vector3(0.12, 0.06, 0.5), P.GLASS)
		h.use(S.M_METAL)
		for s: float in [-1.0, 1.0]:
			h.box(_x(Vector3(-2.2, 1.75, s * 0.75)), Vector3(1.4, 0.02, 0.95), dk)
		h.box(_x(Vector3(-3.865, 1.33, 0)), Vector3(0.03, 0.34, 1.9), dk.darkened(0.3))
		h.use(S.M_PAINT)
		for i in 3:
			h.tube(Vector3(-1.2 + i * 0.5, 1.76, -1.55), Vector3(-1.2 + i * 0.5 + 0.45, 1.76, -1.55), 0.02, 0.02, 4, Color(0.35, 0.25, 0.15))
	# ---- turret
	c.turret_at(Vector3(0.15, 1.73, 0))
	var t := c.t
	t.use(S.M_PAINT)
	var bot := _pv([1.95, -0.5, 1.95, 0.5, 1.25, 1.72, -1.7, 1.78, -2.65, 1.52, -2.65, -1.52, -1.7, -1.78, 1.25, -1.72])
	var top := _pv([1.75, -0.45, 1.75, 0.45, 1.05, 1.58, -1.6, 1.64, -2.55, 1.4, -2.55, -1.4, -1.6, -1.64, 1.05, -1.58])
	t.loft(_x(Vector3.ZERO), bot, 0.0, top, 0.8, tan)
	t.bbox(_x(Vector3(1.98, 0.40, 0)), Vector3(0.42, 0.5, 0.95), 0.05, tan.darkened(0.05))
	var mz := P.barrel(t, Vector3(2.15, 0.42, 0), [[1.15, 0.105], [1.1, 0.095], [0.08, 0.095, 0.135], [0.42, 0.135], [0.08, 0.135, 0.09], [1.35, 0.088], [0.6, 0.083], [0.12, 0.093]], tan, 0, 0.35)
	c.muzzle(0, [mz], true)
	t.use(S.M_WEAPON)
	t.cyl(P.xx(Vector3(1.95, 0.27, 0.38)), 0.028, 0.025, 0.32, 8, P.GUNMETAL)
	c.muzzle(1, [Vector3(2.28, 0.27, 0.38)], true)
	t.use(S.M_PAINT)
	t.bbox(_x(Vector3(-0.85, 0.42, 1.72)), Vector3(1.5, 0.42, 0.14), 0.03, tan)
	t.bbox(_x(Vector3(-0.85, 0.42, -1.72)), Vector3(1.5, 0.42, 0.14), 0.03, tan)
	_team_panels(t, Vector3(-0.85, 0.47, 1.795), Vector3(0.7, 0.16, 0.012))
	if c.detail():
		t.bbox(_x(Vector3(1.2, 0.9, -0.78)), Vector3(0.5, 0.22, 0.42), 0.04, tan)
		t.cyl(_x(Vector3(0.8, 0.78, 0.98)), 0.14, 0.14, 0.22, 10, tan.darkened(0.1))
		t.bbox(_x(Vector3(0.8, 1.1, 0.98)), Vector3(0.36, 0.3, 0.32), 0.04, tan)
		t.use(S.M_GLASS)
		t.box(_x(Vector3(1.455, 0.9, -0.78)), Vector3(0.01, 0.12, 0.3), P.GLASS)
		t.box(_x(Vector3(0.982, 1.1, 0.98)), Vector3(0.01, 0.16, 0.22), P.GLASS)
		t.use(S.M_PAINT)
		t.cyl(_x(Vector3(-0.3, 0.78, 0.85)), 0.42, 0.42, 0.08, 14, tan.darkened(0.1))
		t.bbox(_x(Vector3(-0.35, 1.0, 0.85)), Vector3(0.55, 0.26, 0.4), 0.04, tan)
		P.hmg(t, Vector3(-0.15, 1.2, 0.85), 3)
		t.bbox(_x(Vector3(-0.3, 1.16, 0.62)), Vector3(0.22, 0.16, 0.14), 0.03, dk)
		t.use(S.M_GLASS)
		t.box(_x(Vector3(-0.185, 1.16, 0.62)), Vector3(0.01, 0.08, 0.08), P.GLASS)
		t.use(S.M_PAINT)
		t.cyl(_x(Vector3(-0.45, 0.78, -0.78)), 0.36, 0.36, 0.06, 12, tan.darkened(0.1))
		t.use(S.M_WEAPON)
		t.tube(Vector3(-0.3, 1.0, -0.78), Vector3(0.6, 1.0, -0.78), 0.02, 0.02, 6, P.GUNMETAL)
		t.tube(Vector3(-0.45, 0.82, -0.78), Vector3(-0.3, 1.0, -0.78), 0.02, 0.02, 4, P.GUNMETAL)
		P.smoke(t, Vector3(1.22, 0.58, 1.6), -38.0, 2, 3, tan.darkened(0.08))
		P.smoke(t, Vector3(1.22, 0.58, -1.6), 38.0, 2, 3, tan.darkened(0.08))
		t.use(S.M_CANVAS)
		t.bbox(_x(Vector3(-2.88, 0.46, 0)), Vector3(0.42, 0.44, 2.5), 0.1, CANVAS)
		t.bbox(_x(Vector3(-2.85, 0.75, 0.6)), Vector3(0.35, 0.2, 0.7), 0.08, CANVAS.darkened(0.15))
		t.use(S.M_PAINT)
		for z: float in [-1.3, 0.0, 1.3]:
			t.box(_x(Vector3(-3.12, 0.45, z)), Vector3(0.04, 0.5, 0.04), dk)
		t.box(_x(Vector3(-3.12, 0.7, 0)), Vector3(0.04, 0.04, 2.7), dk)
		P.antenna(t, Vector3(-2.3, 0.8, 1.2), 2.3)
		P.antenna(t, Vector3(-2.3, 0.8, -1.2), 2.0)
		t.tube(Vector3(-1.9, 0.8, 0), Vector3(-1.9, 1.35, 0), 0.015, 0.012, 4, dk)


# ============================================================== Relic tank ===

static func _relic(c: Ctx) -> void:
	var h := c.h
	var ol := PDB_OLIVE
	var dk := Color(0.2, 0.21, 0.17)
	c.height = 2.7
	h.use(S.M_RUST)
	h.prism(_x(Vector3.ZERO), _pv([-3.1, 0.42, 2.75, 0.42, 3.2, 0.9, -3.15, 0.95]), 2.05, ol.darkened(0.1))
	h.prism(_x(Vector3.ZERO), _pv([-3.15, 0.95, 3.2, 0.9, 2.05, 1.52, -2.6, 1.55, -3.15, 1.35]), 2.2, ol)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(0.05, 0.965, s * 1.4)), Vector3(6.35, 0.03, 0.6), ol)
	var wx := [-2.2, -1.12, -0.04, 1.04, 2.12]
	for z: float in [-1.38, 1.38]:
		P.running_gear(h, z, 0.58, wx, 0.41, 0.48, Vector3(-2.95, 0.6, 0.3), Vector3(2.92, 0.55, 0.3), ol.darkened(0.15), TRACK.darkened(0.1), true, c.wreck)
	h.use(S.M_RUST)
	if c.detail():
		for i in 3:
			h.bbox(_x(Vector3(-2.3 + i * 0.95, 1.17, 1.42)), Vector3(0.85, 0.38, 0.48), 0.04, ol.lightened(0.04))
		h.bbox(_x(Vector3(1.4, 1.12, -1.42)), Vector3(1.1, 0.28, 0.45), 0.03, ol)
		h.bbox(_x(Vector3(-0.2, 1.1, -1.42)), Vector3(0.9, 0.24, 0.45), 0.03, ol.darkened(0.05))
		for s: float in [-1.0, 1.0]:
			h.box(_x(Vector3(2.62, 1.22, s * 0.55), Vector3(0, 0, -28)), Vector3(0.5, 0.06, 0.42), TRACK)
			P.headlight(h, Vector3(2.95, 1.12, s * 0.82), 0.07)
		h.box(_x(Vector3(2.35, 1.4, 0), Vector3(0, 0, -28)), Vector3(0.06, 0.12, 1.9), ol.darkened(0.1))
		h.box(_x(Vector3(-2.2, 1.56, 0)), Vector3(1.0, 0.03, 1.2), dk)
		P.drum(h, Vector3(-3.42, 1.12, 0.47), true, Color(0.28, 0.30, 0.24))
		P.drum(h, Vector3(-3.42, 1.12, -0.47), true, Color(0.32, 0.30, 0.25))
		h.use(S.M_CLOTH)
		P.zcyl(h, -3.2, 1.62, -1.1, 1.1, 0.12, 0.11, 8, Color(0.36, 0.26, 0.16))
		h.use(S.M_RUST)
		h.tube(Vector3(-2.8, 1.0, -1.25), Vector3(-3.3, 1.05, -1.25), 0.08, 0.08, 8, dk)
	# ---- turret: rounded dome
	c.turret_at(Vector3(0.45, 1.53, 0))
	var t := c.t
	t.use(S.M_RUST)
	t.cyl(_x(Vector3(0, -0.04, 0)), 1.2, 1.18, 0.07, 18, ol.darkened(0.08))
	t.sphere(_x(Vector3(0.05, 0.0, 0), Vector3.ZERO, Vector3(1.22, 0.6, 1.1)), 1.12, 12, 20, ol, true)
	t.sphere(_x(Vector3(1.22, 0.33, 0), Vector3.ZERO, Vector3(0.62, 0.62, 0.9)), 0.4, 8, 12, ol.darkened(0.05))
	var mz := P.barrel(t, Vector3(1.35, 0.33, 0), [[2.8, 0.085, 0.074], [0.06, 0.074, 0.11], [0.36, 0.11], [0.06, 0.11, 0.072], [1.28, 0.068], [0.08, 0.075]], ol, 0, 0.3, 10)
	c.muzzle(0, [mz], true)
	t.use(S.M_WEAPON)
	t.cyl(P.xx(Vector3(1.3, 0.22, 0.32)), 0.025, 0.022, 0.2, 6, P.GUNMETAL)
	c.muzzle(1, [Vector3(1.5, 0.22, 0.32)], true)
	_team_panels(t, Vector3(-0.35, 0.3, 1.07), Vector3(0.55, 0.11, 0.08))
	t.use(S.M_RUST)
	if c.detail():
		t.cyl(_x(Vector3(-0.25, 0.52, 0.5)), 0.34, 0.32, 0.2, 12, ol.darkened(0.05))
		t.cyl(_x(Vector3(-0.2, 0.58, -0.5)), 0.3, 0.3, 0.06, 12, ol.darkened(0.05))
		P.hmg(t, Vector3(-0.15, 0.98, -0.5), 3)
		t.tube(Vector3(-0.2, 0.62, -0.5), Vector3(-0.15, 0.86, -0.5), 0.03, 0.03, 6, P.GUNMETAL)
		t.bbox(_x(Vector3(1.0, 0.62, 0.48)), Vector3(0.22, 0.34, 0.34), 0.04, ol.darkened(0.1))
		P.headlight(t, Vector3(1.11, 0.62, 0.48), 0.13)
		P.antenna(t, Vector3(-0.9, 0.45, 0.3), 2.2)
		t.use(S.M_RUST)
		for k in 6:
			var a := deg_to_rad(-60.0 + k * 24.0) + PI
			t.box(_x(Vector3(cos(a) * 1.2, 0.42, sin(a) * 1.08), Vector3(0, -rad_to_deg(a), 0)), Vector3(0.04, 0.04, 0.32), dk)


# ================================================================= Warden ===

static func _ifv(c: Ctx) -> void:
	var h := c.h
	var tan := CDF_TAN
	var dk := CDF_DARK
	c.height = 3.1
	h.use(S.M_PAINT)
	h.prism(_x(Vector3.ZERO), _pv([-3.25, 0.45, 2.7, 0.45, 3.25, 1.0, -3.25, 1.0]), 2.2, tan.darkened(0.08))
	h.prism(_x(Vector3.ZERO), _pv([-3.3, 1.0, 3.3, 1.0, 3.3, 1.12, 2.25, 1.9, -3.3, 1.98]), 3.1, tan)
	var wx := []
	for i in 6:
		wx.append(-2.45 + i * 0.95)
	for z: float in [-1.33, 1.33]:
		P.running_gear(h, z, 0.56, wx, 0.32, 0.39, Vector3(2.95, 0.66, 0.3), Vector3(-3.05, 0.6, 0.28), tan.darkened(0.12), TRACK, false, c.wreck)
	h.use(S.M_PAINT)
	for s: float in [-1.0, 1.0]:
		h.prism(_x(Vector3(0, 0, s * 1.6)), _pv([-3.2, 0.62, 2.6, 0.62, 3.05, 1.0, -3.2, 1.0]), 0.07, tan)
		h.bbox(_x(Vector3(-0.55, 1.45, s * 1.575)), Vector3(5.1, 0.82, 0.06), 0.02, tan)
		if c.detail():
			for i in 9:
				for j in 2:
					h.box(_x(Vector3(-2.9 + i * 0.62, 1.2 + j * 0.5, s * 1.61)), Vector3(0.04, 0.04, 0.02), dk)
			P.headlight(h, Vector3(3.31, 1.05, s * 1.25), 0.06)
			h.box(_x(Vector3(-3.32, 1.75, s * 1.35)), Vector3(0.03, 0.08, 0.14), Color(0.5, 0.08, 0.06))
			h.bbox(_x(Vector3(-2.95, 1.55, s * 1.62)), Vector3(0.5, 0.5, 0.12), 0.03, tan.darkened(0.06))
	# rear ramp
	h.box(_x(Vector3(-3.33, 1.22, 0)), Vector3(0.05, 1.3, 1.9), tan.darkened(0.06))
	P.zcyl(h, -3.33, 0.58, -0.95, 0.95, 0.05, 0.05, 8, dk)
	if c.detail():
		h.box(_x(Vector3(-3.36, 1.3, 0.38)), Vector3(0.03, 0.9, 0.62), tan.darkened(0.12))
		h.box(_x(Vector3(-3.38, 1.35, 0.15)), Vector3(0.03, 0.04, 0.12), dk)
		h.cyl(_x(Vector3(2.35, 1.86, -0.95)), 0.3, 0.3, 0.06, 12, tan.darkened(0.1))
		h.use(S.M_METAL)
		h.box(_x(Vector3(1.8, 1.94, 1.1)), Vector3(0.8, 0.02, 0.5), dk.darkened(0.3))
		h.use(S.M_PAINT)
		h.box(_x(Vector3(3.0, 1.32, 0), Vector3(0, 0, -36)), Vector3(0.05, 0.3, 2.3), tan.darkened(0.04))
	# ---- turret
	c.turret_at(Vector3(-0.1, 1.97, -0.15))
	var t := c.t
	t.use(S.M_PAINT)
	t.loft(_x(Vector3.ZERO), _pv([1.05, -0.5, 1.05, 0.5, 0.6, 1.0, -1.0, 1.0, -1.25, 0.75, -1.25, -0.75, -1.0, -1.0, 0.6, -1.0]), 0.0,
		_pv([0.9, -0.42, 0.9, 0.42, 0.5, 0.86, -0.92, 0.86, -1.15, 0.65, -1.15, -0.65, -0.92, -0.86, 0.5, -0.86]), 0.62, tan)
	t.bbox(_x(Vector3(1.08, 0.33, 0.1)), Vector3(0.26, 0.3, 0.42), 0.04, tan.darkened(0.06))
	var mz := P.barrel(t, Vector3(1.2, 0.33, 0.1), [[0.55, 0.075], [1.5, 0.042], [0.18, 0.056]], dk, 0, 0.12, 10)
	c.muzzle(0, [mz], true)
	t.use(S.M_PAINT)
	t.bbox(_x(Vector3(-0.1, 0.44, -1.13)), Vector3(1.3, 0.4, 0.42), 0.04, tan)
	t.box(_x(Vector3(-0.1, 0.3, -0.93)), Vector3(0.3, 0.12, 0.1), dk)
	t.use(S.M_WEAPON)
	for y: float in [0.35, 0.53]:
		t.cyl(P.xx(Vector3(0.54, y, -1.13)), 0.075, 0.075, 0.02, 10, P.BLACK)
	c.muzzle(1, [Vector3(0.58, 0.53, -1.13), Vector3(0.58, 0.35, -1.13)], true)
	t.cyl(P.xx(Vector3(1.05, 0.24, 0.38)), 0.022, 0.02, 0.25, 6, P.GUNMETAL)
	c.muzzle(2, [Vector3(1.3, 0.24, 0.38)], true)
	_team_panels(t, Vector3(-0.1, 0.48, 1.0), Vector3(0.5, 0.15, 0.02))
	t.use(S.M_PAINT)
	if c.detail():
		t.cyl(_x(Vector3(-0.55, 0.6, 0.45)), 0.14, 0.14, 0.18, 10, tan.darkened(0.1))
		t.bbox(_x(Vector3(-0.55, 0.88, 0.45)), Vector3(0.36, 0.28, 0.3), 0.04, tan)
		t.bbox(_x(Vector3(0.45, 0.72, -0.5)), Vector3(0.42, 0.2, 0.34), 0.04, tan)
		t.use(S.M_GLASS)
		t.box(_x(Vector3(-0.367, 0.88, 0.45)), Vector3(0.01, 0.15, 0.2), P.GLASS)
		t.box(_x(Vector3(0.665, 0.72, -0.5)), Vector3(0.01, 0.1, 0.24), P.GLASS)
		P.smoke(t, Vector3(0.7, 0.45, 0.95), -40.0, 2, 2, tan.darkened(0.08))
		P.smoke(t, Vector3(0.7, 0.45, -0.95), 40.0, 2, 2, tan.darkened(0.08))
		t.use(S.M_CANVAS)
		t.bbox(_x(Vector3(-1.38, 0.38, 0)), Vector3(0.3, 0.36, 1.4), 0.08, CANVAS)
		P.antenna(t, Vector3(-1.0, 0.62, 0.6), 2.0)
		P.antenna(t, Vector3(-1.0, 0.62, -0.6), 1.7)


# ================================================================ Bulwark ===

static func _mrap(c: Ctx) -> void:
	var h := c.h
	var tan := CDF_TAN
	var dk := CDF_DARK
	c.height = 3.7
	c.wheels = true
	h.use(S.M_PAINT)
	_prism_x(h, -3.0, 2.3, [-0.55, 0.62, 0.55, 0.62, 1.22, 1.18, 1.22, 1.5, -1.22, 1.5, -1.22, 1.18], tan.darkened(0.06))
	h.prism(_x(Vector3.ZERO), _pv([-3.05, 1.5, 2.2, 1.5, 3.15, 1.55, 3.2, 1.98, 2.2, 2.08, 1.72, 2.82, -3.05, 2.85]), 2.36, tan)
	for wxp: float in [2.05, -1.95]:
		for s: float in [-1.0, 1.0]:
			P.wheel(h, Vector3(wxp, 0.56, s * 1.06), 0.56, 0.42, Color(0.42, 0.40, 0.34), c.wreck)
			h.use(S.M_PAINT)
			h.box(_x(Vector3(wxp, 1.53, s * 1.07)), Vector3(1.35, 0.05, 0.48), tan.darkened(0.04))
	h.use(S.M_PAINT)
	h.tube(Vector3(2.05, 0.56, -1.0), Vector3(2.05, 0.56, 1.0), 0.07, 0.07, 6, dk)
	h.tube(Vector3(-1.95, 0.56, -1.0), Vector3(-1.95, 0.56, 1.0), 0.07, 0.07, 6, dk)
	# windshield + armoured glass
	var n := Vector3(0.84, 0.545, 0)
	for zz in [[-1.08, -0.06], [0.06, 1.08]]:
		var a := Vector3(2.17, 2.13, zz[0])
		var b := Vector3(2.17, 2.13, zz[1])
		var c2 := Vector3(1.76, 2.76, zz[1])
		var d := Vector3(1.76, 2.76, zz[0])
		_glass_quad(h, [a, b, c2, d], n)
	h.use(S.M_GLASS)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(1.3, 2.33, s * 1.19)), Vector3(0.78, 0.44, 0.04), P.GLASS)
		for wxp: float in [-0.45, -1.55]:
			h.box(_x(Vector3(wxp, 2.4, s * 1.19)), Vector3(0.36, 0.3, 0.04), P.GLASS)
	h.use(S.M_PAINT)
	h.bbox(_x(Vector3(3.27, 1.22, 0)), Vector3(0.2, 0.26, 2.3), 0.04, dk)
	_team_panels(h, Vector3(0.4, 2.35, 1.185), Vector3(0.5, 0.18, 0.02))
	if c.detail():
		h.use(S.M_METAL)
		h.box(_x(Vector3(3.205, 1.76, 0)), Vector3(0.02, 0.3, 1.3), dk.darkened(0.4))
		h.use(S.M_PAINT)
		for s: float in [-1.0, 1.0]:
			P.headlight(h, Vector3(3.22, 1.75, s * 0.92), 0.08)
			h.box(_x(Vector3(2.05, 2.35, s * 1.3)), Vector3(0.05, 0.05, 0.25), dk)
			h.bbox(_x(Vector3(2.05, 2.3, s * 1.43)), Vector3(0.04, 0.24, 0.16), 0.01, dk)
			h.box(_x(Vector3(0.9, 1.3, s * 1.15)), Vector3(0.4, 0.04, 0.22), dk)
			h.box(_x(Vector3(-3.07, 2.6, s * 1.0)), Vector3(0.03, 0.08, 0.14), Color(0.5, 0.08, 0.06))
		h.box(_x(Vector3(-3.07, 2.05, 0)), Vector3(0.03, 1.1, 0.9), tan.darkened(0.1))
		h.box(_x(Vector3(-3.15, 1.35, 0)), Vector3(0.2, 0.05, 0.8), dk)
		P.antenna(h, Vector3(-2.7, 2.85, 0.95), 2.4)
		P.antenna(h, Vector3(-2.7, 2.85, -0.95), 2.4)
		h.bbox(_x(Vector3(-2.2, 2.95, 0)), Vector3(0.5, 0.18, 0.6), 0.04, tan.darkened(0.08))
		h.cyl(_x(Vector3(0.9, 2.82, 0.5)), 0.3, 0.3, 0.06, 12, tan.darkened(0.1))
	# ---- roof turret: ring, gunner shield with armoured glass, M2
	c.turret_at(Vector3(-0.45, 2.85, 0))
	var t := c.t
	t.use(S.M_PAINT)
	t.cyl(_x(Vector3(0, 0, 0)), 0.68, 0.66, 0.12, 16, tan.darkened(0.08))
	t.prism(_x(Vector3(0.6, 0, 0)), _pv([-0.03, 0.1, 0.03, 0.1, 0.03, 0.78, -0.03, 0.72]), 0.9, tan)
	for s: float in [-1.0, 1.0]:
		t.prism(Transform3D(Basis(Vector3.UP, s * deg_to_rad(55)), Vector3(0.3, 0, s * 0.62)), _pv([-0.03, 0.1, 0.03, 0.1, 0.03, 0.7, -0.03, 0.66]), 0.6, tan)
	t.use(S.M_GLASS)
	t.box(_x(Vector3(0.635, 0.6, 0.26)), Vector3(0.02, 0.2, 0.3), P.GLASS)
	t.use(S.M_PAINT)
	var mz := P.hmg(t, Vector3(0.2, 0.42, -0.12), 0)
	c.muzzle(0, [mz], true)
	t.tube(Vector3(0.1, 0.1, -0.12), Vector3(0.1, 0.32, -0.12), 0.04, 0.04, 6, dk)


# ============================================================ Supply truck ===

static func _supply(c: Ctx) -> void:
	var h := c.h
	var tan := CDF_TAN
	var dk := CDF_DARK
	c.height = 3.0
	c.wheels = true
	h.use(S.M_PAINT)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(-0.15, 0.85, s * 0.45)), Vector3(6.5, 0.22, 0.12), dk)
	for wxp: float in [2.55, -1.15, -2.45]:
		for s: float in [-1.0, 1.0]:
			P.wheel(h, Vector3(wxp, 0.55, s * 1.0), 0.55, 0.38, Color(0.40, 0.38, 0.33), c.wreck)
		h.use(S.M_PAINT)
		h.tube(Vector3(wxp, 0.55, -0.9), Vector3(wxp, 0.55, 0.9), 0.06, 0.06, 6, dk)
	h.use(S.M_PAINT)
	h.prism(_x(Vector3.ZERO), _pv([1.9, 1.0, 3.35, 1.0, 3.42, 1.55, 3.3, 2.6, 3.05, 2.78, 1.9, 2.78]), 2.4, tan)
	_glass_quad(h, [Vector3(3.32, 1.95, -1.05), Vector3(3.32, 1.95, 1.05), Vector3(3.27, 2.55, 1.05), Vector3(3.27, 2.55, -1.05)], Vector3(1, 0.08, 0))
	h.use(S.M_GLASS)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(2.9, 2.22, s * 1.2)), Vector3(0.62, 0.5, 0.02), P.GLASS)
	h.use(S.M_PAINT)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(2.55, 1.12, s * 1.05)), Vector3(1.2, 0.06, 0.45), tan.darkened(0.05))
		h.bbox(_x(Vector3(1.3, 0.95, s * 1.0)), Vector3(0.8, 0.4, 0.35), 0.06, dk.lightened(0.05))
	h.bbox(_x(Vector3(3.48, 0.98, 0)), Vector3(0.14, 0.24, 2.4), 0.03, dk)
	# cargo bed + canvas
	h.box(_x(Vector3(-0.95, 1.22, 0)), Vector3(5.1, 0.16, 2.44), dk.lightened(0.05))
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(-0.95, 1.5, s * 1.2)), Vector3(5.1, 0.42, 0.05), tan)
	h.use(S.M_CANVAS)
	_prism_x(h, -3.48, 1.6, [-1.24, 1.68, 1.24, 1.68, 1.24, 2.45, 0.92, 2.8, 0.0, 2.9, -0.92, 2.8, -1.24, 2.45], CANVAS.lightened(0.08))
	h.use(S.M_PAINT)
	h.box(_x(Vector3(-3.49, 2.2, 0)), Vector3(0.02, 1.0, 2.2), Color(0.06, 0.06, 0.06))
	_team_panels(h, Vector3(2.6, 1.6, 1.205), Vector3(0.45, 0.25, 0.02))
	if c.detail():
		h.use(S.M_CANVAS)
		for i in 5:
			h.box(_x(Vector3(-3.1 + i * 1.12, 2.45, 0)), Vector3(0.05, 0.06, 2.52), CANVAS.darkened(0.15))
		h.use(S.M_PAINT)
		for s: float in [-1.0, 1.0]:
			P.headlight(h, Vector3(3.43, 1.28, s * 0.95), 0.08)
			h.box(_x(Vector3(3.2, 2.3, s * 1.35)), Vector3(0.05, 0.05, 0.25), dk)
			h.bbox(_x(Vector3(3.2, 2.25, s * 1.48)), Vector3(0.04, 0.3, 0.16), 0.01, dk)
			h.box(_x(Vector3(-3.5, 1.15, s * 1.0)), Vector3(0.03, 0.08, 0.14), Color(0.5, 0.08, 0.06))
		h.use(S.M_METAL)
		h.box(_x(Vector3(3.44, 1.42, 0)), Vector3(0.02, 0.22, 1.2), dk.darkened(0.4))
		h.use(S.M_PAINT)
		for i in 3:
			P.jerrycan(h, Vector3(-3.25, 1.53, -0.7 + i * 0.36), Color(0.32, 0.34, 0.24))
		h.bbox(_x(Vector3(-2.7, 1.5, 0.6)), Vector3(0.6, 0.4, 0.5), 0.03, Color(0.32, 0.34, 0.24))
		P.antenna(h, Vector3(2.0, 2.78, 1.0), 1.8)
		h.use(S.M_RUBBER)
		P.zcyl(h, 1.72, 2.05, -0.2, 0.2, 0.5, 0.5, 14, P.RUBBER)


# ================================================================= Pickups ===

static func _pickup(c: Ctx, def_id: String) -> void:
	var h := c.h
	var paint: Color = PICKUP_PAINT[c.variant % PICKUP_PAINT.size()]
	var code := S.M_RUST if c.variant == 2 else S.M_PAINT
	var dk := Color(0.1, 0.1, 0.1)
	c.height = 2.4
	c.wheels = true
	h.use(code)
	h.prism(_x(Vector3.ZERO), _pv([-0.55, 0.5, 2.35, 0.5, 2.6, 0.72, 2.58, 0.98, 1.3, 1.1, -0.55, 1.12]), 1.8, paint)
	h.prism(_x(Vector3.ZERO), _pv([-2.6, 0.5, -0.55, 0.5, -0.55, 0.86, -2.6, 0.86]), 1.8, paint)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(-1.58, 1.0, s * 0.875)), Vector3(2.05, 0.3, 0.05), paint)
	h.box(_x(Vector3(-2.575, 1.0, 0)), Vector3(0.05, 0.3, 1.8), paint)
	h.box(_x(Vector3(-0.58, 1.0, 0)), Vector3(0.05, 0.3, 1.8), paint)
	h.use(S.M_PAINT)
	h.box(_x(Vector3(-1.58, 0.865, 0)), Vector3(1.98, 0.012, 1.7), paint.darkened(0.45))
	h.use(code)
	h.prism(_x(Vector3.ZERO), _pv([-0.55, 1.1, 1.28, 1.1, 0.72, 1.72, -0.48, 1.76]), 1.66, paint)
	_glass_quad(h, [Vector3(1.22, 1.17, -0.78), Vector3(1.22, 1.17, 0.78), Vector3(0.76, 1.68, 0.76), Vector3(0.76, 1.68, -0.76)], Vector3(0.74, 0.67, 0))
	for s: float in [-1.0, 1.0]:
		var zz := s * 0.83
		_glass_quad(h, [Vector3(-0.42, 1.2, zz), Vector3(1.1, 1.2, zz), Vector3(0.68, 1.66, zz), Vector3(-0.4, 1.69, zz)], Vector3(0, 0, s))
	_glass_quad(h, [Vector3(-0.552, 1.25, 0.65), Vector3(-0.552, 1.25, -0.65), Vector3(-0.5, 1.62, -0.6), Vector3(-0.5, 1.62, 0.6)], Vector3(-1, 0, 0))
	for wxp: float in [1.5, -1.55]:
		for s: float in [-1.0, 1.0]:
			P.wheel(h, Vector3(wxp, 0.38, s * 0.8), 0.38, 0.28, Color(0.55, 0.55, 0.55), c.wreck, 1)
			h.use(S.M_PAINT)
			h.box(_x(Vector3(wxp, 0.84, s * 0.9)), Vector3(0.95, 0.1, 0.07), dk)
	h.use(S.M_METAL)
	h.bbox(_x(Vector3(2.64, 0.6, 0)), Vector3(0.12, 0.18, 1.82), 0.03, Color(0.45, 0.45, 0.45))
	h.bbox(_x(Vector3(-2.64, 0.62, 0)), Vector3(0.1, 0.14, 1.8), 0.03, Color(0.3, 0.3, 0.3))
	h.use(S.M_PAINT)
	h.box(_x(Vector3(2.6, 0.84, 0)), Vector3(0.02, 0.18, 0.95), dk)
	_team_panels(h, Vector3(0.35, 0.82, 0.903), Vector3(0.6, 0.14, 0.01))
	if c.detail():
		for s: float in [-1.0, 1.0]:
			P.headlight(h, Vector3(2.585, 0.86, s * 0.68), 0.075)
			h.box(_x(Vector3(-2.61, 0.95, s * 0.8)), Vector3(0.03, 0.16, 0.1), Color(0.6, 0.06, 0.04))
			h.box(_x(Vector3(1.1, 1.32, s * 0.95)), Vector3(0.04, 0.1, 0.16), dk)
			h.box(_x(Vector3(0.25, 0.8, s * 0.905)), Vector3(0.012, 0.55, 0.01), paint.darkened(0.4))
			h.box(_x(Vector3(-0.35, 1.0, s * 0.906)), Vector3(0.1, 0.03, 0.01), dk)
	# ---- weapon fits
	var t := c.t
	match def_id:
		"pdb_technical":
			h.use(S.M_WEAPON)
			h.tube(Vector3(-1.45, 0.87, 0), Vector3(-1.45, 1.55, 0), 0.05, 0.045, 8, P.GUNMETAL)
			for k in 3:
				var a := TAU * k / 3.0
				h.tube(Vector3(-1.45, 1.1, 0), Vector3(-1.45 + cos(a) * 0.45, 0.87, sin(a) * 0.45), 0.025, 0.025, 4, P.GUNMETAL)
			c.turret_at(Vector3(-1.45, 1.62, 0))
			var mz := P.hmg(t, Vector3(0.05, 0.05, 0), 0)
			c.muzzle(0, [mz], true)
			t.use(S.M_WEAPON)
			t.bbox(_x(Vector3(0.42, 0.12, 0)), Vector3(0.03, 0.42, 0.62), 0.01, Color(0.25, 0.27, 0.2))
			t.tube(Vector3(-0.42, 0.0, 0.0), Vector3(-0.42, 0.18, 0.0), 0.016, 0.016, 6, P.GUNMETAL)
		"pdb_spg":
			h.use(S.M_WEAPON)
			h.tube(Vector3(-1.35, 0.87, 0), Vector3(-1.35, 1.5, 0), 0.07, 0.06, 8, P.GUNMETAL)
			c.turret_at(Vector3(-1.35, 1.58, 0))
			t.use(S.M_WEAPON)
			t.bbox(_x(Vector3(0, 0.02, 0)), Vector3(0.36, 0.14, 0.2), 0.02, P.GUNMETAL)
			var col := Color(0.30, 0.33, 0.22)
			t.use(S.M_PAINT, S.A_RECOIL, P.recoil_custom(0, 0.06))
			t.cyl(P.xx(Vector3(-1.55, 0.14, 0)), 0.075, 0.075, 3.25, 12, col)
			t.cyl(P.xx(Vector3(-1.9, 0.14, 0)), 0.14, 0.085, 0.36, 12, col.darkened(0.2))
			t.cyl(P.xx(Vector3(1.66, 0.14, 0)), 0.085, 0.085, 0.08, 12, col.darkened(0.25))
			t.cyl(P.xx(Vector3(-0.6, 0.27, 0)), 0.018, 0.018, 1.7, 6, P.GUNMETAL)
			t.use(S.M_WEAPON, S.A_NONE, Color(0, 0, 0, 0))
			t.bbox(_x(Vector3(-0.2, 0.22, -0.13)), Vector3(0.22, 0.12, 0.08), 0.02, P.BLACK)
			t.bbox(_x(Vector3(0.05, 0.12, 0.12)), Vector3(0.16, 0.08, 0.06), 0.02, P.GUNMETAL)
			c.muzzle(0, [Vector3(1.75, 0.14, 0)], true)
		"pdb_mrl":
			c.turret_at(Vector3(-1.55, 0.88, 0))
			t.use(S.M_WEAPON)
			t.cyl(_x(Vector3(0, 0, 0)), 0.45, 0.45, 0.1, 14, P.GUNMETAL)
			t.box(_x(Vector3(0.0, 0.25, 0)), Vector3(0.3, 0.32, 0.5), P.GUNMETAL)
			var el := deg_to_rad(22.0)
			var b := Basis(Vector3.BACK, el)
			var o := Vector3(0.05, 0.62, 0)
			var col := Color(0.34, 0.36, 0.25)
			t.use(S.M_RUST)
			t.bbox(Transform3D(b, o), Vector3(0.95, 0.42, 0.56), 0.03, col.darkened(0.15))
			var pts := []
			for i in 3:
				for j in 4:
					var lc := Vector3(-0.48, (i - 1) * 0.13, (j - 1.5) * 0.13)
					t.cyl(Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), o + b * lc), 0.058, 0.058, 0.98, 10, col)
					pts.append(o + b * (lc + Vector3(0.5, 0, 0)))
			t.use(S.M_WEAPON)
			for i in 3:
				for j in 4:
					var lc := Vector3(0.505, (i - 1) * 0.13, (j - 1.5) * 0.13)
					t.cyl(Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), o + b * lc), 0.045, 0.045, 0.005, 8, P.BLACK)
			c.muzzle(0, pts, true)


# ==================================================================== UGVs ===

static func _ugv(c: Ctx, atgm: bool) -> void:
	var h := c.h
	var g := HAC_GRAPHITE
	var gd := HAC_DARK
	c.height = 1.9
	h.dirt_h = 0.8
	h.use(S.M_PAINT)
	h.bbox(_x(Vector3(0, 0.6, 0)), Vector3(2.5, 0.42, 1.08), 0.08, g)
	for z: float in [-0.78, 0.78]:
		P.running_gear(h, z, 0.42, [-0.85, -0.3, 0.25, 0.8], 0.17, 0.24, Vector3(-1.2, 0.42, 0.2), Vector3(1.22, 0.4, 0.18), gd, TRACK.darkened(0.2), false, c.wreck)
		h.use(S.M_PAINT)
		h.bbox(_x(Vector3(0, 0.52, z * 1.29)), Vector3(2.3, 0.28, 0.05), 0.02, g)
		h.box(_x(Vector3(0, 0.52, z * 0.72)), Vector3(2.2, 0.3, 0.04), gd)
		h.use(S.M_EMIT)
		h.box(_x(Vector3(0.2, 0.6, z * 1.32)), Vector3(1.2, 0.015, 0.006), P.CYAN)
		h.use(S.M_PAINT)
	_team_panels(h, Vector3(-0.75, 0.48, 1.32), Vector3(0.4, 0.1, 0.01))
	h.bbox(_x(Vector3(1.28, 0.74, 0)), Vector3(0.22, 0.18, 0.52), 0.04, gd)
	h.use(S.M_GLASS)
	h.box(_x(Vector3(1.392, 0.75, 0)), Vector3(0.01, 0.1, 0.36), P.GLASS)
	h.use(S.M_EMIT)
	for zz: float in [-0.14, 0.14]:
		h.box(_x(Vector3(1.398, 0.75, zz)), Vector3(0.006, 0.03, 0.05), P.CYAN)
	h.box(_x(Vector3(-1.252, 0.68, 0)), Vector3(0.006, 0.03, 0.6), Color(1.0, 0.15, 0.1))
	h.use(S.M_PAINT)
	if c.detail():
		h.bbox(_x(Vector3(-0.85, 0.86, 0.3)), Vector3(0.5, 0.12, 0.3), 0.03, gd)
		h.box(_x(Vector3(0.0, 0.815, 0)), Vector3(1.8, 0.02, 0.9), gd)
		P.antenna(h, Vector3(-1.0, 0.82, -0.38), 1.0)
	c.turret_at(Vector3(-0.1, 0.82, 0))
	var t := c.t
	t.use(S.M_PAINT)
	t.cyl(_x(Vector3.ZERO), 0.36, 0.34, 0.12, 14, gd)
	if not atgm:
		t.bbox(_x(Vector3(0.0, 0.3, 0)), Vector3(0.82, 0.32, 0.64), 0.06, g)
		var mz := P.barrel(t, Vector3(0.4, 0.3, 0.12), [[0.3, 0.06], [1.15, 0.032], [0.12, 0.042]], gd, 0, 0.1, 10)
		c.muzzle(0, [mz], true)
		t.use(S.M_PAINT)
		t.bbox(_x(Vector3(0.15, 0.56, -0.2)), Vector3(0.3, 0.2, 0.22), 0.04, gd)
		t.bbox(_x(Vector3(-0.1, 0.24, 0.38)), Vector3(0.4, 0.22, 0.12), 0.03, gd)
		t.use(S.M_GLASS)
		t.box(_x(Vector3(0.302, 0.56, -0.2)), Vector3(0.01, 0.12, 0.16), P.GLASS)
		t.use(S.M_EMIT)
		t.box(_x(Vector3(0.306, 0.6, -0.2)), Vector3(0.004, 0.02, 0.06), P.CYAN)
	else:
		t.box(_x(Vector3(0.0, 0.25, 0)), Vector3(0.24, 0.3, 0.24), gd)
		var b := Basis(Vector3.BACK, deg_to_rad(8))
		var o := Vector3(0.1, 0.55, 0)
		t.bbox(Transform3D(b, o), Vector3(1.25, 0.44, 0.62), 0.05, g)
		var pts := []
		t.use(S.M_WEAPON)
		for yy: float in [-0.1, 0.1]:
			for zz: float in [-0.15, 0.15]:
				var p := o + b * Vector3(0.628, yy, zz)
				t.cyl(Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), p - b * Vector3(0.004, 0, 0)), 0.08, 0.08, 0.008, 10, P.BLACK)
				pts.append(p + b * Vector3(0.05, 0, 0))
		c.muzzle(0, pts, true)
		t.use(S.M_PAINT)
		t.bbox(_x(Vector3(0.0, 0.62, -0.42)), Vector3(0.24, 0.2, 0.16), 0.04, gd)
		t.use(S.M_GLASS)
		t.box(_x(Vector3(0.122, 0.62, -0.42)), Vector3(0.01, 0.12, 0.12), P.GLASS)
		t.use(S.M_EMIT)
		t.box(_x(Vector3(0.126, 0.66, -0.42)), Vector3(0.004, 0.02, 0.05), P.CYAN)
		t.box(Transform3D(b, o + b * Vector3(0.0, 0.222, 0.0)), Vector3(0.8, 0.006, 0.03), P.CYAN)


# ================================================================ HAC trucks ===

static func _hac_truck_base(c: Ctx, cab_x: float) -> void:
	var h := c.h
	var g := HAC_GRAPHITE
	var gd := HAC_DARK
	c.wheels = true
	h.use(S.M_PAINT)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(-0.2, 0.85, s * 0.45)), Vector3(6.4, 0.22, 0.12), gd)
	for wxp: float in [2.35, -1.15, -2.4]:
		for s: float in [-1.0, 1.0]:
			P.wheel(h, Vector3(wxp, 0.53, s * 1.02), 0.53, 0.4, gd.lightened(0.05), c.wreck)
		h.use(S.M_PAINT)
		h.tube(Vector3(wxp, 0.53, -0.92), Vector3(wxp, 0.53, 0.92), 0.06, 0.06, 6, gd)
	h.use(S.M_PAINT)
	h.prism(_x(Vector3.ZERO), _pv([cab_x, 0.95, 3.2, 0.95, 3.32, 1.5, 3.0, 2.45, cab_x, 2.5]), 2.36, g)
	_glass_quad(h, [Vector3(3.22, 1.82, -1.0), Vector3(3.22, 1.82, 1.0), Vector3(3.04, 2.3, 1.0), Vector3(3.04, 2.3, -1.0)], Vector3(0.94, 0.35, 0))
	h.use(S.M_GLASS)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(2.55, 2.05, s * 1.185)), Vector3(0.6, 0.36, 0.02), P.GLASS)
	h.use(S.M_PAINT)
	h.bbox(_x(Vector3(3.36, 1.0, 0)), Vector3(0.14, 0.24, 2.36), 0.03, gd)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(2.35, 1.1, s * 1.05)), Vector3(1.2, 0.06, 0.45), g)
		h.box(_x(Vector3(-1.78, 1.1, s * 1.05)), Vector3(1.8, 0.06, 0.45), g)
		h.use(S.M_EMIT)
		h.box(_x(Vector3(3.3, 1.55, s * 0.95)), Vector3(0.01, 0.025, 0.25), P.CYAN)
		h.use(S.M_PAINT)
	_team_panels(h, Vector3(2.35, 1.45, 1.185), Vector3(0.45, 0.2, 0.02))
	if c.detail():
		for s: float in [-1.0, 1.0]:
			P.headlight(h, Vector3(3.33, 1.25, s * 0.9), 0.07)
			h.box(_x(Vector3(3.1, 2.2, s * 1.33)), Vector3(0.05, 0.05, 0.22), gd)
			h.bbox(_x(Vector3(3.1, 2.15, s * 1.45)), Vector3(0.04, 0.26, 0.15), 0.01, gd)


static func _ew(c: Ctx) -> void:
	var h := c.h
	var g := HAC_GRAPHITE
	var gd := HAC_DARK
	c.height = 4.2
	_hac_truck_base(c, 1.55)
	h.use(S.M_PAINT)
	h.bbox(_x(Vector3(-0.9, 1.95, 0)), Vector3(4.6, 1.75, 2.36), 0.06, g)
	var dome := Color(0.72, 0.73, 0.75)
	h.cyl(_x(Vector3(-0.2, 2.82, -0.5)), 0.2, 0.2, 0.18, 10, gd)
	h.sphere(_x(Vector3(-0.2, 3.0, -0.5)), 0.44, 8, 14, dome, true)
	h.cyl(_x(Vector3(-2.1, 2.82, 0.5)), 0.18, 0.18, 0.12, 10, gd)
	h.sphere(_x(Vector3(-2.1, 2.94, 0.5), Vector3.ZERO, Vector3(1, 0.8, 1)), 0.36, 8, 14, dome, true)
	h.use(S.M_EMIT)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(-0.9, 2.8, s * 1.182)), Vector3(4.5, 0.015, 0.006), P.CYAN)
	h.use(S.M_PAINT)
	for s: float in [-1.0, 1.0]:
		for i in 2:
			h.bbox(_x(Vector3(-0.2 - i * 1.6, 2.05, s * 1.2)), Vector3(1.2, 0.9, 0.05), 0.02, gd)
			h.box(_x(Vector3(-0.2 - i * 1.6, 2.05, s * 1.226)), Vector3(1.05, 0.75, 0.01), gd.darkened(0.3))
	# log-periodic array on a mast
	h.use(S.M_WEAPON)
	h.tube(Vector3(-2.85, 2.82, -0.6), Vector3(-2.85, 4.3, -0.6), 0.06, 0.05, 8, gd)
	h.tube(Vector3(-3.3, 4.35, -0.6), Vector3(-2.0, 4.35, -0.6), 0.03, 0.03, 6, gd)
	if c.detail():
		for k in 8:
			var xk := -3.25 + k * 0.17
			var hl := 0.7 - k * 0.07
			h.tube(Vector3(xk, 4.35, -0.6 - hl), Vector3(xk, 4.35, -0.6 + hl), 0.008, 0.008, 4, Color(0.6, 0.6, 0.62))
		for p in [Vector3(1.2, 2.82, 1.0), Vector3(1.2, 2.82, -1.0), Vector3(-3.1, 2.82, 1.0)]:
			P.antenna(h, p, 2.6)
		h.box(_x(Vector3(-3.205, 1.9, 0.4)), Vector3(0.02, 1.2, 0.7), gd.darkened(0.2))
		h.use(S.M_EMIT)
		h.box(_x(Vector3(-3.21, 2.6, -0.6)), Vector3(0.006, 0.05, 0.05), Color(1.0, 0.2, 0.1))


static func _mast_truck(c: Ctx) -> void:
	var h := c.h
	var g := HAC_GRAPHITE
	var gd := HAC_DARK
	c.height = 3.2
	_hac_truck_base(c, 1.55)
	h.use(S.M_PAINT)
	h.bbox(_x(Vector3(0.35, 1.75, 0)), Vector3(2.2, 1.35, 2.36), 0.06, g)
	h.box(_x(Vector3(-1.85, 1.2, 0)), Vector3(2.7, 0.18, 2.36), gd)
	h.bbox(_x(Vector3(-2.2, 1.6, 0)), Vector3(0.9, 0.62, 0.9), 0.06, g)
	h.use(S.M_EMIT)
	for s: float in [-1.0, 1.0]:
		h.box(_x(Vector3(0.35, 2.4, s * 1.182)), Vector3(2.1, 0.015, 0.006), P.CYAN)
	h.use(S.M_PAINT)
	if c.detail():
		for s: float in [-1.0, 1.0]:
			h.tube(Vector3(-2.2, 1.3, s * 0.42), Vector3(-2.2 + 0.0, 0.95, s * 1.15), 0.05, 0.05, 6, gd)
			h.bbox(_x(Vector3(-2.2, 0.75, s * 1.18)), Vector3(0.25, 0.08, 0.25), 0.02, gd)
		P.antenna(h, Vector3(1.2, 2.42, 0.9), 2.0)
		h.bbox(_x(Vector3(-1.2, 1.5, 0.75)), Vector3(0.6, 0.45, 0.5), 0.04, gd)
	if c.wreck:
		h.use(S.M_PAINT)
		h.tube(Vector3(-2.2, 1.9, 0), Vector3(-1.4, 3.9, 0.3), 0.16, 0.12, 8, gd)
		return
	# telescopic mast: 4 nested sections (separate nodes so they can extend)
	var mat := S.vehicle_material()
	var sections := []
	var radii := [0.17, 0.135, 0.105, 0.078]
	for k in 4:
		var m := UnitMesh.new()
		m.use(S.M_PAINT)
		var r: float = radii[k]
		m.cyl(_x(Vector3.ZERO), r, r * 0.97, 2.6, 12, g if k % 2 == 0 else gd)
		m.cyl(_x(Vector3(0, 2.5, 0)), r * 1.15, r * 1.15, 0.1, 12, gd)
		if k == 0:
			m.use(S.M_EMIT)
			m.box(_x(Vector3(0, 2.3, r)), Vector3(0.04, 0.04, 0.01), P.CYAN)
		sections.append(m.commit(mat))
	var hm := UnitMesh.new()
	hm.use(S.M_PAINT)
	hm.cyl(_x(Vector3.ZERO), 0.12, 0.12, 0.18, 10, gd)
	hm.bbox(_x(Vector3(0, 0.32, 0)), Vector3(0.34, 0.26, 0.34), 0.05, g)
	hm.sphere(_x(Vector3(0.22, 0.32, 0)), 0.15, 8, 12, gd)
	hm.bbox(_x(Vector3(-0.05, 0.75, 0)), Vector3(0.1, 0.55, 0.95), 0.02, gd)
	hm.use(S.M_GLASS)
	hm.sphere(_x(Vector3(0.33, 0.32, 0)), 0.07, 6, 10, Color(0.08, 0.1, 0.14))
	hm.use(S.M_EMIT)
	hm.box(_x(Vector3(0.006, 0.75, 0)), Vector3(0.006, 0.4, 0.04), P.CYAN)
	hm.box(_x(Vector3(0, 0.47, 0)), Vector3(0.36, 0.015, 0.36), P.CYAN)
	c.extra["mast"] = {"pos": Vector3(-2.2, 1.9, 0), "sections": sections, "ext": PackedFloat32Array([0.9, 2.35, 2.35, 2.35]),
		"head": hm.commit(mat), "head_y": 2.6}

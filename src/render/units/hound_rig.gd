extends RefCounted
## Quadruped robot ("Hound"): one MeshInstance3D per robot, posed by the hound shader
## (trot gait with analytic two-bone leg IK, collapse when dead). Rest pose matches
## the constants in UnitShaders.HOUND_HEAD: body center (0, 0.62, 0), hips at
## (+-0.31, 0.56, +-0.15), upper leg 0.30, lower leg 0.32, facing +X.
class_name HoundRig

const B_BODY := 0
const B_HEAD := 1
const B_GUN := 2
const HIPS := [Vector3(0.31, 0.56, -0.15), Vector3(0.31, 0.56, 0.15), Vector3(-0.31, 0.56, -0.15), Vector3(-0.31, 0.56, 0.15)]
const AABB_HOUND := AABB(Vector3(-1.4, -0.2, -1.4), Vector3(2.8, 1.5, 2.8))

const M = preload("res://src/render/units/unit_shaders.gd")

static var _mesh: ArrayMesh


static func _x(p: Vector3, r: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return UnitMesh.xf(p, r, s)


static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var g := Color(0.33, 0.34, 0.365)
	var gd := Color(0.17, 0.175, 0.19)
	var cy := Color(0.12, 0.85, 1.0)
	var m := UnitMesh.new()
	# ---- body
	m.use(M.M_PAINT, B_BODY)
	m.bbox(_x(Vector3(0, 0.62, 0)), Vector3(0.80, 0.19, 0.29), 0.05, g)
	m.bbox(_x(Vector3(0.0, 0.725, 0)), Vector3(0.62, 0.04, 0.24), 0.015, gd)
	m.prism(_x(Vector3(0, 0, 0)), PackedVector2Array([Vector2(0.4, 0.56), Vector2(0.47, 0.6), Vector2(0.45, 0.69), Vector2(0.38, 0.71)]), 0.25, gd)
	m.prism(_x(Vector3(0, 0, 0)), PackedVector2Array([Vector2(-0.4, 0.56), Vector2(-0.38, 0.71), Vector2(-0.45, 0.69), Vector2(-0.47, 0.6)]), 0.25, gd)
	for h: Vector3 in HIPS:
		m.cyl(_x(h + Vector3(0, 0, -0.06 * signf(h.z)), Vector3(90 * signf(h.z), 0, 0)), 0.055, 0.055, 0.07, 10, gd)
	m.use(M.M_TEAM)
	for s in [-1, 1]:
		m.box(_x(Vector3(0.05, 0.64, s * 0.147)), Vector3(0.36, 0.035, 0.004), Color.WHITE)
	m.use(M.M_EMIT)
	for s in [-1, 1]:
		m.box(_x(Vector3(-0.2, 0.67, s * 0.147)), Vector3(0.12, 0.01, 0.004), cy)
	m.box(_x(Vector3(-0.471, 0.65, 0)), Vector3(0.004, 0.015, 0.12), Color(1.0, 0.15, 0.1))
	# ---- head (sensor block)
	m.use(M.M_PAINT, B_HEAD)
	m.bbox(_x(Vector3(0.52, 0.66, 0)), Vector3(0.16, 0.12, 0.2), 0.03, gd)
	m.bbox(_x(Vector3(0.44, 0.67, 0)), Vector3(0.06, 0.08, 0.14), 0.015, g)
	m.cyl(_x(Vector3(0.5, 0.72, 0)), 0.04, 0.04, 0.035, 10, Color(0.08, 0.08, 0.09))
	m.use(M.M_GLASS)
	m.bbox(_x(Vector3(0.598, 0.665, 0)), Vector3(0.012, 0.06, 0.15), 0.004, Color(0.03, 0.035, 0.04))
	m.use(M.M_EMIT)
	for z: float in [-0.045, 0.045]:
		m.box(_x(Vector3(0.606, 0.668, z)), Vector3(0.004, 0.018, 0.03), cy)
	m.box(_x(Vector3(0.5, 0.74, 0)), Vector3(0.05, 0.006, 0.05), cy)
	# ---- back gun
	m.use(M.M_WEAPON, B_GUN)
	m.cyl(_x(Vector3(0.02, 0.745, 0)), 0.085, 0.075, 0.04, 12, gd)
	m.bbox(_x(Vector3(0.06, 0.82, 0)), Vector3(0.3, 0.08, 0.085), 0.018, g)
	m.tube(Vector3(0.2, 0.82, 0), Vector3(0.48, 0.82, 0), 0.016, 0.014, 8, Color(0.08, 0.08, 0.08))
	m.tube(Vector3(0.44, 0.82, 0), Vector3(0.5, 0.82, 0), 0.02, 0.02, 8, Color(0.08, 0.08, 0.08))
	m.bbox(_x(Vector3(0.02, 0.81, -0.075)), Vector3(0.14, 0.08, 0.06), 0.012, gd)
	m.bbox(_x(Vector3(0.1, 0.875, 0)), Vector3(0.08, 0.035, 0.04), 0.01, gd)
	m.use(M.M_EMIT)
	m.box(_x(Vector3(0.061, 0.875, 0)), Vector3(0.003, 0.02, 0.025), cy)
	# ---- legs
	for li in 4:
		var h: Vector3 = HIPS[li]
		var ub := 3 + li * 2
		m.use(M.M_PAINT, ub)
		m.bbox(_x(h + Vector3(0, -0.13, 0)), Vector3(0.085, 0.3, 0.06), 0.022, g)
		m.cyl(_x(h + Vector3(0, -0.3, -0.035), Vector3(90, 0, 0)), 0.035, 0.035, 0.07, 8, gd)
		m.use(M.M_PAINT, ub + 1)
		var knee := h - Vector3(0, 0.30, 0)
		m.tube(knee, knee - Vector3(0, 0.29, 0), 0.028, 0.02, 8, gd)
		m.use(M.M_RUBBER)
		m.sphere(_x(knee - Vector3(0, 0.32, 0)), 0.036, 5, 8, Color(0.06, 0.06, 0.06))
	_mesh = m.commit(UnitShaders.hound_material())
	return _mesh


static func make_member(team_lin: Color, seed: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh()
	mi.custom_aabb = AABB_HOUND
	var wd := Defs.weapon("robot_mg")
	var burst: int = wd["burst"]
	mi.set_instance_shader_parameter(&"cfg", Vector4(0, seed % 61, burst, float(wd["cooldown"]) + burst * float(wd["burst_dt"])))
	mi.set_instance_shader_parameter(&"team_color", team_lin)
	return mi

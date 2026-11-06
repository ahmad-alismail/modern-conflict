extends RefCounted
## Procedural soldier: one MeshInstance3D (one surface) per soldier, animated by the
## soldier shader (see UnitShaders). This file owns
##   - the skeleton conventions (bone ids, rest pivots mirrored in the shader),
##   - the key-pose table (per pose class x state), uploaded once as a uniform array,
##   - the kit variants per faction and the weapon models,
##   - mesh caching: one ArrayMesh per (faction, kit variant, weapon), shared by all.
## Everything is built in the rest pose: standing, facing +X, right side = +Z, feet at y = 0.
class_name SoldierRig

const B_PELVIS := 0
const B_CHEST := 1
const B_HEAD := 2
const B_UARM_L := 3
const B_FARM_L := 4
const B_UARM_R := 5
const B_FARM_R := 6
const B_THIGH_L := 7
const B_SHIN_L := 8
const B_THIGH_R := 9
const B_SHIN_R := 10
const B_WEAPON := 11
const B_AUX := 12

# pose classes (how a weapon is carried / fired)
const C_RIFLE := 0      # standing aim
const C_RIFLE_K := 1    # kneeling aim
const C_MG := 2         # light MG, standing braced
const C_PRONE := 3      # bipod weapons fired prone (gpmg, sniper)
const C_RPG := 4        # kneeling, launcher on shoulder
const C_MANPADS := 5    # standing, aimed high
const C_HMG := 6        # tripod gun on the ground
const C_ATGM := 7       # tripod launcher on the ground
const C_MORTAR := 8     # baseplate mortar
const NC := 9
const NR := 6           # rows per class: idle, move, fire, prone, dead A, dead B
const NV := 12          # vec4 per key pose

const AABB_SOLDIER := AABB(Vector3(-1.8, -0.2, -1.8), Vector3(3.6, 2.3, 3.6))

const M = preload("res://src/render/units/unit_shaders.gd")

static var _table: PackedVector4Array
static var _meshes := {}    # key -> [ArrayMesh, Vector3 left grip]


# =============================================================== pose table ===

static func _pose(o: Dictionary) -> Dictionary:
	var d := {
		"root": Vector3(0, 0.975, 0), "rrot": Vector3(0, -6, 0), "spine": Vector3(3, -4, 0), "head": Vector3(0, 8, 0),
		"thl": Vector3(3, 6, 5), "thr": Vector3(-2, -8, 6), "knee": Vector2(6, 4), "grip": Vector2(1, 1),
		"wpos": Vector3(0.17, 0.055, 0.13), "wrot": Vector3(35, 22, -10), "wanch": 0.0,
		"freel": Vector3(0.04, -0.22, -0.25), "freer": Vector3(0.04, -0.22, 0.25),
		"apos": Vector3(-0.2, 0.4, 0), "arot": Vector3(-90, 0, 0), "aanch": 0.0,
	}
	for k in o:
		d[k] = o[k]
	return d


static func _row(d: Dictionary, out: PackedVector4Array) -> void:
	var r := PI / 180.0
	var root: Vector3 = d["root"]
	var rrot: Vector3 = d["rrot"] * r
	var spine: Vector3 = d["spine"] * r
	var head: Vector3 = d["head"] * r
	var thl: Vector3 = d["thl"] * r
	var thr: Vector3 = d["thr"] * r
	var knee: Vector2 = d["knee"] * r
	var grip: Vector2 = d["grip"]
	var wpos: Vector3 = d["wpos"]
	var wrot: Vector3 = d["wrot"] * r
	var fl: Vector3 = d["freel"]
	var fr: Vector3 = d["freer"]
	var apos: Vector3 = d["apos"]
	var arot: Vector3 = d["arot"] * r
	out.append(Vector4(root.x, root.y, root.z, grip.x))
	out.append(Vector4(rrot.x, rrot.y, rrot.z, grip.y))
	out.append(Vector4(spine.x, spine.y, spine.z, knee.x))
	out.append(Vector4(head.x, head.y, head.z, knee.y))
	out.append(Vector4(thl.x, thl.y, thl.z, 0))
	out.append(Vector4(thr.x, thr.y, thr.z, 0))
	out.append(Vector4(wpos.x, wpos.y, wpos.z, d["wanch"]))
	out.append(Vector4(wrot.x, wrot.y, wrot.z, 0))
	out.append(Vector4(fl.x, fl.y, fl.z, 0))
	out.append(Vector4(fr.x, fr.y, fr.z, 0))
	out.append(Vector4(apos.x, apos.y, apos.z, d["aanch"]))
	out.append(Vector4(arot.x, arot.y, arot.z, 0))


## Shared building blocks for the key poses.
const _KNEEL := {"root": Vector3(-0.06, 0.56, 0), "rrot": Vector3(0, -25, 0), "spine": Vector3(8, 0, 0),
	"thl": Vector3(90, 10, 8), "thr": Vector3(-6, -5, 4), "knee": Vector2(90, 100)}
const _MOVE := {"root": Vector3(0.02, 0.95, 0), "rrot": Vector3(8, 0, 0), "spine": Vector3(6, 0, 0), "head": Vector3(-4, 0, 0),
	"thl": Vector3(0, 0, 3), "thr": Vector3(0, 0, 3), "knee": Vector2(14, 14)}
const _PRONE := {"root": Vector3(-0.42, 0.17, 0), "rrot": Vector3(86, 0, 0), "spine": Vector3(-26, -10, 0), "head": Vector3(40, 0, 0),
	"thl": Vector3(0, 0, 10), "thr": Vector3(0, 0, 13), "knee": Vector2(4, 3), "wpos": Vector3(0.70, 0.10, 0.12), "wrot": Vector3(0, 0, 0)}
const _AIM := {"root": Vector3(-0.02, 0.96, 0), "rrot": Vector3(0, -22, 0), "spine": Vector3(6, -4, 0), "head": Vector3(6, 0, 12),
	"thl": Vector3(12, 10, 5), "thr": Vector3(-8, -10, 6), "knee": Vector2(12, 8), "wpos": Vector3(0.26, 0.36, 0.13), "wrot": Vector3(0, 0, 0)}
const _DEAD_A := {"root": Vector3(0.05, 0.13, 0), "rrot": Vector3(-87, 18, 0), "spine": Vector3(-4, 0, 6), "head": Vector3(-75, 35, 10),
	"thl": Vector3(10, 0, 16), "thr": Vector3(-2, 0, 9), "knee": Vector2(25, 6), "grip": Vector2(0, 0),
	"freel": Vector3(-0.08, 0.38, -0.5), "freer": Vector3(-0.08, -0.12, 0.44),
	"wpos": Vector3(0.45, 0.03, 0.62), "wrot": Vector3(0, 70, 90), "wanch": 1.0}
const _DEAD_B := {"root": Vector3(0.0, 0.14, 0), "rrot": Vector3(87, -25, 4), "spine": Vector3(4, 0, -4), "head": Vector3(80, -30, -60),
	"thl": Vector3(5, 0, 14), "thr": Vector3(8, 0, 6), "knee": Vector2(16, 6), "grip": Vector2(0, 0),
	"freel": Vector3(0.1, 0.28, -0.45), "freer": Vector3(0.1, -0.3, 0.32),
	"wpos": Vector3(0.95, 0.03, -0.35), "wrot": Vector3(0, -35, 90), "wanch": 1.0}


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := a.duplicate()
	for k in b:
		d[k] = b[k]
	return d


static func _class_rows(c: int) -> Array:
	var idle := {}
	var move := {"wpos": Vector3(0.22, 0.15, 0.12), "wrot": Vector3(25, 20, -15)}
	var fire := _AIM.duplicate()
	var prone := _PRONE.duplicate()
	var dead_a := _DEAD_A.duplicate()
	var dead_b := _DEAD_B.duplicate()
	match c:
		C_RIFLE_K:
			fire = _merge(_KNEEL, {"head": Vector3(6, 2, 10), "wpos": Vector3(0.26, 0.37, 0.13), "wrot": Vector3(0, 0, 0)})
		C_MG:
			idle = {"wpos": Vector3(0.15, 0.0, 0.15), "wrot": Vector3(28, 14, -5)}
			move = {"wpos": Vector3(0.2, 0.08, 0.14), "wrot": Vector3(20, 18, -10)}
			fire = _merge(_AIM, {"root": Vector3(-0.05, 0.94, 0), "rrot": Vector3(0, -20, 0), "spine": Vector3(12, -4, 0),
				"thl": Vector3(18, 10, 6), "thr": Vector3(-12, -10, 7), "knee": Vector2(18, 8), "head": Vector3(10, 0, 10),
				"wpos": Vector3(0.27, 0.36, 0.13)})
			prone["wpos"] = Vector3(0.70, 0.12, 0.12)
		C_PRONE:
			idle = {"wpos": Vector3(0.15, 0.0, 0.15), "wrot": Vector3(28, 14, -5)}
			move = {"wpos": Vector3(0.2, 0.08, 0.14), "wrot": Vector3(20, 18, -10)}
			prone["wpos"] = Vector3(0.70, 0.12, 0.12)
			fire = prone.duplicate()
		C_RPG:
			idle = {"wpos": Vector3(0.2, 0.06, 0.18), "wrot": Vector3(-45, 10, 0)}
			move = {"wpos": Vector3(0.18, 0.12, 0.15), "wrot": Vector3(-50, 15, 0)}
			fire = _merge(_KNEEL, {"rrot": Vector3(0, -15, 0), "head": Vector3(5, 5, 8), "wpos": Vector3(0.2, 0.41, 0.17), "wrot": Vector3(0, 0, 0)})
		C_MANPADS:
			idle = {"wpos": Vector3(0.18, 0.08, 0.17), "wrot": Vector3(-42, 10, 0)}
			move = {"wpos": Vector3(0.16, 0.1, 0.16), "wrot": Vector3(-50, 12, 0)}
			fire = _merge(_AIM, {"head": Vector3(-20, 0, 10), "wpos": Vector3(0.16, 0.51, 0.17), "wrot": Vector3(-25, 0, 0)})
			prone["wpos"] = Vector3(0.62, 0.14, 0.14)
		C_HMG, C_ATGM:
			var gun := Vector3(0.42, 0.60, 0.07) if c == C_HMG else Vector3(0.36, 0.68, 0.1)
			var aux := gun + (Vector3(0.30, -0.08, -0.07) if c == C_HMG else Vector3(0.18, -0.1, -0.1))
			var deployed := _merge(_KNEEL, {"rrot": Vector3(0, 0, 0), "spine": Vector3(18, 0, 0), "head": Vector3(8, 0, 0),
				"wpos": gun, "wrot": Vector3(0, 0, 0), "wanch": 1.0, "apos": aux, "arot": Vector3(0, 0, 0), "aanch": 1.0})
			idle = deployed
			fire = deployed.duplicate()
			move = {"wpos": Vector3(-0.52, 0.42, 0.26) if c == C_HMG else Vector3(-0.3, 0.48, 0.24), "wrot": Vector3(-20, 0, 0),
				"grip": Vector2(0, 0), "freer": Vector3(0.24, 0.5, 0.25), "freel": Vector3(0.05, -0.2, -0.25),
				"apos": Vector3(-0.24, 0.42, 0), "arot": Vector3(-80, 0, 0)}
			prone = _merge(_PRONE, {"wpos": gun - Vector3(0.0, 0.0, 0.0), "wrot": Vector3(0, 0, 0), "wanch": 1.0,
				"apos": aux, "arot": Vector3(0, 0, 0), "aanch": 1.0, "grip": Vector2(0, 0),
				"freel": Vector3(0.12, 0.25, -0.3), "freer": Vector3(0.12, 0.25, 0.3)})
			dead_a = _merge(dead_a, {"wpos": gun, "wrot": Vector3(0, 0, 0), "apos": aux, "arot": Vector3(0, 0, 0), "aanch": 1.0})
			dead_b = _merge(dead_b, {"wpos": gun, "wrot": Vector3(0, 0, 0), "apos": aux, "arot": Vector3(0, 0, 0), "aanch": 1.0})
		C_MORTAR:
			var tube := Vector3(0.53, 0.79, 0.35)
			var plate := Vector3(0.10, 0.02, 0.35)
			var deployed := _merge(_KNEEL, {"root": Vector3(-0.1, 0.56, -0.05), "rrot": Vector3(0, -30, 0), "spine": Vector3(14, 10, 0),
				"head": Vector3(10, -20, 0), "wpos": tube, "wrot": Vector3(-60, 0, 0), "wanch": 1.0,
				"apos": plate, "arot": Vector3(0, 0, 0), "aanch": 1.0})
			idle = deployed
			fire = deployed.duplicate()
			move = {"wpos": Vector3(0.10, 0.62, 0.22), "wrot": Vector3(-15, 0, 0), "grip": Vector2(0, 0),
				"freer": Vector3(0.22, 0.42, 0.22), "freel": Vector3(0.05, -0.2, -0.25), "apos": Vector3(-0.22, 0.42, 0), "arot": Vector3(-90, 0, 0)}
			prone = _merge(_PRONE, {"wpos": tube, "wrot": Vector3(-60, 0, 0), "wanch": 1.0, "apos": plate, "arot": Vector3(0, 0, 0),
				"aanch": 1.0, "grip": Vector2(0, 0), "freel": Vector3(0.12, 0.25, -0.3), "freer": Vector3(0.12, 0.25, 0.3)})
			dead_a = _merge(dead_a, {"wpos": tube, "wrot": Vector3(-60, 0, 0), "apos": plate, "arot": Vector3(0, 0, 0), "aanch": 1.0})
			dead_b = _merge(dead_b, {"wpos": tube, "wrot": Vector3(-60, 0, 0), "apos": plate, "arot": Vector3(0, 0, 0), "aanch": 1.0})
	return [_pose(idle), _pose(_merge(_MOVE, move)), _pose(fire), _pose(prone), _pose(dead_a), _pose(dead_b)]


static func pose_table() -> PackedVector4Array:
	if _table.is_empty():
		for c in NC:
			for row in _class_rows(c):
				_row(row, _table)
	return _table


static func class_for(weapon: String, seed: int) -> int:
	match weapon:
		"lmg": return C_MG
		"gpmg", "sniper": return C_PRONE
		"dmr": return C_RIFLE_K
		"rpg": return C_RPG
		"manpads": return C_MANPADS
		"hmg_team": return C_HMG
		"atgm": return C_ATGM
		"mortar": return C_MORTAR
	return C_RIFLE_K if seed % 5 < 2 else C_RIFLE


# ================================================================ kit looks ===

const SKINS := [Color(0.86, 0.68, 0.55), Color(0.74, 0.55, 0.41), Color(0.58, 0.42, 0.31), Color(0.42, 0.29, 0.21)]


static func variant_count(faction: String) -> int:
	match faction:
		"pdb": return 10
		"hac": return 3
	return 6


static func _kit(faction: String, vi: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(faction) + vi * 7919
	var k := {"skin": SKINS[rng.randi() % SKINS.size()], "beard": false, "backpack": false, "goggles": false, "earpro": false,
		"rolled": false, "rig": "carrier", "head": "helmet", "scarf": Color(0.7, 0.12, 0.12), "accent": false}
	match faction:
		"cdf":
			k["skin"] = SKINS[vi % SKINS.size()]
			k["top"] = Color(0.70, 0.62, 0.47); k["top_code"] = M.M_CAMO
			k["pants"] = Color(0.68, 0.60, 0.46); k["pants_code"] = M.M_CAMO
			k["gear"] = Color(0.55, 0.46, 0.33)
			k["head_col"] = Color(0.60, 0.53, 0.40)
			k["boots"] = Color(0.50, 0.41, 0.29)
			k["gloves"] = [Color(0.2, 0.19, 0.17), Color(0.56, 0.48, 0.36)][vi % 2]; k["glove_code"] = M.M_GEAR
			k["backpack"] = vi % 2 == 0
			k["goggles"] = vi % 3 == 1
			k["earpro"] = vi % 3 != 2
		"hac":
			k["top"] = Color(0.29, 0.30, 0.32); k["top_code"] = M.M_CLOTH
			k["pants"] = Color(0.26, 0.27, 0.29); k["pants_code"] = M.M_CLOTH
			k["gear"] = Color(0.15, 0.16, 0.17)
			k["head_col"] = Color(0.2, 0.21, 0.23)
			k["boots"] = Color(0.10, 0.10, 0.11)
			k["gloves"] = Color(0.08, 0.08, 0.09); k["glove_code"] = M.M_GEAR
			k["head"] = "hac"
			k["backpack"] = vi == 1
			k["accent"] = true
		_:
			var tops := [Color(0.38, 0.40, 0.27), Color(0.62, 0.56, 0.42), Color(0.13, 0.13, 0.14), Color(0.42, 0.42, 0.40),
				Color(0.44, 0.45, 0.31), Color(0.52, 0.44, 0.32)]
			var pants := [Color(0.36, 0.38, 0.26), Color(0.58, 0.52, 0.39), Color(0.12, 0.12, 0.13), Color(0.25, 0.30, 0.42),
				Color(0.36, 0.30, 0.22)]
			var ti := rng.randi() % tops.size()
			k["top"] = tops[ti]
			k["top_code"] = M.M_CAMO if ti == 4 else M.M_CLOTH
			k["pants"] = pants[rng.randi() % pants.size()]
			k["pants_code"] = M.M_CLOTH
			k["gear"] = [Color(0.33, 0.35, 0.24), Color(0.52, 0.47, 0.35), Color(0.14, 0.14, 0.14)][rng.randi() % 3]
			k["boots"] = [Color(0.1, 0.1, 0.1), Color(0.3, 0.22, 0.15), Color(0.36, 0.30, 0.22)][rng.randi() % 3]
			k["gloves"] = k["skin"]; k["glove_code"] = M.M_SKIN
			k["rolled"] = rng.randf() < 0.35
			k["rig"] = ["chestrig", "chestrig", "vest", "none"][rng.randi() % 4]
			var heads := ["shemagh", "shemagh_b", "cap", "beanie", "helmet_old", "hair", "shemagh", "hair", "cap", "shemagh_b"]
			k["head"] = heads[vi % heads.size()]
			k["scarf"] = Color(0.66, 0.1, 0.1) if k["head"] == "shemagh" else Color(0.07, 0.07, 0.07)
			k["head_col"] = [Color(0.12, 0.12, 0.12), Color(0.35, 0.37, 0.26), Color(0.58, 0.52, 0.40)][rng.randi() % 3]
			if k["head"] == "helmet_old":
				k["head_col"] = Color(0.30, 0.34, 0.24)
			k["beard"] = rng.randf() < 0.6
			k["backpack"] = rng.randf() < 0.25
	return k


# =================================================================== meshes ===

static func _x(p: Vector3, r: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return UnitMesh.xf(p, r, s)


static func _oct(hx: float, hz: float, c: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(hx, hz - c), Vector2(hx - c, hz), Vector2(-hx + c, hz), Vector2(-hx, hz - c),
		Vector2(-hx, -hz + c), Vector2(-hx + c, -hz), Vector2(hx - c, -hz), Vector2(hx, -hz + c)])


## Returns [mesh, left_grip] for a soldier look + weapon, built once.
static func mesh_for(faction: String, vi: int, weapon: String) -> Array:
	var key := "%s/%d/%s" % [faction, vi, weapon]
	if _meshes.has(key):
		return _meshes[key]
	var k := _kit(faction, vi)
	var m := UnitMesh.new()
	_body(m, k)
	_head(m, k)
	if weapon == "law":
		_law_tube(m, k)
	if weapon == "grenade":
		m.use(M.M_WEAPON, B_CHEST)
		for z: float in [-0.12, 0.12]:
			m.sphere(_x(Vector3(0.175, 1.07, z), Vector3.ZERO, Vector3(1, 1.25, 1)), 0.03, 4, 6, Color(0.24, 0.27, 0.18))
	var model := held_model(faction, weapon)
	m.use(M.M_WEAPON, B_WEAPON)
	var gl := _weapon(m, model, faction)
	var res := [m.commit(UnitShaders.soldier_material()), gl]
	_meshes[key] = res
	return res


static func held_model(faction: String, weapon: String) -> String:
	match weapon:
		"rifle", "law", "grenade":
			return {"cdf": "m4", "pdb": "ak", "hac": "smart"}.get(faction, "m4")
		"ak": return "ak"
		"smart_rifle": return "smart"
		"lmg": return "pkm" if faction == "pdb" else "m249"
		"gpmg": return "pkm" if faction == "pdb" else "m240"
		"hmg_team": return "dshk"
		"sniper": return "sniper"
		"dmr": return "svd"
		"rpg": return "rpg7"
		"atgm": return "atgm"
		"mortar": return "mortar"
		"manpads": return "igla"
	return "m4"


static func _body(m: UnitMesh, k: Dictionary) -> void:
	var skin: Color = k["skin"]
	var top: Color = k["top"]
	var tc: int = k["top_code"]
	var pants: Color = k["pants"]
	var pc: int = k["pants_code"]
	var gear: Color = k["gear"]
	var boots: Color = k["boots"]
	var gloves: Color = k["gloves"]
	var gcode: int = k["glove_code"]
	var dark := gear.darkened(0.35)
	# ---- pelvis
	m.use(pc, B_PELVIS)
	m.bbox(_x(Vector3(0, 0.935, 0)), Vector3(0.23, 0.21, 0.34), 0.05, pants)
	m.use(M.M_GEAR)
	m.box(_x(Vector3(0, 1.035, 0)), Vector3(0.245, 0.05, 0.352), dark)
	m.bbox(_x(Vector3(-0.115, 0.96, -0.11)), Vector3(0.07, 0.12, 0.11), 0.02, gear)        # dump pouch
	m.bbox(_x(Vector3(0.03, 0.9, 0.175)), Vector3(0.12, 0.17, 0.035), 0.012, dark)         # holster/leg panel
	# ---- chest / torso
	m.use(tc, B_CHEST)
	m.loft(_x(Vector3.ZERO), _oct(0.11, 0.16, 0.045), 1.0, _oct(0.12, 0.205, 0.06), 1.40, top, false, false)
	m.loft(_x(Vector3.ZERO), _oct(0.12, 0.205, 0.06), 1.40, _oct(0.095, 0.15, 0.05), 1.49, top, false, true)
	m.use(M.M_SKIN)
	m.cyl(_x(Vector3(0, 1.44, 0)), 0.054, 0.05, 0.15, 8, skin, false)
	m.use(tc)
	m.cyl(_x(Vector3(0, 1.45, 0)), 0.078, 0.07, 0.05, 8, top, false)
	var rig: String = k["rig"]
	m.use(M.M_GEAR)
	if rig == "carrier":
		m.bbox(_x(Vector3(0.125, 1.27, 0)), Vector3(0.055, 0.31, 0.29), 0.018, gear)
		m.bbox(_x(Vector3(-0.125, 1.28, 0)), Vector3(0.05, 0.33, 0.29), 0.018, gear)
		m.box(_x(Vector3(0, 1.15, 0)), Vector3(0.265, 0.13, 0.36), gear)
		for z: float in [-0.11, 0.11]:
			m.box(_x(Vector3(0, 1.465, z)), Vector3(0.262, 0.035, 0.07), gear)
		for z: float in [-0.085, 0.0, 0.085]:
			m.bbox(_x(Vector3(0.172, 1.17, z)), Vector3(0.042, 0.115, 0.074), 0.012, gear.lightened(0.04))
		m.bbox(_x(Vector3(0.165, 1.33, 0)), Vector3(0.03, 0.085, 0.14), 0.01, dark)
		m.bbox(_x(Vector3(-0.165, 1.24, -0.085)), Vector3(0.05, 0.15, 0.075), 0.012, dark)
		m.use(M.M_WEAPON)
		m.tube(Vector3(-0.17, 1.3, -0.1), Vector3(-0.2, 1.72, -0.13), 0.005, 0.003, 4, Color(0.08, 0.08, 0.08), false)
		if k["accent"]:
			m.use(M.M_EMIT)
			for z: float in [-0.1, 0.1]:
				m.box(_x(Vector3(0.155, 1.41, z)), Vector3(0.01, 0.012, 0.05), Color(0.15, 0.8, 1.0))
	elif rig == "chestrig":
		m.bbox(_x(Vector3(0.14, 1.18, 0)), Vector3(0.065, 0.14, 0.30), 0.015, gear)
		for z: float in [-0.1, 0.0, 0.1]:
			m.bbox(_x(Vector3(0.178, 1.19, z)), Vector3(0.03, 0.12, 0.085), 0.01, gear.lightened(0.05))
		for z: float in [-0.1, 0.1]:
			m.box(_x(Vector3(0.0, 1.44, z)), Vector3(0.25, 0.03, 0.05), gear)
			m.box(_x(Vector3(0.07, 1.33, z)), Vector3(0.12, 0.2, 0.04), gear)
	elif rig == "vest":
		m.bbox(_x(Vector3(0.11, 1.25, 0)), Vector3(0.04, 0.34, 0.33), 0.012, gear)
		m.bbox(_x(Vector3(-0.115, 1.27, 0)), Vector3(0.035, 0.34, 0.33), 0.012, gear)
		for z: float in [-0.09, 0.09]:
			m.bbox(_x(Vector3(0.14, 1.12, z)), Vector3(0.03, 0.09, 0.09), 0.01, gear.darkened(0.1))
	if k["backpack"]:
		m.bbox(_x(Vector3(-0.22, 1.27, 0)), Vector3(0.13, 0.36, 0.27), 0.035, gear.darkened(0.08))
		m.cyl(_x(Vector3(-0.22, 1.47, -0.13), Vector3(90, 0, 0)), 0.05, 0.05, 0.26, 8, gear.darkened(0.2))
		m.bbox(_x(Vector3(-0.29, 1.2, 0)), Vector3(0.04, 0.16, 0.2), 0.012, gear)
	# ---- arms
	var sleeve_end := 1.0 if k["rolled"] else 0.9
	for side in [-1, 1]:
		var z: float = side * 0.19
		var ub := B_UARM_L if side < 0 else B_UARM_R
		var fb := B_FARM_L if side < 0 else B_FARM_R
		m.use(tc, ub)
		m.sphere(_x(Vector3(0, 1.405, z)), 0.066, 6, 8, top)
		m.tube(Vector3(0, 1.41, z), Vector3(0, 1.14, z), 0.059, 0.048, 8, top, false)
		m.sphere(_x(Vector3(0, 1.13, z)), 0.048, 6, 8, top)
		m.use(M.M_TEAM)
		m.cyl(_x(Vector3(0, 1.22, z)), 0.0565, 0.0545, 0.045, 8, Color.WHITE, false)
		m.use(tc, fb)
		m.tube(Vector3(0, 1.13, z), Vector3(0, sleeve_end, z), 0.047, 0.044, 8, top, false)
		m.use(M.M_SKIN)
		m.tube(Vector3(0, sleeve_end + 0.01, z), Vector3(0, 0.88, z), 0.042, 0.036, 8, skin, false)
		m.use(gcode)
		m.bbox(_x(Vector3(0.012, 0.84, z)), Vector3(0.078, 0.1, 0.044), 0.014, gloves)
		m.bbox(_x(Vector3(0.05, 0.86, z - side * 0.016)), Vector3(0.022, 0.05, 0.022), 0.008, gloves)
	# ---- legs
	for side in [-1, 1]:
		var z: float = side * 0.1
		var tb := B_THIGH_L if side < 0 else B_THIGH_R
		var sb := B_SHIN_L if side < 0 else B_SHIN_R
		m.use(pc, tb)
		m.tube(Vector3(0, 0.96, z), Vector3(0, 0.5, z), 0.084, 0.062, 8, pants, false)
		m.sphere(_x(Vector3(0, 0.49, z)), 0.062, 6, 8, pants)
		m.bbox(_x(Vector3(0.0, 0.70, z + side * 0.068)), Vector3(0.11, 0.13, 0.03), 0.01, pants.darkened(0.06))
		m.use(pc, sb)
		m.tube(Vector3(0, 0.49, z), Vector3(0, 0.15, z), 0.059, 0.047, 8, pants, false)
		m.use(M.M_GEAR)
		if k["rig"] == "carrier":
			m.bbox(_x(Vector3(0.062, 0.47, z)), Vector3(0.035, 0.11, 0.09), 0.012, dark)
		m.cyl(_x(Vector3(0, 0.05, z)), 0.057, 0.053, 0.16, 8, boots)
		m.bbox(_x(Vector3(0.04, 0.055, z)), Vector3(0.25, 0.11, 0.105), 0.035, boots)
		m.box(_x(Vector3(0.042, 0.009, z)), Vector3(0.262, 0.018, 0.11), Color(0.08, 0.075, 0.07))


static func _head(m: UnitMesh, k: Dictionary) -> void:
	var skin: Color = k["skin"]
	var hc: Color = k["head_col"]
	m.use(M.M_SKIN, B_HEAD)
	m.sphere(_x(Vector3(0.012, 1.64, 0), Vector3.ZERO, Vector3(1.0, 1.12, 0.9)), 0.1, 8, 10, skin)
	m.bbox(_x(Vector3(0.05, 1.57, 0)), Vector3(0.09, 0.06, 0.12), 0.025, skin)
	m.bbox(_x(Vector3(0.112, 1.625, 0)), Vector3(0.03, 0.045, 0.026), 0.008, skin)
	m.bbox(_x(Vector3(0.1, 1.678, 0)), Vector3(0.02, 0.016, 0.125), 0.005, skin.darkened(0.12))
	for z: float in [-0.09, 0.09]:
		m.bbox(_x(Vector3(0.0, 1.635, z)), Vector3(0.045, 0.06, 0.02), 0.008, skin)
	m.use(M.M_CLOTH)
	for z: float in [-0.034, 0.034]:
		m.box(_x(Vector3(0.099, 1.66, z)), Vector3(0.012, 0.016, 0.028), Color(0.1, 0.08, 0.07))
	if k["beard"]:
		m.use(M.M_HAIR)
		m.bbox(_x(Vector3(0.065, 1.56, 0)), Vector3(0.07, 0.07, 0.13), 0.025, Color(0.09, 0.07, 0.06))
		m.box(_x(Vector3(0.105, 1.6, 0)), Vector3(0.02, 0.012, 0.06), Color(0.09, 0.07, 0.06))
	var h: String = k["head"]
	match h:
		"helmet":
			m.use(M.M_GEAR)
			m.sphere(_x(Vector3(0.0, 1.655, 0), Vector3.ZERO, Vector3(1.08, 0.92, 1.0)), 0.128, 8, 12, hc, true)
			m.box(_x(Vector3(0.0, 1.665, -0.124)), Vector3(0.12, 0.025, 0.02), hc.darkened(0.3))
			m.box(_x(Vector3(0.0, 1.665, 0.124)), Vector3(0.12, 0.025, 0.02), hc.darkened(0.3))
			m.box(_x(Vector3(0.134, 1.712, 0)), Vector3(0.028, 0.042, 0.055), Color(0.09, 0.09, 0.09))
			m.bbox(_x(Vector3(-0.135, 1.69, 0)), Vector3(0.03, 0.05, 0.08), 0.01, hc.darkened(0.2))
			if k["earpro"]:
				for s in [-1, 1]:
					m.cyl(_x(Vector3(0.0, 1.63, s * 0.088), Vector3(90 * s, 0, 0)), 0.046, 0.042, 0.04, 8, Color(0.30, 0.31, 0.24))
			if k["goggles"]:
				m.use(M.M_GLASS)
				m.bbox(_x(Vector3(0.106, 1.664, 0)), Vector3(0.026, 0.034, 0.16), 0.01, Color(0.12, 0.11, 0.1))
		"hac":
			m.use(M.M_WEAPON)
			m.sphere(_x(Vector3(-0.005, 1.65, 0), Vector3.ZERO, Vector3(1.1, 0.98, 1.03)), 0.13, 8, 12, hc, true)
			m.bbox(_x(Vector3(-0.01, 1.6, 0)), Vector3(0.2, 0.08, 0.24), 0.04, hc)
			m.use(M.M_GLASS)
			m.sphere(_x(Vector3(0.03, 1.615, 0), Vector3.ZERO, Vector3(0.86, 0.78, 0.94)), 0.12, 8, 12, Color(0.05, 0.055, 0.065))
			m.use(M.M_EMIT)
			m.box(_x(Vector3(0.132, 1.655, 0)), Vector3(0.012, 0.013, 0.12), Color(0.12, 0.85, 1.0))
			for s in [-1, 1]:
				m.box(_x(Vector3(-0.02, 1.68, s * 0.133)), Vector3(0.08, 0.008, 0.006), Color(0.12, 0.85, 1.0))
		"shemagh", "shemagh_b":
			var sc: Color = k["scarf"]
			m.use(M.M_CHECKER)
			m.sphere(_x(Vector3(-0.005, 1.648, 0), Vector3.ZERO, Vector3(1.04, 1.02, 0.97)), 0.118, 8, 12, sc, true)
			m.bbox(_x(Vector3(0.07, 1.582, 0)), Vector3(0.095, 0.09, 0.172), 0.035, sc)
			m.cyl(_x(Vector3(0, 1.47, 0)), 0.08, 0.072, 0.1, 10, sc, false)
			m.bbox(_x(Vector3(-0.115, 1.53, 0.03), Vector3(0, 0, 12)), Vector3(0.03, 0.16, 0.1), 0.012, sc)
		"cap":
			m.use(M.M_CLOTH)
			m.sphere(_x(Vector3(0.0, 1.668, 0), Vector3.ZERO, Vector3(1.02, 0.78, 0.96)), 0.112, 8, 12, hc, true)
			m.box(_x(Vector3(0.13, 1.676, 0), Vector3(0, 0, -8)), Vector3(0.09, 0.012, 0.15), hc)
		"beanie":
			m.use(M.M_CLOTH)
			m.sphere(_x(Vector3(-0.005, 1.66, 0), Vector3.ZERO, Vector3(1.0, 1.06, 0.96)), 0.113, 8, 12, hc, true)
		"helmet_old":
			m.use(M.M_PAINT)
			m.sphere(_x(Vector3(0.0, 1.655, 0), Vector3.ZERO, Vector3(1.05, 0.95, 1.05)), 0.128, 8, 12, hc, true)
			m.cyl(_x(Vector3(0, 1.64, 0)), 0.15, 0.134, 0.022, 12, hc.darkened(0.1))
		_:
			m.use(M.M_HAIR)
			m.sphere(_x(Vector3(-0.012, 1.66, 0), Vector3.ZERO, Vector3(1.0, 0.95, 0.94)), 0.106, 8, 10, Color(0.08, 0.06, 0.05), true)


static func _law_tube(m: UnitMesh, k: Dictionary) -> void:
	var x0 := -0.3 if k["backpack"] else -0.17
	m.use(M.M_WEAPON, B_CHEST)
	m.tube(Vector3(x0, 0.98, 0.17), Vector3(x0 - 0.05, 1.62, -0.13), 0.036, 0.036, 8, Color(0.30, 0.33, 0.22))
	m.tube(Vector3(x0, 0.97, 0.175), Vector3(x0, 1.01, 0.16), 0.04, 0.04, 8, Color(0.1, 0.1, 0.1))
	m.tube(Vector3(x0 - 0.048, 1.6, -0.12), Vector3(x0 - 0.052, 1.64, -0.14), 0.04, 0.04, 8, Color(0.1, 0.1, 0.1))


# ================================================================== weapons ===
# Weapon space: origin = right-hand grip, +X toward the muzzle, +Y up. Returns the
# left-hand grip point. Tripods / baseplates go on B_AUX (origin = mount pivot).

static func _weapon(m: UnitMesh, model: String, faction: String) -> Vector3:
	var blk := Color(0.09, 0.09, 0.095)
	var tan := Color(0.56, 0.48, 0.34)
	var wood := Color(0.42, 0.24, 0.12)
	var ol := Color(0.30, 0.33, 0.22)
	var gr := Color(0.17, 0.18, 0.20)
	match model:
		"m4":
			_grip(m, blk)
			m.bbox(_x(Vector3(0.05, 0.045, 0)), Vector3(0.24, 0.07, 0.036), 0.008, blk)
			m.bbox(_x(Vector3(0.28, 0.05, 0)), Vector3(0.25, 0.055, 0.048), 0.012, tan)
			m.tube(Vector3(0.4, 0.05, 0), Vector3(0.62, 0.05, 0), 0.009, 0.009, 6, blk)
			m.tube(Vector3(0.6, 0.05, 0), Vector3(0.66, 0.05, 0), 0.013, 0.013, 6, blk)
			m.bbox(_x(Vector3(0.10, -0.05, 0), Vector3(0, 0, 6)), Vector3(0.036, 0.12, 0.024), 0.006, tan)
			m.tube(Vector3(-0.07, 0.055, 0), Vector3(-0.2, 0.05, 0), 0.014, 0.014, 6, blk)
			m.bbox(_x(Vector3(-0.22, 0.035, 0)), Vector3(0.13, 0.075, 0.038), 0.012, tan)
			m.bbox(_x(Vector3(0.06, 0.115, 0)), Vector3(0.1, 0.045, 0.04), 0.01, blk)
			m.use(M.M_GLASS)
			m.box(_x(Vector3(0.112, 0.115, 0)), Vector3(0.006, 0.03, 0.03), Color(0.25, 0.1, 0.08))
			m.use(M.M_WEAPON)
			return Vector3(0.27, 0.01, 0)
		"ak":
			_grip(m, blk)
			m.bbox(_x(Vector3(0.08, 0.04, 0)), Vector3(0.27, 0.065, 0.036), 0.01, blk)
			m.bbox(_x(Vector3(0.31, 0.033, 0)), Vector3(0.17, 0.05, 0.046), 0.014, wood)
			m.bbox(_x(Vector3(0.31, 0.077, 0)), Vector3(0.16, 0.03, 0.036), 0.01, wood)
			m.tube(Vector3(0.39, 0.045, 0), Vector3(0.62, 0.045, 0), 0.009, 0.009, 6, blk)
			m.tube(Vector3(0.39, 0.078, 0), Vector3(0.45, 0.078, 0), 0.01, 0.01, 6, blk)
			m.box(_x(Vector3(0.56, 0.07, 0)), Vector3(0.02, 0.05, 0.02), blk)
			m.tube(Vector3(0.6, 0.045, 0), Vector3(0.65, 0.045, 0), 0.013, 0.012, 6, blk)
			m.bbox(_x(Vector3(0.13, -0.045, 0), Vector3(0, 0, 14)), Vector3(0.04, 0.1, 0.026), 0.008, Color(0.36, 0.17, 0.08))
			m.bbox(_x(Vector3(0.162, -0.126, 0), Vector3(0, 0, 30)), Vector3(0.04, 0.08, 0.026), 0.008, Color(0.36, 0.17, 0.08))
			m.prism(_x(Vector3.ZERO), PackedVector2Array([Vector2(-0.04, 0.055), Vector2(-0.33, 0.04), Vector2(-0.33, -0.075), Vector2(-0.07, 0.0)]), 0.036, wood)
			return Vector3(0.30, 0.0, 0)
		"smart":
			m.bbox(_x(Vector3(0.0, -0.045, 0), Vector3(0, 0, -12)), Vector3(0.035, 0.1, 0.03), 0.008, gr)
			m.bbox(_x(Vector3(0.04, 0.035, 0)), Vector3(0.5, 0.1, 0.052), 0.018, gr)
			m.bbox(_x(Vector3(-0.12, -0.04, 0)), Vector3(0.05, 0.1, 0.03), 0.008, gr.darkened(0.3))
			m.tube(Vector3(0.28, 0.05, 0), Vector3(0.48, 0.05, 0), 0.017, 0.015, 8, gr.darkened(0.4))
			m.bbox(_x(Vector3(0.06, 0.112, 0)), Vector3(0.13, 0.05, 0.042), 0.012, gr.darkened(0.2))
			m.use(M.M_EMIT)
			m.box(_x(Vector3(-0.006, 0.112, 0)), Vector3(0.004, 0.026, 0.028), Color(0.1, 0.8, 1.0))
			m.box(_x(Vector3(0.08, 0.035, 0.027)), Vector3(0.22, 0.006, 0.002), Color(0.1, 0.8, 1.0))
			m.use(M.M_WEAPON)
			return Vector3(0.22, 0.0, 0)
		"m249", "m240", "pkm":
			var big := model != "m249"
			var col := tan if faction == "cdf" else blk
			_grip(m, blk)
			var rl := 0.36 if big else 0.30
			m.bbox(_x(Vector3(0.06, 0.05, 0)), Vector3(rl, 0.095, 0.055), 0.012, blk)
			m.bbox(_x(Vector3(0.24, 0.05, 0)), Vector3(0.12, 0.07, 0.06), 0.012, col)
			var bl := 0.78 if big else 0.66
			m.tube(Vector3(0.22, 0.06, 0), Vector3(bl, 0.06, 0), 0.015, 0.013, 8, blk)
			m.tube(Vector3(bl - 0.03, 0.06, 0), Vector3(bl + 0.03, 0.06, 0), 0.018, 0.016, 8, blk)
			m.box(_x(Vector3(0.18, 0.125, 0)), Vector3(0.14, 0.02, 0.02), blk)
			var ammo := Color(0.30, 0.33, 0.22) if faction != "hac" else gr
			m.bbox(_x(Vector3(0.07, -0.05, -0.035)), Vector3(0.11, 0.11, 0.08), 0.015, ammo)
			for s in [-1, 1]:
				m.tube(Vector3(0.52, 0.04, 0), Vector3(0.6, -0.2, s * 0.08), 0.007, 0.006, 4, blk)
			if model == "pkm":
				m.prism(_x(Vector3.ZERO), PackedVector2Array([Vector2(-0.06, 0.06), Vector2(-0.34, 0.03), Vector2(-0.34, -0.08), Vector2(-0.1, 0.0)]), 0.036, wood)
			else:
				m.bbox(_x(Vector3(-0.21, 0.035, 0)), Vector3(0.24, 0.08, 0.042), 0.014, col)
			return Vector3(0.24, 0.01, 0)
		"sniper":
			_grip(m, blk)
			m.bbox(_x(Vector3(0.05, 0.045, 0)), Vector3(0.28, 0.065, 0.045), 0.012, tan)
			m.bbox(_x(Vector3(0.3, 0.04, 0)), Vector3(0.25, 0.055, 0.05), 0.014, tan)
			m.tube(Vector3(0.18, 0.06, 0), Vector3(0.86, 0.06, 0), 0.012, 0.01, 8, blk)
			m.tube(Vector3(0.84, 0.06, 0), Vector3(0.92, 0.06, 0), 0.016, 0.016, 8, blk)
			m.tube(Vector3(-0.05, 0.13, 0), Vector3(0.3, 0.13, 0), 0.02, 0.02, 8, blk)
			m.tube(Vector3(0.24, 0.13, 0), Vector3(0.33, 0.13, 0), 0.026, 0.028, 8, blk)
			m.tube(Vector3(-0.08, 0.13, 0), Vector3(-0.04, 0.13, 0), 0.024, 0.02, 8, blk)
			m.prism(_x(Vector3.ZERO), PackedVector2Array([Vector2(-0.06, 0.07), Vector2(-0.36, 0.07), Vector2(-0.38, -0.07), Vector2(-0.3, -0.06), Vector2(-0.08, 0.0)]), 0.042, tan)
			for s in [-1, 1]:
				m.tube(Vector3(0.45, 0.03, 0), Vector3(0.5, -0.22, s * 0.09), 0.007, 0.006, 4, blk)
			return Vector3(0.3, 0.0, 0)
		"svd":
			_grip(m, blk)
			m.bbox(_x(Vector3(0.08, 0.04, 0)), Vector3(0.27, 0.065, 0.036), 0.01, blk)
			m.bbox(_x(Vector3(0.33, 0.045, 0)), Vector3(0.2, 0.06, 0.046), 0.014, wood)
			m.tube(Vector3(0.42, 0.05, 0), Vector3(0.86, 0.05, 0), 0.009, 0.009, 6, blk)
			m.tube(Vector3(0.84, 0.05, 0), Vector3(0.9, 0.05, 0), 0.013, 0.013, 6, blk)
			m.tube(Vector3(0.0, 0.12, -0.03), Vector3(0.2, 0.12, -0.03), 0.017, 0.017, 8, blk)
			m.tube(Vector3(0.17, 0.12, -0.03), Vector3(0.23, 0.12, -0.03), 0.022, 0.022, 8, blk)
			m.bbox(_x(Vector3(0.12, -0.05, 0), Vector3(0, 0, -10)), Vector3(0.04, 0.1, 0.026), 0.008, blk)
			m.prism(_x(Vector3.ZERO), PackedVector2Array([Vector2(-0.05, 0.06), Vector2(-0.36, 0.05), Vector2(-0.36, -0.08), Vector2(-0.24, -0.08), Vector2(-0.18, -0.01), Vector2(-0.07, 0.0)]), 0.036, wood)
			return Vector3(0.32, 0.01, 0)
		"rpg7":
			_grip(m, blk)
			m.bbox(_x(Vector3(0.21, -0.04, 0), Vector3(0, 0, -10)), Vector3(0.035, 0.09, 0.03), 0.008, blk)
			m.tube(Vector3(-0.58, 0.075, 0), Vector3(0.32, 0.075, 0), 0.026, 0.026, 8, Color(0.2, 0.21, 0.19))
			m.tube(Vector3(-0.72, 0.075, 0), Vector3(-0.58, 0.075, 0), 0.05, 0.03, 8, Color(0.2, 0.21, 0.19))
			m.tube(Vector3(-0.12, 0.075, 0), Vector3(0.12, 0.075, 0), 0.036, 0.036, 8, wood)
			m.bbox(_x(Vector3(0.04, 0.12, -0.04)), Vector3(0.09, 0.04, 0.03), 0.008, blk)
			m.tube(Vector3(0.32, 0.075, 0), Vector3(0.44, 0.075, 0), 0.02, 0.02, 8, Color(0.25, 0.27, 0.2))
			m.tube(Vector3(0.44, 0.075, 0), Vector3(0.6, 0.075, 0), 0.03, 0.045, 8, Color(0.30, 0.33, 0.22))
			m.tube(Vector3(0.6, 0.075, 0), Vector3(0.74, 0.075, 0), 0.045, 0.006, 8, Color(0.30, 0.33, 0.22))
			return Vector3(0.21, -0.01, 0)
		"igla":
			m.bbox(_x(Vector3(0.0, -0.04, 0), Vector3(0, 0, -10)), Vector3(0.035, 0.1, 0.03), 0.008, blk)
			m.bbox(_x(Vector3(0.0, 0.03, 0)), Vector3(0.16, 0.05, 0.05), 0.01, blk)
			m.tube(Vector3(-0.8, 0.075, 0), Vector3(0.85, 0.075, 0), 0.037, 0.037, 8, ol)
			m.tube(Vector3(0.85, 0.075, 0), Vector3(0.92, 0.075, 0), 0.041, 0.041, 8, Color(0.12, 0.12, 0.12))
			m.tube(Vector3(-0.84, 0.075, 0), Vector3(-0.8, 0.075, 0), 0.042, 0.042, 8, Color(0.12, 0.12, 0.12))
			m.bbox(_x(Vector3(0.6, 0.11, -0.05)), Vector3(0.06, 0.06, 0.02), 0.008, blk)
			return Vector3(0.36, 0.02, 0)
		"dshk":
			# right spade grip at origin, left grip at z = -0.14, receiver centered at z = -0.07
			for z: float in [0.0, -0.14]:
				m.tube(Vector3(-0.02, -0.06, z), Vector3(-0.02, 0.06, z), 0.016, 0.016, 6, wood)
			m.bbox(_x(Vector3(0.24, 0.02, -0.07)), Vector3(0.44, 0.13, 0.11), 0.02, Color(0.16, 0.17, 0.15))
			m.tube(Vector3(0.45, 0.02, -0.07), Vector3(1.5, 0.02, -0.07), 0.024, 0.022, 8, Color(0.12, 0.12, 0.12))
			for i in 6:
				m.cyl(_x(Vector3(0.48 + i * 0.05, 0.02, -0.07), Vector3(0, 0, -90)), 0.04, 0.04, 0.02, 8, Color(0.12, 0.12, 0.12))
			m.tube(Vector3(1.44, 0.02, -0.07), Vector3(1.58, 0.02, -0.07), 0.04, 0.035, 8, Color(0.1, 0.1, 0.1))
			m.bbox(_x(Vector3(0.24, -0.04, -0.2)), Vector3(0.24, 0.15, 0.1), 0.015, Color(0.30, 0.33, 0.22))
			m.box(_x(Vector3(0.36, 0.11, -0.07)), Vector3(0.05, 0.06, 0.02), Color(0.12, 0.12, 0.12))
			m.use(M.M_WEAPON, B_AUX)
			_tripod(m, 0.52, Color(0.22, 0.24, 0.18))
			return Vector3(0, 0, -0.14)
		"atgm":
			m.bbox(_x(Vector3(-0.02, 0.0, -0.1)), Vector3(0.2, 0.15, 0.13), 0.02, Color(0.42, 0.40, 0.32))
			for z: float in [0.0, -0.2]:
				m.tube(Vector3(0.0, -0.05, z), Vector3(0.0, 0.05, z), 0.017, 0.017, 6, blk)
			m.bbox(_x(Vector3(0.06, 0.06, -0.1)), Vector3(0.1, 0.06, 0.08), 0.012, blk)
			m.use(M.M_GLASS)
			m.box(_x(Vector3(0.111, 0.06, -0.1)), Vector3(0.004, 0.04, 0.05), Color(0.2, 0.25, 0.3))
			m.use(M.M_WEAPON)
			var tube_col := Color(0.30, 0.33, 0.22) if faction != "cdf" else Color(0.45, 0.43, 0.33)
			m.tube(Vector3(-0.4, 0.15, -0.1), Vector3(0.85, 0.15, -0.1), 0.075, 0.075, 10, tube_col)
			m.tube(Vector3(0.83, 0.15, -0.1), Vector3(0.88, 0.15, -0.1), 0.08, 0.08, 10, Color(0.15, 0.15, 0.15))
			m.tube(Vector3(-0.43, 0.15, -0.1), Vector3(-0.38, 0.15, -0.1), 0.082, 0.082, 10, Color(0.15, 0.15, 0.15))
			m.use(M.M_WEAPON, B_AUX)
			_tripod(m, 0.6, Color(0.2, 0.2, 0.19))
			return Vector3(0, 0, -0.2)
		"mortar":
			# origin near the muzzle (right hand); tube runs to -X (base end)
			m.tube(Vector3(-0.86, 0, 0), Vector3(0.14, 0, 0), 0.046, 0.044, 10, Color(0.24, 0.27, 0.18))
			m.tube(Vector3(0.12, 0, 0), Vector3(0.16, 0, 0), 0.054, 0.054, 10, Color(0.16, 0.17, 0.13))
			m.sphere(_x(Vector3(-0.88, 0, 0)), 0.05, 4, 8, Color(0.16, 0.17, 0.13))
			m.cyl(_x(Vector3(-0.25, 0, 0), Vector3(0, 0, -90)), 0.06, 0.06, 0.06, 8, blk)
			for s in [-1, 1]:
				m.tube(Vector3(-0.25, 0, s * 0.04), Vector3(-0.6, -0.49, s * 0.22), 0.012, 0.012, 5, blk)
			m.tube(Vector3(-0.42, -0.24, -0.13), Vector3(-0.42, -0.24, 0.13), 0.008, 0.008, 4, blk)
			m.use(M.M_WEAPON, B_AUX)
			m.cyl(_x(Vector3(0, 0, 0)), 0.24, 0.22, 0.035, 12, Color(0.22, 0.24, 0.17))
			for a in 4:
				m.box(_x(Vector3(0, 0.03, 0), Vector3(0, a * 45, 0)), Vector3(0.44, 0.03, 0.025), Color(0.18, 0.2, 0.14))
			m.sphere(_x(Vector3(0, 0.05, 0)), 0.05, 4, 8, Color(0.16, 0.17, 0.13))
			return Vector3(-0.28, 0.0, 0)
	return Vector3(0.27, 0.01, 0)


static func _grip(m: UnitMesh, col: Color) -> void:
	m.bbox(_x(Vector3(-0.012, -0.04, 0), Vector3(0, 0, -16)), Vector3(0.035, 0.1, 0.03), 0.008, col)


## Tripod on B_AUX: origin = mount pivot, feet `h` below.
static func _tripod(m: UnitMesh, h: float, col: Color) -> void:
	m.cyl(_x(Vector3(0, -0.06, 0)), 0.035, 0.035, 0.08, 8, col)
	var feet := [Vector3(0.42, -h, 0.38), Vector3(0.42, -h, -0.38), Vector3(-0.55, -h, 0.0)]
	for f: Vector3 in feet:
		m.tube(Vector3(0, -0.05, 0), f, 0.018, 0.014, 6, col)
		m.box(_x(f + Vector3(0, 0.01, 0)), Vector3(0.07, 0.02, 0.07), col.darkened(0.2))


# =============================================================== instances ===

## Creates one soldier MeshInstance3D (shared mesh + material, per-instance uniforms).
static func make_member(faction: String, weapon: String, team_lin: Color, seed: int) -> MeshInstance3D:
	var vi := seed % variant_count(faction)
	var res := mesh_for(faction, vi, weapon)
	var mi := MeshInstance3D.new()
	mi.mesh = res[0]
	mi.custom_aabb = AABB_SOLDIER
	var gl: Vector3 = res[1]
	var wd := Defs.weapon(weapon)
	var burst: int = wd["burst"]
	var period: float = float(wd["cooldown"]) + burst * float(wd["burst_dt"])
	mi.set_instance_shader_parameter(&"cfg", Vector4(class_for(weapon, seed), seed % 61, burst, period))
	mi.set_instance_shader_parameter(&"gl", Vector4(gl.x, gl.y, gl.z, 0))
	mi.set_instance_shader_parameter(&"team_color", team_lin)
	return mi


## Approximate muzzle in member space for the standing aim (used for squad muzzle_world).
static func muzzle_local(weapon: String) -> Vector3:
	match weapon:
		"hmg_team": return Vector3(2.0, 0.62, 0.0)
		"atgm": return Vector3(1.2, 0.83, 0.0)
		"mortar": return Vector3(0.62, 0.86, 0.35)
		"rpg", "manpads": return Vector3(0.9, 1.5, 0.17)
		"sniper", "dmr", "gpmg": return Vector3(1.2, 1.35, 0.13)
	return Vector3(0.9, 1.36, 0.13)

extends RefCounted
## Runtime state of one unit (a squad, vehicle or aircraft). Pure data + small helpers;
## behavior lives in SimWorld / Combat / Detection.
class_name SimUnit

enum State { IDLE, MOVING, GARRISONED, EMBARKED, DEAD }
enum Stance { FIRE_AT_WILL, RETURN_FIRE, HOLD_FIRE }

var id := 0
var team := 0
var def_id := ""
var def: Dictionary
var cat := 0
var move_class := 0

var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var facing := 0.0
var prev_facing := 0.0
var turret := 0.0
var prev_turret := 0.0
var alt := 0.0
var prev_alt := 0.0
var cur_speed := 0.0

var max_hp := 100.0
var members_hp := PackedFloat32Array()   # squads: per member; vehicles/air: single entry
var alive := true
var state := State.IDLE

var orders: Array = []                   # queued order dicts (front = active)
var path := PackedVector2Array()
var path_i := 0
var move_goal := Vector2.ZERO
var attack_move := false
var repath_t := 0.0
var stuck_t := 0.0
var stuck_ref := Vector2.ZERO

var weapons: Array = []                  # WeaponState dicts
var loadout_slot := PackedInt32Array()   # squads: member index -> weapon slot

var suppression := 0.0
var suppressed_t := 99.0                 # time since last suppression gain
var morale := 100.0
var pinned := false
var broken := false
var shaken_t := 0.0                      # vehicles: crew shaken (cannot fire)
var stance: int = Stance.FIRE_AT_WILL
var hold_pos := false

var garrison_bld := -1
var transport_id := -1
var cargo: Array = []                    # unit ids
var smoke_charges := 0

var mobility := 0                        # 0 ok, 1 damaged, 2 immobilized
var firepower := 0                       # 0 ok, 2 main weapon destroyed
var burn_t := 0.0

var stationary_t := 0.0
var fired_t := 99.0
var last_attacker := -1
var attacked_t := 99.0
var jammed_t := 0.0
var linked := true                       # HAC network link
var loiter_center := Vector2.ZERO
var kills := 0
var engaging := false                    # set by Combat when any weapon has a target in range
var vis_mask := 0                        # bit per team that currently sees this unit
var spawn_tick := 0


func setup(p_id: int, p_team: int, p_def_id: String, p_pos: Vector2, p_facing: float) -> void:
	id = p_id
	team = p_team
	def_id = p_def_id
	def = Defs.unit(p_def_id)
	cat = def["cat"]
	move_class = def["move"]
	pos = p_pos
	prev_pos = p_pos
	facing = p_facing
	prev_facing = p_facing
	turret = p_facing
	prev_turret = p_facing
	alt = def.get("alt", 0.0)
	prev_alt = alt
	loiter_center = p_pos
	morale = def["base_morale"]
	smoke_charges = def.get("smoke", 0)
	var n: int = def["members"]
	max_hp = def["hp"]
	members_hp.resize(n)
	members_hp.fill(def["hp"])
	_build_weapons()


func _build_weapons() -> void:
	weapons.clear()
	var slots := {}
	var loadout: Array = def["loadout"]
	if cat == Defs.CAT_INF:
		loadout_slot.resize(loadout.size())
		for i in loadout.size():
			var wid: String = loadout[i]
			if not slots.has(wid):
				slots[wid] = weapons.size()
				weapons.append(_wstate(wid))
			var si: int = slots[wid]
			weapons[si]["holders"] += 1
			loadout_slot[i] = si
	else:
		for wid in loadout:
			var ws := _wstate(wid)
			ws["holders"] = 1
			weapons.append(ws)


func _wstate(wid: String) -> Dictionary:
	var wd := Defs.weapon(wid)
	return {"id": wid, "def": wd, "holders": 0, "cd": 0.0, "burst_left": 0, "burst_t": 0.0,
		"ammo": int(wd["ammo"]), "ammo_max": int(wd["ammo"]), "target": -1, "forced": false, "aim": Vector2.ZERO}


# ------------------------------------------------------------------ queries ---

func is_squad() -> bool:
	return cat == Defs.CAT_INF


func is_air() -> bool:
	return cat == Defs.CAT_AIR


func is_robot() -> bool:
	return def["morale"] == "robot"


func hp() -> float:
	var s := 0.0
	for v in members_hp:
		s += maxf(v, 0.0)
	return s


func hp_frac() -> float:
	return hp() / (max_hp * members_hp.size())


func alive_members() -> int:
	var n := 0
	for v in members_hp:
		if v > 0.0:
			n += 1
	return n


func is_active() -> bool:
	return alive and state != State.EMBARKED


func targetable() -> bool:
	return alive and state != State.EMBARKED


func is_moving() -> bool:
	return state == State.MOVING and cur_speed > 0.2


func eye_height() -> float:
	if is_air():
		return alt
	return def["eye"]


func body_height() -> float:
	if is_air():
		return alt
	return 1.0 if cat == Defs.CAT_INF else 2.0


func target_mask() -> int:
	if cat == Defs.CAT_INF:
		return Defs.T_INF
	if cat == Defs.CAT_AIR:
		return Defs.T_AIR
	return Defs.T_VEH


func has_special(tag: String) -> bool:
	return tag in def.get("special", [])


## Squad member world offset (formation) — deterministic, used for splash & visuals.
func member_offset(i: int) -> Vector2:
	var n := members_hp.size()
	if n <= 1:
		return Vector2.ZERO
	var spacing := 3.0
	var cols := 3 if n > 4 else 2
	var row := i / cols
	var col := i % cols
	var local := Vector2(-row * spacing - (1.0 if col % 2 else 0.0), (col - (cols - 1) * 0.5) * spacing)
	return local.rotated(facing)


func current_order() -> Dictionary:
	return orders[0] if orders.size() > 0 else {}


func total_ammo_frac() -> float:
	var a := 0.0
	var m := 0.0
	for ws in weapons:
		a += ws["ammo"]
		m += ws["ammo_max"]
	return a / m if m > 0.0 else 1.0

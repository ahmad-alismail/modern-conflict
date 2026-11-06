extends RefCounted
## Combat resolution: target selection, firing, hit chance, armor penetration by
## facing, projectiles, splash, building damage/collapse, wrecks, and the
## faction-specific systems (HAC network link + EW jamming, resupply, mines).
class_name Combat

const COVER_MOD := [1.0, 0.68, 0.42]
const SPLASH_COVER := [1.0, 0.6, 0.35]
const JAM_RADIUS := 80.0
const LINK_RADIUS := 150.0
const MINE := {"name": "AT Mine", "damage": 480.0, "pen": 260.0, "splash": 4.0, "suppress": 30.0, "proj": Defs.P_BOMB}
const STRIKE_SHELL := {"name": "155mm Shell", "splash_dmg": 220.0, "damage": 280.0, "pen": 80.0, "splash": 12.0, "suppress": 60.0, "proj": Defs.P_MORTAR}
const STRIKE_BOMB := {"name": "Bomb", "splash_dmg": 300.0, "damage": 450.0, "pen": 120.0, "splash": 15.0, "suppress": 80.0, "proj": Defs.P_BOMB}
const STRIKE_ROCKET := {"name": "Rocket", "damage": 150.0, "pen": 40.0, "splash": 8.0, "suppress": 45.0, "proj": Defs.P_MORTAR}
const STRIKE_MISSILE := {"name": "Precision Missile", "splash_dmg": 160.0, "damage": 540.0, "pen": 720.0, "splash": 7.0, "suppress": 50.0, "proj": Defs.P_MISSILE, "top_attack": true}


static func update(w: SimWorld) -> void:
	if w.tick % 10 == 0:
		_update_network(w)
	if w.tick % 20 == 0:
		_update_support_vehicles(w)
	if w.tick % 4 == 0:
		_update_mines(w)
	for u in w.units:
		if u.is_active():
			_update_weapons(w, u)
	_update_projectiles(w)


# ============================================================== targeting =====

static func p_pen(pen: float, armor: float) -> float:
	if armor <= 0.0:
		return 1.0
	return clampf((pen / armor - 0.8) / 0.5, 0.0, 1.0)


static func can_target(wd: Dictionary, t: SimUnit) -> bool:
	return (int(wd["targets"]) & t.target_mask()) != 0


static func effectiveness(wd: Dictionary, t: SimUnit) -> float:
	if not can_target(wd, t):
		return 0.0
	var e := 0.0
	if t.cat == Defs.CAT_INF:
		var armor: float = t.def["armor"][0]
		var p := p_pen(wd["pen"], armor)
		e = wd["damage"] * wd["burst"] * (1.0 + wd.get("splash", 0.0) * 0.4) / 100.0 * maxf(p, 0.08)
		if wd["pen"] >= 200.0:
			e *= 0.3
	else:
		var armor: float = t.def["armor"][3 if wd.get("top_attack", false) else 1]
		var p := p_pen(wd["pen"], armor)
		if p <= 0.01:
			return 0.0
		e = p * wd["damage"] * wd["burst"] / maxf(t.hp(), 60.0)
		if t.is_air():
			e *= wd.get("air_acc", 0.3)
	return e


static func best_range(u: SimUnit, t: SimUnit) -> float:
	var r := 0.0
	for ws in u.weapons:
		if ws["holders"] > 0 and ws["ammo"] > 0 and effectiveness(ws["def"], t) > 0.0:
			r = maxf(r, ws["def"]["range"])
	return r if r > 0.0 else 35.0


static func _valid_target(w: SimWorld, u: SimUnit, ws: Dictionary, t: SimUnit) -> bool:
	if t == null or not t.targetable() or t.team == u.team:
		return false
	if (t.vis_mask & (1 << u.team)) == 0:
		return false
	return can_target(ws["def"], t)


static func _acquire(w: SimWorld, u: SimUnit, ws: Dictionary) -> int:
	var wd: Dictionary = ws["def"]
	var rng_max: float = wd["range"]
	var best := -1
	var best_score := 0.0
	for t: SimUnit in w.units_near(u.pos, rng_max + 8.0):
		if not _valid_target(w, u, ws, t):
			continue
		if u.stance == SimUnit.Stance.RETURN_FIRE and t.id != u.last_attacker:
			continue
		var d := w.unit_origin(u, t.pos).distance_to(t.pos)
		if d > rng_max or d < wd.get("min_range", 0.0):
			continue
		var e := effectiveness(wd, t)
		if e <= 0.0:
			continue
		var score: float = e * (0.5 + t.def["points"] / 20.0) / (1.0 + d / rng_max)
		if t.id == ws["target"]:
			score *= 1.4
		if t.id == u.last_attacker and u.attacked_t < 5.0:
			score *= 1.25
		if score <= best_score:
			continue
		if not wd.get("indirect", false) and not w.has_los_units(u, t):
			continue
		best = t.id
		best_score = score
	return best


static func aim_angle(w: SimWorld, u: SimUnit) -> Variant:
	for ws in u.weapons:
		if ws["target"] >= 0:
			var t: SimUnit = w.by_id.get(ws["target"])
			if t != null and t.alive:
				return (t.pos - u.pos).angle()
	var o := u.current_order()
	if o.get("o", "") == "attack_ground":
		return (o["pos"] - u.pos).angle()
	return null


# ================================================================ firing ======

static func _can_fire(u: SimUnit) -> bool:
	if u.broken or u.shaken_t > 0.0 or u.jammed_t > 0.0:
		return false
	if u.current_order().get("o", "") == "retreat":
		return false
	if u.is_squad() and u.alive_members() == 0:
		return false
	return true


static func _update_weapons(w: SimWorld, u: SimUnit) -> void:
	var engaging := false
	var can_fire := _can_fire(u)
	var order := u.current_order()
	for si in u.weapons.size():
		var ws: Dictionary = u.weapons[si]
		var wd: Dictionary = ws["def"]
		ws["cd"] -= SimWorld.DT
		if ws["holders"] <= 0 or ws["ammo"] <= 0 or wd["proj"] == Defs.P_KAMIKAZE:
			continue
		if si == 0 and u.firepower >= 2 and u.cat != Defs.CAT_INF:
			continue
		if ws["burst_left"] > 0:
			ws["burst_t"] -= SimWorld.DT
			if ws["burst_t"] <= 0.0:
				if ws["target"] == -2:
					_fire_at_point(w, u, ws, ws["aim"])
					ws["burst_left"] -= 1
				else:
					var bt: SimUnit = w.by_id.get(ws["target"])
					if _valid_target(w, u, ws, bt) and w.unit_origin(u, bt.pos).distance_to(bt.pos) <= wd["range"] + 5.0:
						_fire_at_unit(w, u, ws, bt)
						ws["burst_left"] -= 1
					else:
						ws["burst_left"] = 0
				ws["burst_t"] = wd["burst_dt"]
			engaging = true
			continue
		if not can_fire or u.stance == SimUnit.Stance.HOLD_FIRE and not ws["forced"]:
			continue
		# area fire order for indirect weapons
		if order.get("o", "") == "attack_ground" and wd.get("indirect", false):
			var gp: Vector2 = order["pos"]
			var gd := u.pos.distance_to(gp)
			if gd <= wd["range"] and gd >= wd.get("min_range", 0.0) and ws["cd"] <= 0.0 and u.stationary_t >= wd.get("setup", 0.0):
				ws["target"] = -2
				ws["aim"] = gp
				_start_burst(w, u, ws)
				_fire_at_point(w, u, ws, gp)
			engaging = true
			continue
		# target maintenance
		var t: SimUnit = w.by_id.get(ws["target"]) if ws["target"] >= 0 else null
		if ws["forced"] and (t == null or not t.alive):
			ws["forced"] = false
			ws["target"] = -1
			t = null
		if ws["forced"] and t != null and not _valid_target(w, u, ws, t):
			# forced target not hittable by this weapon: free it for auto targeting
			if not can_target(wd, t):
				t = null
		if not ws["forced"] and ((w.tick + u.id * 3 + si) % 8 == 0 or t == null or not _valid_target(w, u, ws, t)):
			var auto_ok := u.stance != SimUnit.Stance.HOLD_FIRE
			ws["target"] = _acquire(w, u, ws) if auto_ok else -1
			t = w.by_id.get(ws["target"]) if ws["target"] >= 0 else null
		if t == null or not _valid_target(w, u, ws, t):
			continue
		var d := w.unit_origin(u, t.pos).distance_to(t.pos)
		if d > wd["range"]:
			continue
		engaging = true
		if ws["cd"] > 0.0:
			continue
		if d < wd.get("min_range", 0.0):
			continue
		if u.stationary_t < wd.get("setup", 0.0) and u.state != SimUnit.State.GARRISONED:
			continue
		if not _aligned(u, wd, t):
			continue
		if not wd.get("indirect", false) and (w.tick + si) % 2 == 0 and not w.has_los_units(u, t):
			continue
		_start_burst(w, u, ws)
		_fire_at_unit(w, u, ws, t)
	u.engaging = engaging


static func _start_burst(w: SimWorld, u: SimUnit, ws: Dictionary) -> void:
	var wd: Dictionary = ws["def"]
	ws["burst_left"] = int(wd["burst"]) - 1
	ws["burst_t"] = wd["burst_dt"]
	ws["cd"] = wd["cooldown"] * w.rng.range_f(0.9, 1.1) + wd["burst_dt"] * wd["burst"]
	ws["ammo"] -= 1
	u.fired_t = 0.0
	w.teams[u.team]["stats"]["shots"] += 1


static func _aligned(u: SimUnit, wd: Dictionary, t: SimUnit) -> bool:
	var ang := (t.pos - u.pos).angle()
	if u.cat == Defs.CAT_INF:
		return true
	if u.is_air():
		if wd["proj"] == Defs.P_BULLET or wd["proj"] == Defs.P_BOMB or wd.get("guided", false):
			return true
		return absf(angle_difference(u.facing, ang)) < 0.35
	if u.def.get("turret", 0.0) > 0.0:
		var tol := 0.12 if wd["proj"] != Defs.P_BULLET else 0.35
		if wd.get("indirect", false):
			tol = 0.5
		return absf(angle_difference(u.turret, ang)) < tol
	return absf(angle_difference(u.facing, ang)) < 0.5


static func muzzle(w: SimWorld, u: SimUnit, toward: Vector2) -> Vector3:
	var p := w.unit_origin(u, toward)
	var h := 1.3
	if u.state == SimUnit.State.GARRISONED:
		h = w.garrison_eye(u)
	elif u.is_air():
		h = u.alt - 0.8
	elif u.cat == Defs.CAT_VEH:
		h = u.def["eye"] - 0.3
		p += Vector2.from_angle(u.turret) * u.def["radius"] * 0.6
	elif u.is_squad():
		var alive := []
		for i in u.members_hp.size():
			if u.members_hp[i] > 0.0:
				alive.append(i)
		if alive.size() > 0:
			p += u.member_offset(alive[w.rng.range_i(0, alive.size() - 1)])
	return Vector3(p.x, h, p.y)


static func target_point(w: SimWorld, t: SimUnit, from: Vector2) -> Vector3:
	var p := w.unit_origin(t, from)
	var h := 1.0
	if t.state == SimUnit.State.GARRISONED:
		h = w.garrison_eye(t)
	elif t.is_air():
		h = t.alt
	elif t.cat == Defs.CAT_VEH:
		h = 1.4
	elif t.is_squad():
		var alive := []
		for i in t.members_hp.size():
			if t.members_hp[i] > 0.0:
				alive.append(i)
		if alive.size() > 0:
			p += t.member_offset(alive[w.rng.range_i(0, alive.size() - 1)])
		h = 0.5 if t.pinned else 1.1
	return Vector3(p.x, h, p.y)


static func hit_chance(w: SimWorld, u: SimUnit, wd: Dictionary, t: SimUnit, d: float) -> float:
	var f := clampf(d / maxf(wd["range"], 1.0), 0.0, 1.0)
	var acc: float = lerpf(wd["acc_near"], wd["acc_far"], f)
	if t.is_squad():
		if t.state == SimUnit.State.GARRISONED:
			acc *= 0.3 if Defs.has_special(t.def, "urban_bonus") else 0.36
		else:
			acc *= COVER_MOD[w.nav.cover_at(t.pos)]
		if t.pinned:
			acc *= 0.7
		if t.is_moving():
			acc *= 0.9
	elif t.cat == Defs.CAT_VEH:
		acc = minf(0.97, acc * 1.7)
		if t.is_moving():
			acc *= 0.85
	else:
		acc *= wd.get("air_acc", 0.3)
		if t.has_special("drone"):
			acc *= 0.75
	if u.is_moving():
		acc *= 0.8 if (u.cat == Defs.CAT_VEH and u.def.get("thermal", false)) else 0.5
	if u.pinned:
		acc *= 0.45
	acc *= 1.0 - u.suppression / 250.0
	if w.env.get("night", false) and not u.def.get("thermal", false):
		acc *= 0.65
	if w.env.get("weather", "") == "dust":
		acc *= 0.8
	if not u.linked:
		acc *= 0.7
	if wd.get("guided", false) and (_jammed_at(w, u.team, u.pos) or _jammed_at(w, u.team, t.pos)):
		acc *= 0.45
	acc *= 1.0 + minf(u.kills, 5) * 0.03
	return clampf(acc, 0.02, 0.97)


static func _fire_at_unit(w: SimWorld, u: SimUnit, ws: Dictionary, t: SimUnit) -> void:
	var wd: Dictionary = ws["def"]
	var shots: int = ws["holders"] if u.is_squad() else 1
	var origin2 := w.unit_origin(u, t.pos)
	var d := origin2.distance_to(t.pos)
	var hp := hit_chance(w, u, wd, t, d)
	for k in shots:
		var from := muzzle(w, u, t.pos)
		var to := target_point(w, t, origin2)
		var hit := w.rng.chance(hp)
		if wd["proj"] == Defs.P_BULLET:
			if hit:
				apply_damage(w, u, wd, t, Vector2(from.x, from.z), wd.get("top_attack", false), 1.0)
			else:
				var miss := w.rng.unit_vector() * w.rng.range_f(1.0, 2.5 + d * 0.03)
				to += Vector3(miss.x, w.rng.range_f(-0.6, 0.8), miss.y)
				to.y = maxf(to.y, 0.05)
				if wd.get("splash", 0.0) > 0.0:
					splash(w, u, wd, Vector2(to.x, to.z), 0.6)
			if t.is_squad():
				w.add_suppression(t, wd["suppress"] / maxf(float(wd["burst"]), 1.0) * (1.0 if hit else 0.8), u)
			elif hit:
				w.add_suppression(t, wd["suppress"], u)
			w.emit({"t": "shot", "u": u.id, "w": ws["id"], "from": from, "to": to, "hit": hit, "tgt": t.id})
		else:
			_launch(w, u, ws, from, to, t, hit, d)


static func _fire_at_point(w: SimWorld, u: SimUnit, ws: Dictionary, p: Vector2) -> void:
	var from := muzzle(w, u, p)
	var to := Vector3(p.x, 0.0, p.y)
	_launch(w, u, ws, from, to, null, false, u.pos.distance_to(p))


static func _launch(w: SimWorld, u: SimUnit, ws: Dictionary, from: Vector3, to: Vector3, t: SimUnit, hit: bool, d: float) -> void:
	var wd: Dictionary = ws["def"]
	var kind: int = wd["proj"]
	if kind == Defs.P_MORTAR or wd.get("indirect", false):
		var acc: float = lerpf(wd["acc_near"], wd["acc_far"], clampf(d / wd["range"], 0.0, 1.0))
		var scatter: float = wd.get("scatter", 4.0) * (1.4 - acc)
		to += Vector3(w.rng.gauss() * scatter, 0.0, w.rng.gauss() * scatter)
		to.y = 0.0
		hit = false
	elif not hit:
		var miss := w.rng.unit_vector() * w.rng.range_f(2.0, 3.5 + d * 0.06)
		to += Vector3(miss.x, 0.0, miss.y)
		to.y = 0.0 if wd.get("splash", 0.0) > 0.0 else to.y
	if kind == Defs.P_BOMB:
		from = Vector3(u.pos.x, u.alt - 0.5, u.pos.y)
	var dist := from.distance_to(to)
	var speed: float = wd.get("speed", 200.0)
	var dur := maxf(dist / speed, 0.08)
	if kind == Defs.P_MORTAR:
		dur = maxf(dur, 1.2 + dist / 120.0)
	var proj := {"id": w.next_proj, "team": u.team, "src": u.id, "wid": ws["id"], "def": wd, "from": from, "to": to,
		"target": t.id if t != null else -1, "hit": hit, "t": 0.0, "dur": dur, "kind": kind,
		"arc": (dist * 0.35 if kind == Defs.P_MORTAR else 0.0)}
	w.next_proj += 1
	w.projectiles.append(proj)
	w.emit({"t": "launch", "u": u.id, "w": ws["id"], "from": from, "to": to, "kind": kind, "proj": proj["id"]})


static func _update_projectiles(w: SimWorld) -> void:
	if w.projectiles.is_empty():
		return
	var keep := []
	for p in w.projectiles:
		p["t"] += SimWorld.DT
		# guided weapons that will hit track their target
		if p["hit"] and p["target"] >= 0 and p["def"].get("guided", false):
			var t: SimUnit = w.by_id.get(p["target"])
			if t != null and t.alive:
				var aim := Vector3(t.pos.x, t.alt + 1.2 if t.is_air() else 1.2, t.pos.y)
				p["to"] = aim
		if p["t"] >= p["dur"]:
			_impact(w, p)
		else:
			keep.append(p)
	w.projectiles = keep


static func projectile_pos(p: Dictionary, extra_t: float = 0.0) -> Vector3:
	var f := clampf((p["t"] + extra_t) / p["dur"], 0.0, 1.0)
	var pos: Vector3 = p["from"].lerp(p["to"], f)
	if p["arc"] > 0.0:
		pos.y += sin(f * PI) * p["arc"]
	return pos


static func _impact(w: SimWorld, p: Dictionary) -> void:
	var wd: Dictionary = p["def"]
	var src: SimUnit = w.by_id.get(p["src"])
	var to: Vector3 = p["to"]
	var p2 := Vector2(to.x, to.z)
	var hit_veh := false
	var t: SimUnit = w.by_id.get(p["target"]) if p["target"] >= 0 else null
	if p["hit"] and t != null and t.alive and t.state != SimUnit.State.EMBARKED:
		var from2 := Vector2(p["from"].x, p["from"].z)
		if t.state == SimUnit.State.GARRISONED and wd.get("splash", 0.0) > 0.0:
			damage_building(w, t.garrison_bld, wd["damage"] * 0.5, src)
		apply_damage(w, src, wd, t, from2, wd.get("top_attack", false), 1.0)
		hit_veh = t.cat != Defs.CAT_INF
	var bi := _building_hit(w, p2)
	if bi >= 0 and wd.get("splash", 0.0) > 0.0:
		var f := 1.0
		match int(wd["proj"]):
			Defs.P_ROCKET: f = 0.8
			Defs.P_MISSILE: f = 0.6
			Defs.P_BOMB: f = 1.5
		damage_building(w, bi, wd["damage"] * f, src)
	if to.y < 4.0 or p["kind"] == Defs.P_MORTAR:
		splash(w, src, wd, p2, 1.0)
	w.emit({"t": "impact", "p": to, "w": p["wid"], "splash": wd.get("splash", 0.0), "kind": p["kind"], "veh": hit_veh, "bld": bi})


static func _building_hit(w: SimWorld, p: Vector2) -> int:
	var bi := w.nav.building_at(p)
	if bi >= 0:
		return bi
	for off in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		bi = w.nav.building_at(p + off)
		if bi >= 0:
			return bi
	return -1


# ================================================================ damage ======

## Apply one hit from weapon wd (fired by `src`, may be null) to unit t.
static func apply_damage(w: SimWorld, src: SimUnit, wd: Dictionary, t: SimUnit, from: Vector2, top: bool, mult: float) -> void:
	if not t.alive:
		return
	if src != null:
		t.last_attacker = src.id
		t.attacked_t = 0.0
	if t.is_squad():
		var alive := []
		for i in t.members_hp.size():
			if t.members_hp[i] > 0.0:
				alive.append(i)
		if alive.is_empty():
			return
		var mi: int = alive[w.rng.range_i(0, alive.size() - 1)]
		var dmg: float = wd["damage"] * mult
		var armor: float = t.def["armor"][0]
		if armor > 0.0 and not w.rng.chance(p_pen(wd["pen"], armor)):
			dmg *= 0.12
		if t.state == SimUnit.State.GARRISONED:
			dmg *= 0.75
		damage_member(w, t, mi, dmg, src)
		return
	var idx := 1
	if top:
		idx = 3
	elif not t.is_air():
		var rel := absf(angle_difference(t.facing, (from - t.pos).angle()))
		idx = 0 if rel < PI * 0.25 else (2 if rel > PI * 0.75 else 1)
	var armor: float = t.def["armor"][idx]
	var pen: float = wd["pen"]
	var dmg := 0.0
	var penetrated := w.rng.chance(p_pen(pen, armor))
	if penetrated:
		dmg = wd["damage"] * mult
		if pen >= 150.0 and w.rng.chance(0.2):
			_critical(w, t)
	else:
		dmg = wd["damage"] * mult * (0.05 if pen >= armor * 0.3 else 0.0)
		if pen >= armor * 0.5 and w.rng.chance(0.25):
			t.shaken_t = maxf(t.shaken_t, 1.5)
	if pen >= 150.0 or penetrated:
		w.emit({"t": "armor_hit", "u": t.id, "pen": penetrated, "p": t.pos})
	t.members_hp[0] -= dmg
	if t.members_hp[0] <= 0.0:
		destroy_unit(w, t, src.id if src != null else -1)


static func _critical(w: SimWorld, t: SimUnit) -> void:
	var roll := w.rng.range_i(0, 3)
	var text := ""
	match roll:
		0:
			if t.is_air():
				t.members_hp[0] -= 60.0
				text = "airframe damaged"
			else:
				t.mobility = mini(2, t.mobility + 1)
				text = "immobilized" if t.mobility >= 2 else "engine damaged"
		1:
			if t.weapons.size() > 0:
				t.firepower = 2
				text = "main weapon destroyed"
		2:
			t.shaken_t = 4.0
			text = "crew stunned"
		3:
			t.burn_t = 10.0
			text = "on fire"
	if text != "":
		w.emit({"t": "crit", "u": t.id, "text": text})
		w.message("%s %s!" % [t.def["name"], text], t.team, "alert")


static func damage_member(w: SimWorld, t: SimUnit, mi: int, dmg: float, src: SimUnit) -> void:
	if t.members_hp[mi] <= 0.0:
		return
	t.members_hp[mi] -= dmg
	if t.members_hp[mi] <= 0.0:
		t.members_hp[mi] = 0.0
		if t.loadout_slot.size() > mi:
			var si := t.loadout_slot[mi]
			t.weapons[si]["holders"] = maxi(0, t.weapons[si]["holders"] - 1)
		w.emit({"t": "death", "u": t.id, "m": mi})
		w.on_member_lost(t)
		if t.alive_members() == 0:
			destroy_unit(w, t, src.id if src != null else -1)


static func splash(w: SimWorld, src: SimUnit, wd: Dictionary, p: Vector2, mult: float) -> void:
	var r: float = wd.get("splash", 0.0)
	if r <= 0.0:
		return
	for t: SimUnit in w.units_near(p, r * 2.0 + 4.0):
		if t.is_air() or not t.targetable():
			continue
		if t.is_squad():
			var d0 := t.pos.distance_to(p)
			if t.state == SimUnit.State.GARRISONED:
				if w.building_distance(t.garrison_bld, p) < 1.5:
					for i in t.members_hp.size():
						if t.members_hp[i] > 0.0 and w.rng.chance(0.35):
							damage_member(w, t, i, splash_damage(wd) * 0.5 * mult, src)
					w.add_suppression(t, wd["suppress"] * 0.6, src)
				continue
			for i in t.members_hp.size():
				if t.members_hp[i] <= 0.0:
					continue
				var mp := t.pos + t.member_offset(i)
				var d := mp.distance_to(p)
				if d >= r:
					continue
				var f := 1.0 - d / r
				var dmg: float = splash_damage(wd) * f * SPLASH_COVER[w.nav.cover_at(mp)] * mult
				if t.pinned:
					dmg *= 0.7
				var armor: float = t.def["armor"][0]
				if armor > 0.0 and not w.rng.chance(p_pen(wd["pen"] * 0.5, armor)):
					dmg *= 0.2
				damage_member(w, t, i, dmg, src)
			if d0 < r * 2.0 and t.alive:
				w.add_suppression(t, wd["suppress"] * (1.0 - d0 / (r * 2.0)) * mult, src)
		elif t.cat == Defs.CAT_VEH:
			var d := maxf(0.0, t.pos.distance_to(p) - t.def["radius"] * 0.5)
			if d < r * 0.6:
				var armor: float = t.def["armor"][3]
				if w.rng.chance(p_pen(wd["pen"] * 0.6, armor)):
					t.members_hp[0] -= wd["damage"] * 0.35 * (1.0 - d / r) * mult
					if t.members_hp[0] <= 0.0:
						destroy_unit(w, t, src.id if src != null else -1)


## Anti-personnel blast damage at the center of a splash (falls off linearly).
static func splash_damage(wd: Dictionary) -> float:
	return wd.get("splash_dmg", minf(wd["damage"], 130.0))


static func damage_building(w: SimWorld, bi: int, dmg: float, src: SimUnit) -> void:
	if bi < 0:
		return
	var bs: Dictionary = w.buildings[bi]
	if bs["state"] == 2:
		return
	bs["hp"] -= dmg
	if bs["state"] == 0 and bs["hp"] < bs["max_hp"] * 0.5:
		bs["state"] = 1
		w.emit({"t": "bld_damaged", "b": bi})
	if bs["hp"] <= 0.0:
		bs["state"] = 2
		var occupants: Array = bs["garrison"].duplicate()
		bs["garrison"].clear()
		w.nav.collapse_building(bi)
		w.emit({"t": "bld_collapsed", "b": bi})
		for id in occupants:
			var u: SimUnit = w.by_id.get(id)
			if u == null or not u.alive:
				continue
			u.garrison_bld = -1
			u.state = SimUnit.State.IDLE
			u.pos = w.nav.nearest_open_point(Defs.MOVE_FOOT, u.pos)
			u.prev_pos = u.pos
			for i in u.members_hp.size():
				if u.members_hp[i] > 0.0 and w.rng.chance(0.55):
					damage_member(w, u, i, 999.0, src)
			if u.alive:
				w.add_suppression(u, 100.0, src)
		w.message("A building collapsed", -1, "alert")


static func destroy_unit(w: SimWorld, u: SimUnit, killer_id: int, expended: bool = false) -> void:
	if not u.alive:
		return
	u.alive = false
	u.state = SimUnit.State.DEAD
	u.orders.clear()
	u.path = PackedVector2Array()
	if u.garrison_bld >= 0:
		w.buildings[u.garrison_bld]["garrison"].erase(u.id)
		u.garrison_bld = -1
	if u.transport_id >= 0:
		var tr: SimUnit = w.by_id.get(u.transport_id)
		if tr != null:
			tr.cargo.erase(u.id)
	if u.cargo.size() > 0:
		var passengers := u.cargo.duplicate()
		w.unload_all(u)
		for id in passengers:
			var c: SimUnit = w.by_id.get(id)
			if c == null or not c.alive:
				continue
			for i in c.members_hp.size():
				if c.members_hp[i] > 0.0 and w.rng.chance(0.45):
					damage_member(w, c, i, 999.0, null)
			if c.alive:
				w.add_suppression(c, 90.0, null)
	var killer: SimUnit = w.by_id.get(killer_id)
	if killer != null and killer.team != u.team:
		killer.kills += 1
		w.teams[killer.team]["stats"]["killed"] += 1
	if not expended:
		w.on_unit_lost(u)
	var wreck := false
	if u.cat == Defs.CAT_VEH or (u.is_air() and u.def.get("air_kind", "") == "heli"):
		wreck = true
		w.wrecks.append({"p": u.pos, "def": u.def_id, "facing": u.facing, "turret": u.turret, "burn": 40.0})
		w.nav.add_wreck(u.pos, u.def["radius"] * 0.6)
		splash(w, null, {"damage": 90.0, "pen": 10.0, "splash": 6.0, "suppress": 40.0}, u.pos, 1.0)
	w.emit({"t": "destroyed", "u": u.id, "wreck": wreck, "air": u.is_air(), "expended": expended})
	if u.cat != Defs.CAT_INF and not expended:
		w.message("%s destroyed" % u.def["name"], u.team, "alert")
	elif u.cat == Defs.CAT_INF:
		w.message("%s wiped out" % u.def["name"], u.team, "alert")


static func kamikaze(w: SimWorld, u: SimUnit, t: SimUnit) -> void:
	var wd := Defs.weapon("fpv_charge")
	if w.rng.chance(hit_chance(w, u, wd, t, 2.0)):
		apply_damage(w, u, wd, t, u.pos, true, 1.0)
	splash(w, u, wd, t.pos, 1.0)
	w.emit({"t": "impact", "p": Vector3(t.pos.x, 1.0, t.pos.y), "w": "fpv_charge", "splash": 4.0, "kind": Defs.P_KAMIKAZE, "veh": t.cat != Defs.CAT_INF, "bld": -1})
	destroy_unit(w, u, -1, true)


# ===================================================== faction systems ======

static func _jammed_at(w: SimWorld, team: int, p: Vector2) -> bool:
	for u in w.units:
		if u.alive and u.team != team and u.has_special("jammer") and u.pos.distance_to(p) <= JAM_RADIUS:
			return true
	return false


static func _update_network(w: SimWorld) -> void:
	var nodes := []
	var jammers := []
	for u in w.units:
		if not u.is_active():
			continue
		if u.has_special("network_node"):
			nodes.append(u)
		if u.has_special("jammer"):
			jammers.append(u)
	for u in w.units:
		if not u.alive:
			continue
		if u.has_special("networked"):
			var ok := false
			for n in nodes:
				if n.team == u.team and n.pos.distance_to(u.pos) <= LINK_RADIUS:
					ok = true
					break
			u.linked = ok
		if u.has_special("drone") and u.is_air():
			for j in jammers:
				if j.team != u.team and j.pos.distance_to(u.pos) <= JAM_RADIUS:
					u.jammed_t = 0.8
					break


static func _update_support_vehicles(w: SimWorld) -> void:
	for s in w.units:
		if not s.is_active() or not (s.has_special("resupply") or s.has_special("repair")):
			continue
		for u in w.units_near(s.pos, 25.0):
			if u.team != s.team or u == s:
				continue
			if s.has_special("resupply"):
				for ws in u.weapons:
					if ws["ammo"] < ws["ammo_max"]:
						ws["ammo"] = mini(ws["ammo_max"], ws["ammo"] + maxi(1, int(ws["ammo_max"] * 0.1)))
			if s.has_special("repair") and u.cat == Defs.CAT_VEH:
				u.members_hp[0] = minf(u.max_hp, u.members_hp[0] + 12.0)
				if u.mobility > 0 and w.rng.chance(0.07):
					u.mobility -= 1
				u.burn_t = 0.0


static func _update_mines(w: SimWorld) -> void:
	if w.mines.is_empty():
		return
	var keep := []
	for m in w.mines:
		var triggered := false
		for u in w.units_near(m["p"], 3.0):
			if u.team != m["team"] and u.cat == Defs.CAT_VEH:
				apply_damage(w, null, MINE, u, u.pos, true, 1.0)
				triggered = true
				break
		if triggered:
			splash(w, null, MINE, m["p"], 1.0)
			w.emit({"t": "impact", "p": Vector3(m["p"].x, 0.0, m["p"].y), "w": "mine", "splash": 4.0, "kind": Defs.P_BOMB, "veh": true, "bld": -1})
		else:
			keep.append(m)
	w.mines = keep

extends Commander
## Classic offline AI commander. No LLM, no network, no cheating: it only reads its
## own units, enemies its team currently sees, its team's last-known contacts, and
## public map/objective state. Difficulty changes decision *quality* (reaction time,
## coordination, combined arms, support usage, retreat discipline, judgement noise),
## never information or equipment.
##
## Layers:
##  - strategic (every few seconds): score objectives, split forces into groups, assign
##    goals, stage assaults (hard), position fire support, recon and network nodes
##  - tactical (sub-second to seconds): garrison, smoke, retreat, focus fire, AT response,
##    helicopter AA avoidance, kamikaze drone targeting
##  - support: artillery/air/drone strikes on clusters, recon, mines, tunnels, reinforcements
class_name ClassicAI

const PROFILES := {
	"easy": {"react": 3.2, "strategic": 13.0, "noise": 0.45, "support": 0.3, "garrison": 0.3, "retreat_hp": 0.0,
		"focus": false, "combined": false, "targets": 3, "smoke": 0.15, "scout": false, "avoid_aa": false,
		"reinforce_at": 0.4, "stage": false, "aggression": 0.6},
	"medium": {"react": 1.6, "strategic": 8.0, "noise": 0.2, "support": 0.7, "garrison": 0.6, "retreat_hp": 0.25,
		"focus": true, "combined": true, "targets": 2, "smoke": 0.5, "scout": true, "avoid_aa": true,
		"reinforce_at": 0.65, "stage": false, "aggression": 0.8},
	"hard": {"react": 0.7, "strategic": 5.0, "noise": 0.06, "support": 1.0, "garrison": 0.85, "retreat_hp": 0.34,
		"focus": true, "combined": true, "targets": 2, "smoke": 0.9, "scout": true, "avoid_aa": true,
		"reinforce_at": 0.8, "stage": true, "aggression": 1.0},
}

var difficulty := "medium"
var p: Dictionary
var rng: Rng
var _react_t := 0.0
var _strat_t := 0.0
var _support_t := 3.0
var _initial_strength := 0.0
var _assign: Dictionary = {}       # unit id -> {"goal": Vector2, "kind": String, "t": float}
var _staging: Dictionary = {}      # objective index -> {"pos": Vector2, "since": float, "go": bool}
var _focus := {"id": -1, "t": -99.0}
var _garrisoned_once: Dictionary = {}
var _mined: Dictionary = {}
var _spawn := Vector2.ZERO
var _enemy_spawn := Vector2.ZERO
var doctrine := "combined"         # "combined" (CDF), "ambush" (PDB), "network" (HAC)


func _init(p_team: int, p_difficulty: String) -> void:
	team = p_team
	difficulty = p_difficulty if PROFILES.has(p_difficulty) else "medium"
	p = PROFILES[difficulty]
	rng = Rng.new(9173 + p_team * 31)
	_react_t = rng.range_f(0.2, 1.0)


func think(w: SimWorld) -> void:
	if not w.outcome.is_empty():
		return
	if _initial_strength <= 0.0:
		_spawn = w.map.team_spawn(team).get_center()
		match w.teams[team]["faction"]:
			"pdb": doctrine = "ambush"
			"hac": doctrine = "network"
		_enemy_spawn = w.map.team_spawn(1 - team).get_center()
		_initial_strength = _strength(w.team_units(team))
		_strat_t = rng.range_f(0.5, 2.0)
	_strat_t -= SimWorld.DT
	_react_t -= SimWorld.DT
	_support_t -= SimWorld.DT
	if _strat_t <= 0.0:
		_strat_t = p["strategic"] * rng.range_f(0.85, 1.15)
		_strategic(w)
	if _react_t <= 0.0:
		_react_t = p["react"] * rng.range_f(0.8, 1.2)
		_tactical(w)
	if _support_t <= 0.0:
		_support_t = 4.0 + p["react"] * 2.0
		_support(w)


# ================================================================ knowledge ===

## Enemies our team can currently see.
func visible_enemies(w: SimWorld) -> Array:
	var out := []
	for u in w.units:
		if u.alive and u.team != team and u.targetable() and (u.vis_mask & (1 << team)) != 0:
			out.append(u)
	return out


## Visible enemies plus last-known contacts: [{p, def, pts, unit (or null)}].
func known_enemies(w: SimWorld) -> Array:
	var out := []
	for u in visible_enemies(w):
		out.append({"p": u.pos, "def": u.def_id, "pts": float(u.def["points"]) * u.hp_frac(), "unit": u, "veh": u.cat == Defs.CAT_VEH})
	var lk: Dictionary = w.teams[team]["last_known"]
	for id in lk:
		var e: Dictionary = lk[id]
		var age: float = w.time - e["time"]
		var d := Defs.unit(e["def"])
		out.append({"p": e["p"], "def": e["def"], "pts": float(d["points"]) * clampf(1.0 - age / 90.0, 0.2, 1.0), "unit": null, "veh": d["cat"] == Defs.CAT_VEH})
	return out


static func _strength(units: Array) -> float:
	var s := 0.0
	for u in units:
		s += float(u.def["points"]) * u.hp_frac()
	return s


static func role(u: SimUnit) -> String:
	if u.is_air():
		if u.weapons.is_empty():
			return "recon_air"
		if u.has_special("kamikaze"):
			return "fpv"
		return "air"
	if u.has_special("resupply"):
		return "supply"
	if u.has_special("network_node") and u.cat == Defs.CAT_VEH:
		return "node"
	for ws in u.weapons:
		if ws["def"].get("indirect", false):
			return "fire"
	if u.is_squad() and u.def["camo"] < 0.5:
		return "recon"
	if u.cat == Defs.CAT_VEH:
		return "armor"
	if u.weapons.size() > 0 and u.weapons[0]["def"]["pen"] >= 200.0 and not u.def.get("capture", false):
		return "at"
	return "inf"


static func is_at(u: SimUnit) -> bool:
	for ws in u.weapons:
		if ws["holders"] > 0 and ws["ammo"] > 0 and ws["def"]["pen"] >= 250.0 and (int(ws["def"]["targets"]) & Defs.T_VEH):
			return true
	return false


func _order(w: SimWorld, u: SimUnit, kind: String, goal: Vector2, type: String = "attack_move") -> void:
	## Issue a movement order unless an equivalent one is already active.
	var a: Dictionary = _assign.get(u.id, {})
	var active := not u.orders.is_empty()
	if not a.is_empty() and a["kind"] == kind and a["goal"].distance_to(goal) < 12.0 and active:
		return
	if not a.is_empty() and a["goal"].distance_to(goal) < 6.0 and u.pos.distance_to(goal) < 10.0:
		return
	_assign[u.id] = {"goal": goal, "kind": kind, "t": w.time}
	issue(w, {"type": type, "ids": [u.id], "pos": goal})


# ================================================================ strategic ===

func _objective_scores(w: SimWorld, known: Array, center: Vector2) -> Array:
	var scores := []
	for i in w.objectives.size():
		var o: Dictionary = w.objectives[i]
		var enemy := 0.0
		for e in known:
			if e["p"].distance_to(o["p"]) < 70.0:
				enemy += e["pts"]
		var base := 1.2
		if o["owner"] == 1 - team:
			base = 1.45
		elif o["owner"] == team:
			base = 1.6 if enemy > 5.0 else 0.15
		var dist := center.distance_to(o["p"])
		var s: float = base / (1.0 + dist / 220.0) - enemy / 220.0 * (1.2 - p["aggression"])
		s *= 1.0 + rng.gauss() * p["noise"]
		scores.append({"i": i, "s": s, "enemy": enemy, "p": o["p"]})
	scores.sort_custom(func(a, b): return a["s"] > b["s"])
	return scores


func _strategic(w: SimWorld) -> void:
	var mine := w.team_units(team)
	if mine.is_empty():
		return
	var known := known_enemies(w)
	var ground := []
	var center := Vector2.ZERO
	for u in mine:
		var r := role(u)
		if r in ["inf", "armor", "at", "recon"] and not u.is_air():
			ground.append(u)
			center += u.pos
	center = center / ground.size() if ground.size() > 0 else _spawn
	var scores := _objective_scores(w, known, center)
	if scores.is_empty():
		return
	var n_targets := mini(int(p["targets"]), scores.size())
	var targets := scores.slice(0, n_targets)
	# Assign ground units to targets: balanced, combined arms, nearest first.
	var quota := int(ceil(float(ground.size()) / n_targets))
	var load := []
	load.resize(n_targets)
	load.fill(0)
	ground.sort_custom(func(a, b): return a.id < b.id)
	for u in ground:
		if u.broken or u.current_order().get("o", "") == "retreat":
			continue
		var best := 0
		var best_c := INF
		for k in n_targets:
			var c: float = u.pos.distance_to(targets[k]["p"]) + (400.0 if load[k] >= quota else 0.0)
			if c < best_c:
				best_c = c
				best = k
		load[best] += 1
		_send_to_objective(w, u, targets[best], known)
	# Non-maneuver roles
	var front := _front_point(w, targets[0]["p"])
	for u in mine:
		if u.broken:
			continue
		match role(u):
			"fire":
				var stand: Vector2 = targets[0]["p"].lerp(_spawn, 0.55)
				var wr: float = u.weapons[0]["def"]["range"] if u.weapons.size() > 0 else 200.0
				var to_t: Vector2 = targets[0]["p"] - stand
				if to_t.length() > wr * 0.85:
					stand = targets[0]["p"] - to_t.normalized() * wr * 0.8
				_order(w, u, "fire", w.nav.nearest_open_point(u.move_class, stand), "move")
			"recon_air":
				var spot: Vector2 = targets[mini(1, targets.size() - 1)]["p"].lerp(_enemy_spawn, 0.25 if p["scout"] else 0.0)
				_order(w, u, "scout", spot, "move")
			"air":
				_air_strategy(w, u, known, targets[0]["p"])
			"fpv":
				if u.orders.is_empty():
					_order(w, u, "loiter", front.lerp(_spawn, 0.35), "move")
			"supply":
				var armor_c := _role_center(mine, "armor")
				if armor_c != Vector2.INF:
					_order(w, u, "follow", w.nav.nearest_open_point(u.move_class, armor_c.lerp(_spawn, 0.15)), "move")
			"node":
				var robot_c := _robot_center(mine)
				var goal := robot_c if robot_c != Vector2.INF else front.lerp(_spawn, 0.4)
				_order(w, u, "net", w.nav.nearest_open_point(u.move_class, goal.lerp(_spawn, 0.12)), "move")


func _send_to_objective(w: SimWorld, u: SimUnit, t: Dictionary, known: Array) -> void:
	var oi: int = t["i"]
	var o: Dictionary = w.objectives[oi]
	var goal: Vector2 = o["p"]
	var r := role(u)
	# armor holds an overwatch position when enemy AT infantry is known near the objective
	if r == "armor" and p["combined"]:
		var at_threat := false
		for e in known:
			var d := Defs.unit(e["def"])
			if d["cat"] == Defs.CAT_INF and e["p"].distance_to(goal) < 80.0:
				for wid in d["loadout"]:
					if Defs.weapon(wid)["pen"] >= 250.0:
						at_threat = true
		if at_threat:
			var back := (_spawn - goal).normalized()
			goal = goal + back * 55.0
	elif r == "recon":
		var back := (_spawn - goal).normalized()
		goal = goal + back * 85.0 + Vector2(-back.y, back.x) * rng.range_f(-30, 30)
	elif doctrine == "ambush" and u.is_squad() and (t["enemy"] > 6.0 or o["owner"] == team or r == "at"):
		# light forces fight from buildings around the objective instead of crossing open ground
		var bi := _ambush_building(w, o["p"], u)
		if bi >= 0:
			if u.garrison_bld != bi:
				var a: Dictionary = _assign.get(u.id, {})
				if a.get("kind", "") != "ambush" or a.get("bld", -1) != bi or u.orders.is_empty() and u.state != SimUnit.State.GARRISONED:
					_assign[u.id] = {"goal": w.map.buildings[bi]["c"], "kind": "ambush", "t": w.time, "obj": oi, "bld": bi}
					issue(w, {"type": "garrison", "ids": [u.id], "bld": bi})
			return
	else:
		var off := Vector2.from_angle(u.id * 2.39996) * rng.range_f(0.0, o["r"] * 0.8)
		goal += off
	# staged assault (hard): gather before committing against a defended objective
	if p["stage"] and t["enemy"] > 12.0 and r != "recon":
		var st: Dictionary = _staging.get(oi, {})
		if st.is_empty() or w.time - st["since"] > 120.0:
			st = {"pos": o["p"].lerp(_spawn, 0.0) + (_spawn - o["p"]).normalized() * 95.0, "since": w.time, "go": false}
			_staging[oi] = st
		if not st["go"]:
			var near := 0
			var total := 0
			for v in w.team_units(team):
				var a: Dictionary = _assign.get(v.id, {})
				if a.get("obj", -1) == oi:
					total += 1
					if v.pos.distance_to(st["pos"]) < 45.0:
						near += 1
			if (total > 0 and float(near) / total >= 0.65) or w.time - st["since"] > 45.0:
				st["go"] = true
			else:
				var sp := w.nav.nearest_open_point(u.move_class, st["pos"] + Vector2.from_angle(u.id * 1.7) * 12.0)
				_order(w, u, "stage", sp, "move")
				_assign[u.id]["obj"] = oi
				return
	_order(w, u, "obj", w.nav.nearest_open_point(u.move_class, goal), "attack_move")
	_assign[u.id]["obj"] = oi


## A free building near the objective, preferring ones facing the enemy approach.
func _ambush_building(w: SimWorld, obj: Vector2, u: SimUnit) -> int:
	if u.garrison_bld >= 0 and w.building_distance(u.garrison_bld, obj) < 60.0:
		return u.garrison_bld
	var toward_enemy := (_enemy_spawn - obj).normalized()
	var best := -1
	var best_s := -INF
	for bi in w.buildings.size():
		var bs: Dictionary = w.buildings[bi]
		if bs["state"] == 2 or bs["garrison"].size() >= w.building_capacity(bi):
			continue
		var c: Vector2 = w.map.buildings[bi]["c"]
		var d := c.distance_to(obj)
		if d > 60.0:
			continue
		var s := -d * 0.4 + (c - obj).normalized().dot(toward_enemy) * 12.0 - c.distance_to(u.pos) * 0.05
		if s > best_s:
			best_s = s
			best = bi
	return best


func _front_point(w: SimWorld, target: Vector2) -> Vector2:
	return target.lerp(_spawn, 0.3)


func _role_center(units: Array, r: String) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for u in units:
		if role(u) == r:
			c += u.pos
			n += 1
	return c / n if n > 0 else Vector2.INF


func _robot_center(units: Array) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for u in units:
		if u.has_special("networked"):
			c += u.pos
			n += 1
	return c / n if n > 0 else Vector2.INF


func _air_strategy(w: SimWorld, u: SimUnit, known: Array, fallback: Vector2) -> void:
	if u.hp_frac() < 0.4 and u.def.get("air_kind", "") == "heli":
		_order(w, u, "rearm", _spawn, "move")
		return
	if p["avoid_aa"] and _aa_threat_near(w, u.pos, 210.0):
		_order(w, u, "evade", u.pos.lerp(_spawn, 0.5), "move")
		return
	var best := Vector2.INF
	var best_v := 0.0
	for e in known:
		var v: float = e["pts"] * (1.6 if e["veh"] else 1.0)
		if v > best_v and (not p["avoid_aa"] or not _aa_threat_near(w, e["p"], 160.0)):
			best_v = v
			best = e["p"]
	var goal := best if best != Vector2.INF else fallback
	_order(w, u, "strike", goal.lerp(_spawn, 0.15), "attack_move")


func _aa_threat_near(w: SimWorld, pos: Vector2, r: float) -> bool:
	for e in known_enemies(w):
		if e["p"].distance_to(pos) > r:
			continue
		var d := Defs.unit(e["def"])
		for wid in d["loadout"]:
			if wid == "manpads" or (wid in ["autocannon30", "autocannon25"] and e["p"].distance_to(pos) < r * 0.7):
				return true
	return false


# ================================================================ tactical ====

func _tactical(w: SimWorld) -> void:
	var mine := w.team_units(team)
	var vis := visible_enemies(w)
	for u in mine:
		if u.broken or u.state == SimUnit.State.EMBARKED:
			continue
		if u.is_squad():
			_squad_tactics(w, u, vis)
		elif u.cat == Defs.CAT_VEH:
			_vehicle_tactics(w, u, vis)
		elif u.has_special("kamikaze"):
			_fpv_tactics(w, u, vis)
		elif u.is_air() and p["avoid_aa"] and u.def.get("air_kind", "") == "heli" and _aa_threat_near(w, u.pos, 190.0):
			_order(w, u, "evade", u.pos.lerp(_spawn, 0.5), "move")
	if p["focus"]:
		_focus_fire(w, mine, vis)
	if p["combined"]:
		_at_response(w, mine, vis)


func _squad_tactics(w: SimWorld, u: SimUnit, vis: Array) -> void:
	# fall back when badly mauled (preserves tickets and the unit)
	if p["retreat_hp"] > 0.0 and not u.is_robot() and u.hp_frac() < p["retreat_hp"] and u.current_order().get("o", "") != "retreat":
		var threatened := false
		for e in vis:
			if e.pos.distance_to(u.pos) < 90.0:
				threatened = true
				break
		if threatened:
			issue(w, {"type": "retreat", "ids": [u.id]})
			_assign.erase(u.id)
			return
	# smoke when pinned under fire
	if u.suppression > 55.0 and u.smoke_charges > 0 and rng.chance(p["smoke"]):
		var nearest := _nearest(vis, u.pos, 90.0)
		if nearest != null:
			issue(w, {"type": "smoke", "ids": [u.id], "pos": u.pos.lerp(nearest.pos, 0.35)})
	# garrison a building at / near the objective once arrived
	var a: Dictionary = _assign.get(u.id, {})
	if u.def.get("garrison", false) and u.state != SimUnit.State.GARRISONED and u.orders.is_empty() and not _garrisoned_once.has(u.id):
		var oi: int = a.get("obj", -1)
		var anchor: Vector2 = w.objectives[oi]["p"] if oi >= 0 else u.pos
		if (oi >= 0 and u.pos.distance_to(anchor) < 35.0) or a.get("kind", "") == "recon" or role(u) == "recon":
			if rng.chance(p["garrison"]):
				var bi := _free_building_near(w, u.pos, 30.0)
				if bi >= 0:
					issue(w, {"type": "garrison", "ids": [u.id], "bld": bi})
			_garrisoned_once[u.id] = true


func _vehicle_tactics(w: SimWorld, u: SimUnit, vis: Array) -> void:
	if not p["combined"]:
		return
	# break contact with close AT infantry when damaged
	var threat: SimUnit = null
	for e in vis:
		if e.is_squad() and is_at(e) and e.pos.distance_to(u.pos) < 75.0:
			threat = e
			break
	if threat != null and u.hp_frac() < 0.75:
		if u.smoke_charges > 0 and rng.chance(p["smoke"]):
			issue(w, {"type": "smoke", "ids": [u.id]})
		var away := (u.pos - threat.pos).normalized()
		_order(w, u, "evade", w.nav.nearest_open_point(u.move_class, u.pos + away * 45.0), "move")
	elif u.hp_frac() < 0.35 and u.mobility < 2:
		_order(w, u, "repair", w.nav.nearest_open_point(u.move_class, _spawn), "move")


func _fpv_tactics(w: SimWorld, u: SimUnit, vis: Array) -> void:
	if u.current_order().get("o", "") == "attack":
		return
	var best: SimUnit = null
	var best_s := 0.0
	for e in vis:
		var d: float = e.pos.distance_to(u.pos)
		if d > 240.0:
			continue
		var s: float = float(e.def["points"]) / (1.0 + d / 80.0) * (2.0 if e.cat == Defs.CAT_VEH else 0.7)
		if s > best_s:
			best_s = s
			best = e
	if best != null:
		issue(w, {"type": "attack", "ids": [u.id], "target": best.id})


func _focus_fire(w: SimWorld, mine: Array, vis: Array) -> void:
	if vis.is_empty():
		return
	if w.time - _focus["t"] < 6.0:
		var cur: SimUnit = w.by_id.get(_focus["id"])
		if cur != null and cur.alive and (cur.vis_mask & (1 << team)):
			return
	# most dangerous visible enemy: AT near our vehicles, tanks, then the rest
	var best: SimUnit = null
	var best_s := 0.0
	for e in vis:
		var s: float = e.def["points"] * (1.0 - e.hp_frac() * 0.4)
		if is_at(e):
			s *= 1.6
		if e.cat == Defs.CAT_VEH:
			s *= 1.3
		if s > best_s:
			best_s = s
			best = e
	if best == null:
		return
	var shooters := []
	for u in mine:
		if u.broken or u.is_air() or role(u) in ["fire", "supply", "node"]:
			continue
		if u.pos.distance_to(best.pos) > Combat.best_range(u, best) * 1.1:
			continue
		var eff := 0.0
		for ws in u.weapons:
			eff = maxf(eff, Combat.effectiveness(ws["def"], best))
		if eff > 0.05:
			shooters.append(u.id)
		if shooters.size() >= 4:
			break
	if shooters.size() >= 2:
		issue(w, {"type": "attack", "ids": shooters, "target": best.id})
		_focus = {"id": best.id, "t": w.time}
		for id in shooters:
			_assign.erase(id)


func _at_response(w: SimWorld, mine: Array, vis: Array) -> void:
	for e in vis:
		if e.cat != Defs.CAT_VEH:
			continue
		for u in mine:
			if not is_at(u) or u.broken or not u.orders.is_empty() and u.current_order().get("o", "") == "attack":
				continue
			var d: float = u.pos.distance_to(e.pos)
			var reach := 190.0
			if u.is_squad() and u.weapons[0]["def"]["range"] < 90.0:
				# short-range AT waits for armor to come close instead of charging it
				reach = 75.0 if doctrine == "ambush" else 110.0
			if d < reach and d > 20.0:
				issue(w, {"type": "attack", "ids": [u.id], "target": e.id})
				_assign.erase(u.id)
				break


# ================================================================= support ====

func _support(w: SimWorld) -> void:
	var t: Dictionary = w.teams[team]
	var vis := visible_enemies(w)
	var mine := w.team_units(team)
	# reinforcements
	if not t["waves"].is_empty() and t["wave_cd"] <= 0.0:
		var s := _strength(mine)
		if s < _initial_strength * p["reinforce_at"] or (w.time > 300.0 and s < _initial_strength * 0.9):
			issue(w, {"type": "reinforce"})
	for k in t["support"]:
		var sp: Dictionary = t["support"][k]
		if sp["charges"] <= 0 or sp["cd"] > 0.0 or not rng.chance(p["support"]):
			continue
		var target = null
		match k:
			"artillery", "rocket_barrage":
				target = _best_cluster(vis, mine, 25.0, 22.0, 45.0)
			"airstrike":
				target = _best_cluster(vis, mine, 30.0, 35.0, 55.0)
			"drone_strike":
				var best: SimUnit = null
				for e in vis:
					if e.cat == Defs.CAT_VEH and (best == null or e.def["points"] > best.def["points"]):
						best = e
				if best != null:
					target = best.pos
			"emp":
				var drones := vis.filter(func(e): return e.is_air() or e.is_robot() or e.cat == Defs.CAT_VEH)
				target = _best_cluster(drones, mine, 30.0, 25.0, 30.0)
			"recon_uav":
				if p["scout"] and w.time > 30.0:
					target = _scout_point(w, vis)
			"smoke_barrage":
				target = _smoke_point(w, mine, vis)
			"minefield":
				target = _mine_point(w)
			"tunnel":
				target = _tunnel_point(w, vis)
		if target != null:
			issue(w, {"type": "support", "power": k, "pos": target, "dir": (_enemy_spawn - _spawn).normalized()})
			return


## Center of the visible enemy group with the most value within `r`, if worth a strike
## and no friendly units are inside the danger radius.
func _best_cluster(vis: Array, mine: Array, r: float, min_pts: float, danger: float) -> Variant:
	var best = null
	var best_v := min_pts
	for e in vis:
		var c := Vector2.ZERO
		var n := 0
		var v := 0.0
		for o in vis:
			if o.pos.distance_to(e.pos) < r:
				c += o.pos
				n += 1
				v += float(o.def["points"])
		c /= n
		if v <= best_v:
			continue
		var safe := true
		for m in mine:
			if m.pos.distance_to(c) < danger:
				safe = false
				break
		if safe:
			best_v = v
			best = c
	return best


func _scout_point(w: SimWorld, vis: Array) -> Variant:
	for o in w.objectives:
		if o["owner"] == team:
			continue
		var seen := false
		for e in vis:
			if e.pos.distance_to(o["p"]) < 80.0:
				seen = true
				break
		if not seen:
			return o["p"]
	return null


func _smoke_point(w: SimWorld, mine: Array, vis: Array) -> Variant:
	if not p["stage"]:
		return null
	for st_k in _staging:
		var st: Dictionary = _staging[st_k]
		if st["go"] and w.time - st["since"] < 70.0:
			var o: Dictionary = w.objectives[st_k]
			for e in vis:
				if e.pos.distance_to(o["p"]) < 90.0:
					return st["pos"].lerp(o["p"], 0.5)
	return null


func _mine_point(w: SimWorld) -> Variant:
	for i in w.objectives.size():
		var o: Dictionary = w.objectives[i]
		if o["owner"] == team and not _mined.has(i):
			_mined[i] = true
			var toward: Vector2 = (_enemy_spawn - o["p"]).normalized()
			var pt: Vector2 = o["p"] + toward * 45.0
			return w.nav.nearest_open_point(Defs.MOVE_WHEELED, pt)
	return null


func _tunnel_point(w: SimWorld, vis: Array) -> Variant:
	for o in w.objectives:
		if o["owner"] == team:
			continue
		var best := -1
		var best_d := 60.0
		for bi in w.buildings.size():
			if w.buildings[bi]["state"] == 2 or w.buildings[bi]["garrison"].size() > 0:
				continue
			var d := w.building_distance(bi, o["p"])
			if d >= best_d:
				continue
			var safe := true
			for e in vis:
				if e.pos.distance_to(w.map.buildings[bi]["c"]) < 38.0:
					safe = false
					break
			if safe:
				best = bi
				best_d = d
		if best >= 0:
			return w.map.buildings[best]["c"]
	return null


# ================================================================= helpers ====

static func _nearest(units: Array, p: Vector2, max_d: float) -> SimUnit:
	var best: SimUnit = null
	var bd := max_d
	for u in units:
		var d: float = u.pos.distance_to(p)
		if d < bd:
			bd = d
			best = u
	return best


func _free_building_near(w: SimWorld, pos: Vector2, r: float) -> int:
	var best := -1
	var best_d := r
	for bi in w.buildings.size():
		var bs: Dictionary = w.buildings[bi]
		if bs["state"] == 2 or bs["garrison"].size() >= w.building_capacity(bi):
			continue
		var d := w.building_distance(bi, pos)
		if d < best_d:
			best_d = d
			best = bi
	return best

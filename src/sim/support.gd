extends RefCounted
## Team support powers (limited charges + cooldowns, no economy), reinforcement
## waves and unit smoke. Strikes are scheduled and resolved deterministically.
class_name Support

const REINFORCE_DELAY := 15.0
const REINFORCE_CD := 90.0


static func request(w: SimWorld, team: int, power: String, pos: Vector2, dir: Vector2) -> bool:
	var sup: Dictionary = w.teams[team]["support"]
	if not sup.has(power):
		return false
	var s: Dictionary = sup[power]
	if s["charges"] <= 0 or s["cd"] > 0.0:
		return false
	var size := w.map.size_m()
	if pos.x < 0 or pos.y < 0 or pos.x > size.x or pos.y > size.y:
		return false
	var def: Dictionary = Defs.SUPPORT[power]
	if power == "tunnel":
		var bi := w.nav.building_at(pos)
		if bi < 0 or w.buildings[bi]["state"] == 2:
			return false
		for e in w.enemies_of(team):
			if w.is_visible_to(e, team) and e.pos.distance_to(pos) < 35.0:
				w.message("Tunnel exit is compromised: enemies nearby", team, "warn")
				return false
	s["charges"] -= 1
	s["cd"] = def["cooldown"]
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var strike := {"power": power, "team": team, "pos": pos, "dir": d, "t": def["delay"], "left": 1, "interval": 0.0}
	match power:
		"artillery":
			strike["left"] = 8
			strike["interval"] = 0.7
		"missile_strike":
			strike["left"] = 2
			strike["interval"] = 1.2
		"airstrike":
			strike["left"] = 6
			strike["interval"] = 0.14
			w.emit({"t": "jet", "team": team, "pos": pos, "dir": d, "eta": def["delay"]})
		"rocket_barrage":
			strike["left"] = 14
			strike["interval"] = 0.22
		"smoke_barrage":
			strike["left"] = 7
			strike["interval"] = 0.3
	w.strikes.append(strike)
	w.emit({"t": "support", "power": power, "team": team, "pos": pos})
	w.message("%s requested" % def["name"], team, "info")
	return true


static func reinforce(w: SimWorld, team: int) -> bool:
	var t: Dictionary = w.teams[team]
	if t["waves"].is_empty() or t["wave_cd"] > 0.0:
		return false
	var wave: Array = t["waves"].pop_front()
	t["wave_cd"] = REINFORCE_CD
	w.strikes.append({"power": "reinforce", "team": team, "pos": w.map.team_spawn(team).get_center(), "dir": Vector2.RIGHT,
		"t": REINFORCE_DELAY, "left": 1, "interval": 0.0, "units": wave})
	w.message("Reinforcements en route (%d units)" % wave.size(), team, "good")
	return true


static func unit_smoke(w: SimWorld, u: SimUnit, pos: Vector2) -> void:
	if u.smoke_charges <= 0 or not u.is_active():
		return
	u.smoke_charges -= 1
	if u.cat == Defs.CAT_VEH:
		var p := u.pos + Vector2.from_angle(u.turret) * 7.0
		w.add_smoke(p, 10.0, 32.0)
	else:
		var dv := pos - u.pos
		var p := u.pos + dv.limit_length(25.0)
		w.add_smoke(p, 7.0, 26.0)


static func update(w: SimWorld) -> void:
	for t in w.teams:
		t["wave_cd"] = maxf(0.0, t["wave_cd"] - SimWorld.DT)
		for k in t["support"]:
			var s: Dictionary = t["support"][k]
			s["cd"] = maxf(0.0, s["cd"] - SimWorld.DT)
	if w.strikes.is_empty():
		return
	var keep := []
	for s in w.strikes:
		s["t"] -= SimWorld.DT
		while s["t"] <= 0.0 and s["left"] > 0:
			_fire(w, s, int(s.get("fired", 0)))
			s["fired"] = int(s.get("fired", 0)) + 1
			s["left"] -= 1
			s["t"] += s["interval"] if s["interval"] > 0.0 else 1.0
		if s["left"] > 0:
			keep.append(s)
	w.strikes = keep


static func _fire(w: SimWorld, s: Dictionary, i: int) -> void:
	var team: int = s["team"]
	var pos: Vector2 = s["pos"]
	var power: String = s["power"]
	var radius: float = Defs.SUPPORT[power]["radius"] if Defs.SUPPORT.has(power) else 0.0
	match power:
		"artillery":
			_detonate(w, Combat.STRIKE_SHELL, pos + Vector2(w.rng.gauss(), w.rng.gauss()) * radius * 0.4, "shell")
		"airstrike":
			var d: Vector2 = s["dir"]
			_detonate(w, Combat.STRIKE_BOMB, pos + d * (i - 2.5) * 10.0 + Vector2(-d.y, d.x) * w.rng.range_f(-3, 3), "bomb")
		"rocket_barrage":
			_detonate(w, Combat.STRIKE_ROCKET, pos + Vector2(w.rng.gauss(), w.rng.gauss()) * radius * 0.5, "rocket")
		"smoke_barrage":
			var a := TAU * i / 7.0
			w.add_smoke(pos + Vector2.from_angle(a) * (radius * 0.55 if i > 0 else 0.0), 10.0, 42.0)
		"recon_uav":
			w.reveals.append({"team": team, "p": pos, "r": radius, "t": 30.0})
			w.emit({"t": "uav", "team": team, "pos": pos, "r": radius})
		"minefield":
			for k in 6:
				var mp := pos + w.rng.unit_vector() * w.rng.range_f(0.0, radius)
				if w.nav.is_open(Defs.MOVE_TRACKED, mp):
					w.mines.append({"p": mp, "team": team})
			w.emit({"t": "mines", "team": team, "pos": pos})
		"tunnel":
			var bi := w.nav.building_at(pos)
			var u := w.spawn_unit(team, "pdb_militia", w.building_entry_point(bi, pos) if bi >= 0 else pos, 0.0)
			if bi >= 0 and w.buildings[bi]["state"] != 2 and w.buildings[bi]["garrison"].size() < w.building_capacity(bi):
				w._enter_building(u, bi)
			w.message("Militia emerged from a tunnel", team, "good")
		"missile_strike":
			# each missile homes on the nearest visible enemy vehicle near the aim point
			var tgt: SimUnit = null
			var td := radius + 6.0
			for e in w.units_near(pos, radius + 6.0):
				if e.team != team and e.cat == Defs.CAT_VEH and w.is_visible_to(e, team) and e.pos.distance_to(pos) < td:
					tgt = e
					td = e.pos.distance_to(pos)
			var mp := tgt.pos if tgt != null else pos + Vector2(w.rng.gauss(), w.rng.gauss()) * radius * 0.3
			if tgt != null:
				Combat.apply_damage(w, null, Combat.STRIKE_TACTICAL, tgt, tgt.pos, true, 1.0)
			_detonate(w, Combat.STRIKE_TACTICAL, mp, "missile")
		"drone_strike":
			var best: SimUnit = null
			var bd := 14.0
			for e in w.units_near(pos, 14.0):
				if e.team != team and e.cat == Defs.CAT_VEH and w.is_visible_to(e, team) and e.pos.distance_to(pos) < bd:
					best = e
					bd = e.pos.distance_to(pos)
			var p := best.pos if best != null else pos
			if best != null:
				Combat.apply_damage(w, null, Combat.STRIKE_MISSILE, best, best.pos, true, 1.0)
			_detonate(w, Combat.STRIKE_MISSILE, p, "missile")
		"emp":
			for e in w.units_near(pos, radius):
				if e.team == team:
					continue
				w.add_suppression(e, 60.0, null)
				if e.is_air() or e.is_robot():
					e.jammed_t = 7.0
				elif e.cat == Defs.CAT_VEH:
					e.shaken_t = maxf(e.shaken_t, 4.0)
			w.emit({"t": "emp", "team": team, "pos": pos, "r": radius})
		"reinforce":
			var rect := w.map.team_spawn(team)
			var face := 0.0 if rect.get_center().x < w.map.size_m().x * 0.5 else PI
			var edge_x := rect.position.x + (4.0 if face == 0.0 else rect.size.x - 4.0)
			var list: Array = s["units"]
			for k in list.size():
				var p := Vector2(edge_x, rect.position.y + (k + 0.5) / list.size() * rect.size.y)
				var def := Defs.unit(list[k])
				w.spawn_unit(team, list[k], w.nav.nearest_open_point(def["move"], p), face)
			w.message("Reinforcements have arrived", team, "good")


static func _detonate(w: SimWorld, wd: Dictionary, p: Vector2, kind: String) -> void:
	var bi := Combat._building_hit(w, p)
	if bi >= 0:
		Combat.damage_building(w, bi, wd["damage"] * 1.2, null)
	Combat.splash(w, null, wd, p, 1.0)
	w.emit({"t": "impact", "p": Vector3(p.x, 0.0, p.y), "w": kind, "splash": wd["splash"], "kind": Defs.P_BOMB, "veh": false, "bld": bi, "big": true})

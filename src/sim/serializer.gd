extends RefCounted
## Full simulation state capture/restore for save games. Static data (defs) is
## referenced by id and re-linked on load. The map (with runtime terrain changes)
## is saved separately by SaveSystem.
class_name Serializer

const SKIP_UNIT := ["def", "weapons", "script", "RefCounted", "sim_unit.gd"]


static func capture(w: SimWorld) -> Dictionary:
	var units := []
	for u in w.units:
		units.append(_unit_to(u))
	var projs := []
	for p in w.projectiles:
		var c: Dictionary = p.duplicate()
		c.erase("def")
		projs.append(c)
	var teams := []
	for t in w.teams:
		teams.append(t.duplicate(true))
	return {"tick": w.tick, "time": w.time, "rng": w.rng.state, "next_id": w._next_id, "next_proj": w.next_proj,
		"units": units, "projectiles": projs, "smokes": w.smokes.duplicate(true), "mines": w.mines.duplicate(true),
		"strikes": w.strikes.duplicate(true), "reveals": w.reveals.duplicate(true), "wrecks": w.wrecks.duplicate(true),
		"buildings": w.buildings.duplicate(true), "objectives": w.objectives.duplicate(true), "teams": teams,
		"outcome": w.outcome.duplicate(), "env": w.env.duplicate(), "mode": w.mode, "time_limit": w.time_limit,
		"hold_team": w.hold_team, "command_log": w.command_log.duplicate(true), "nav_log": w.nav_log.duplicate(true)}


static func _unit_to(u: SimUnit) -> Dictionary:
	var d := {}
	for prop in u.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = prop["name"]
		if n in SKIP_UNIT:
			continue
		d[n] = u.get(n)
	var ws := []
	for w in u.weapons:
		var c: Dictionary = w.duplicate()
		c.erase("def")
		ws.append(c)
	d["weapons"] = ws
	return d


static func restore(w: SimWorld, d: Dictionary) -> void:
	w.tick = d["tick"]
	w.time = d["time"]
	w.rng.state = d["rng"]
	w._next_id = d["next_id"]
	w.next_proj = d["next_proj"]
	w.units.clear()
	w.by_id.clear()
	for ud in d["units"]:
		var u := SimUnit.new()
		u.setup(ud["id"], ud["team"], ud["def_id"], ud["pos"], ud["facing"])
		for k in ud:
			if k == "weapons":
				continue
			u.set(k, ud[k])
		u.weapons.clear()
		for wd in ud["weapons"]:
			var c: Dictionary = wd.duplicate()
			c["def"] = Defs.weapon(c["id"])
			u.weapons.append(c)
		w.units.append(u)
		w.by_id[u.id] = u
	w.projectiles.clear()
	for p in d["projectiles"]:
		var c: Dictionary = p.duplicate()
		c["def"] = _proj_def(c["wid"])
		w.projectiles.append(c)
	w.smokes = d["smokes"]
	w.mines = d["mines"]
	w.strikes = d["strikes"]
	w.reveals = d["reveals"]
	w.buildings = d["buildings"]
	w.objectives = d["objectives"]
	w.teams = d["teams"]
	w.outcome = d["outcome"]
	w.env = d["env"]
	w.mode = d["mode"]
	w.time_limit = d["time_limit"]
	w.hold_team = d["hold_team"]
	w.command_log = d["command_log"]
	# replay runtime navigation edits in their original order (overlaps are order-dependent);
	# pre-war ruins were already applied by setup()
	w.wrecks = d["wrecks"]
	w.nav_log = []
	for e in d.get("nav_log", []):
		if e[0] == "c":
			w.nav_collapse(int(e[1]))
		else:
			w.nav_wreck(e[1], float(e[2]))


static func _proj_def(wid: String) -> Dictionary:
	if Defs.WEAPONS.has(wid):
		return Defs.weapon(wid)
	match wid:
		"shell": return Combat.STRIKE_SHELL
		"bomb": return Combat.STRIKE_BOMB
		"rocket": return Combat.STRIKE_ROCKET
		"missile": return Combat.STRIKE_MISSILE
	return Combat.MINE

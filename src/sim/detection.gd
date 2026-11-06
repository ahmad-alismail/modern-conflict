extends RefCounted
## Team visibility. A unit is visible to a team when any of that team's units sees it:
## within sight range scaled by target camouflage, environment and activity, with
## clear line of sight (buildings, walls, smoke). Results are stored in
## SimUnit.vis_mask and team["last_known"]. Every consumer (renderer, AI, LLM,
## targeting) reads only these, so no opponent ever gets hidden information.
class_name Detection

const PROXIMITY := 10.0


static func update(w: SimWorld) -> void:
	var nteams := w.teams.size()
	var viewers := []
	for ti in nteams:
		viewers.append([])
	for u in w.units:
		if u.is_active() and u.team < nteams:
			if u.is_air() and u.jammed_t > 0.0:
				continue
			viewers[u.team].append(u)
	for t: SimUnit in w.units:
		if not t.alive:
			continue
		var mask := 1 << t.team
		if t.state != SimUnit.State.EMBARKED:
			for ti in nteams:
				if ti == t.team:
					continue
				if _team_sees(w, viewers[ti], t, ti):
					mask |= 1 << ti
		var prev := t.vis_mask
		t.vis_mask = mask
		for ti in nteams:
			if ti == t.team:
				continue
			var bit := 1 << ti
			var lk: Dictionary = w.teams[ti]["last_known"]
			if mask & bit:
				if lk.has(t.id):
					lk.erase(t.id)
				if not (prev & bit):
					w.emit({"t": "spotted", "u": t.id, "team": ti})
			elif prev & bit:
				lk[t.id] = {"p": t.pos, "def": t.def_id, "time": w.time}
	# forget stale or disproven last-known contacts
	for ti in nteams:
		var lk: Dictionary = w.teams[ti]["last_known"]
		for id in lk.keys():
			var e: Dictionary = lk[id]
			var u: SimUnit = w.by_id.get(id)
			if u == null or not u.alive or w.time - e["time"] > 90.0:
				lk.erase(id)
				continue
			for v in viewers[ti]:
				if v.pos.distance_to(e["p"]) < v.def["sight"] * 0.4:
					lk.erase(id)
					break


static func detect_range(w: SimWorld, v: SimUnit, t: SimUnit) -> float:
	var sight: float = v.def["sight"] * w.sight_mult(v)
	if v.has_special("sensor_mast") and v.stationary_t > 3.0:
		sight = 175.0 * w.sight_mult(v)
	if not v.linked:
		sight *= 0.8
	var camo: float = t.def["camo"]
	if t.is_squad():
		if t.stationary_t > 3.0 and w.nav.cover_at(t.pos) > 0:
			camo *= 0.75
		if t.state == SimUnit.State.GARRISONED:
			camo *= 0.7
		if t.def.has("special") and "urban_bonus" in t.def["special"] and t.state == SimUnit.State.GARRISONED:
			camo *= 0.85
	if t.fired_t < 3.0:
		camo = maxf(camo * 1.8, 1.0)
	if t.is_moving() and t.cat == Defs.CAT_VEH:
		camo *= 1.15
	if v.has_special("sensor_mast") and v.stationary_t > 3.0:
		camo = maxf(camo, 0.85)
	return sight * camo


static func _team_sees(w: SimWorld, viewers: Array, t: SimUnit, team: int) -> bool:
	for r in w.reveals:
		if r["team"] == team and t.pos.distance_to(r["p"]) <= r["r"] and t.state != SimUnit.State.GARRISONED:
			return true
	for v: SimUnit in viewers:
		var d := v.pos.distance_to(t.pos)
		if d <= PROXIMITY:
			return true
		if d > detect_range(w, v, t):
			continue
		if w.has_los_units(v, t):
			return true
	return false

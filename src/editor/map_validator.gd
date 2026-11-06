extends RefCounted
## Playability checks for edited maps: two spawn zones, at least one objective,
## foot and wheeled routes between the spawns, every objective reachable on foot.
## Pure data (thread-safe): the editor runs it on a worker thread.
class_name MapValidator

const LV_OK := "ok"
const LV_WARN := "warn"
const LV_ERROR := "error"


## Returns [{level: ok|warn|error, text: String}], errors first.
static func validate(m: MapDef) -> Array:
	var out: Array = []
	var teams := {}
	for s in m.spawns:
		teams[int(s["team"])] = teams.get(int(s["team"]), 0) + 1
	var has0 := teams.has(0)
	var has1 := teams.has(1)
	if has0 and has1:
		out.append(_r(LV_OK, "Spawn zones for both teams"))
	else:
		out.append(_r(LV_ERROR, "Missing spawn zone for %s" % ("both teams" if not has0 and not has1 else ("Blue (team 0)" if not has0 else "Red (team 1)"))))
	if m.spawns.size() > 2:
		out.append(_r(LV_WARN, "%d spawn zones; only the first per team is used" % m.spawns.size()))
	if m.objectives.is_empty():
		out.append(_r(LV_ERROR, "No objectives (place at least one)"))
	else:
		out.append(_r(LV_OK, "%d objective%s" % [m.objectives.size(), "" if m.objectives.size() == 1 else "s"]))
		var ids := {}
		for o in m.objectives:
			if ids.has(o["id"]):
				out.append(_r(LV_WARN, "Duplicate objective id '%s'" % o["id"]))
			ids[o["id"]] = true
	if m.name.strip_edges() == "":
		out.append(_r(LV_WARN, "Map has no name"))
	if not (has0 and has1):
		return _sorted(out)
	var nav := NavGrid.new(m)
	var s0 := m.team_spawn(0).get_center()
	var s1 := m.team_spawn(1).get_center()
	for t in 2:
		var r := m.team_spawn(t)
		if not _mostly_open(nav, r):
			out.append(_r(LV_WARN, "%s spawn zone is mostly blocked" % ["Blue", "Red"][t]))
	var foot := _route(nav, Defs.MOVE_FOOT, s0, s1)
	out.append(_r(LV_OK, "Infantry route between spawns") if foot else _r(LV_ERROR, "No infantry route between the spawns"))
	var wheeled := _route(nav, Defs.MOVE_WHEELED, s0, s1)
	out.append(_r(LV_OK, "Vehicle route between spawns") if wheeled else _r(LV_WARN, "Wheeled vehicles cannot drive between the spawns (streets too narrow or blocked)"))
	var bad := []
	for o in m.objectives:
		var p: Vector2 = o["p"]
		if not (_route(nav, Defs.MOVE_FOOT, s0, p, 10.0) and _route(nav, Defs.MOVE_FOOT, s1, p, 10.0)):
			bad.append(o["id"])
	if not m.objectives.is_empty():
		if bad.is_empty():
			out.append(_r(LV_OK, "All objectives reachable on foot"))
		else:
			out.append(_r(LV_ERROR, "Objective%s %s not reachable on foot" % ["" if bad.size() == 1 else "s", ", ".join(bad)]))
	return _sorted(out)


static func has_errors(results: Array) -> bool:
	for r in results:
		if r["level"] == LV_ERROR:
			return true
	return false


static func _r(level: String, text: String) -> Dictionary:
	return {"level": level, "text": text}


static func _sorted(out: Array) -> Array:
	var rank := {LV_ERROR: 0, LV_WARN: 1, LV_OK: 2}
	out.sort_custom(func(a, b): return rank[a["level"]] < rank[b["level"]])
	return out


static func _route(nav: NavGrid, k: int, a: Vector2, b: Vector2, tol: float = 4.0) -> bool:
	var pa := nav.nearest_open_point(k, a)
	var pb := nav.nearest_open_point(k, b)
	if pb.distance_to(b) > 12.0 and tol > 4.0:
		return false
	var path := nav.find_path(k, pa, pb)
	return path.size() > 0 and path[path.size() - 1].distance_to(pb) < tol


static func _mostly_open(nav: NavGrid, r: Rect2) -> bool:
	var open := 0
	var total := 0
	var y := r.position.y + 1.0
	while y < r.end.y:
		var x := r.position.x + 1.0
		while x < r.end.x:
			total += 1
			if nav.is_open(Defs.MOVE_FOOT, Vector2(x, y)):
				open += 1
			x += 4.0
		y += 4.0
	return total == 0 or open >= total * 0.4

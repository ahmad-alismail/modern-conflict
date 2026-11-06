extends RefCounted
## Fog-of-war-respecting battlefield snapshot for one team, as plain JSON-able data.
## Used by the LLM commander (and tests that verify no hidden information leaks).
class_name Observation


static func build(w: SimWorld, team: int) -> Dictionary:
	var size := w.map.size_m()
	var own := []
	for u: SimUnit in w.team_units(team):
		var o := u.current_order()
		var e := {
			"id": u.id, "type": u.def["name"], "role": ClassicAI.role(u),
			"x": int(round(u.pos.x)), "y": int(round(u.pos.y)),
			"hp": int(round(u.hp_frac() * 100.0)), "ammo": int(round(u.total_ammo_frac() * 100.0)),
			"order": o.get("o", "idle"),
		}
		if u.is_squad():
			e["men"] = u.alive_members()
			if u.pinned: e["pinned"] = true
			if u.broken: e["broken"] = true
		if u.state == SimUnit.State.GARRISONED: e["in_building"] = true
		if u.state == SimUnit.State.EMBARKED: e["embarked_in"] = u.transport_id
		if u.def.get("transport", 0) > 0: e["transport_slots"] = u.def["transport"]
		if u.smoke_charges > 0: e["smoke"] = u.smoke_charges
		if u.mobility >= 2: e["immobilized"] = true
		own.append(e)
	var enemies := []
	for u: SimUnit in w.units:
		if not u.alive or u.team == team or not u.targetable() or (u.vis_mask & (1 << team)) == 0:
			continue
		var e := {"id": u.id, "type": u.def["name"], "x": int(round(u.pos.x)), "y": int(round(u.pos.y)),
			"hp": int(round(u.hp_frac() * 100.0)), "kind": ["infantry", "vehicle", "air"][u.cat]}
		if u.state == SimUnit.State.GARRISONED: e["in_building"] = true
		enemies.append(e)
	var contacts := []
	var lk: Dictionary = w.teams[team]["last_known"]
	for id in lk:
		var c: Dictionary = lk[id]
		contacts.append({"type": Defs.unit(c["def"])["name"], "x": int(c["p"].x), "y": int(c["p"].y), "seconds_ago": int(w.time - c["time"])})
	var objs := []
	for o in w.objectives:
		objs.append({"id": o["id"], "name": o["name"], "x": int(o["p"].x), "y": int(o["p"].y),
			"owner": "us" if o["owner"] == team else ("enemy" if o["owner"] >= 0 else "neutral"),
			"capture_progress": snappedf(o["progress"] * (1.0 if team == 0 else -1.0), 0.01), "contested": o.get("contested", false)})
	var t: Dictionary = w.teams[team]
	var support := {}
	for k in t["support"]:
		support[k] = {"charges": t["support"][k]["charges"], "ready_in_s": int(ceil(t["support"][k]["cd"]))}
	var other: Dictionary = w.teams[1 - team]
	return {
		"time_s": int(w.time), "map_size_m": [int(size.x), int(size.y)], "victory_mode": w.mode,
		"our_faction": Defs.FACTIONS[t["faction"]]["name"], "enemy_faction": Defs.FACTIONS[other["faction"]]["name"],
		"tickets": {"us": int(t["tickets"]), "enemy": int(other["tickets"])},
		"our_deployment_zone": _rect(w.map.team_spawn(team)), "enemy_deployment_zone": _rect(w.map.team_spawn(1 - team)),
		"objectives": objs, "our_units": own, "visible_enemies": enemies, "last_known_contacts": contacts,
		"support_powers": support, "reinforcement_waves_left": t["waves"].size(), "reinforcement_ready_in_s": int(ceil(t["wave_cd"])),
		"conditions": w.env,
	}


static func _rect(r: Rect2) -> Dictionary:
	return {"x": int(r.get_center().x), "y": int(r.get_center().y), "w": int(r.size.x), "h": int(r.size.y)}

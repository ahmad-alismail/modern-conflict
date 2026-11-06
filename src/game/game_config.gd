extends RefCounted
## Builders for GameSession configs.
class_name GameConfig


static func skirmish(player_faction: String, enemy_faction: String, difficulty: String, map_seed: int,
		opts: Dictionary = {}) -> Dictionary:
	var cfg := _base(map_seed, opts)
	cfg["mode"] = "skirmish"
	cfg["player_team"] = 0
	cfg["teams"] = [
		{"faction": player_faction, "controller": "human"},
		{"faction": enemy_faction, "controller": "ai", "difficulty": difficulty},
	]
	return cfg


## commanders: [{"controller": "ai"|"llm", "difficulty": ...}, {...}]
static func ai_vs_ai(f0: String, f1: String, c0: Dictionary, c1: Dictionary, map_seed: int, opts: Dictionary = {}) -> Dictionary:
	var cfg := _base(map_seed, opts)
	cfg["mode"] = "aivai"
	cfg["player_team"] = -1
	var t0 := {"faction": f0}
	t0.merge(c0)
	var t1 := {"faction": f1}
	t1.merge(c1)
	cfg["teams"] = [t0, t1]
	return cfg


## Translate a GameSession config into a SimWorld.setup() scenario (generating the map
## if needed). Shared by the game and headless tools so both run exactly the same battle.
static func to_sim_scenario(config: Dictionary) -> Dictionary:
	var map: MapDef = config.get("map")
	if map == null:
		var gen_opts := {"war_damage": config.get("war_damage", 0.25)}
		if String(config.get("map_name", "")) != "":
			gen_opts["name"] = config["map_name"]
		map = CityGenerator.generate(int(config.get("map_seed", 1)), gen_opts)
	var teams := []
	for t in config["teams"]:
		var td := {"faction": t["faction"], "name": t.get("name", Defs.FACTIONS[t["faction"]]["name"])}
		for k in ["forces", "placed", "support", "reinforcements", "tickets"]:
			if t.has(k):
				td[k] = t[k]
		teams.append(td)
	var env: Dictionary = config.get("env", {"tod": "day", "weather": "clear"})
	return {"map": map, "seed": int(config.get("seed", 1)), "mode": config.get("victory", "vp"),
		"tickets": int(config.get("tickets", 500)), "time_limit": float(config.get("time_limit", 0.0)),
		"hold_team": int(config.get("hold_team", -1)), "id": config.get("scenario_id", ""), "sandbox": config.get("sandbox", false),
		"env": {"night": env.get("tod", "day") == "night", "weather": env.get("weather", "clear")}, "teams": teams}


static func _base(map_seed: int, opts: Dictionary) -> Dictionary:
	var cfg := {
		"map_seed": map_seed,
		"seed": opts.get("seed", map_seed * 7 + 13),
		"war_damage": opts.get("war_damage", 0.25),
		"tickets": opts.get("tickets", 500),
		"time_limit": opts.get("time_limit", 0.0),
		"victory": opts.get("victory", "vp"),
		"env": {"tod": opts.get("tod", "day"), "weather": opts.get("weather", "clear")},
	}
	if opts.has("map"):
		cfg["map"] = opts["map"]
	return cfg

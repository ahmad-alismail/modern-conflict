extends RefCounted
## Fictional scenario missions: briefing text, forces, conditions and victory rules.
class_name Scenarios

const LIST := [
	{
		"id": "old_quarter",
		"place": "Tell Hamra",
		"title": "1. The Old Quarter",
		"subtitle": "Coalition Defense Force · Dusk · Tell Hamra",
		"briefing": "Brigade militia have dug into the souq and the old quarter of Tell Hamra. Your company must clear the district street by street. Expect RPG teams in upper floors and technicals racing through the alleys. Use your tanks as overwatch, not as battering rams, and let the infantry clear buildings.",
		"objectives_text": "• Hold more objectives than the enemy to drain their tickets.\n• Every unit you lose costs tickets. Avoid needless losses.",
		"forces_text": "3 rifle squads, MG team, ATGM team, sniper team, mortar section, 2 Sentinel MBTs, Warden IFV, Bulwark MRAP, supply truck. Artillery and airstrike support.",
		"map_seed": 4211, "war": 0.35, "tod": "dusk", "weather": "haze", "player_team": 0, "victory": "vp", "tickets": 500,
		"teams": [
			{"faction": "cdf", "forces": ["cdf_rifle", "cdf_rifle", "cdf_rifle", "cdf_mg", "cdf_atgm", "cdf_sniper", "cdf_mortar", "cdf_mbt", "cdf_mbt", "cdf_ifv", "cdf_mrap", "cdf_supply"]},
			{"faction": "pdb"},
		],
	},
	{
		"id": "long_avenue",
		"place": "Qasr al-Nur",
		"title": "2. The Long Avenue",
		"subtitle": "People's Defense Brigades · Day · Qasr al-Nur",
		"briefing": "An armored Coalition column is pushing down the main avenue toward the city center. You cannot stop tanks head-on. Hide your RPG teams in buildings along the flanks, mine the approaches, and strike the column's sides and rear. Hold on until the deadline.",
		"objectives_text": "• Defend: keep at least one objective until the 18-minute deadline.\n• If the enemy takes every objective, the city falls.",
		"forces_text": "5 militia squads, 3 RPG teams, 2 HMG teams, marksman, mortar team, MANPADS team, 2 technicals, recoilless technical. Mines, tunnel ambushes, rocket barrage.",
		"map_seed": 1838, "war": 0.4, "tod": "day", "weather": "clear", "player_team": 1, "victory": "hold", "hold_team": 1, "time_limit": 1080.0, "tickets": 9999,
		"teams": [
			{"faction": "cdf", "forces": ["cdf_rifle", "cdf_rifle", "cdf_rifle", "cdf_rifle", "cdf_mg", "cdf_atgm", "cdf_mortar", "cdf_mbt", "cdf_mbt", "cdf_mbt", "cdf_ifv", "cdf_ifv", "cdf_mrap", "cdf_heli", "cdf_supply"]},
			{"faction": "pdb", "forces": ["pdb_militia", "pdb_militia", "pdb_militia", "pdb_militia", "pdb_militia", "pdb_rpg", "pdb_rpg", "pdb_rpg", "pdb_hmg", "pdb_hmg", "pdb_marksman", "pdb_mortar", "pdb_manpads", "pdb_technical", "pdb_technical", "pdb_spg"],
				"support": {"minefield": 3, "tunnel": 3, "rocket_barrage": 2, "smoke_barrage": 1}},
		],
	},
	{
		"id": "iron_sky",
		"place": "Deir Saman",
		"title": "3. Iron Sky",
		"subtitle": "Helix Autonomous Command · Dust storm · Deir Saman",
		"briefing": "A dust storm blinds the Coalition's optics, but your drones and sensor masts still see. Keep your robots inside the network: units far from an operator team, EW vehicle or sensor mast lose accuracy. Coalition attack helicopters and autocannons are the main threat to your drones.",
		"objectives_text": "• Drain the enemy's tickets by holding objectives.\n• Keep robots networked. Protect your few human operators.",
		"forces_text": "Operators, Hound packs, gun and missile UGVs, recon quadcopters, FPV strike drones, Wasp drones, Raptor UCAV, Veil EW vehicle, sensor mast.",
		"map_seed": 7020, "war": 0.25, "tod": "day", "weather": "dust", "player_team": 0, "victory": "vp", "tickets": 500,
		"teams": [{"faction": "hac"}, {"faction": "cdf"}],
	},
	{
		"id": "night_raid",
		"place": "Ayn Zarqa",
		"title": "4. Night Raid",
		"subtitle": "Coalition Defense Force · Night · Ayn Zarqa",
		"briefing": "A small, fast Coalition force strikes at night. Your thermal sights see in the dark; the militia's do not. Strike fast, take the objectives, and do not let the fight drag on until dawn.",
		"objectives_text": "• Drain the enemy's tickets before the 20-minute time limit.\n• You are outnumbered. Use the darkness.",
		"forces_text": "2 rifle squads, sniper team, MG team, ATGM team, Sentinel MBT, Warden IFV, 2 Bulwark MRAPs, Kestrel attack helicopter.",
		"map_seed": 5521, "war": 0.2, "tod": "night", "weather": "clear", "player_team": 0, "victory": "vp", "tickets": 350, "time_limit": 1200.0,
		"teams": [
			{"faction": "cdf", "forces": ["cdf_rifle", "cdf_rifle", "cdf_sniper", "cdf_mg", "cdf_atgm", "cdf_mbt", "cdf_ifv", "cdf_mrap", "cdf_mrap", "cdf_heli"]},
			{"faction": "pdb"},
		],
	},
	{
		"id": "swarm",
		"place": "Kafr Ruma",
		"title": "5. The Swarm",
		"subtitle": "People's Defense Brigades · Rain · Kafr Ruma",
		"briefing": "Helix robots and drones are sweeping into Kafr Ruma. Small arms barely scratch the Hound robots; heavy machine guns, RPGs and MANPADS do. Fight from buildings, where drones struggle to see you, and hold out until the storm clears.",
		"objectives_text": "• Defend: keep at least one objective until the 15-minute deadline.",
		"forces_text": "Militia, RPG and HMG teams, two MANPADS teams, marksmen, technicals, relic tank. Mines and tunnels.",
		"map_seed": 912, "war": 0.3, "tod": "dawn", "weather": "rain", "player_team": 1, "victory": "hold", "hold_team": 1, "time_limit": 900.0, "tickets": 9999,
		"teams": [
			{"faction": "hac"},
			{"faction": "pdb", "forces": ["pdb_militia", "pdb_militia", "pdb_militia", "pdb_militia", "pdb_rpg", "pdb_rpg", "pdb_hmg", "pdb_hmg", "pdb_hmg", "pdb_marksman", "pdb_marksman", "pdb_manpads", "pdb_manpads", "pdb_technical", "pdb_technical", "pdb_tank"]},
		],
	},
]


static func all() -> Array:
	return LIST


static func find(id: String) -> Dictionary:
	for s in LIST:
		if s["id"] == id:
			return s
	return {}


static func build(id: String, difficulty: String) -> Dictionary:
	var s := find(id)
	var pt: int = s["player_team"]
	var teams := []
	for ti in s["teams"].size():
		var t: Dictionary = s["teams"][ti].duplicate(true)
		t["controller"] = "human" if ti == pt else "ai"
		t["difficulty"] = difficulty
		teams.append(t)
	return {
		"mode": "scenario", "scenario_id": id, "map_seed": s["map_seed"], "seed": s["map_seed"] * 3 + 1,
		"war_damage": s["war"], "map_name": s.get("place", ""), "player_team": pt, "teams": teams, "victory": s["victory"],
		"tickets": s.get("tickets", 500), "time_limit": s.get("time_limit", 0.0), "hold_team": s.get("hold_team", -1),
		"env": {"tod": s["tod"], "weather": s["weather"]}, "briefing": s["briefing"], "title": s["title"],
	}

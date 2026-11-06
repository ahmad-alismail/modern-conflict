extends RefCounted
## Ready-made army compositions for the Force Builder (per faction).
## Each preset: {"units": {def_id: count}, "support": {power: charges}}.
class_name ForcePresets

const PRESETS := {
	"cdf": {
		"Armored": {"units": {"cdf_mbt": 4, "cdf_ifv": 2, "cdf_mrap": 1, "cdf_rifle": 2, "cdf_atgm": 1, "cdf_supply": 1},
			"support": {"artillery": 1, "airstrike": 1, "missile_strike": 1, "recon_uav": 1, "smoke_barrage": 2}},
		"Infantry": {"units": {"cdf_rifle": 6, "cdf_mg": 2, "cdf_atgm": 2, "cdf_sniper": 2, "cdf_mortar": 1, "cdf_mrap": 2, "cdf_supply": 1},
			"support": {"artillery": 2, "airstrike": 1, "recon_uav": 2, "smoke_barrage": 3}},
		"Air & Drones": {"units": {"cdf_heli": 3, "cdf_rifle": 3, "cdf_mg": 1, "cdf_atgm": 1, "cdf_mrap": 1, "cdf_supply": 1},
			"support": {"airstrike": 3, "missile_strike": 1, "recon_uav": 3}},
		"Artillery & Missiles": {"units": {"cdf_mortar": 3, "cdf_rifle": 3, "cdf_mg": 1, "cdf_atgm": 2, "cdf_mbt": 1, "cdf_ifv": 1, "cdf_supply": 1},
			"support": {"artillery": 4, "missile_strike": 3, "airstrike": 1, "recon_uav": 2, "smoke_barrage": 1}},
	},
	"pdb": {
		"Armored": {"units": {"pdb_tank": 3, "pdb_spg": 3, "pdb_technical": 3, "pdb_militia": 4, "pdb_rpg": 2, "pdb_hmg": 1},
			"support": {"rocket_barrage": 2, "minefield": 2, "tunnel": 1, "smoke_barrage": 1}},
		"Infantry": {"units": {"pdb_militia": 9, "pdb_rpg": 4, "pdb_hmg": 3, "pdb_marksman": 2, "pdb_mortar": 1, "pdb_manpads": 1},
			"support": {"rocket_barrage": 1, "minefield": 2, "tunnel": 4, "smoke_barrage": 2}},
		"Air Defense": {"units": {"pdb_manpads": 4, "pdb_hmg": 4, "pdb_militia": 5, "pdb_rpg": 2, "pdb_technical": 3},
			"support": {"rocket_barrage": 2, "minefield": 1, "tunnel": 2, "smoke_barrage": 2}},
		"Artillery & Rockets": {"units": {"pdb_mortar": 3, "pdb_mrl": 3, "pdb_militia": 5, "pdb_rpg": 2, "pdb_hmg": 2, "pdb_technical": 1},
			"support": {"rocket_barrage": 4, "minefield": 2, "tunnel": 1, "smoke_barrage": 1}},
	},
	"hac": {
		"Armored (UGVs)": {"units": {"hac_ugv_gun": 4, "hac_ugv_atgm": 3, "hac_operator": 2, "hac_hound": 2, "hac_ew": 1, "hac_mast": 1},
			"support": {"drone_strike": 2, "recon_uav": 1, "emp": 1, "smoke_barrage": 1}},
		"Robots": {"units": {"hac_hound": 6, "hac_operator": 3, "hac_ugv_gun": 1, "hac_ew": 1, "hac_mast": 1, "hac_recon": 1},
			"support": {"drone_strike": 2, "recon_uav": 2, "emp": 2, "smoke_barrage": 2}},
		"Air & Drones": {"units": {"hac_recon": 3, "hac_fpv": 6, "hac_wasp": 4, "hac_ucav": 2, "hac_operator": 2, "hac_ew": 1, "hac_mast": 1},
			"support": {"drone_strike": 4, "recon_uav": 2, "emp": 1}},
		"Missiles": {"units": {"hac_ugv_atgm": 4, "hac_ucav": 2, "hac_operator": 2, "hac_hound": 2, "hac_mast": 1, "hac_ew": 1},
			"support": {"drone_strike": 5, "recon_uav": 2, "emp": 1}},
	},
}


static func names(faction: String) -> Array:
	return ["Default"] + PRESETS[faction].keys()


## Returns {"units": {def: n}, "support": {power: charges}} for a preset name.
static func get_preset(faction: String, preset: String) -> Dictionary:
	if preset == "Default" or not PRESETS[faction].has(preset):
		var units := {}
		for id in Defs.FACTIONS[faction]["forces"]:
			units[id] = units.get(id, 0) + 1
		return {"units": units, "support": Defs.FACTIONS[faction]["support"].duplicate()}
	return PRESETS[faction][preset].duplicate(true)


## Flatten unit counts into the forces list the simulation deploys (canonical roster order).
static func to_forces(units: Dictionary) -> Array:
	var out := []
	for id in Defs.UNITS:
		for k in int(units.get(id, 0)):
			out.append(id)
	return out

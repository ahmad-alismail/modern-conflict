extends TestBase
## Custom forces chosen in the Force Builder must reach the battle exactly.


func test_custom_forces_and_support_reach_battle() -> void:
	var cfg := GameConfig.skirmish("cdf", "hac", "medium", 7)
	cfg["teams"][0]["forces"] = ForcePresets.to_forces({"cdf_mbt": 3, "cdf_heli": 2, "cdf_mortar": 1})
	cfg["teams"][0]["support"] = {"missile_strike": 2, "airstrike": 3}
	cfg["teams"][1]["forces"] = ForcePresets.to_forces(ForcePresets.get_preset("hac", "Air & Drones")["units"])
	var w := SimWorld.new()
	w.setup(GameConfig.to_sim_scenario(cfg))
	var counts := {}
	for u in w.team_units(0):
		counts[u.def_id] = counts.get(u.def_id, 0) + 1
	eq(counts, {"cdf_mbt": 3, "cdf_heli": 2, "cdf_mortar": 1}, "blue army is exactly the custom list")
	eq(w.teams[0]["support"].keys().size(), 2, "only the chosen support powers")
	eq(w.teams[0]["support"]["missile_strike"]["charges"], 2, "missile strike charges")
	var air := 0
	for u in w.team_units(1):
		if u.is_air():
			air += 1
	eq(air, 15, "enemy Air & Drones preset deployed (3 recon + 6 FPV + 4 Wasp + 2 UCAV)")


func test_missile_strike_destroys_vehicle() -> void:
	var m := MapDef.new(80, 80)
	m.spawns = [{"team": 0, "rect": Rect2(4, 4, 20, 20)}, {"team": 1, "rect": Rect2(136, 136, 20, 20)}]
	var w := SimWorld.new()
	w.setup({"map": m, "seed": 3, "mode": "annihilation", "teams": [
		{"faction": "cdf", "placed": [{"def": "cdf_sniper", "p": Vector2(60, 80)}], "support": {"missile_strike": 1}, "reinforcements": []},
		{"faction": "pdb", "placed": [{"def": "pdb_technical", "p": Vector2(100, 80)}], "reinforcements": []}]})
	var tech: SimUnit = w.team_units(1)[0]
	for i in 10:
		w.step()
	w.issue({"type": "support", "team": 0, "power": "missile_strike", "pos": tech.pos + Vector2(6, 4), "dir": Vector2.RIGHT})
	for i in 400:
		w.step()
	check(not tech.alive, "missile strike homed on and destroyed the technical")
	eq(w.teams[0]["support"]["missile_strike"]["charges"], 0, "charge consumed")

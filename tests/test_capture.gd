extends TestBase
## Every ground unit can capture objectives; aircraft cannot.


func _world(def_id: String) -> SimWorld:
	var m := MapDef.new(80, 80)
	m.spawns = [{"team": 0, "rect": Rect2(4, 4, 20, 20)}, {"team": 1, "rect": Rect2(136, 136, 20, 20)}]
	m.objectives = [{"id": "A", "name": "Test Point", "p": Vector2(80, 80), "r": 16.0}]
	var w := SimWorld.new()
	w.setup({"map": m, "seed": 1, "teams": [
		{"faction": Defs.unit(def_id)["faction"], "placed": [{"def": def_id, "p": Vector2(80, 80)}], "reinforcements": []},
		{"faction": "pdb", "placed": [{"def": "pdb_militia", "p": Vector2(150, 150)}], "reinforcements": []}]})
	return w


func test_vehicles_and_support_infantry_capture() -> void:
	for id in ["cdf_mbt", "cdf_sniper", "cdf_mortar", "pdb_technical", "hac_ugv_gun", "hac_ew"]:
		var w := _world(id)
		for i in 75 * SimWorld.TICK_RATE:
			w.step()
		eq(w.objectives[0]["owner"], 0, "%s captured the point" % id)


func test_aircraft_cannot_capture() -> void:
	for id in ["cdf_heli", "hac_recon"]:
		var w := _world(id)
		for i in 75 * SimWorld.TICK_RATE:
			w.step()
		eq(w.objectives[0]["owner"], -1, "%s did not capture" % id)

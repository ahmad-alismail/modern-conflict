extends TestBase


func _scenario(m: MapDef) -> Dictionary:
	return {"map": m, "seed": 77, "teams": [{"faction": "cdf"}, {"faction": "hac"}]}


func test_save_restore_continues_identically() -> void:
	var m := CityGenerator.generate(19)
	var w := SimWorld.new()
	w.setup(_scenario(m))
	var center := m.size_m() * 0.5
	for ti in 2:
		var ids := []
		for u in w.team_units(ti):
			ids.append(u.id)
		w.issue({"type": "attack_move", "team": ti, "ids": ids, "pos": center})
	for i in 1400:
		w.step()
	var snap := Serializer.capture(w)
	# round-trip through the on-disk binary format, like SaveSystem does
	var bytes := var_to_bytes({"map": w.map.to_dict(), "state": snap})
	var data: Dictionary = bytes_to_var(bytes)
	var w2 := SimWorld.new()
	w2.setup(_scenario(MapDef.from_dict(data["map"])))
	Serializer.restore(w2, data["state"])
	eq(w2.units.size(), w.units.size(), "unit count restored")
	eq(w2.tick, w.tick, "tick restored")
	for i in 600:
		w.step()
		w2.step()
	eq(w2.state_hash(), w.state_hash(), "restored world evolves identically")

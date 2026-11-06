extends TestBase


func test_fog_limits_visibility() -> void:
	var m := CityGenerator.generate(7)
	var w := SimWorld.new()
	w.setup({"map": m, "seed": 1, "teams": [{"faction": "cdf"}, {"faction": "pdb"}]})
	var fog := FogOfWar.new()
	var t0 := Time.get_ticks_msec()
	fog.setup(w, 0)
	var ms := Time.get_ticks_msec() - t0
	var vis := 0
	for v in fog.visible_now:
		if v:
			vis += 1
	var frac := float(vis) / fog.visible_now.size()
	print("    fog visible fraction %.3f (%d cells), compute %d ms" % [frac, vis, ms])
	check(frac > 0.01 and frac < 0.35, "visible fraction plausible: %.3f" % frac)
	var east := w.map.team_spawn(1).get_center()
	check(not fog.is_cell_visible(east), "enemy spawn is fogged")
	var dark := 0
	for d in fog.display:
		if d < 0.3:
			dark += 1
	check(dark > fog.display.size() / 2, "most of the map starts unexplored (%d dark)" % dark)
	fog.free()

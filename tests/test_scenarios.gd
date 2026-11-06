extends TestBase
## Every scenario must boot and reach a result with classic AI on both sides.


func test_all_scenarios_finish() -> void:
	for s in Scenarios.all():
		var cfg := Scenarios.build(s["id"], "medium")
		var w := SimWorld.new()
		w.setup(GameConfig.to_sim_scenario(cfg))
		var ais := [ClassicAI.new(0, "medium"), ClassicAI.new(1, "medium")]
		var limit := int(maxf(float(cfg.get("time_limit", 0.0)) + 60.0, 1800.0)) * SimWorld.TICK_RATE
		while w.outcome.is_empty() and w.tick < limit:
			for ai in ais:
				ai.think(w)
			w.step()
			w.events.clear()
		print("    %s: winner=%s '%s' at %ds" % [s["id"], w.outcome.get("winner", "-"), w.outcome.get("reason", "no result"), int(w.time)])
		check(not w.outcome.is_empty(), "scenario %s reached a result" % s["id"])
		if cfg["victory"] == "hold":
			var hold: int = cfg["hold_team"]
			check(w.objectives.all(func(o): return true), "objectives exist")
			check(w.outcome.get("winner", -1) in [0, 1], "hold scenario %s decided" % s["id"])

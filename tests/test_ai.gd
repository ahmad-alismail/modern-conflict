extends TestBase


static func _world(seed_value: int = 5) -> SimWorld:
	var w := SimWorld.new()
	w.setup({"map": CityGenerator.generate(seed_value), "seed": seed_value, "teams": [{"faction": "cdf"}, {"faction": "pdb"}]})
	return w


func test_observation_respects_fog() -> void:
	var w := _world()
	var obs := Observation.build(w, 0)
	for e in obs["visible_enemies"]:
		var u: SimUnit = w.by_id[e["id"]]
		check((u.vis_mask & 1) != 0, "observation leaked unseen enemy %d" % u.id)
	eq(obs["our_units"].size(), w.team_units(0).size(), "all own units listed")
	check(JSON.stringify(obs).length() < 20000, "observation stays compact")


func test_classic_ai_sees_only_visible() -> void:
	var w := _world()
	var ai := ClassicAI.new(0, "hard")
	for e in ai.visible_enemies(w):
		check((e.vis_mask & 1) != 0, "AI read an unseen enemy")


func test_llm_order_validation() -> void:
	var w := _world()
	var mine: SimUnit = w.team_units(0)[0]
	var theirs: SimUnit = w.team_units(1)[0]
	theirs.vis_mask = 1 << 1   # not visible to team 0
	var reply := {"reasoning": "test", "orders": [
		{"action": "move", "unit_ids": [mine.id, theirs.id, 99999], "x": 100, "y": 5000},
		{"action": "attack", "unit_ids": [mine.id], "target_id": theirs.id},
		{"action": "support", "unit_ids": [], "power": "nuke", "x": 10, "y": 10},
		{"action": "support", "unit_ids": [], "power": "artillery", "x": 200, "y": 200},
		{"action": "dance", "unit_ids": [mine.id]},
	]}
	var cmds := LLMCommander.parse_orders(reply, w, 0)
	eq(cmds.size(), 2, "only valid orders survive")
	eq(cmds[0]["ids"], [mine.id], "foreign and unknown unit ids dropped")
	check(cmds[0]["pos"].y <= w.map.size_m().y, "position clamped into the map")
	eq(cmds[1]["power"], "artillery", "valid support power kept")


func test_ai_vs_ai_match_finishes() -> void:
	var w := _world(23)
	var ais := [ClassicAI.new(0, "hard"), ClassicAI.new(1, "medium")]
	var max_ticks := 30 * 60 * SimWorld.TICK_RATE
	while w.outcome.is_empty() and w.tick < max_ticks:
		for ai in ais:
			ai.think(w)
		w.step()
		w.events.clear()
	print("    AI vs AI: %s after %d s (lost %d / %d)" % [w.outcome.get("reason", "no result"), int(w.time), w.teams[0]["stats"]["lost"], w.teams[1]["stats"]["lost"]])
	check(not w.outcome.is_empty(), "match reached a result within 30 minutes")
	check(w.teams[0]["stats"]["shots"] > 50 and w.teams[1]["stats"]["shots"] > 50, "both sides fought")

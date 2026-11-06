extends SceneTree
## Headless AI-vs-AI batch for balance testing.
##   godot --headless --path . -s res://tools/aivai_headless.gd -- --pairs=cdf:pdb,hac:cdf --diff=hard --seeds=3 --max-min=25

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var pairs: PackedStringArray = String(args.get("pairs", "cdf:pdb")).split(",")
	var d0: String = args.get("d0", args.get("diff", "hard"))
	var d1: String = args.get("d1", args.get("diff", "hard"))
	var seeds := int(args.get("seeds", "2"))
	var max_ticks := int(float(args.get("max-min", "25")) * 60.0 * SimWorld.TICK_RATE)
	var wins := {}
	for pair in pairs:
		var f := pair.split(":")
		for s in seeds:
			var seed_v := 100 + s * 17
			var m := CityGenerator.generate(seed_v)
			var w := SimWorld.new()
			w.setup({"map": m, "seed": seed_v, "tickets": 500, "teams": [{"faction": f[0]}, {"faction": f[1]}]})
			var ais := [ClassicAI.new(0, d0), ClassicAI.new(1, d1)]
			# --p1=key:value;key:value overrides team 1's profile (experiments)
			for kv in String(args.get("p1", "")).split(";", false):
				var parts := kv.split(":")
				var cur = ais[1].p[parts[0]]
				ais[1].p[parts[0]] = (parts[1] == "true") if typeof(cur) == TYPE_BOOL else float(parts[1])
			var t0 := Time.get_ticks_msec()
			while w.outcome.is_empty() and w.tick < max_ticks:
				for ai in ais:
					ai.think(w)
				w.step()
				w.events.clear()
			var ms := Time.get_ticks_msec() - t0
			var winner: int = w.outcome.get("winner", -1)
			var key := "%s(%s) vs %s(%s)" % [f[0], d0, f[1], d1]
			if not wins.has(key):
				wins[key] = [0, 0, 0]
			wins[key][winner if winner >= 0 else 2] += 1
			print("%s seed %d: winner=%s reason='%s' time=%.0fs tickets=%.0f/%.0f lost=%d/%d units=%d/%d  [%d ms, %.2f ms/tick]" % [
				key, seed_v, (f[winner] if winner >= 0 else "none"), w.outcome.get("reason", "timeout"), w.time,
				w.teams[0]["tickets"], w.teams[1]["tickets"], w.teams[0]["stats"]["lost"], w.teams[1]["stats"]["lost"],
				w.team_units(0).size(), w.team_units(1).size(), ms, float(ms) / maxi(w.tick, 1)])
	for k in wins:
		print("SUMMARY %s: %d - %d (draws %d)" % [k, wins[k][0], wins[k][1], wins[k][2]])
	quit()

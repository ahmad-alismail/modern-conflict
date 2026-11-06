extends SceneTree
## Diagnostic: which unit types inflict losses (men + vehicles) in an AI-vs-AI match.
##   ... -s res://tools/kill_stats.gd -- --pair=pdb:cdf --seed=100

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var f: PackedStringArray = String(args.get("pair", "pdb:cdf")).split(":")
	var seed_v := int(args.get("seed", "100"))
	var w := SimWorld.new()
	w.setup({"map": CityGenerator.generate(seed_v), "seed": seed_v, "teams": [{"faction": f[0]}, {"faction": f[1]}]})
	var ais := [ClassicAI.new(0, "hard"), ClassicAI.new(1, "hard")]
	var killers := [{}, {}]   # team -> killer def -> count of men/vehicles killed
	var victims := [{}, {}]
	var counts := {}
	while w.outcome.is_empty() and w.tick < 36000:
		for ai in ais:
			ai.think(w)
		w.step()
		for e in w.drain_events():
			if e["t"] in ["embark", "disembark", "garrison", "bld_collapsed"]:
				counts[e["t"]] = counts.get(e["t"], 0) + 1
			if e["t"] == "death" or (e["t"] == "destroyed" and not w.by_id[e["u"]].is_squad() and not e.get("expended", false)):
				var v: SimUnit = w.by_id[e["u"]]
				var k: SimUnit = w.by_id.get(e.get("killer", -1))
				var kname: String = k.def_id if k != null else "support/splash"
				var kt: int = k.team if k != null else 1 - v.team
				killers[kt][kname] = killers[kt].get(kname, 0) + 1
				victims[v.team][v.def_id] = victims[v.team].get(v.def_id, 0) + 1
	print("result: ", w.outcome.get("reason", "timeout"), " at ", int(w.time), "s  events: ", counts)
	for t in 2:
		print("team %d (%s) inflicted: %s" % [t, f[t], killers[t]])
		print("team %d (%s) lost:      %s" % [t, f[t], victims[t]])
	quit()

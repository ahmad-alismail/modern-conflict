extends Node3D
## Preview: every MapDef.PROPS kind in a row of variants, plus the four wall kinds.
## Args: --dist=<m> --pitch=<deg> --yaw=<deg> --focus=x,z --tod=day

func _ready() -> void:
	var kinds := MapDef.PROPS.keys()
	kinds.sort()
	var props: Array = []
	for i in kinds.size():
		var kind: String = kinds[i]
		var row := i / 6
		var col := i % 6
		var base := Vector2(col * 14.0 - 35.0, row * 14.0 - 14.0)
		for v in 3:
			var p := base + Vector2(0, (v - 1) * 4.2) if kind not in ["bus_wreck", "container", "rubble"] else base + Vector2(0, (v - 1) * 4.6)
			if kind == "bus_wreck" and v > 0:
				continue
			props.append({"kind": kind, "p": p, "rot": 0.3 * v, "s": 1.0 if kind not in ["palm", "tree"] else 0.9 + 0.15 * v})
	var t0 := Time.get_ticks_usec()
	add_child(PropBuilder.build_props(props))
	var walls := [
		{"a": Vector2(-35, 30), "b": Vector2(-20, 30), "h": 2.6, "kind": MapDef.W_COMPOUND},
		{"a": Vector2(-20, 30), "b": Vector2(-20, 40), "h": 2.6, "kind": MapDef.W_COMPOUND},
		{"a": Vector2(-14, 30), "b": Vector2(-2, 30), "h": 1.1, "kind": MapDef.W_LOW},
		{"a": Vector2(4, 30), "b": Vector2(16, 33), "h": 2.1, "kind": MapDef.W_HESCO},
		{"a": Vector2(22, 30), "b": Vector2(26, 33), "h": 0.9, "kind": MapDef.W_SANDBAG},
		{"a": Vector2(26, 33), "b": Vector2(30, 31), "h": 0.9, "kind": MapDef.W_SANDBAG},
	]
	add_child(PropBuilder.build_walls(walls))
	print("[preview_props] built in %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var f := DevHarness.arg("focus", "0,8").split(",")
	var focus := Vector3(float(f[0]), 1.0, float(f[1]))
	PreviewKit.setup(self, focus, float(DevHarness.arg("dist", "60")), float(DevHarness.arg("pitch", "35")), float(DevHarness.arg("yaw", "70")), DevHarness.arg("tod", "day"))

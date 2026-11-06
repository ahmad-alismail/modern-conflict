extends Node3D
## Preview: every building style (intact row, damaged row, ruins row).
## Args: --focus=<i> (0-7 style, 8+ damaged, 16+ ruin)  --dist=<m>  --pitch=<deg>  --yaw=<deg>
##       --tod=day|dawn|dusk|night  --seed=<n>

const STYLES := [
	[MapDef.S_OLD, Vector2(12, 11), 2], [MapDef.S_APARTMENT, Vector2(26, 14), 6], [MapDef.S_SHOP, Vector2(16, 17), 5],
	[MapDef.S_VILLA, Vector2(12, 11), 2], [MapDef.S_MOSQUE, Vector2(24, 22), 3], [MapDef.S_INDUSTRIAL, Vector2(30, 20), 1],
	[MapDef.S_UNFINISHED, Vector2(14, 12), 4], [MapDef.S_TOWER, Vector2(18, 17), 10]]


func _ready() -> void:
	var sd := int(DevHarness.arg("seed", "100"))
	var t0 := Time.get_ticks_usec()
	var positions: Array[Vector3] = []
	for row in 3:
		for i in STYLES.size():
			var spec: Array = STYLES[i]
			var b := {"id": row * 10 + i, "c": Vector2.ZERO, "size": spec[1], "rot": 0.0, "floors": spec[2],
				"style": spec[0], "color": (i + sd) % 8, "seed": sd + i * 7919}
			var n: Node3D
			if row == 2:
				n = BuildingBuilder.build_ruin(b)
			else:
				n = BuildingBuilder.build(b)
				if row == 1:
					BuildingBuilder.apply_damage(n, 1)
			var p := Vector3((i % 4) * 40.0 - 60.0, 0, (i / 4) * 40.0 - 20.0 + row * 100.0)
			n.position = p
			positions.append(p)
			add_child(n)
	print("[preview_buildings] built 24 in %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var focus := int(DevHarness.arg("focus", "-1"))
	var tod := DevHarness.arg("tod", "day")
	if focus >= 0:
		var fp := positions[focus] + Vector3(0, 6, 0)
		PreviewKit.setup(self, fp, float(DevHarness.arg("dist", "34")), float(DevHarness.arg("pitch", "22")), float(DevHarness.arg("yaw", "60")), tod)
	else:
		PreviewKit.setup(self, Vector3(0, 0, 0), float(DevHarness.arg("dist", "120")), float(DevHarness.arg("pitch", "35")), float(DevHarness.arg("yaw", "65")), tod)

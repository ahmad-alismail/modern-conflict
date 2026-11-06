extends Node3D
## Preview: a few buildings + units using whatever builders are installed.

func _ready() -> void:
	PreviewKit.setup(self, Vector3(0, 4, 0), 60.0, 28.0, 30.0)
	var styles := [MapDef.S_OLD, MapDef.S_APARTMENT, MapDef.S_SHOP, MapDef.S_VILLA, MapDef.S_MOSQUE, MapDef.S_INDUSTRIAL, MapDef.S_UNFINISHED, MapDef.S_TOWER]
	for i in styles.size():
		var b := {"id": i, "c": Vector2.ZERO, "size": Vector2(14, 12), "rot": 0.0, "floors": 3 if styles[i] != MapDef.S_TOWER else 9, "style": styles[i], "color": i, "seed": 100 + i}
		var n := BuildingBuilder.build(b)
		n.position = Vector3((i % 4) * 20 - 30, 0, (i / 4) * 20 - 20)
		add_child(n)
	var ids := ["cdf_mbt", "cdf_rifle", "pdb_technical", "hac_hound", "cdf_heli"]
	for i in ids.size():
		var m := UnitModels.create(ids[i], Color.CORNFLOWER_BLUE)
		m.position = Vector3(i * 9 - 18, 0 if ids[i] != "cdf_heli" else 8, 18)
		add_child(m)

extends Node3D
## Preview: the full CityGenerator.generate(seed) map - every building, wall and prop at
## its map position over sandy ground. Prints build time and FPS (vsync off).
## Args: --seed=<n> (7)  --dist=<m> --pitch=<deg> --yaw=<deg> --focus=x,z (map coords)
##       --damage=<0..1> fraction of buildings damaged  --tod=day  --size=<cells> (240)  --war=<0..1>

var _timer := 0.0
var _frames := 0
var _reported := false


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var sd := int(DevHarness.arg("seed", "7"))
	var t0 := Time.get_ticks_usec()
	var opts := {"size": int(DevHarness.arg("size", "240")), "war_damage": float(DevHarness.arg("war", "0.25"))}
	var m := CityGenerator.generate(sd, opts)
	var t1 := Time.get_ticks_usec()
	var dmg_frac := float(DevHarness.arg("damage", "0.15"))
	var city := Node3D.new()
	city.name = "City"
	add_child(city)
	var rng := Rng.new(sd * 31 + 5)
	var nb := 0
	var nr := 0
	var verts := 0
	for b in m.buildings:
		var n := BuildingBuilder.build(b)
		var c: Vector2 = b["c"]
		n.position = Vector3(c.x, 0, c.y)
		n.rotation.y = -float(b["rot"])
		if rng.chance(dmg_frac):
			BuildingBuilder.apply_damage(n, 1)
		city.add_child(n)
		nb += 1
		for ch in n.get_children():
			if ch is MeshInstance3D:
				verts += (ch as MeshInstance3D).mesh.surface_get_array_len(0)
	var t2 := Time.get_ticks_usec()
	city.add_child(PropBuilder.build_walls(m.walls))
	var t3 := Time.get_ticks_usec()
	city.add_child(PropBuilder.build_props(m.props))
	var t4 := Time.get_ticks_usec()
	# a few collapsed buildings on rubble lots so ruins show up too
	for p in m.props:
		if p["kind"] == "rubble" and float(p["s"]) >= 2.0 and nr < 12:
			var s: float = p["s"]
			var rb := {"id": 9000 + nr, "c": p["p"], "size": Vector2(4.0 * s, 3.5 * s), "rot": 0.0, "floors": 3,
				"style": nr % 3, "color": nr % 8, "seed": 777 + nr}
			var rn := BuildingBuilder.build_ruin(rb)
			rn.position = Vector3(p["p"].x + 3.0 * s, 0, p["p"].y)
			city.add_child(rn)
			nr += 1
	var t5 := Time.get_ticks_usec()
	print("[preview_city] seed %d: %d buildings, %d walls, %d props, %d ruins" % [sd, nb, m.walls.size(), m.props.size(), nr])
	print("[preview_city] generate %.0f ms | buildings %.0f ms (%.2f ms each, %.1fk verts) | walls %.0f ms | props %.0f ms | ruins %.0f ms | total build %.0f ms" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t2 - t1) / 1000.0 / maxi(nb, 1), verts / 1000.0, (t3 - t2) / 1000.0,
		(t4 - t3) / 1000.0, (t5 - t4) / 1000.0, (t5 - t1) / 1000.0])
	var size := m.size_m()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size + Vector2(400, 400)
	ground.mesh = pm
	ground.position = Vector3(size.x * 0.5, -0.01, size.y * 0.5)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.72, 0.64, 0.52)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	EnvMaterials.set_night_lights(1.0 if DevHarness.arg("tod", "day") == "night" else 0.0)
	var f := DevHarness.arg("focus", "%f,%f" % [size.x * 0.5, size.y * 0.5]).split(",")
	var focus := Vector3(float(f[0]), 0.0, float(f[1]))
	PreviewKit.setup(self, focus, float(DevHarness.arg("dist", "260")), float(DevHarness.arg("pitch", "42")),
		float(DevHarness.arg("yaw", "60")), DevHarness.arg("tod", "day"))
	# PreviewKit adds its own 600 m ground at the origin; hide it in favour of ours.
	for ch in get_children():
		if ch is MeshInstance3D and ch != ground:
			(ch as MeshInstance3D).visible = false


func _process(delta: float) -> void:
	_timer += delta
	if _timer > 2.0:
		_frames += 1
	if _timer > 6.0 and not _reported:
		_reported = true
		print("[preview_city] FPS %.1f (engine) | %.1f (avg over %d frames) | draw calls %d | primitives %.0fk" % [
			Engine.get_frames_per_second(), _frames / (_timer - 2.0), _frames,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0])

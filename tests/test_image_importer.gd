extends TestBase
## ImageImporter: classification, building extraction, roads, playability.
## The synthetic image builders are static so tools/preview_editor_images.gd can
## write them to tools/test_images/ for manual testing in the editor.

const OPEN_COL := Color(0.86, 0.8, 0.62)
const ROAD_COL := Color(0.6, 0.6, 0.6)
const BLDG_COL := Color(0.1, 0.1, 0.1)
const PARK_COL := Color(0.3, 0.6, 0.25)
const WATER_COL := Color(0.25, 0.4, 0.8)


## Color-coded plan: gray road grid (one wide avenue each way), black blocks
## (some solid, some split into houses), a green park, a blue pond.
static func make_plan_image(px: int = 480) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(OPEN_COL)
	var s := px / 480.0
	var lines := [40, 130, 240, 350, 440]
	for i in lines.size():
		var w := int((16 if i == 2 else 9) * s)
		var c := int(lines[i] * s)
		img.fill_rect(Rect2i(c - w / 2, 0, w, px), ROAD_COL)
		img.fill_rect(Rect2i(0, c - w / 2, px, w), ROAD_COL)
	var rng := Rng.new(5)
	for bx in lines.size() - 1:
		for by in lines.size() - 1:
			var x0 := int(lines[bx] * s) + int(12 * s)
			var x1 := int(lines[bx + 1] * s) - int(12 * s)
			var y0 := int(lines[by] * s) + int(12 * s)
			var y1 := int(lines[by + 1] * s) - int(12 * s)
			var r := Rect2i(x0, y0, x1 - x0, y1 - y0)
			if bx == 1 and by == 2:
				img.fill_rect(r, PARK_COL)
				continue
			if bx == 2 and by == 1:
				var cx := r.get_center()
				var rad := mini(r.size.x, r.size.y) * 0.4
				for y in range(r.position.y, r.end.y):
					for x in range(r.position.x, r.end.x):
						if Vector2(x, y).distance_to(Vector2(cx)) < rad:
							img.set_pixel(x, y, WATER_COL)
				continue
			if (bx + by) % 2 == 0:
				img.fill_rect(r, BLDG_COL)
			else:
				# a row of detached houses
				var n := rng.range_i(2, 4)
				var bw := r.size.x / n
				for k in n:
					img.fill_rect(Rect2i(r.position.x + k * bw + int(3 * s), r.position.y + int(4 * s), bw - int(6 * s), r.size.y / 2 - int(6 * s)), BLDG_COL)
					img.fill_rect(Rect2i(r.position.x + k * bw + int(3 * s), r.position.y + r.size.y / 2 + int(3 * s), bw - int(6 * s), r.size.y / 2 - int(7 * s)), BLDG_COL)
	return img


## Pencil sketch on white paper: filled blocks, a few outline-only buildings, a
## blue river and a green park in colored pencil, light paper noise.
static func make_sketch_image(px: int = 480, colored: bool = true) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(Color(0.97, 0.96, 0.93))
	var rng := Rng.new(11)
	var s := px / 480.0
	var ink := Color(0.18, 0.18, 0.2)
	for row in 5:
		for col in 6:
			var x := int((30 + col * 72) * s)
			var y := int((40 + row * 84) * s)
			var w := int(rng.range_f(40, 58) * s)
			var h := int(rng.range_f(44, 62) * s)
			if row == 2 and col == 3:
				continue
			if (row + col) % 5 == 1:
				var t := maxi(2, int(3 * s))
				img.fill_rect(Rect2i(x, y, w, t), ink)
				img.fill_rect(Rect2i(x, y + h - t, w, t), ink)
				img.fill_rect(Rect2i(x, y, t, h), ink)
				img.fill_rect(Rect2i(x + w - t, y, t, h), ink)
			else:
				img.fill_rect(Rect2i(x, y, w, h), ink)
	if not colored:
		return img
	# colored pencil park and river
	img.fill_rect(Rect2i(int(246 * s), int(208 * s), int(56 * s), int(60 * s)), Color(0.35, 0.65, 0.3))
	for x in px:
		var yc := int((455 + sin(x * 0.02) * 6) * s)
		img.fill_rect(Rect2i(x, yc - int(7 * s), 1, int(14 * s)), Color(0.3, 0.45, 0.85))
	for i in px * px / 40:
		var x := rng.range_i(0, px - 1)
		var y := rng.range_i(0, px - 1)
		var c := img.get_pixel(x, y)
		img.set_pixel(x, y, c.darkened(rng.range_f(0.0, 0.12)))
	return img


## Satellite-like: sandy ground, gray roads, varied roofs, tree blobs, a canal.
static func make_photo_image(px: int = 480) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(Color(0.78, 0.68, 0.5))
	var rng := Rng.new(23)
	var s := px / 480.0
	var lines := [60, 170, 290, 400]
	for c in lines:
		var w := int(12 * s)
		img.fill_rect(Rect2i(int(c * s) - w / 2, 0, w, px), Color(0.72, 0.72, 0.7))
		img.fill_rect(Rect2i(0, int(c * s) - w / 2, px, w), Color(0.72, 0.72, 0.7))
	for i in 140:
		var x := rng.range_i(0, px - 30)
		var y := rng.range_i(0, px - 30)
		var r := Rect2i(x, y, int(rng.range_f(10, 26) * s), int(rng.range_f(10, 26) * s))
		var v := rng.range_f(0.3, 0.55)
		img.fill_rect(r, Color(v, v * 0.98, v * 0.95))
	for i in 60:
		var c := Vector2(rng.range_i(0, px - 1), rng.range_i(0, px - 1))
		var rad := rng.range_f(3, 8) * s
		for y in range(int(c.y - rad), int(c.y + rad)):
			for x in range(int(c.x - rad), int(c.x + rad)):
				if x >= 0 and y >= 0 and x < px and y < px and Vector2(x, y).distance_to(c) < rad:
					img.set_pixel(x, y, Color(0.28, 0.45, 0.2))
	img.fill_rect(Rect2i(0, int(225 * s), px, int(14 * s)), Color(0.2, 0.35, 0.55))
	return img


func _class_count(m: MapDef, t: int) -> int:
	var n := 0
	for v in m.terrain:
		if v == t:
			n += 1
	return n


func _check_playable(m: MapDef, label: String) -> void:
	eq(m.spawns.size(), 2, label + " spawns")
	check(m.objectives.size() >= 3, "%s objectives >= 3: %d" % [label, m.objectives.size()])
	if m.spawns.size() < 2:
		return
	var nav := NavGrid.new(m)
	var s0 := m.team_spawn(0).get_center()
	var s1 := m.team_spawn(1).get_center()
	for k in [Defs.MOVE_FOOT, Defs.MOVE_WHEELED]:
		var a := nav.nearest_open_point(k, s0)
		var b := nav.nearest_open_point(k, s1)
		var path := nav.find_path(k, a, b)
		check(path.size() > 0 and path[path.size() - 1].distance_to(b) < 4.0, "%s spawn-to-spawn path for class %d" % [label, k])
	for o in m.objectives:
		var a := nav.nearest_open_point(Defs.MOVE_FOOT, s0)
		var path := nav.find_path(Defs.MOVE_FOOT, a, o["p"])
		check(path.size() > 0 and path[path.size() - 1].distance_to(o["p"]) < 10.0, "%s objective %s reachable on foot" % [label, o["id"]])


func test_plan_legend_classification() -> void:
	var img := Image.create(8, 2, false, Image.FORMAT_RGB8)
	var cols := [ROAD_COL, Color.WHITE, BLDG_COL, Color(0.45, 0.3, 0.15), PARK_COL, WATER_COL, OPEN_COL, Color(0.9, 0.5, 0.4)]
	var want := [ImageImporter.C_ROAD, ImageImporter.C_ROAD, ImageImporter.C_BUILDING, ImageImporter.C_BUILDING,
		ImageImporter.C_VEG, ImageImporter.C_WATER, ImageImporter.C_OPEN, ImageImporter.C_OPEN]
	for i in cols.size():
		img.set_pixel(i, 0, cols[i])
		img.set_pixel(i, 1, cols[i])
	var px := PackedByteArray()
	px.resize(16)
	ImageImporter._classify_plan(img.get_data(), px, ImageImporter.default_params())
	for i in cols.size():
		eq(px[i], want[i], "legend color %d" % i)


func test_plan_import() -> void:
	var img := make_plan_image()
	var t0 := Time.get_ticks_msec()
	var m := ImageImporter.analyze(img, {"mode": ImageImporter.MODE_PLAN, "size": 240, "seed": 3})
	var ms := Time.get_ticks_msec() - t0
	var roads := _class_count(m, MapDef.T_ROAD)
	var water := _class_count(m, MapDef.T_WATER)
	var grass := _class_count(m, MapDef.T_GRASS) + _class_count(m, MapDef.T_FIELD)
	print("    plan: %d buildings, %d road segs, %d props, %d walls, road %d, water %d, green %d cells; %d ms" % [
		m.buildings.size(), m.roads.size(), m.props.size(), m.walls.size(), roads, water, grass, ms])
	eq(m.width, 240, "map size")
	check(m.buildings.size() >= 40 and m.buildings.size() <= 400, "building count in range: %d" % m.buildings.size())
	check(roads > 240 * 240 * 0.05, "road cells present: %d" % roads)
	check(water > 60, "water present: %d" % water)
	check(grass > 200, "park present: %d" % grass)
	check(m.roads.size() >= 8, "road segments extracted: %d" % m.roads.size())
	var styles := {}
	for b in m.buildings:
		styles[b["style"]] = true
		check(b["floors"] >= 1 and b["floors"] <= 12, "floors in range")
	check(styles.size() >= 3, "style variety: %s" % str(styles.keys()))
	_check_playable(m, "plan")


func test_plan_deterministic_and_lot_size() -> void:
	var img := make_plan_image()
	var a := ImageImporter.analyze(img, {"size": 160, "seed": 9, "max_lot": 20.0})
	var b := ImageImporter.analyze(img, {"size": 160, "seed": 9, "max_lot": 20.0})
	eq(a.buildings.size(), b.buildings.size(), "same building count")
	eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "identical map for identical params")
	var oversized := 0
	for bl in a.buildings:
		var sz: Vector2 = bl["size"]
		if bl["style"] != MapDef.S_INDUSTRIAL and bl["style"] != MapDef.S_MOSQUE and maxf(sz.x, sz.y) > 20.0 + MapDef.CELL:
			oversized += 1
	eq(oversized, 0, "lots respect max lot size")
	var c := ImageImporter.analyze(img, {"size": 160, "seed": 9, "max_lot": 40.0})
	check(c.buildings.size() < a.buildings.size(), "bigger lots -> fewer buildings (%d vs %d)" % [c.buildings.size(), a.buildings.size()])


func test_sketch_import() -> void:
	var img := make_sketch_image()
	var m := ImageImporter.analyze(img, {"mode": ImageImporter.MODE_SKETCH, "size": 240, "seed": 4})
	print("    sketch: %d buildings, %d road segs, %d props, water %d, road %d" % [m.buildings.size(), m.roads.size(),
		m.props.size(), _class_count(m, MapDef.T_WATER), _class_count(m, MapDef.T_ROAD)])
	check(m.buildings.size() >= 20, "sketch buildings: %d" % m.buildings.size())
	check(_class_count(m, MapDef.T_WATER) > 100, "colored-pencil river becomes water")
	check(_class_count(m, MapDef.T_ROAD) > 500, "gaps between blocks become streets")
	# outline-only building (row 0, col 1) is filled into a building
	var outline_center := Vector2((30 + 72 + 25), (40 + 28)) * (480.0 / 480.0)
	var hit := false
	for b in m.buildings:
		if Rect2(b["c"] - b["size"] * 0.5, b["size"]).grow(2.0).has_point(outline_center):
			hit = true
	check(hit, "outlined building filled")
	_check_playable(m, "sketch")
	# inverted sketch (light marks on dark paper) gives the same layout with "invert"
	var gray := make_sketch_image(480, false)
	var inv := gray.duplicate() as Image
	var data := inv.get_data()
	for i in data.size():
		data[i] = 255 - data[i]
	inv.set_data(inv.get_width(), inv.get_height(), false, inv.get_format(), data)
	var opts := {"mode": ImageImporter.MODE_SKETCH, "size": 240, "seed": 4, "auto_zones": false, "props": false, "war_damage": 0.0}
	var mg := ImageImporter.analyze(gray, opts)
	opts["invert"] = true
	var mi := ImageImporter.analyze(inv, opts)
	eq(mi.buildings.size(), mg.buildings.size(), "invert option")


func test_photo_import() -> void:
	var m := ImageImporter.analyze(make_photo_image(), {"mode": ImageImporter.MODE_PHOTO, "size": 160, "seed": 2})
	print("    photo: %d buildings, %d road segs, water %d" % [m.buildings.size(), m.roads.size(), _class_count(m, MapDef.T_WATER)])
	check(m.buildings.size() >= 15, "photo buildings: %d" % m.buildings.size())
	check(_class_count(m, MapDef.T_WATER) > 50, "photo canal")
	_check_playable(m, "photo")


func test_non_square_letterbox() -> void:
	var img := Image.create(400, 200, false, Image.FORMAT_RGB8)
	img.fill(OPEN_COL)
	img.fill_rect(Rect2i(0, 95, 400, 10), ROAD_COL)
	var cls := ImageImporter.classify(img, {"size": 100})
	eq(cls.size(), 100 * 100, "square grid")
	eq(cls[10 * 100 + 50], ImageImporter.C_OPEN, "padding is open ground")
	eq(cls[50 * 100 + 50], ImageImporter.C_ROAD, "road centered vertically")


func test_connectivity_carve() -> void:
	# a solid wall of buildings splits the map: make_playable must carve through
	var m := MapDef.new(120, 120)
	for i in 12:
		m.buildings.append({"id": i + 1, "c": Vector2(120, 10 + i * 20), "size": Vector2(16, 20.5), "rot": 0.0,
			"floors": 3, "style": MapDef.S_APARTMENT, "color": 0, "seed": i})
	var rep := ImageImporter.make_playable(m, {"seed": 1, "war_damage": 0.0})
	check(int(rep["carved"]) >= 1, "carved a street")
	_check_playable(m, "carve")

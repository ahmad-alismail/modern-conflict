extends SceneTree
## Writes procedural test images for the image importer to tools/test_images/
## and (with --out=<dir>) a debug render of each imported map.
##   godot --headless --path . -s res://tools/preview_editor_images.gd -- --out=C:/tmp

const TESTS := "res://tests/test_image_importer.gd"
const STYLE_COLORS := [Color(0.85, 0.75, 0.55), Color(0.75, 0.75, 0.8), Color(0.9, 0.6, 0.4), Color(0.95, 0.9, 0.8),
	Color(0.4, 0.9, 0.85), Color(0.6, 0.55, 0.5), Color(0.6, 0.6, 0.6), Color(0.5, 0.65, 0.95)]


func _initialize() -> void:
	var out_dir := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).substr(6)
	var dir := ProjectSettings.globalize_path("res://tools/test_images")
	DirAccess.make_dir_recursive_absolute(dir)
	var T: GDScript = load(TESTS)
	var images := {
		"plan_grid.png": [T.make_plan_image(480), ImageImporter.MODE_PLAN],
		"sketch.png": [T.make_sketch_image(480), ImageImporter.MODE_SKETCH],
		"satellite.png": [T.make_photo_image(480), ImageImporter.MODE_PHOTO],
		"old_town_plan.png": [make_town_plan(), ImageImporter.MODE_PLAN],
	}
	for file: String in images:
		var img: Image = images[file][0]
		img.save_png(dir + "/" + file)
		print("wrote ", dir + "/" + file)
		if out_dir == "":
			continue
		var t0 := Time.get_ticks_msec()
		var m := ImageImporter.analyze(img, {"mode": images[file][1], "size": 240, "seed": 7})
		print("  %s: %d buildings, %d roads, %d props, %d objectives, %d ms" % [file, m.buildings.size(), m.roads.size(),
			m.props.size(), m.objectives.size(), Time.get_ticks_msec() - t0])
		debug_render(m).save_png(out_dir + "/dbg_" + file)
	quit()


## A non-square color-coded plan of a riverside town: avenues, a diagonal
## boulevard, street grid with jittered blocks, dense old quarter (brown),
## courtyard blocks, industrial halls, villas in gardens, park, fields, river
## with two bridges.
static func make_town_plan() -> Image:
	var W := 960
	var H := 720
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var open := Color(0.88, 0.83, 0.68)
	var road := Color(0.62, 0.62, 0.62)
	var avenue := Color(0.97, 0.97, 0.97)
	var dark := Color(0.16, 0.16, 0.17)
	var brown := Color(0.42, 0.28, 0.16)
	var green := Color(0.36, 0.62, 0.28)
	var field := Color(0.55, 0.7, 0.3)
	var water := Color(0.22, 0.42, 0.78)
	img.fill(open)
	var rng := Rng.new(42)
	# fields along the west edge
	img.fill_rect(Rect2i(0, 0, 90, H), field)
	# street grid
	var xs := [90, 200, 300, 410, 520, 640, 760, 870]
	var ys := [60, 170, 280, 400, 520, 630]
	for x in xs:
		img.fill_rect(Rect2i(x - 5, 0, 10, H), road)
	for y in ys:
		img.fill_rect(Rect2i(0, y - 5, W, 10), road)
	# blocks
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var r := Rect2i(xs[i] + 9, ys[j] + 9, xs[i + 1] - xs[i] - 18, ys[j + 1] - ys[j] - 18)
			var c := r.get_center()
			if i == 0:
				# villas in gardens
				img.fill_rect(r, green)
				for k in 2:
					var hr := Rect2i(r.position.x + 12 + k * 46, r.position.y + rng.range_i(10, 40), rng.range_i(16, 22), rng.range_i(14, 20))
					img.fill_rect(hr, dark)
			elif i == 3 and j == 2:
				img.fill_rect(r, green)   # park
			elif i >= 5 and j >= 3:
				# industrial halls on dirt
				img.fill_rect(Rect2i(r.position.x + 6, r.position.y + 8, r.size.x - 20, r.size.y / 2 - 12), dark)
				img.fill_rect(Rect2i(r.position.x + 14, r.position.y + r.size.y / 2 + 4, r.size.x / 2, r.size.y / 2 - 12), dark)
			elif i >= 4 and j <= 1:
				# dense old quarter: small brown houses with narrow lanes
				var yy := r.position.y
				while yy < r.end.y - 8:
					var hh := rng.range_i(9, 15)
					var xx := r.position.x
					while xx < r.end.x - 8:
						var ww := rng.range_i(9, 16)
						img.fill_rect(Rect2i(xx, yy, mini(ww, r.end.x - xx), mini(hh, r.end.y - yy)), brown)
						xx += ww + (3 if rng.chance(0.3) else 1)
					yy += hh + 3
			elif (i + j) % 3 == 0:
				# courtyard perimeter block
				img.fill_rect(r, dark)
				img.fill_rect(r.grow(-22), open)
			else:
				img.fill_rect(r, dark)
				if rng.chance(0.5):
					img.fill_rect(Rect2i(c.x - 2, r.position.y, 4, r.size.y), open)
	# main avenue and diagonal boulevard (white)
	img.fill_rect(Rect2i(0, 395, W, 20), avenue)
	for t in 1200:
		var p := Vector2(300, 720).lerp(Vector2(900, 60), t / 1200.0)
		img.fill_rect(Rect2i(int(p.x) - 9, int(p.y) - 9, 18, 18), avenue)
	# river with two bridges
	for x in W:
		var yc := 470.0 + sin(x * 0.006) * 40.0 + x * 0.05
		img.fill_rect(Rect2i(x, int(yc) - 16, 1, 32), water)
	for bx in [300, 640]:
		img.fill_rect(Rect2i(bx - 5, 380, 10, 160), road)
	img.fill_rect(Rect2i(0, 395, W, 20), avenue)
	return img


## Plan render with styles, road segments, spawns and objectives (debug only).
static func debug_render(m: MapDef) -> Image:
	var s := 3
	var img := Image.create(m.width * s, m.height * s, false, Image.FORMAT_RGBA8)
	for y in m.height:
		for x in m.width:
			var c := Color(0.45, 0.4, 0.32)
			match m.terrain[y * m.width + x]:
				MapDef.T_ROAD: c = Color(0.2, 0.2, 0.21)
				MapDef.T_PAVED: c = Color(0.4, 0.38, 0.35)
				MapDef.T_GRASS: c = Color(0.25, 0.38, 0.17)
				MapDef.T_FIELD: c = Color(0.42, 0.45, 0.22)
				MapDef.T_RUBBLE: c = Color(0.35, 0.28, 0.25)
				MapDef.T_DIRT: c = Color(0.4, 0.34, 0.26)
				MapDef.T_WATER: c = Color(0.2, 0.32, 0.5)
			img.fill_rect(Rect2i(x * s, y * s, s, s), c)
	var k := float(s) / MapDef.CELL
	for b in m.buildings:
		var r := Rect2(b["c"] - b["size"] * 0.5, b["size"])
		var ri := Rect2i(int(r.position.x * k), int(r.position.y * k), maxi(1, int(r.size.x * k)), maxi(1, int(r.size.y * k)))
		img.fill_rect(ri, STYLE_COLORS[b["style"]].darkened(0.3 - b["floors"] * 0.04))
	for w in m.walls:
		_line(img, w["a"] * k, w["b"] * k, Color(0.9, 0.85, 0.7))
	for r in m.roads:
		_line(img, r["a"] * k, r["b"] * k, [Color(1, 0.9, 0.2), Color(1, 1, 1), Color(0.6, 0.9, 1)][r["kind"]])
	for p in m.props:
		var q: Vector2 = p["p"] * k
		var col := Color(0.2, 0.8, 0.2) if p["kind"] in ["tree", "palm", "bush"] else Color(1, 0.3, 0.8)
		img.fill_rect(Rect2i(int(q.x), int(q.y), 2, 2), col)
	for sp in m.spawns:
		var r: Rect2 = sp["rect"]
		var col := Color(0.3, 0.6, 1) if sp["team"] == 0 else Color(1, 0.4, 0.3)
		var a := r.position * k
		var e := r.end * k
		_line(img, a, Vector2(e.x, a.y), col)
		_line(img, Vector2(e.x, a.y), e, col)
		_line(img, e, Vector2(a.x, e.y), col)
		_line(img, Vector2(a.x, e.y), a, col)
	for o in m.objectives:
		var c: Vector2 = o["p"] * k
		for t in 48:
			var ang := TAU * t / 48.0
			var q := c + Vector2(cos(ang), sin(ang)) * float(o["r"]) * k
			img.fill_rect(Rect2i(int(q.x) - 1, int(q.y) - 1, 3, 3), Color(1, 0.9, 0.2))
	return img


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := maxi(1, int(a.distance_to(b)))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
			img.set_pixel(int(p.x), int(p.y), col)

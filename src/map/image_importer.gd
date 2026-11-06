extends RefCounted
## Image-to-map importer: interprets a color-coded plan, a drawing or a map
## screenshot as a city layout and turns it into a playable, editable MapDef.
##
## Pipeline: prepare (letterbox into a square, downscale) -> classify pixels
## (pooled SSxSS into cells) -> terrain -> buildings (connected components split
## into lots, styled by footprint and context) -> road segments (for markings)
## -> vegetation -> war damage -> make_playable (spawns, connectivity, objectives,
## street props). make_playable / decorate_streets also work on hand-made maps.
class_name ImageImporter

const MODE_PLAN := 0
const MODE_SKETCH := 1
const MODE_PHOTO := 2
const MODE_NAMES := ["Color-coded plan", "Drawing / sketch", "Map screenshot / satellite"]

## Cell classes of the analysis grid.
const C_OPEN := 0
const C_ROAD := 1
const C_BUILDING := 2
const C_VEG := 3
const C_WATER := 4

const SS := 2                 # classification pixels per cell edge
const SPAWN_DEPTH := 34.0     # m, like CityGenerator
const SPAWN_INSET := 6.0
const OBJ_RADIUS := 16.0
const INV255 := 1.0 / 255.0


static func default_params() -> Dictionary:
	return {
		"mode": MODE_PLAN,
		"size": 240,              # target map size in cells (maps are square)
		"seed": 1,
		"name": "Imported City",
		# classification thresholds, 0..1
		"building_dark": 0.36,    # gray darker than this is a building (plan, photo)
		"road_sat": 0.2,          # max saturation of road / roof grays
		"road_light": 0.62,       # photo: min brightness of a road
		"veg": 0.5,               # vegetation sensitivity
		"water": 0.5,             # water sensitivity
		"ink": 0.5,               # sketch: darkness threshold of a mark
		"invert": false,          # sketch: light marks on dark paper
		"white_open": false,      # plan: pure white is open ground instead of road
		"fill_outlines": true,    # sketch: closed outlines become buildings
		"gap_streets": true,      # sketch: narrow gaps between marks become streets
		"smooth": -1,             # majority-filter passes, -1 = mode default
		# layout
		"min_building": 6.0,      # m, smallest building side kept
		"max_lot": 26.0,          # m, larger blocks are subdivided into lots
		"floors_min": 1,
		"floors_max": 6,
		"war_damage": 0.2,
		"auto_zones": true,       # spawns, objectives and connectivity fix
		"props": true,            # street furniture, parked and wrecked cars
	}


static func _with_defaults(params: Dictionary) -> Dictionary:
	var p := default_params()
	p.merge(params, true)
	return p


## Full analysis: image -> playable MapDef.
static func analyze(img: Image, params: Dictionary = {}) -> MapDef:
	var p := _with_defaults(params)
	return build_map(classify(img, p), p)


# ================================================================ classify ====

## Letterbox-fit and downscale to (size * SS) on the long side, RGB8. Idempotent,
## so callers can cache the result and pass it back to classify / analyze.
static func prepare(img: Image, cells: int) -> Image:
	var target := cells * SS
	var src: Image = img.duplicate()
	if src.is_compressed():
		src.decompress()
	if src.get_format() == Image.FORMAT_RGB8 and maxi(src.get_width(), src.get_height()) == target:
		return src
	if src.detect_alpha() != Image.ALPHA_NONE:
		src.convert(Image.FORMAT_RGBA8)
		var bg := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
		bg.fill(Color.WHITE)
		bg.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
		src = bg
	src.convert(Image.FORMAT_RGB8)
	while maxi(src.get_width(), src.get_height()) >= target * 2:
		src.shrink_x2()
	var f := float(target) / maxi(src.get_width(), src.get_height())
	src.resize(maxi(1, roundi(src.get_width() * f)), maxi(1, roundi(src.get_height() * f)), Image.INTERPOLATE_BILINEAR)
	return src


## Per-cell class grid (size x size, C_* values).
static func classify(img: Image, params: Dictionary) -> PackedByteArray:
	var p := _with_defaults(params)
	var n: int = p["size"]
	var src := prepare(img, n)
	var iw := src.get_width()
	var ih := src.get_height()
	var data := src.get_data()
	var px := PackedByteArray()
	px.resize(iw * ih)
	var mode: int = p["mode"]
	match mode:
		MODE_SKETCH: _classify_sketch(data, px, p)
		MODE_PHOTO: _classify_photo(data, px, p)
		_: _classify_plan(data, px, p)
	var cls := _pool(px, iw, ih, n)
	var passes: int = p["smooth"]
	if passes < 0:
		passes = [0, 1, 2][mode]
	for i in passes:
		cls = _majority(cls, n)
	if mode == MODE_SKETCH:
		if p["fill_outlines"]:
			_fill_enclosed(cls, n, int(pow(float(p["max_lot"]) * 3.0 / MapDef.CELL, 2.0)))
		if p["gap_streets"]:
			_gap_streets(cls, n)
	_drop_small(cls, n, C_ROAD, 8)
	_drop_small(cls, n, C_WATER, 6)
	return cls


static func _hue(r: float, g: float, b: float, mx: float, d: float) -> float:
	if d < 0.0001:
		return 0.0
	if mx == r:
		return fposmod((g - b) / d, 6.0) / 6.0
	if mx == g:
		return ((b - r) / d + 2.0) / 6.0
	return ((r - g) / d + 4.0) / 6.0


## Legend: gray/white = road, dark gray/black/brown = building, green = park or
## field, blue = water, everything else = open ground.
static func _classify_plan(data: PackedByteArray, out: PackedByteArray, p: Dictionary) -> void:
	var bd: float = p["building_dark"]
	var rs: float = p["road_sat"]
	var ws := lerpf(0.55, 0.12, float(p["water"]))
	var vs := lerpf(0.55, 0.1, float(p["veg"]))
	var white_open: bool = p["white_open"]
	var sat_min := minf(minf(ws, vs), 0.3)
	for i in out.size():
		var j := i * 3
		var r := data[j] * INV255
		var g := data[j + 1] * INV255
		var b := data[j + 2] * INV255
		var mx := maxf(r, maxf(g, b))
		var d := mx - minf(r, minf(g, b))
		var s := 0.0 if mx < 0.0001 else d / mx
		var h := _hue(r, g, b, mx, d) if s > sat_min else 0.0
		var c := C_OPEN
		if s > ws and mx > 0.15 and h >= 0.5 and h <= 0.75:
			c = C_WATER
		elif s > vs and mx > 0.12 and h >= 0.16 and h < 0.5:
			c = C_VEG
		elif mx < bd:
			c = C_BUILDING
		elif s < rs:
			c = C_OPEN if white_open and mx > 0.93 else C_ROAD
		elif h < 0.13 and s > 0.3 and mx < 0.62:
			c = C_BUILDING
		out[i] = c


## Dark marks = buildings, light = open; colored ink: blue = water, green = vegetation.
static func _classify_sketch(data: PackedByteArray, out: PackedByteArray, p: Dictionary) -> void:
	var ink: float = p["ink"]
	var invert: bool = p["invert"]
	var ws := lerpf(0.6, 0.2, float(p["water"]))
	var vs := lerpf(0.6, 0.2, float(p["veg"]))
	var sat_min := minf(ws, vs)
	for i in out.size():
		var j := i * 3
		var r := data[j] * INV255
		var g := data[j + 1] * INV255
		var b := data[j + 2] * INV255
		var mx := maxf(r, maxf(g, b))
		var d := mx - minf(r, minf(g, b))
		var s := 0.0 if mx < 0.0001 else d / mx
		var h := _hue(r, g, b, mx, d) if s > sat_min else 0.0
		var lum := 0.299 * r + 0.587 * g + 0.114 * b
		if invert:
			lum = 1.0 - lum
		var c := C_OPEN
		if s > ws and mx > 0.25 and h >= 0.5 and h <= 0.75:
			c = C_WATER
		elif s > vs and mx > 0.2 and h >= 0.16 and h < 0.5:
			c = C_VEG
		elif lum < ink:
			c = C_BUILDING
		out[i] = c


## Heuristics: low-saturation light = road, green = vegetation, blue = water,
## mid/dark grays = buildings, warm light colors = open ground.
static func _classify_photo(data: PackedByteArray, out: PackedByteArray, p: Dictionary) -> void:
	var bd: float = p["building_dark"]
	var rs: float = p["road_sat"]
	var rl: float = p["road_light"]
	var ws := lerpf(0.45, 0.08, float(p["water"]))
	var vs := lerpf(0.45, 0.06, float(p["veg"]))
	var sat_min := minf(ws, vs)
	for i in out.size():
		var j := i * 3
		var r := data[j] * INV255
		var g := data[j + 1] * INV255
		var b := data[j + 2] * INV255
		var mx := maxf(r, maxf(g, b))
		var d := mx - minf(r, minf(g, b))
		var s := 0.0 if mx < 0.0001 else d / mx
		var h := _hue(r, g, b, mx, d) if s > sat_min else 0.0
		var c := C_OPEN
		if s > ws and h >= 0.48 and h <= 0.72 and b > r + 0.03:
			c = C_WATER
		elif s > vs and h >= 0.15 and h < 0.48 and g >= r:
			c = C_VEG
		elif s < rs and mx >= rl:
			c = C_ROAD
		elif mx < bd or (s < rs * 1.6 and mx < rl):
			c = C_BUILDING
		out[i] = c


## SSxSS majority pooling into the square cell grid (letterbox padding = open).
## Ties prefer building > road > water > vegetation > open so thin features survive.
static func _pool(px: PackedByteArray, iw: int, ih: int, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n * n)
	var g := n * SS
	var ox := (g - iw) / 2
	var oy := (g - ih) / 2
	var cnt := PackedInt32Array()
	cnt.resize(5)
	const PRIORITY := [C_BUILDING, C_ROAD, C_WATER, C_VEG, C_OPEN]
	for cy in n:
		var y0 := cy * SS - oy
		for cx in n:
			var x0 := cx * SS - ox
			if SS == 2 and x0 >= 0 and y0 >= 0 and x0 + 1 < iw and y0 + 1 < ih:
				var j := y0 * iw + x0
				var a := px[j]
				if a == px[j + 1] and a == px[j + iw] and a == px[j + iw + 1]:
					out[cy * n + cx] = a
					continue
			cnt.fill(0)
			var any := false
			for sy in SS:
				var y := cy * SS + sy - oy
				if y < 0 or y >= ih:
					continue
				for sx in SS:
					var x := cx * SS + sx - ox
					if x < 0 or x >= iw:
						continue
					cnt[px[y * iw + x]] += 1
					any = true
			if not any:
				continue
			var best := C_OPEN
			var bc := -1
			for c: int in PRIORITY:
				if cnt[c] > bc:
					bc = cnt[c]
					best = c
			out[cy * n + cx] = best
	return out


static func _majority(cls: PackedByteArray, n: int) -> PackedByteArray:
	var out := cls.duplicate()
	var cnt := PackedInt32Array()
	cnt.resize(5)
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			cnt.fill(0)
			for dy in range(-1, 2):
				var row := (y + dy) * n + x
				cnt[cls[row - 1]] += 1
				cnt[cls[row]] += 1
				cnt[cls[row + 1]] += 1
			var cur := cls[y * n + x]
			var best := cur
			for c in 5:
				if cnt[c] > cnt[best]:
					best = c
			if cnt[best] >= 5:
				out[y * n + x] = best
	return out


## Connected components (4-neighbour) of cells equal to `cid`.
## Returns {labels: PackedInt32Array (-1 = other), comps: [{first, count, x0, y0, x1, y1}]}.
static func _components(cls: PackedByteArray, n: int, cid: int, rows: int = -1) -> Dictionary:
	var hgt := n if rows < 0 else rows
	var labels := PackedInt32Array()
	labels.resize(n * hgt)
	labels.fill(-1)
	var comps := []
	var stack := PackedInt32Array()
	for i in n * hgt:
		if cls[i] != cid or labels[i] != -1:
			continue
		var id := comps.size()
		labels[i] = id
		stack.resize(0)
		stack.append(i)
		var count := 0
		var x0 := n
		var y0 := n
		var x1 := -1
		var y1 := -1
		while stack.size() > 0:
			var j := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			var x := j % n
			var y := j / n
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
			if x > 0 and cls[j - 1] == cid and labels[j - 1] == -1:
				labels[j - 1] = id
				stack.append(j - 1)
			if x < n - 1 and cls[j + 1] == cid and labels[j + 1] == -1:
				labels[j + 1] = id
				stack.append(j + 1)
			if y > 0 and cls[j - n] == cid and labels[j - n] == -1:
				labels[j - n] = id
				stack.append(j - n)
			if y < hgt - 1 and cls[j + n] == cid and labels[j + n] == -1:
				labels[j + n] = id
				stack.append(j + n)
		comps.append({"first": i, "count": count, "x0": x0, "y0": y0, "x1": x1, "y1": y1})
	return {"labels": labels, "comps": comps}


static func _drop_small(cls: PackedByteArray, n: int, cid: int, min_cells: int) -> void:
	var cc := _components(cls, n, cid)
	var labels: PackedInt32Array = cc["labels"]
	var comps: Array = cc["comps"]
	for i in n * n:
		var l := labels[i]
		if l >= 0 and int(comps[l]["count"]) < min_cells:
			cls[i] = C_OPEN


## Sketch: open regions fully enclosed by marks (outlined buildings) become buildings.
static func _fill_enclosed(cls: PackedByteArray, n: int, max_cells: int) -> void:
	var cc := _components(cls, n, C_OPEN)
	var labels: PackedInt32Array = cc["labels"]
	var comps: Array = cc["comps"]
	var fill := PackedByteArray()
	fill.resize(comps.size())
	for i in comps.size():
		var c: Dictionary = comps[i]
		var touches_edge: bool = c["x0"] == 0 or c["y0"] == 0 or c["x1"] == n - 1 or c["y1"] == n - 1
		fill[i] = 1 if not touches_edge and int(c["count"]) <= max_cells else 0
	for i in n * n:
		var l := labels[i]
		if l >= 0 and fill[l] == 1:
			cls[i] = C_BUILDING


## Sketch: streets along the middle of the open gaps between marks (ridges of the
## distance-to-building field), 5 cells wide; wide open areas stay open.
static func _gap_streets(cls: PackedByteArray, n: int) -> void:
	var blocked := PackedByteArray()
	blocked.resize(n * n)
	for i in n * n:
		blocked[i] = 1 if cls[i] == C_BUILDING else 0
	var d := _open_distance(blocked, n, n)
	var mark := PackedByteArray()
	mark.resize(n * n)
	for y in range(2, n - 2):
		for x in range(2, n - 2):
			var i := y * n + x
			var v := d[i]
			if cls[i] != C_OPEN or v < 2 or v > 12:
				continue
			var l := d[i - 1]
			var r := d[i + 1]
			var u := d[i - n]
			var dn := d[i + n]
			var ridge_x := v >= l and v >= r and (v > l or v > r) and _mark_near(cls, n, x - v, y, true) and _mark_near(cls, n, x + v, y, true)
			var ridge_y := v >= u and v >= dn and (v > u or v > dn) and _mark_near(cls, n, x, y - v, false) and _mark_near(cls, n, x, y + v, false)
			if not (ridge_x or ridge_y):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var j := i + dy * n + dx
					if cls[j] == C_OPEN:
						mark[j] = 1
	# join street pieces across crossings: close short open gaps along rows / columns
	for pass_i in 2:
		var stride := 1 if pass_i == 0 else n
		var lstride := n if pass_i == 0 else 1
		for line in n:
			var base := line * lstride
			var last := -1
			for a in n:
				var idx := base + a * stride
				if mark[idx] == 1:
					if last >= 0 and a - last > 1 and a - last <= 13:
						var open_gap := true
						for t in range(last + 1, a):
							if cls[base + t * stride] != C_OPEN:
								open_gap = false
								break
						if open_gap:
							for t in range(last + 1, a):
								mark[base + t * stride] = 2
					last = a
				elif cls[idx] != C_OPEN:
					last = -1
	for i in n * n:
		if mark[i] != 0:
			cls[i] = C_ROAD


## A building cell at (x, y) or one step beside it (across the scan axis), or one
## step further out (plateau ridges).
static func _mark_near(cls: PackedByteArray, n: int, x: int, y: int, horizontal: bool) -> bool:
	for o in range(-1, 2):
		for e in range(-1, 2):
			var xx := x + (e if horizontal else o)
			var yy := y + (o if horizontal else e)
			if xx >= 0 and yy >= 0 and xx < n and yy < n and cls[yy * n + xx] == C_BUILDING:
				return true
	return false


# ================================================================ build map ===

## Turn a class grid into a MapDef (terrain, buildings, roads, vegetation, damage,
## and optionally spawns / objectives / connectivity / street props).
static func build_map(cls: PackedByteArray, params: Dictionary) -> MapDef:
	var p := _with_defaults(params)
	var n: int = p["size"]
	var seed_v: int = p["seed"]
	var m := MapDef.new(n, n)
	m.name = p["name"]
	m.map_seed = seed_v
	m.description = "Imported from an image (%s)." % MODE_NAMES[int(p["mode"])].to_lower()
	var war: float = p["war_damage"]
	var bsat := _sat(cls, n, C_BUILDING)
	var vsat := _sat(cls, n, C_VEG)
	_paint_terrain(m, cls, bsat, seed_v)
	_extract_buildings(m, cls, bsat, vsat, p)
	m.roads = road_segments(cls, n)
	_vegetation(m, cls, Rng.new(seed_v * 31 + 5), int(p["mode"]) == MODE_PHOTO)
	if p["auto_zones"] or p["props"]:
		make_playable(m, {"seed": seed_v, "war_damage": war, "zones": p["auto_zones"], "props": p["props"]})
	return m


## Summed-area table of cells equal to `cid`, (n+1)^2 entries.
static func _sat(cls: PackedByteArray, n: int, cid: int) -> PackedInt32Array:
	var s := PackedInt32Array()
	var w := n + 1
	s.resize(w * w)
	for y in n:
		var row := 0
		for x in n:
			if cls[y * n + x] == cid:
				row += 1
			s[(y + 1) * w + x + 1] = s[y * w + x + 1] + row
	return s


## Count of class cells in the inclusive cell rectangle (clamped).
static func _sat_count(s: PackedInt32Array, n: int, x0: int, y0: int, x1: int, y1: int) -> int:
	x0 = clampi(x0, 0, n - 1)
	y0 = clampi(y0, 0, n - 1)
	x1 = clampi(x1, 0, n - 1)
	y1 = clampi(y1, 0, n - 1)
	var w := n + 1
	return s[(y1 + 1) * w + x1 + 1] - s[y0 * w + x1 + 1] - s[(y1 + 1) * w + x0] + s[y0 * w + x0]


static func _sat_density(s: PackedInt32Array, n: int, cx: int, cy: int, r: int) -> float:
	var x0 := clampi(cx - r, 0, n - 1)
	var y0 := clampi(cy - r, 0, n - 1)
	var x1 := clampi(cx + r, 0, n - 1)
	var y1 := clampi(cy + r, 0, n - 1)
	return float(_sat_count(s, n, x0, y0, x1, y1)) / float((x1 - x0 + 1) * (y1 - y0 + 1))


static func _paint_terrain(m: MapDef, cls: PackedByteArray, bsat: PackedInt32Array, seed_v: int) -> void:
	var n := m.width
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.035
	# local road width (min of horizontal / vertical run) for sidewalk decisions
	var hrun := _runs(cls, n, C_ROAD, true)
	var vrun := _runs(cls, n, C_ROAD, false)
	var vc := _components(cls, n, C_VEG)
	var vlabels: PackedInt32Array = vc["labels"]
	var vcomps: Array = vc["comps"]
	var near_road := _dilate(cls, n, C_ROAD)
	for y in n:
		for x in n:
			var i := y * n + x
			var t := MapDef.T_SAND
			match cls[i]:
				C_ROAD:
					t = MapDef.T_ROAD
					if mini(hrun[i], vrun[i]) >= 4 and _has_neighbor(cls, n, x, y, C_BUILDING):
						t = MapDef.T_PAVED
				C_WATER:
					t = MapDef.T_WATER
				C_BUILDING:
					t = MapDef.T_PAVED
				C_VEG:
					var vcomp: Dictionary = vcomps[vlabels[i]]
					var big: bool = int(vcomp["count"]) > 900 or (int(vcomp["count"]) > 250 and (vcomp["x0"] == 0 or vcomp["y0"] == 0 or vcomp["x1"] == n - 1 or vcomp["y1"] == n - 1))
					t = MapDef.T_FIELD if big else MapDef.T_GRASS
				_:
					if near_road[i] != 0:
						t = MapDef.T_PAVED
					elif _sat_density(bsat, n, x, y, 3) > 0.45:
						t = MapDef.T_PAVED
					else:
						t = MapDef.T_DIRT if noise.get_noise_2d(x, y) > 0.15 else MapDef.T_SAND
			m.terrain[i] = t


## Length of the horizontal (or vertical) run of `cid` cells through each cell.
static func _runs(cls: PackedByteArray, n: int, cid: int, horizontal: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(n * n)
	var stride := 1 if horizontal else n
	var lstride := n if horizontal else 1
	for line in n:
		var base := line * lstride
		var a := 0
		while a < n:
			if cls[base + a * stride] != cid:
				a += 1
				continue
			var b := a
			while b + 1 < n and cls[base + (b + 1) * stride] == cid:
				b += 1
			for t in range(a, b + 1):
				out[base + t * stride] = b - a + 1
			a = b + 1
	return out


static func _has_neighbor(cls: PackedByteArray, n: int, x: int, y: int, cid: int) -> bool:
	return (x > 0 and cls[y * n + x - 1] == cid) or (x < n - 1 and cls[y * n + x + 1] == cid) \
		or (y > 0 and cls[(y - 1) * n + x] == cid) or (y < n - 1 and cls[(y + 1) * n + x] == cid)


## 1 where a cell of class `cid` lies in the 3x3 neighbourhood.
static func _dilate(cls: PackedByteArray, n: int, cid: int) -> PackedByteArray:
	var row := PackedByteArray()
	row.resize(n * n)
	for y in n:
		for x in n:
			var i := y * n + x
			if cls[i] == cid or (x > 0 and cls[i - 1] == cid) or (x < n - 1 and cls[i + 1] == cid):
				row[i] = 1
	var out := PackedByteArray()
	out.resize(n * n)
	for i in n * n:
		if row[i] != 0 or (i >= n and row[i - n] != 0) or (i < n * (n - 1) and row[i + n] != 0):
			out[i] = 1
	return out


# --------------------------------------------------------------- buildings ---

static func _extract_buildings(m: MapDef, cls: PackedByteArray, bsat: PackedInt32Array, vsat: PackedInt32Array, p: Dictionary) -> void:
	var n := m.width
	var cell := MapDef.CELL
	var min_c := maxi(2, int(ceil(float(p["min_building"]) / cell)))
	var max_c := maxi(min_c * 2, int(float(p["max_lot"]) / cell))
	var fmin: int = p["floors_min"]
	var fmax: int = maxi(fmin, int(p["floors_max"]))
	var war: float = p["war_damage"]
	var seed_v: int = p["seed"]
	var cc := _components(cls, n, C_BUILDING)
	var labels: PackedInt32Array = cc["labels"]
	var comps: Array = cc["comps"]
	var mosques := 0
	var max_mosques := maxi(1, n / 150)
	for ci in comps.size():
		var c: Dictionary = comps[ci]
		var count: int = c["count"]
		var x0: int = c["x0"]
		var y0: int = c["y0"]
		var x1: int = c["x1"]
		var y1: int = c["y1"]
		var w := x1 - x0 + 1
		var h := y1 - y0 + 1
		if count < min_c * min_c or mini(w, h) < min_c:
			continue
		var rng := Rng.new(seed_v * 7919 + int(c["first"]))
		var fill := float(count) / (w * h)
		var comp_m2 := count * cell * cell
		# surrounding density excluding the component itself
		var gx0 := x0 - 12
		var gy0 := y0 - 12
		var gx1 := x1 + 12
		var gy1 := y1 + 12
		var win := (clampi(gx1, 0, n - 1) - clampi(gx0, 0, n - 1) + 1) * (clampi(gy1, 0, n - 1) - clampi(gy0, 0, n - 1) + 1)
		var ring := float(_sat_count(bsat, n, gx0, gy0, gx1, gy1) - count) / maxf(1.0, win - w * h)
		var green := float(_sat_count(vsat, n, gx0 + 6, gy0 + 6, gx1 - 6, gy1 - 6)) / maxf(1.0, (w + 12) * (h + 12) - w * h)
		var bbox := Rect2(x0 * cell, y0 * cell, w * cell, h * cell)
		# landmark mosque on a big squarish block
		var aspect := float(maxi(w, h)) / mini(w, h)
		if mosques < max_mosques and aspect < 1.4 and mini(w, h) * cell >= 18.0 and maxi(w, h) * cell <= 46.0 and fill > 0.75 and rng.chance(0.3):
			mosques += 1
			var ms := Vector2(minf(bbox.size.x - 3.0, 30.0), minf(bbox.size.y - 3.0, 30.0))
			_add_building(m, Rect2(bbox.get_center() - ms * 0.5, ms), 3, MapDef.S_MOSQUE, rng, 0.0)
			continue
		# isolated small house with greenery around: walled villa
		if comp_m2 < 320.0 and maxi(w, h) * cell <= 20.0 and ring < 0.22 and green > 0.08:
			var tr := _trim_lot(cls, n, Rect2i(x0, y0, w, h), min_c)
			if tr.size.x == 0:
				continue
			var vr := Rect2(tr.position.x * cell, tr.position.y * cell, tr.size.x * cell, tr.size.y * cell).grow(-0.4)
			_add_building(m, vr, clampi(rng.range_i(1, 2), fmin, fmax), MapDef.S_VILLA, rng, war)
			_villa_compound(m, cls, n, bbox, rng)
			continue
		# industrial: big low-density blocks get large halls
		var industrial := comp_m2 > 1600.0 and fill > 0.6 and ring < 0.3
		var lots: Array = []
		_split_lots(labels, n, ci, x0, y0, x1, y1, max_c * (2 if industrial else 1), min_c, rng, lots, 0)
		for lot: Dictionary in lots:
			var lr := _trim_lot(cls, n, lot["r"], min_c)
			if lr.size.x == 0:
				continue
			var lot_m := Rect2(lr.position.x * cell, lr.position.y * cell, lr.size.x * cell, lr.size.y * cell)
			if lots.size() >= 6 and _is_interior(labels, n, ci, lr) and rng.chance(0.6):
				_courtyard(m, lot_m, rng)
				continue
			var area := lot_m.get_area()
			var lc := lr.get_center()
			var dens := _sat_density(bsat, n, lc.x, lc.y, 10)
			var style := MapDef.S_APARTMENT
			var floors := 4
			var gap := rng.range_f(0.3, 1.2)
			if industrial:
				style = MapDef.S_INDUSTRIAL
				floors = rng.range_i(1, 2)
				gap = rng.range_f(2.0, 4.0)
			elif area < 200.0 and dens > 0.45:
				style = MapDef.S_UNFINISHED if rng.chance(0.07) else MapDef.S_OLD
				floors = rng.range_i(1, 3)
				gap = rng.range_f(0.0, 0.3)
			elif area > 380.0:
				if fmax >= 8 and area > 480.0 and float(maxi(lr.size.x, lr.size.y)) / mini(lr.size.x, lr.size.y) < 1.6 and rng.chance(0.15):
					style = MapDef.S_TOWER
					floors = rng.range_i(8, 12)
				else:
					style = MapDef.S_UNFINISHED if rng.chance(0.1) else MapDef.S_APARTMENT
					floors = rng.range_i(4, 8)
			else:
				var roll := rng.next_float()
				if roll < 0.45:
					style = MapDef.S_SHOP
					floors = rng.range_i(2, 5)
				elif roll < 0.75:
					style = MapDef.S_APARTMENT
					floors = rng.range_i(3, 7)
				elif roll < 0.93:
					style = MapDef.S_OLD
					floors = rng.range_i(1, 3)
				else:
					style = MapDef.S_UNFINISHED
					floors = rng.range_i(2, 5)
			if style != MapDef.S_INDUSTRIAL:
				floors = clampi(floors, fmin, fmax)
			_add_building(m, lot_m.grow(-gap * 0.5), floors, style, rng, war)


## Recursive lot subdivision of one component inside the cell window [x0..x1]x[y0..y1].
## Splits the long axis at the line with the fewest component cells (separates
## L-shapes) near a jittered middle, until lots fit max_c and are well filled.
static func _split_lots(labels: PackedInt32Array, n: int, id: int, x0: int, y0: int, x1: int, y1: int,
		max_c: int, min_c: int, rng: Rng, out: Array, depth: int) -> void:
	var cnt := 0
	var tx0 := x1 + 1
	var ty0 := y1 + 1
	var tx1 := x0 - 1
	var ty1 := y0 - 1
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if labels[y * n + x] == id:
				cnt += 1
				tx0 = mini(tx0, x)
				ty0 = mini(ty0, y)
				tx1 = maxi(tx1, x)
				ty1 = maxi(ty1, y)
	if cnt == 0:
		return
	var w := tx1 - tx0 + 1
	var h := ty1 - ty0 + 1
	if mini(w, h) < min_c:
		return
	var fill := float(cnt) / (w * h)
	var long := maxi(w, h)
	var need := long > max_c or (fill < 0.72 and depth < 10)
	if need and long >= min_c * 2:
		var along_x := w >= h
		var start := tx0 if along_x else ty0
		var lo := start + maxi(min_c, int(long * 0.35))
		var hi := start + mini(long - min_c, int(long * 0.65))
		if lo > hi:
			lo = start + long / 2
			hi = lo
		var target := start + int(long * rng.range_f(0.42, 0.58))
		var best := lo
		var best_cnt := 1 << 30
		var best_d := 1 << 30
		for s in range(lo, hi + 1):
			var line_cnt := 0
			if along_x:
				for y in range(ty0, ty1 + 1):
					if labels[y * n + s] == id:
						line_cnt += 1
			else:
				for x in range(tx0, tx1 + 1):
					if labels[s * n + x] == id:
						line_cnt += 1
			var dd := absi(s - target)
			if line_cnt < best_cnt or (line_cnt == best_cnt and dd < best_d):
				best = s
				best_cnt = line_cnt
				best_d = dd
		if along_x:
			_split_lots(labels, n, id, tx0, ty0, best - 1, ty1, max_c, min_c, rng, out, depth + 1)
			_split_lots(labels, n, id, best, ty0, tx1, ty1, max_c, min_c, rng, out, depth + 1)
		else:
			_split_lots(labels, n, id, tx0, ty0, tx1, best - 1, max_c, min_c, rng, out, depth + 1)
			_split_lots(labels, n, id, tx0, best, tx1, ty1, max_c, min_c, rng, out, depth + 1)
		return
	if fill < 0.5:
		return
	out.append({"r": Rect2i(tx0, ty0, w, h), "fill": fill})


## Shrink a lot until its border holds no road or water cell (removing the edge
## with the most such cells first). Returns an empty rect if it gets too small.
static func _trim_lot(cls: PackedByteArray, n: int, r: Rect2i, min_c: int) -> Rect2i:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x - 1
	var y1 := r.end.y - 1
	for guard in 32:
		var bad := [0, 0, 0, 0]
		for x in range(x0, x1 + 1):
			bad[0] += 1 if _blocked_cls(cls[y0 * n + x]) else 0
			bad[1] += 1 if _blocked_cls(cls[y1 * n + x]) else 0
		for y in range(y0, y1 + 1):
			bad[2] += 1 if _blocked_cls(cls[y * n + x0]) else 0
			bad[3] += 1 if _blocked_cls(cls[y * n + x1]) else 0
		var worst := 0
		for k in range(1, 4):
			if bad[k] > bad[worst]:
				worst = k
		if bad[worst] == 0:
			break
		match worst:
			0: y0 += 1
			1: y1 -= 1
			2: x0 += 1
			_: x1 -= 1
		if x1 - x0 + 1 < min_c or y1 - y0 + 1 < min_c:
			return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


static func _blocked_cls(c: int) -> bool:
	return c == C_ROAD or c == C_WATER


## True if the lot is surrounded by cells of the same component on all four sides.
static func _is_interior(labels: PackedInt32Array, n: int, id: int, r: Rect2i) -> bool:
	if r.position.x < 1 or r.position.y < 1 or r.end.x >= n or r.end.y >= n:
		return false
	var sides := [0, 0, 0, 0]
	for x in range(r.position.x, r.end.x):
		sides[0] += 1 if labels[(r.position.y - 1) * n + x] == id else 0
		sides[1] += 1 if labels[r.end.y * n + x] == id else 0
	for y in range(r.position.y, r.end.y):
		sides[2] += 1 if labels[y * n + r.position.x - 1] == id else 0
		sides[3] += 1 if labels[y * n + r.end.x] == id else 0
	return sides[0] >= r.size.x * 0.8 and sides[1] >= r.size.x * 0.8 and sides[2] >= r.size.y * 0.8 and sides[3] >= r.size.y * 0.8


static func _courtyard(m: MapDef, r: Rect2, rng: Rng) -> void:
	m.fill_rect_terrain(r, MapDef.T_PAVED if rng.chance(0.6) else MapDef.T_DIRT)
	if r.size.x > 6.0 and r.size.y > 6.0:
		for k in rng.range_i(0, 2):
			_add_prop(m, rng.pick(["tree", "palm", "barrels", "crates"]), _rand_point(r.grow(-1.5), rng), rng.range_f(0, TAU))


static func _villa_compound(m: MapDef, cls: PackedByteArray, n: int, house: Rect2, rng: Rng) -> void:
	var yard := house.grow(rng.range_f(2.4, 4.0))
	# only where the yard lies on open ground or greenery
	var c0 := m.world_to_cell(yard.position)
	var c1 := m.world_to_cell(yard.end)
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			if not m.in_bounds(x, y):
				return
			var k := cls[y * n + x]
			if k == C_ROAD or k == C_WATER:
				return
	m.fill_rect_terrain(yard, MapDef.T_GRASS if rng.chance(0.6) else MapDef.T_DIRT)
	var gate := rng.range_i(0, 3)
	var c := [yard.position, Vector2(yard.end.x, yard.position.y), yard.end, Vector2(yard.position.x, yard.end.y)]
	for side in 4:
		var a: Vector2 = c[side]
		var b: Vector2 = c[(side + 1) % 4]
		if side == gate:
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_add_wall(m, a, mid - dir * 2.2, MapDef.W_COMPOUND)
			_add_wall(m, mid + dir * 2.2, b, MapDef.W_COMPOUND)
		else:
			_add_wall(m, a, b, MapDef.W_COMPOUND)
	for k in rng.range_i(1, 2):
		var p := _rand_point(yard.grow(-1.0), rng)
		if not house.grow(0.8).has_point(p):
			_add_prop(m, "palm" if rng.chance(0.5) else "tree", p, 0.0, rng.range_f(0.8, 1.2))


## Adds a building, or a ruin (rubble + shell) with probability from war damage.
static func _add_building(m: MapDef, r: Rect2, floors: int, style: int, rng: Rng, war: float) -> void:
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	var id := m.buildings.size() + 1
	if style != MapDef.S_MOSQUE and rng.chance(war * 0.22):
		m.fill_rect_terrain(r.grow(1.0), MapDef.T_RUBBLE)
		_add_prop(m, "rubble", r.get_center(), rng.range_f(0, TAU), clampf(minf(r.size.x, r.size.y) / 4.0, 1.0, 3.0))
		if rng.chance(0.5):
			m.buildings.append({"id": id, "c": r.get_center(), "size": r.size, "rot": 0.0, "floors": 1,
				"style": MapDef.S_UNFINISHED, "color": rng.range_i(0, 7), "seed": rng.range_i(1, 1 << 30)})
		return
	m.buildings.append({"id": id, "c": r.get_center(), "size": r.size, "rot": 0.0, "floors": maxi(1, floors),
		"style": style, "color": rng.range_i(0, 7), "seed": rng.range_i(1, 1 << 30)})


# ------------------------------------------------------------------- roads ---

## Straight road segments (horizontal, vertical, diagonal) from the road mask:
## parallel runs on adjacent lines are grouped into bands; a band that is long
## compared to its thickness is a road. Its axis is a line fit through the run
## endpoints, so slightly skewed or near-diagonal roads are found too.
static func road_segments(cls: PackedByteArray, n: int) -> Array:
	var out := []
	var hrun := _runs(cls, n, C_ROAD, true)
	var vrun := _runs(cls, n, C_ROAD, false)
	for dir in 4:
		_bands(cls, n, dir, hrun, vrun, out)
	return _dedupe_roads(out)


## Drops segments that run along a longer, parallel segment (same road found as
## several bands).
static func _dedupe_roads(segs: Array) -> Array:
	segs.sort_custom(func(a, b): return (a["a"] as Vector2).distance_squared_to(a["b"]) > (b["a"] as Vector2).distance_squared_to(b["b"]))
	var out := []
	for sg: Dictionary in segs:
		var a: Vector2 = sg["a"]
		var b: Vector2 = sg["b"]
		var d := (b - a).normalized()
		var dup := false
		for k: Dictionary in out:
			var ka: Vector2 = k["a"]
			var kb: Vector2 = k["b"]
			if absf(d.dot((kb - ka).normalized())) < 0.97:
				continue
			var tol: float = (float(k["w"]) + float(sg["w"])) * 0.5
			var covered := 0
			for t in 5:
				var p := a.lerp(b, t / 4.0)
				if Geometry2D.get_closest_point_to_segment(p, ka, kb).distance_to(p) <= tol:
					covered += 1
			if covered >= 4:
				dup = true
				break
		if not dup:
			out.append(sg)
	return out


static func _bands(cls: PackedByteArray, n: int, dir: int, hrun: PackedInt32Array, vrun: PackedInt32Array, out: Array) -> void:
	var diag := dir >= 2
	var kmin := -(n - 1) if dir == 2 else 0
	var kmax := 2 * n - 2 if dir == 3 else n - 1
	var min_run := 14 if diag else 8
	var active: Array = []
	for k in range(kmin, kmax + 1):
		var base := 0
		var step := 1
		var a0 := 0
		var a1 := n - 1
		match dir:
			0:
				base = k * n
			1:
				base = k
				step = n
			2:
				base = k
				step = n + 1
				a0 = maxi(0, -k)
				a1 = mini(n - 1, n - 1 - k)
			3:
				base = k
				step = n - 1
				a0 = maxi(0, k - n + 1)
				a1 = mini(n - 1, k)
		var next: Array = []
		var a := a0
		while a <= a1:
			if cls[base + a * step] != C_ROAD:
				a += 1
				continue
			var b := a
			while b + 1 <= a1 and cls[base + (b + 1) * step] == C_ROAD:
				b += 1
			var keep := b - a + 1 >= min_run
			if keep and diag:
				# diagonal chords through intersections of long H/V roads are not roads
				var inside := 0
				for t in range(a, b + 1):
					var idx := base + t * step
					if maxi(hrun[idx], vrun[idx]) >= 24:
						inside += 1
				keep = inside <= (b - a + 1) * 0.35
			if keep:
				var matched := false
				for band: Dictionary in active:
					if band["used"]:
						continue
					var la0: int = band["la0"]
					var la1: int = band["la1"]
					var ov := mini(la1, b) - maxi(la0, a) + 1
					if ov >= 0.6 * maxi(la1 - la0 + 1, b - a + 1):
						band["used"] = true
						band["la0"] = a
						band["la1"] = b
						(band["runs"] as Array).append(Vector3i(k, a, b))
						next.append(band)
						matched = true
						break
				if not matched:
					next.append({"la0": a, "la1": b, "used": true, "runs": [Vector3i(k, a, b)]})
			a = b + 1
		for band: Dictionary in active:
			if not band["used"]:
				_finish_band(band["runs"], dir, out)
		for band: Dictionary in next:
			band["used"] = false
		active = next
	for band: Dictionary in active:
		_finish_band(band["runs"], dir, out)


## World position of cell `a` on line `k` of direction `dir` (cell center).
static func _line_point(dir: int, k: int, a: int) -> Vector2:
	match dir:
		0: return Vector2(a + 0.5, k + 0.5) * MapDef.CELL
		1: return Vector2(k + 0.5, a + 0.5) * MapDef.CELL
		2: return Vector2(a + k + 0.5, a + 0.5) * MapDef.CELL
		_: return Vector2(k - a + 0.5, a + 0.5) * MapDef.CELL


static func _finish_band(runs: Array, dir: int, out: Array) -> void:
	if runs.size() < 2:
		return
	var pts := PackedVector2Array()
	var c := Vector2.ZERO
	for r: Vector3i in runs:
		pts.append(_line_point(dir, r.x, r.y))
		pts.append(_line_point(dir, r.x, r.z))
	for p in pts:
		c += p
	c /= pts.size()
	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0
	for p in pts:
		var d := p - c
		sxx += d.x * d.x
		sxy += d.x * d.y
		syy += d.y * d.y
	var ang := 0.5 * atan2(2.0 * sxy, sxx - syy)
	var dir_v := Vector2(cos(ang), sin(ang))
	var nrm := Vector2(-dir_v.y, dir_v.x)
	var tmin := INF
	var tmax := -INF
	var umin := INF
	var umax := -INF
	for p in pts:
		var t := (p - c).dot(dir_v)
		var u := (p - c).dot(nrm)
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
		umin = minf(umin, u)
		umax = maxf(umax, u)
	var cell := MapDef.CELL
	var width := umax - umin + (cell / sqrt(2.0) if dir >= 2 else cell)
	var length := tmax - tmin + cell
	if width > 24.0 or width < 2.0 or length < maxf(40.0 if dir >= 2 else 16.0, width * 3.0):
		return
	var kind := 0 if width >= 10.0 else (1 if width >= 5.5 else 2)
	var mid := c + nrm * (umin + umax) * 0.5
	out.append({"a": mid + dir_v * (tmin - cell * 0.5), "b": mid + dir_v * (tmax + cell * 0.5), "w": snappedf(width, 0.1), "kind": kind})


# -------------------------------------------------------------- vegetation ---

static func _vegetation(m: MapDef, cls: PackedByteArray, rng: Rng, dense: bool) -> void:
	var n := m.width
	var cell := MapDef.CELL
	for y in n:
		for x in n:
			var i := y * n + x
			if cls[i] != C_VEG:
				continue
			var t := m.terrain[i]
			var chance := 0.0
			if t == MapDef.T_GRASS:
				chance = 0.11 if dense else 0.05
			elif t == MapDef.T_FIELD and _has_neighbor(cls, n, x, y, C_OPEN):
				chance = 0.05
			if chance > 0.0 and rng.chance(chance):
				var p := Vector2((x + rng.range_f(0.2, 0.8)) * cell, (y + rng.range_f(0.2, 0.8)) * cell)
				var roll := rng.next_float()
				var kind := "tree" if roll < 0.55 else ("palm" if roll < 0.85 else "bush")
				_add_prop(m, kind, p, rng.range_f(0, TAU), rng.range_f(0.8, 1.3))


# ================================================================ playable ====

## Make a map playable: spawn zones on the two most open opposite edges,
## connectivity carving, well-spread objectives and street dressing.
## opts: {seed, war_damage, zones: bool, props: bool}. Returns {carved: int}.
static func make_playable(m: MapDef, opts: Dictionary = {}) -> Dictionary:
	var seed_v: int = opts.get("seed", m.map_seed)
	var war: float = opts.get("war_damage", 0.2)
	var rng := Rng.new(seed_v * 131 + 17)
	var carved := 0
	if opts.get("zones", true):
		place_spawns(m)
		var res := _connect(m)
		carved = res["carved"]
		place_objectives(m, rng, res["grids"])
		_districts(m)
	if opts.get("props", true):
		decorate_streets(m, seed_v, war)
		if m.spawns.size() >= 2:
			_strip_vehicle_blockers(m)
	return {"carved": carved}


## Grids for connectivity: foot-blocked, vehicle-blocked (inflated by one cell like
## NavGrid) and building index per cell.
static func _grids(m: MapDef) -> Dictionary:
	var w := m.width
	var h := m.height
	var n := w * h
	var foot := PackedByteArray()
	foot.resize(n)
	var raw := PackedByteArray()
	raw.resize(n)
	var bidx := PackedInt32Array()
	bidx.resize(n)
	bidx.fill(-1)
	for i in n:
		if m.terrain[i] == MapDef.T_WATER:
			foot[i] = 1
			raw[i] = 1
	for bi in m.buildings.size():
		var b: Dictionary = m.buildings[bi]
		for c in m.footprint_cells(b["c"], b["size"], b["rot"]):
			var i := c.y * w + c.x
			foot[i] = 1
			raw[i] = 1
			bidx[i] = bi
	for wl in m.walls:
		var kind: int = wl["kind"]
		var blocks_foot := kind == MapDef.W_COMPOUND or kind == MapDef.W_HESCO
		for i in _segment_cells(m, wl["a"], wl["b"]):
			raw[i] = 1
			if blocks_foot:
				foot[i] = 1
	for p in m.props:
		var spec: Dictionary = MapDef.PROPS.get(p["kind"], {})
		var blk: int = spec.get("block", 0)
		if blk == 0:
			continue
		var cells := m.footprint_cells(p["p"], spec["dims"] * float(p["s"]), p["rot"])
		if cells.is_empty():
			var c := m.world_to_cell(p["p"])
			if m.in_bounds(c.x, c.y):
				cells.append(c)
		for c in cells:
			var i := c.y * w + c.x
			if blk & 2:
				raw[i] = 1
			if blk & 1:
				foot[i] = 1
	var veh := PackedByteArray()
	veh.resize(n)
	for y in h:
		for x in w:
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				veh[y * w + x] = 1
				continue
			var i := y * w + x
			if raw[i - w - 1] | raw[i - w] | raw[i - w + 1] | raw[i - 1] | raw[i] | raw[i + 1] | raw[i + w - 1] | raw[i + w] | raw[i + w + 1]:
				veh[i] = 1
	return {"foot": foot, "veh": veh, "bidx": bidx}


static func _segment_cells(m: MapDef, a: Vector2, b: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var steps := maxi(1, int(ceil(a.distance_to(b) / (MapDef.CELL * 0.4))))
	var last := -1
	for s in steps + 1:
		var c := m.world_to_cell(a.lerp(b, float(s) / steps))
		if not m.in_bounds(c.x, c.y):
			continue
		var i := c.y * m.width + c.x
		if i != last:
			out.append(i)
			last = i
	return out


## Breadth-first flood over unblocked cells from `start`; returns visited flags.
static func _flood(blocked: PackedByteArray, w: int, h: int, start: int) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w * h)
	if start < 0 or blocked[start] != 0:
		return seen
	var queue := PackedInt32Array()
	queue.append(start)
	seen[start] = 1
	var head := 0
	while head < queue.size():
		var j := queue[head]
		head += 1
		var x := j % w
		if x > 0 and seen[j - 1] == 0 and blocked[j - 1] == 0:
			seen[j - 1] = 1
			queue.append(j - 1)
		if x < w - 1 and seen[j + 1] == 0 and blocked[j + 1] == 0:
			seen[j + 1] = 1
			queue.append(j + 1)
		if j >= w and seen[j - w] == 0 and blocked[j - w] == 0:
			seen[j - w] = 1
			queue.append(j - w)
		if j < w * (h - 1) and seen[j + w] == 0 and blocked[j + w] == 0:
			seen[j + w] = 1
			queue.append(j + w)
	return seen


## Nearest unblocked cell index to a world point (spiral search), or -1.
static func _nearest_open(m: MapDef, blocked: PackedByteArray, p: Vector2, max_r: int = 24) -> int:
	var c := m.world_to_cell(p)
	c.x = clampi(c.x, 0, m.width - 1)
	c.y = clampi(c.y, 0, m.height - 1)
	for r in range(0, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var x := c.x + dx
				var y := c.y + dy
				if m.in_bounds(x, y) and blocked[y * m.width + x] == 0:
					return y * m.width + x
	return -1


static func _clear_area(m: MapDef, r: Rect2) -> void:
	m.buildings = m.buildings.filter(func(b): return not r.intersects(Rect2(b["c"] - b["size"] * 0.5, b["size"])))
	m.walls = m.walls.filter(func(w): return not (r.has_point(w["a"]) or r.has_point(w["b"]) or Geometry2D.segment_intersects_segment(w["a"], w["b"], r.position, r.end) != null or Geometry2D.segment_intersects_segment(w["a"], w["b"], Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y)) != null))
	m.props = m.props.filter(func(p): return not r.has_point(p["p"]))


## Spawn zones on the opposite pair of edges (W/E preferred) with the most open
## ground; buildings and water inside the zones are cleared. Connectivity between
## them is ensured afterwards by ensure_connectivity (carving if needed).
static func place_spawns(m: MapDef) -> void:
	var g := _grids(m)
	var foot: PackedByteArray = g["foot"]
	var w := m.width
	var h := m.height
	var open := PackedByteArray()
	open.resize(w * h)
	for i in w * h:
		open[i] = 1 if foot[i] == 0 else 0
	var depth := int((SPAWN_DEPTH + SPAWN_INSET) / MapDef.CELL)
	var we := [_edge_window(open, w, h, 0, depth), _edge_window(open, w, h, 1, depth)]
	var ns := [_edge_window(open, w, h, 2, depth), _edge_window(open, w, h, 3, depth)]
	var use_ns: bool = minf(ns[0]["score"], ns[1]["score"]) > minf(we[0]["score"], we[1]["score"]) + 0.2
	var pick: Array = ns if use_ns else we
	var size := m.size_m()
	m.spawns.clear()
	for team in 2:
		var edge: int = (2 if use_ns else 0) + team
		var start: float = pick[team]["start"] * MapDef.CELL
		var length: float = pick[team]["len"] * MapDef.CELL
		var r: Rect2
		match edge:
			0: r = Rect2(SPAWN_INSET, start, SPAWN_DEPTH, length)
			1: r = Rect2(size.x - SPAWN_INSET - SPAWN_DEPTH, start, SPAWN_DEPTH, length)
			2: r = Rect2(start, SPAWN_INSET, length, SPAWN_DEPTH)
			_: r = Rect2(start, size.y - SPAWN_INSET - SPAWN_DEPTH, length, SPAWN_DEPTH)
		_clear_area(m, r)
		var c0 := m.world_to_cell(r.position)
		var c1 := m.world_to_cell(r.end)
		for y in range(maxi(c0.y, 0), mini(c1.y + 1, h)):
			for x in range(maxi(c0.x, 0), mini(c1.x + 1, w)):
				var t := m.terrain[y * w + x]
				if t == MapDef.T_WATER or t == MapDef.T_RUBBLE:
					m.terrain[y * w + x] = MapDef.T_DIRT
		m.spawns.append({"team": team, "rect": r})


## Best window along an edge band: {start (cells along the edge), len, score 0..1}.
## edge: 0 west, 1 east, 2 north, 3 south.
static func _edge_window(open: PackedByteArray, w: int, h: int, edge: int, depth: int) -> Dictionary:
	var along := h if edge < 2 else w
	var prof := PackedInt32Array()
	prof.resize(along)
	for t in along:
		var cnt := 0
		for d in depth:
			var x := d
			var y := t
			match edge:
				1: x = w - 1 - d
				2:
					x = t
					y = d
				3:
					x = t
					y = h - 1 - d
			if open[y * w + x] != 0:
				cnt += 1
		prof[t] = cnt
	var win := maxi(8, int(along * 0.38))
	var sum := 0
	for t in win:
		sum += prof[t]
	var best := sum
	var best_t := 0
	for t in range(1, along - win + 1):
		sum += prof[t + win - 1] - prof[t - 1]
		# prefer the middle of the edge on ties
		if sum > best or (sum == best and absi(t + win / 2 - along / 2) < absi(best_t + win / 2 - along / 2)):
			best = sum
			best_t = t
	return {"start": best_t, "len": win, "score": float(best) / float(win * depth)}


## Carves streets until both spawns connect on foot and by wheeled vehicle.
## Returns the number of carved corridors.
static func ensure_connectivity(m: MapDef) -> int:
	return _connect(m)["carved"]


## {carved: int, grids: grids of the final map state}
static func _connect(m: MapDef) -> Dictionary:
	var g := {}
	var carved := 0
	if m.spawns.size() < 2:
		return {"carved": 0, "grids": g}
	for iter in 4:
		g = _grids(m)
		if iter == 3:
			break
		var foot: PackedByteArray = g["foot"]
		var veh: PackedByteArray = g["veh"]
		var p0 := m.team_spawn(0).get_center()
		var p1 := m.team_spawn(1).get_center()
		var f0 := _nearest_open(m, foot, p0)
		var f1 := _nearest_open(m, foot, p1)
		var v0 := _nearest_open(m, veh, p0)
		var v1 := _nearest_open(m, veh, p1)
		var foot_ok := f0 >= 0 and f1 >= 0 and _flood(foot, m.width, m.height, f0)[f1] != 0
		var veh_ok := v0 >= 0 and v1 >= 0 and _flood(veh, m.width, m.height, v0)[v1] != 0
		if foot_ok and veh_ok:
			break
		_carve(m, g, p0, p1)
		carved += 1
	return {"carved": carved, "grids": g}


## Least-destruction street between two points: A* where blocked cells are costly,
## then a 5-cell corridor is cleared (buildings, walls, props) and paved.
static func _carve(m: MapDef, g: Dictionary, from: Vector2, to: Vector2) -> void:
	var w := m.width
	var h := m.height
	var veh: PackedByteArray = g["veh"]
	var bidx: PackedInt32Array = g["bidx"]
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for i in w * h:
		var t := m.terrain[i]
		var cost := 1.0 if t == MapDef.T_ROAD or t == MapDef.T_PAVED else 1.6
		if t == MapDef.T_WATER:
			cost = 25.0
		elif bidx[i] >= 0:
			cost = 14.0
		elif veh[i] != 0:
			cost = 5.0
		if cost > 1.0:
			astar.set_point_weight_scale(Vector2i(i % w, i / w), cost)
	var c0 := m.world_to_cell(from).clamp(Vector2i.ZERO, Vector2i(w - 1, h - 1))
	var c1 := m.world_to_cell(to).clamp(Vector2i.ZERO, Vector2i(w - 1, h - 1))
	var path := astar.get_id_path(c0, c1)
	if path.is_empty():
		return
	var kill := {}
	var corridor := {}
	var cut := PackedByteArray()   # path cells that were blocked before carving
	cut.resize(path.size())
	for pi in path.size():
		var pc: Vector2i = path[pi]
		var pt := m.terrain[pc.y * w + pc.x]
		cut[pi] = 1 if veh[pc.y * w + pc.x] != 0 or pt == MapDef.T_WATER else 0
	for c in path:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := c.x + dx
				var y := c.y + dy
				if not m.in_bounds(x, y):
					continue
				var i := y * w + x
				corridor[i] = true
				if bidx[i] >= 0:
					kill[bidx[i]] = true
				var t := m.terrain[i]
				var was_blocked: bool = veh[i] != 0 or t == MapDef.T_WATER
				if absi(dx) <= 1 and absi(dy) <= 1 and was_blocked:
					m.terrain[i] = MapDef.T_ROAD
				elif t == MapDef.T_WATER:
					m.terrain[i] = MapDef.T_PAVED
	var keep := []
	for bi in m.buildings.size():
		if not kill.has(bi):
			keep.append(m.buildings[bi])
	m.buildings = keep
	m.walls = m.walls.filter(func(wl):
		for i in _segment_cells(m, wl["a"], wl["b"]):
			if corridor.has(i):
				return false
		return true)
	m.props = m.props.filter(func(p):
		var c := m.world_to_cell(p["p"])
		return not (m.in_bounds(c.x, c.y) and corridor.has(c.y * w + c.x)))
	# straight runs of newly cut cells become street segments (markings)
	var run_start := -1
	for k in path.size() + 1:
		var go := k < path.size() and cut[k] == 1 and (run_start < 0 or k - run_start < 2 or (path[k] - path[k - 1]) == (path[k - 1] - path[k - 2]))
		if go:
			if run_start < 0:
				run_start = k
			continue
		if run_start >= 0 and k - 1 - run_start >= 4:
			m.roads.append({"a": m.cell_center(path[run_start]), "b": m.cell_center(path[k - 1]), "w": 6.0, "kind": 1})
		run_start = k if k < path.size() and cut[k] == 1 else -1


## 3-5 objectives at well-spread open junctions reachable on foot from both spawns.
static func place_objectives(m: MapDef, rng: Rng, grids: Dictionary = {}) -> void:
	var w := m.width
	var h := m.height
	var size := m.size_m()
	var g := grids if not grids.is_empty() else _grids(m)
	var foot: PackedByteArray = g["foot"]
	var p0 := m.team_spawn(0).get_center()
	var p1 := m.team_spawn(1).get_center()
	var s0 := _nearest_open(m, foot, p0)
	var reach := _flood(foot, w, h, s0)
	var open_d := _open_distance(foot, w, h)
	var bidx: PackedInt32Array = g["bidx"]
	var bmask := PackedByteArray()
	bmask.resize(w * h)
	for i in w * h:
		bmask[i] = 1 if bidx[i] >= 0 else 0
	var bsat := _sat(bmask, w, 1)
	var cands: Array = []   # [Vector2, score]
	var junctions := _junctions(m)
	for jp: Vector2 in junctions:
		cands.append([jp, 2.0])
	# open spots as fallback / plazas
	for y in range(4, h - 4, 3):
		for x in range(4, w - 4, 3):
			var i := y * w + x
			if open_d[i] >= 5:
				cands.append([m.cell_center(Vector2i(x, y)), 0.5 + minf(open_d[i], 10) * 0.08])
	var valid: Array = []
	for cd: Array in cands:
		var p: Vector2 = cd[0]
		var c := m.world_to_cell(p)
		if not m.in_bounds(c.x, c.y):
			continue
		# objectives belong in the built-up area: [p, score, urban density]
		var dens := _sat_density(bsat, w, c.x, c.y, 14)
		cd[1] = float(cd[1]) + minf(dens * 4.0, 1.6)
		cd.append(dens)
		var i := c.y * w + c.x
		if reach[i] == 0 or foot[i] != 0:
			continue
		if p.x < 24.0 or p.y < 24.0 or p.x > size.x - 24.0 or p.y > size.y - 24.0:
			continue
		var near_spawn := false
		for s in m.spawns:
			if _rect_dist(s["rect"], p) < 50.0:
				near_spawn = true
		if not near_spawn:
			valid.append(cd)
	var want := 5 if w >= 200 else (4 if w >= 140 else 3)
	var urban := valid.filter(func(cd): return float(cd[2]) >= 0.12)
	if urban.size() >= want * 3:
		valid = urban
	var chosen := _pick_objectives(valid, want, p0, p1, size)
	m.objectives.clear()
	var letters := ["A", "B", "C", "D", "E"]
	var used_names := {}
	for i in chosen.size():
		var p := chosen[i]
		var nm := _objective_name(m, p, junctions)
		if used_names.has(nm):
			nm = "%s %s" % [nm, letters[i]]
		used_names[nm] = true
		m.objectives.append({"id": letters[i], "name": nm, "p": p, "r": OBJ_RADIUS})
		# open up the spot: props, walls and small sheds go, real buildings stay
		var box := Rect2(p - Vector2(6, 6), Vector2(12, 12))
		m.props = m.props.filter(func(pr): return not box.has_point(pr["p"]))
		m.walls = m.walls.filter(func(wl): return not (box.has_point(wl["a"]) or box.has_point(wl["b"])))
		m.buildings = m.buildings.filter(func(b): return (b["size"] as Vector2).x * (b["size"] as Vector2).y > 120.0 			or b["style"] == MapDef.S_MOSQUE or not box.intersects(Rect2(b["c"] - b["size"] * 0.5, b["size"])))
		# defensive dressing on non-road ground
		for k in rng.range_i(1, 2):
			var a := rng.range_f(0, TAU)
			var q := p + Vector2(cos(a), sin(a)) * rng.range_f(8, 12)
			var e := q + Vector2(cos(a + PI * 0.5), sin(a + PI * 0.5)) * 3.5
			var ok := true
			for ci in _segment_cells(m, q, e):
				if m.terrain[ci] == MapDef.T_ROAD or m.terrain[ci] == MapDef.T_WATER or foot[ci] != 0:
					ok = false
			if ok:
				_add_wall(m, q, e, MapDef.W_SANDBAG)


## Balanced picks: the most contested spot between the spawns first, then pairs
## mirrored through the midpoint so both sides get objectives at equal distance.
static func _pick_objectives(valid: Array, want: int, p0: Vector2, p1: Vector2, size: Vector2) -> Array[Vector2]:
	var chosen: Array[Vector2] = []
	var mid := (p0 + p1) * 0.5
	var nearest := func(target: Vector2, spacing: float) -> Variant:
		var best_d := INF
		var best: Variant = null
		for cd: Array in valid:
			var p: Vector2 = cd[0]
			var ok := true
			for q in chosen:
				if q.distance_to(p) < spacing:
					ok = false
					break
			var dd := p.distance_to(target) - float(cd[1]) * 4.0
			if ok and dd < best_d:
				best_d = dd
				best = p
		return best
	var first: Variant = nearest.call(mid, 0.0)
	if first == null:
		return chosen
	chosen.append(first)
	var banned := {}   # pair seeds without a mirror partner
	for spacing: float in [size.x * 0.2, size.x * 0.13, 30.0]:
		var guard := 0
		while chosen.size() < want and guard < 40:
			guard += 1
			var best := -INF
			var seed_p: Variant = null
			for cd: Array in valid:
				var p: Vector2 = cd[0]
				if banned.has(p):
					continue
				var dmin := INF
				for q in chosen:
					dmin = minf(dmin, q.distance_to(p))
				if dmin < spacing:
					continue
				var score: float = minf(dmin, size.x * 0.3) / size.x * 5.0 + float(cd[1]) - absf(p.distance_to(p0) - p.distance_to(p1)) / size.x * 3.0
				if score > best:
					best = score
					seed_p = p
			if seed_p == null:
				break
			chosen.append(seed_p)
			if chosen.size() < want:
				var mirror: Variant = nearest.call(mid * 2.0 - seed_p, spacing)
				if mirror != null and (mirror as Vector2).distance_to(mid * 2.0 - seed_p) < size.x * 0.12:
					chosen.append(mirror)
				else:
					chosen.pop_back()
					banned[seed_p] = true
		if chosen.size() >= want:
			break
	return chosen


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)


## Chessboard distance (cells) to the nearest foot-blocked cell, capped at 30.
static func _open_distance(blocked: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(w * h)
	for i in w * h:
		d[i] = 0 if blocked[i] != 0 else 30
	for y in h:
		for x in w:
			var i := y * w + x
			if d[i] == 0:
				continue
			var v := d[i]
			if x > 0: v = mini(v, d[i - 1] + 1)
			if y > 0:
				v = mini(v, d[i - w] + 1)
				if x > 0: v = mini(v, d[i - w - 1] + 1)
				if x < w - 1: v = mini(v, d[i - w + 1] + 1)
			d[i] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0:
				continue
			var v := d[i]
			if x < w - 1: v = mini(v, d[i + 1] + 1)
			if y < h - 1:
				v = mini(v, d[i + w] + 1)
				if x < w - 1: v = mini(v, d[i + w + 1] + 1)
				if x > 0: v = mini(v, d[i + w - 1] + 1)
			d[i] = v
	return d


## Intersection points of non-parallel road segments.
static func _junctions(m: MapDef) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rs := m.roads
	for i in rs.size():
		for j in range(i + 1, rs.size()):
			var a: Dictionary = rs[i]
			var b: Dictionary = rs[j]
			var hit = Geometry2D.segment_intersects_segment(a["a"], a["b"], b["a"], b["b"])
			if hit == null:
				continue
			var da: Vector2 = (a["b"] - a["a"]).normalized()
			var db: Vector2 = (b["b"] - b["a"]).normalized()
			if absf(da.dot(db)) > 0.9:
				continue
			var dup := false
			for q in out:
				if q.distance_to(hit) < 10.0:
					dup = true
					break
			if not dup:
				out.append(hit)
	return out


static func _objective_name(m: MapDef, p: Vector2, junctions: Array[Vector2]) -> String:
	var size := m.size_m()
	var rel := (p - size * 0.5) / size
	var compass := "Central"
	if rel.length() > 0.14:
		var ang := rad_to_deg(atan2(rel.y, rel.x))
		var names := ["East", "Southeast", "South", "Southwest", "West", "Northwest", "North", "Northeast"]
		compass = names[int(fposmod(round(ang / 45.0), 8.0))]
	var feature := "Square"
	var near_j := false
	for q in junctions:
		if q.distance_to(p) < 6.0:
			near_j = true
	if near_j:
		feature = "Crossroads"
	var water := 0
	var veg := 0
	var c := m.world_to_cell(p)
	for dy in range(-8, 9, 2):
		for dx in range(-8, 9, 2):
			var t := m.get_terrain(c.x + dx, c.y + dy)
			if t == MapDef.T_WATER:
				water += 1
			elif t == MapDef.T_GRASS:
				veg += 1
	for b in m.buildings:
		if b["style"] == MapDef.S_MOSQUE and (b["c"] as Vector2).distance_to(p) < 40.0:
			feature = "Mosque Square"
	if water >= 4:
		feature = "Bridge" if near_j else "Riverside"
	elif veg >= 10:
		feature = "Park"
	return "%s %s" % [compass, feature]


static func _districts(m: MapDef) -> void:
	var size := m.size_m()
	var q := size * 0.5
	m.districts.clear()
	for s in m.spawns:
		var r: Rect2 = s["rect"]
		m.districts.append({"name": "%s Approach" % ("Blue" if s["team"] == 0 else "Red"), "rect": r.grow(10.0)})
	m.districts.append({"name": "Northern District", "rect": Rect2(0, 0, size.x, q.y)})
	m.districts.append({"name": "Southern District", "rect": Rect2(0, q.y, size.x, q.y)})


## Street furniture along road segments, like CityGenerator: lamps and palms on
## avenues, poles on streets, parked / wrecked cars on roads wide enough to keep
## a vehicle lane free, debris scaled by war damage.
static func decorate_streets(m: MapDef, seed_v: int, war: float) -> void:
	var rng := Rng.new(seed_v * 53 + 11)
	var w := m.width
	var occ := PackedByteArray()
	occ.resize(w * m.height)
	for b in m.buildings:
		for c in m.footprint_cells(b["c"], b["size"] + Vector2(1.0, 1.0), b["rot"]):
			occ[c.y * w + c.x] = 1
	for i in w * m.height:
		if m.terrain[i] == MapDef.T_WATER:
			occ[i] = 1
	var keep_out: Array[Rect2] = []
	for s in m.spawns:
		keep_out.append((s["rect"] as Rect2).grow(4.0))
	for o in m.objectives:
		keep_out.append(Rect2(o["p"] - Vector2(9, 9), Vector2(18, 18)))
	var try_prop := func(kind: String, p: Vector2, rot: float, s: float) -> void:
		var c := m.world_to_cell(p)
		if not m.in_bounds(c.x, c.y) or occ[c.y * w + c.x] != 0:
			return
		for r in keep_out:
			if r.has_point(p):
				return
		_add_prop(m, kind, p, rot, s)
	for r in m.roads:
		var a: Vector2 = r["a"]
		var b: Vector2 = r["b"]
		var rw: float = r["w"]
		var kind: int = r["kind"]
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var length := a.distance_to(b)
		var step := 22.0 if kind == 0 else 30.0
		var t := rng.range_f(4.0, step)
		while t < length - 2.0:
			var p := a + dir * t
			if kind == 0:
				try_prop.call("lamp", p + nrm * (rw * 0.5 + 0.8), 0.0, 1.0)
				try_prop.call("lamp", p - nrm * (rw * 0.5 + 0.8), 0.0, 1.0)
				if rng.chance(0.5):
					try_prop.call("palm", p + nrm * (rw * 0.5 + 1.6), 0.0, rng.range_f(0.9, 1.2))
			elif kind == 1:
				try_prop.call("pole", p + nrm * (rw * 0.5 + 0.6), 0.0, 1.0)
			if rw >= 8.0 and rng.chance(0.4):
				var side := 1.0 if rng.chance(0.5) else -1.0
				var kp := "car"
				var roll := rng.next_float()
				if roll < war * 0.6:
					kp = "car_wreck"
				elif roll < war * 0.7 and rw >= 10.0:
					kp = "bus_wreck"
				try_prop.call(kp, p + nrm * side * (rw * 0.5 - 1.3) + dir * rng.range_f(-4, 4), dir.angle() + rng.range_f(-0.12, 0.12), 1.0)
			if rng.chance(0.06 + war * 0.12):
				try_prop.call(rng.pick(["dumpster", "barrels", "tires", "rubble", "crates"]), p + nrm * rng.range_f(-1, 1) * (rw * 0.5 + 1.0), rng.range_f(0, TAU), 1.0)
			t += step * rng.range_f(0.6, 1.4)


## Safety net: if street props cut the wheeled route between spawns, remove the
## vehicle-blocking decoration (wrecks, debris) on the route.
static func _strip_vehicle_blockers(m: MapDef) -> void:
	for pass_i in 2:
		var g := _grids(m)
		var veh: PackedByteArray = g["veh"]
		var v0 := _nearest_open(m, veh, m.team_spawn(0).get_center())
		var v1 := _nearest_open(m, veh, m.team_spawn(1).get_center())
		if v0 >= 0 and v1 >= 0 and _flood(veh, m.width, m.height, v0)[v1] != 0:
			return
		var removable := ["car", "car_wreck", "bus_wreck", "dumpster", "barrels", "tires", "rubble", "crates", "barrier"]
		if pass_i == 0:
			removable = ["bus_wreck", "car_wreck", "rubble", "dumpster", "barrels", "tires", "crates"]
		m.props = m.props.filter(func(p): return not removable.has(p["kind"]))


# ----------------------------------------------------------------- helpers ---

static func _add_prop(m: MapDef, kind: String, p: Vector2, rot: float, s: float = 1.0) -> void:
	m.props.append({"kind": kind, "p": p, "rot": rot, "s": s})


static func _add_wall(m: MapDef, a: Vector2, b: Vector2, kind: int) -> void:
	if a.distance_to(b) < 0.8:
		return
	m.walls.append({"a": a, "b": b, "h": MapDef.WALL_HEIGHT[kind], "kind": kind})


static func _rand_point(r: Rect2, rng: Rng) -> Vector2:
	return Vector2(rng.range_f(r.position.x, r.end.x), rng.range_f(r.position.y, r.end.y))

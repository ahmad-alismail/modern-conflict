extends RefCounted
## Procedural fictional Middle-Eastern city generator.
## Produces a MapDef: avenues + streets via recursive block subdivision,
## districts (old quarter, downtown, residential, villa outskirts, industrial),
## perimeter blocks with courtyards, landmarks, props, war damage, objectives and spawns.
class_name CityGenerator

const AVENUE_W := 11.0
const AVENUE_WALK := 2.5
const STREET_W := 7.0
const STREET_WALK := 1.5
const ALLEY_W := 4.0

const D_OLD := "Old Quarter"
const D_DOWNTOWN := "Downtown"
const D_RESIDENTIAL := "Residential"
const D_OUTSKIRTS := "Outskirts"
const D_INDUSTRIAL := "Industrial Zone"

const PLACE_NAMES := ["Tell Hamra", "Qasr al-Nur", "Deir Saman", "Ayn Zarqa", "Kafr Ruma", "Jabal Suwan", "Wadi Khalil", "Harat Bayda"]

var m: MapDef
var rng: Rng
var _next_building_id := 0
var _center := Vector2.ZERO
var _spawn_margin := 54.0
var _war := 0.25
var _avenues_x: Array[float] = []
var _avenues_y: Array[float] = []
var _intersections: Array[Vector2] = []
var _occ := PackedByteArray()


## opts: {size: int cells (default 240), war_damage: 0..1, name: String}
static func generate(seed_value: int, opts: Dictionary = {}) -> MapDef:
	var g := CityGenerator.new()
	return g._generate(seed_value, opts)


func _generate(seed_value: int, opts: Dictionary) -> MapDef:
	rng = Rng.new(seed_value)
	var cells: int = opts.get("size", 240)
	m = MapDef.new(cells, cells)
	m.map_seed = seed_value
	_war = opts.get("war_damage", 0.25)
	var place: String = opts.get("name", PLACE_NAMES[seed_value % PLACE_NAMES.size()])
	m.name = place
	m.description = "A fictional city of %s, contested block by block." % place
	var size := m.size_m()
	_center = size * 0.5 + Vector2(rng.range_f(-20, 20), rng.range_f(-20, 20))

	_base_terrain()
	_layout_avenues(size)
	_layout_superblocks(size)
	_spawn_zones(size)
	_objectives(size)
	_decorate_streets()
	return m


# ------------------------------------------------------------------ terrain ---

func _base_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.range_i(0, 1 << 30)
	noise.frequency = 0.035
	for y in m.height:
		for x in m.width:
			var n := noise.get_noise_2d(x, y)
			m.terrain[y * m.width + x] = MapDef.T_DIRT if n > 0.15 else MapDef.T_SAND


func _district_at(p: Vector2, size: Vector2) -> String:
	var d := p.distance_to(_center)
	var rel := p - _center
	if rel.x > 10.0 and rel.y < -10.0 and d < size.x * 0.36:
		return D_OLD
	if rel.x < -40.0 and rel.y > 60.0:
		return D_INDUSTRIAL
	if d < size.x * 0.2:
		return D_DOWNTOWN
	if d < size.x * 0.38 and p.x > _spawn_margin + 20 and p.x < size.x - _spawn_margin - 20:
		return D_RESIDENTIAL
	return D_OUTSKIRTS


# ------------------------------------------------------------------ roads -----

func _layout_avenues(size: Vector2) -> void:
	_avenues_x = [snappedf(size.x * 0.31 + rng.range_f(-14, 14), 2.0), snappedf(size.x * 0.69 + rng.range_f(-14, 14), 2.0)]
	_avenues_y = [snappedf(size.y * 0.3 + rng.range_f(-14, 14), 2.0), snappedf(size.y * 0.68 + rng.range_f(-14, 14), 2.0)]
	for x in _avenues_x:
		_add_road(Vector2(x, 0), Vector2(x, size.y), AVENUE_W, AVENUE_WALK, 0)
	for y in _avenues_y:
		_add_road(Vector2(0, y), Vector2(size.x, y), AVENUE_W, AVENUE_WALK, 0)
	for x in _avenues_x:
		for y in _avenues_y:
			_intersections.append(Vector2(x, y))


func _add_road(a: Vector2, b: Vector2, w: float, walk: float, kind: int) -> void:
	m.roads.append({"a": a, "b": b, "w": w, "kind": kind})
	m.paint_road(a, b, w, walk)


func _layout_superblocks(size: Vector2) -> void:
	var xs: Array[float] = [0.0]
	for x in _avenues_x:
		xs.append(x)
	xs.append(size.x)
	var ys: Array[float] = [0.0]
	for y in _avenues_y:
		ys.append(y)
	ys.append(size.y)
	var inset := AVENUE_W * 0.5 + AVENUE_WALK
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var x0 := xs[i] + (inset if i > 0 else 0.0)
			var x1 := xs[i + 1] - (inset if i + 1 < xs.size() - 1 else 0.0)
			var y0 := ys[j] + (inset if j > 0 else 0.0)
			var y1 := ys[j + 1] - (inset if j + 1 < ys.size() - 1 else 0.0)
			_split_block(Rect2(x0, y0, x1 - x0, y1 - y0), 0)
	# central plaza and mosque (overrides whatever was placed there)
	_central_plaza()


func _max_block(district: String) -> float:
	match district:
		D_OLD: return 46.0
		D_DOWNTOWN: return 74.0
		D_RESIDENTIAL: return 80.0
		D_INDUSTRIAL: return 96.0
		_: return 90.0


func _split_block(r: Rect2, depth: int) -> void:
	var size := m.size_m()
	var district := _district_at(r.get_center(), size)
	var limit := _max_block(district)
	if (r.size.x > limit or r.size.y > limit) and depth < 8:
		var horizontal := r.size.y > r.size.x
		var alley := district == D_OLD
		var w := ALLEY_W if alley else STREET_W
		var walk := 0.0 if alley else STREET_WALK
		var gap := w * 0.5 + walk
		var t := rng.range_f(0.38, 0.62)
		if horizontal:
			var sy := snappedf(r.position.y + r.size.y * t, 2.0)
			_add_road(Vector2(r.position.x, sy), Vector2(r.end.x, sy), w, walk, 2 if alley else 1)
			_split_block(Rect2(r.position.x, r.position.y, r.size.x, sy - gap - r.position.y), depth + 1)
			_split_block(Rect2(r.position.x, sy + gap, r.size.x, r.end.y - sy - gap), depth + 1)
			if not alley:
				_intersections.append(Vector2(r.position.x, sy))
		else:
			var sx := snappedf(r.position.x + r.size.x * t, 2.0)
			_add_road(Vector2(sx, r.position.y), Vector2(sx, r.end.y), w, walk, 2 if alley else 1)
			_split_block(Rect2(r.position.x, r.position.y, sx - gap - r.position.x, r.size.y), depth + 1)
			_split_block(Rect2(sx + gap, r.position.y, r.end.x - sx - gap, r.size.y), depth + 1)
			if not alley:
				_intersections.append(Vector2(sx, r.position.y))
		return
	_fill_block(r, district)


# ------------------------------------------------------------------ blocks ----

func _in_spawn_margin(r: Rect2) -> bool:
	var size := m.size_m()
	return r.position.x < _spawn_margin or r.end.x > size.x - _spawn_margin


func _fill_block(r: Rect2, district: String) -> void:
	if r.size.x < 8.0 or r.size.y < 8.0:
		return
	if _in_spawn_margin(r):
		_fill_edge(r)
		return
	match district:
		D_OLD: _fill_perimeter(r, 9.0, 15.0, 11.0, 1, 3, MapDef.S_OLD, 0.0)
		D_DOWNTOWN: _fill_perimeter(r, 13.0, 22.0, 17.0, 3, 7, MapDef.S_SHOP, 0.18)
		D_RESIDENTIAL: _fill_slabs(r)
		D_INDUSTRIAL: _fill_industrial(r)
		_: _fill_villas(r)


## Perimeter block: rows of attached buildings around a courtyard.
func _fill_perimeter(r: Rect2, min_w: float, max_w: float, depth: float, fmin: int, fmax: int, style: int, tower_p: float) -> void:
	var lots: Array[Rect2] = []
	if r.size.x < depth * 2.0 + 6.0 or r.size.y < depth * 2.0 + 6.0:
		lots = _split_row(r, min_w, max_w, r.size.x >= r.size.y)
	else:
		lots.append_array(_split_row(Rect2(r.position.x, r.position.y, r.size.x, depth), min_w, max_w, true))
		lots.append_array(_split_row(Rect2(r.position.x, r.end.y - depth, r.size.x, depth), min_w, max_w, true))
		lots.append_array(_split_row(Rect2(r.position.x, r.position.y + depth, depth, r.size.y - 2.0 * depth), min_w, max_w, false))
		lots.append_array(_split_row(Rect2(r.end.x - depth, r.position.y + depth, depth, r.size.y - 2.0 * depth), min_w, max_w, false))
		var court := r.grow(-depth)
		m.fill_rect_terrain(court, MapDef.T_PAVED if style != MapDef.S_OLD or rng.chance(0.5) else MapDef.T_DIRT)
		_courtyard_props(court)
	for lot in lots:
		var st := style
		var floors := rng.range_i(fmin, fmax)
		if style == MapDef.S_SHOP and rng.chance(0.35):
			st = MapDef.S_APARTMENT
		if rng.chance(tower_p) and lot.size.x > 12 and lot.size.y > 12:
			st = MapDef.S_TOWER
			floors = rng.range_i(8, 12)
		if style == MapDef.S_OLD and rng.chance(0.08):
			st = MapDef.S_UNFINISHED
		var g := 0.0 if style == MapDef.S_OLD else rng.range_f(0.0, 0.6)
		_place_building(lot.grow(-g), floors, st)


func _split_row(r: Rect2, min_w: float, max_w: float, along_x: bool) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var total := r.size.x if along_x else r.size.y
	var pos := 0.0
	while pos < total - 0.5:
		var w := rng.range_f(min_w, max_w)
		if total - (pos + w) < min_w:
			w = total - pos
		if along_x:
			out.append(Rect2(r.position.x + pos, r.position.y, w, r.size.y))
		else:
			out.append(Rect2(r.position.x, r.position.y + pos, r.size.x, w))
		pos += w
	return out


func _fill_slabs(r: Rect2) -> void:
	# Free-standing apartment blocks with open ground between them.
	m.fill_rect_terrain(r, MapDef.T_DIRT)
	var along_x := r.size.x >= r.size.y
	var lots := _split_row(r, 22.0, 34.0, along_x)
	for lot in lots:
		var inner := lot.grow(-3.0)
		if inner.size.x < 10 or inner.size.y < 10:
			continue
		if rng.chance(0.12):
			_vacant_lot(inner)
			continue
		var depth := minf(rng.range_f(12.0, 16.0), (inner.size.y if along_x else inner.size.x))
		var b: Rect2
		if along_x:
			var yoff := rng.range_f(0.0, maxf(inner.size.y - depth, 0.0))
			b = Rect2(inner.position.x, inner.position.y + yoff, inner.size.x, depth)
		else:
			var xoff := rng.range_f(0.0, maxf(inner.size.x - depth, 0.0))
			b = Rect2(inner.position.x + xoff, inner.position.y, depth, inner.size.y)
		var st := MapDef.S_UNFINISHED if rng.chance(0.15) else MapDef.S_APARTMENT
		_place_building(b, rng.range_i(4, 8), st)
		# parked cars / trees in the open space
		for k in rng.range_i(0, 2):
			_add_prop("car" if rng.chance(0.7) else "car_wreck", _rand_point(inner.grow(-1.0)), rng.range_f(0, TAU))
		if rng.chance(0.5):
			_add_prop("tree", _rand_point(inner), 0.0, rng.range_f(0.8, 1.3))


func _fill_villas(r: Rect2) -> void:
	var along_x := r.size.x >= r.size.y
	var rows: Array[Rect2] = []
	var short := r.size.y if along_x else r.size.x
	if short > 46.0:
		# two rows of lots back to back
		if along_x:
			rows = [Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5))]
		else:
			rows = [Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y)), Rect2(r.position + Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y))]
	else:
		rows = [r]
	for row in rows:
		for lot in _split_row(row, 20.0, 30.0, along_x):
			if rng.chance(0.18):
				_vacant_lot(lot.grow(-1.0))
				continue
			_villa(lot)


func _villa(lot: Rect2) -> void:
	var inner := lot.grow(-1.0)
	if inner.size.x < 12 or inner.size.y < 12:
		return
	m.fill_rect_terrain(inner, MapDef.T_GRASS if rng.chance(0.55) else MapDef.T_DIRT)
	var hs := Vector2(rng.range_f(9.0, minf(14.0, inner.size.x - 4.0)), rng.range_f(9.0, minf(14.0, inner.size.y - 4.0)))
	var hp := inner.position + Vector2(rng.range_f(2.0, inner.size.x - hs.x - 2.0), rng.range_f(2.0, inner.size.y - hs.y - 2.0))
	_place_building(Rect2(hp, hs), rng.range_i(1, 3), MapDef.S_VILLA)
	# compound wall with a gate gap on a random side
	var gate := rng.range_i(0, 3)
	var c := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for side in 4:
		var a: Vector2 = c[side]
		var b: Vector2 = c[(side + 1) % 4]
		if side == gate:
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_add_wall(a, mid - dir * 2.2, MapDef.W_COMPOUND)
			_add_wall(mid + dir * 2.2, b, MapDef.W_COMPOUND)
		else:
			_add_wall(a, b, MapDef.W_COMPOUND)
	for k in rng.range_i(1, 3):
		var p := _rand_point(inner.grow(-1.5))
		if not Rect2(hp, hs).grow(1.0).has_point(p):
			_add_prop("palm" if rng.chance(0.5) else "tree", p, 0.0, rng.range_f(0.8, 1.25))


func _fill_industrial(r: Rect2) -> void:
	m.fill_rect_terrain(r, MapDef.T_DIRT)
	for lot in _split_row(r, 30.0, 48.0, r.size.x >= r.size.y):
		var inner := lot.grow(-3.0)
		if inner.size.x < 14 or inner.size.y < 14:
			continue
		var bs := Vector2(inner.size.x * rng.range_f(0.55, 0.85), inner.size.y * rng.range_f(0.5, 0.8))
		var bp := inner.position + Vector2(rng.range_f(0, inner.size.x - bs.x), rng.range_f(0, inner.size.y - bs.y))
		_place_building(Rect2(bp, bs), rng.range_i(1, 2), MapDef.S_INDUSTRIAL)
		for k in rng.range_i(1, 4):
			var p := _rand_point(inner)
			if not Rect2(bp, bs).grow(3.0).has_point(p):
				_add_prop(rng.pick(["container", "barrels", "crates", "tires", "car_wreck"]), p, rng.pick([0.0, PI * 0.5]) + rng.range_f(-0.1, 0.1))
	# perimeter fence
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for side in 4:
		var a: Vector2 = c[side]
		var b: Vector2 = c[(side + 1) % 4]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		_add_wall(a, mid - dir * 4.0, MapDef.W_COMPOUND)
		_add_wall(mid + dir * 4.0, b, MapDef.W_COMPOUND)


func _fill_edge(r: Rect2) -> void:
	# Spawn-side outskirts: farmland, scattered compounds, open approach.
	m.fill_rect_terrain(r, MapDef.T_FIELD if rng.chance(0.5) else MapDef.T_DIRT)
	var size := m.size_m()
	var spawn_band := r.get_center().y > size.y * 0.25 and r.get_center().y < size.y * 0.75
	for lot in _split_row(r, 28.0, 40.0, r.size.y > r.size.x):
		if lot.size.x < 14 or lot.size.y < 14:
			continue
		var near_edge := lot.position.x < 30.0 or lot.end.x > size.x - 30.0
		if spawn_band and near_edge:
			continue
		if rng.chance(0.35):
			_villa(lot)
		elif rng.chance(0.4):
			for k in rng.range_i(2, 5):
				_add_prop("tree" if rng.chance(0.6) else "palm", _rand_point(lot), 0.0, rng.range_f(0.8, 1.3))


func _vacant_lot(r: Rect2) -> void:
	if rng.chance(_war + 0.2):
		m.fill_rect_terrain(r, MapDef.T_RUBBLE)
		for k in rng.range_i(1, 3):
			_add_prop("rubble", _rand_point(r.grow(-1.0)), rng.range_f(0, TAU), rng.range_f(0.8, 1.4))
	else:
		m.fill_rect_terrain(r, MapDef.T_DIRT)
		if rng.chance(0.5):
			_add_prop("car_wreck", _rand_point(r.grow(-2.0)), rng.range_f(0, TAU))


func _courtyard_props(r: Rect2) -> void:
	if r.size.x < 4 or r.size.y < 4:
		return
	for k in rng.range_i(0, 2):
		_add_prop(rng.pick(["tree", "palm", "barrels", "crates"]), _rand_point(r.grow(-1.0)), rng.range_f(0, TAU))


func _central_plaza() -> void:
	var size := m.size_m()
	# plaza centered at the city center, cleared of earlier buildings
	var pr := Rect2(_center - Vector2(34, 30), Vector2(68, 60))
	_clear_area(pr.grow(2.0))
	m.fill_rect_terrain(pr, MapDef.T_PAVED)
	# mosque on the north edge of the plaza
	var mosque := Rect2(Vector2(_center.x - 12.0, pr.position.y + 2.0), Vector2(24, 22))
	_place_building(mosque, 3, MapDef.S_MOSQUE)
	# market stalls
	for k in 10:
		var p := Vector2(rng.range_f(pr.position.x + 4, pr.end.x - 4), rng.range_f(_center.y + 2, pr.end.y - 4))
		_add_prop("stall", p, rng.pick([0.0, PI * 0.5]))
	for k in 6:
		_add_prop("palm", Vector2(pr.position.x + 6 + k * 11.0, pr.end.y - 2.0), 0.0, 1.1)
	m.districts.append({"name": "Central Market", "rect": pr})


func _clear_area(r: Rect2) -> void:
	m.buildings = m.buildings.filter(func(b): return not r.intersects(Rect2(b["c"] - b["size"] * 0.5, b["size"])))
	m.walls = m.walls.filter(func(w): return not (r.has_point(w["a"]) or r.has_point(w["b"])))
	m.props = m.props.filter(func(p): return not r.has_point(p["p"]))


# ------------------------------------------------------------------ zones -----

func _spawn_zones(size: Vector2) -> void:
	var h := size.y * 0.38
	var y0 := size.y * 0.5 - h * 0.5
	var r0 := Rect2(6.0, y0, 34.0, h)
	var r1 := Rect2(size.x - 40.0, y0, 34.0, h)
	_clear_area(r0)
	_clear_area(r1)
	m.spawns = [{"team": 0, "rect": r0}, {"team": 1, "rect": r1}]
	# districts for naming
	m.districts.append({"name": "West Approach", "rect": Rect2(0, 0, _spawn_margin, size.y)})
	m.districts.append({"name": "East Approach", "rect": Rect2(size.x - _spawn_margin, 0, _spawn_margin, size.y)})
	var q := size * 0.5
	m.districts.append({"name": "Old Quarter", "rect": Rect2(_center.x + 10, _center.y - size.y * 0.36, size.x * 0.36, size.y * 0.36 - 10)})
	m.districts.append({"name": "Industrial Zone", "rect": Rect2(0, _center.y + 60, _center.x - 40, size.y - _center.y - 60)})
	m.districts.append({"name": "Northern District", "rect": Rect2(0, 0, size.x, q.y)})
	m.districts.append({"name": "Southern District", "rect": Rect2(0, q.y, size.x, q.y)})


func _objectives(size: Vector2) -> void:
	# One central objective, two per side; snapped to the nearest open intersection.
	var targets := [
		["Central Market", _center + Vector2(0, 12)],
		["", Vector2(size.x * 0.3, size.y * 0.25)],
		["", Vector2(size.x * 0.3, size.y * 0.75)],
		["", Vector2(size.x * 0.7, size.y * 0.25)],
		["", Vector2(size.x * 0.7, size.y * 0.75)],
	]
	var used: Array[Vector2] = []
	var letters := ["A", "B", "C", "D", "E"]
	for i in targets.size():
		var want: Vector2 = targets[i][1]
		var p := want
		if i > 0:
			var best := INF
			for c in _intersections:
				if c.x < _spawn_margin + 30 or c.x > size.x - _spawn_margin - 30:
					continue
				var too_close := false
				for u in used:
					if u.distance_to(c) < 90.0:
						too_close = true
				if too_close:
					continue
				var d := c.distance_to(want)
				if d < best:
					best = d
					p = c
		used.append(p)
		var nm: String = targets[i][0]
		if nm == "":
			var dist := _district_at(p, size)
			var suffix: String = ["Crossroads", "Junction", "Square", "Gate"][i % 4]
			nm = "%s %s" % [dist, suffix] if dist != D_OUTSKIRTS else "Outer %s" % suffix
		m.objectives.append({"id": letters[i], "name": nm, "p": p, "r": 16.0})
		_clear_area(Rect2(p - Vector2(9, 9), Vector2(18, 18)))
		# defensive dressing
		for k in rng.range_i(1, 3):
			var a := rng.range_f(0, TAU)
			var q := p + Vector2(cos(a), sin(a)) * rng.range_f(8, 13)
			_add_wall(q, q + Vector2(cos(a + PI * 0.5), sin(a + PI * 0.5)) * 3.5, MapDef.W_SANDBAG)


func _build_occupancy() -> void:
	_occ = PackedByteArray()
	_occ.resize(m.width * m.height)
	for b in m.buildings:
		for c in m.footprint_cells(b["c"], b["size"] + Vector2(1.0, 1.0), b["rot"]):
			_occ[c.y * m.width + c.x] = 1


func _decorate_streets() -> void:
	_build_occupancy()
	for r in m.roads:
		var a: Vector2 = r["a"]
		var b: Vector2 = r["b"]
		var w: float = r["w"]
		var kind: int = r["kind"]
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var length := a.distance_to(b)
		var step := 22.0 if kind == 0 else 30.0
		var t := rng.range_f(4.0, step)
		while t < length - 2.0:
			var p := a + dir * t
			if kind == 0:
				_try_prop("lamp", p + nrm * (w * 0.5 + 0.8), 0.0)
				_try_prop("lamp", p - nrm * (w * 0.5 + 0.8), 0.0)
				if rng.chance(0.5):
					_try_prop("palm", p + nrm * (w * 0.5 + 1.6), 0.0, rng.range_f(0.9, 1.2))
			elif kind == 1:
				_try_prop("pole", p + nrm * (w * 0.5 + 0.6), 0.0)
			# parked or wrecked vehicles along the curb
			if kind != 2 and rng.chance(0.4):
				var side := 1.0 if rng.chance(0.5) else -1.0
				var kindp := "car"
				var roll := rng.next_float()
				if roll < _war * 0.6:
					kindp = "car_wreck"
				elif roll < _war * 0.7 and kind == 0:
					kindp = "bus_wreck"
				var cp := p + nrm * side * (w * 0.5 - 1.3) + dir * rng.range_f(-4, 4)
				_try_prop(kindp, cp, dir.angle() + rng.range_f(-0.12, 0.12))
			if rng.chance(0.08 + _war * 0.1):
				_try_prop(rng.pick(["dumpster", "barrels", "tires", "rubble", "crates"]), p + nrm * (rng.range_f(-1, 1) * w * 0.5), rng.range_f(0, TAU))
			t += step * rng.range_f(0.6, 1.4)
		# occasional checkpoint barriers on avenues
		if kind == 0 and rng.chance(0.5):
			var cp := a + dir * rng.range_f(length * 0.2, length * 0.8)
			_try_prop("barrier", cp + nrm * 2.5, dir.angle() + PI * 0.5)
			_try_prop("barrier", cp - nrm * 2.0 + dir * 6.0, dir.angle() + PI * 0.5)


# ------------------------------------------------------------------ helpers ---

func _place_building(r: Rect2, floors: int, style: int) -> void:
	if r.size.x < 5.0 or r.size.y < 5.0:
		return
	# war damage: some buildings are already ruins, more are battle-scarred
	var b := _bdict(r, floors, style)
	if style != MapDef.S_MOSQUE and rng.chance(_war * 0.18):
		b["ruined"] = true
	elif rng.chance(_war * 0.35):
		b["damaged"] = true
	m.buildings.append(b)


func _bdict(r: Rect2, floors: int, style: int) -> Dictionary:
	_next_building_id += 1
	return {"id": _next_building_id, "c": r.get_center(), "size": r.size, "rot": 0.0, "floors": floors,
		"style": style, "color": rng.range_i(0, 7), "seed": rng.range_i(1, 1 << 30)}


func _add_wall(a: Vector2, b: Vector2, kind: int) -> void:
	if a.distance_to(b) < 0.8:
		return
	m.walls.append({"a": a, "b": b, "h": MapDef.WALL_HEIGHT[kind], "kind": kind})


func _add_prop(kind: String, p: Vector2, rot: float, s: float = 1.0) -> void:
	m.props.append({"kind": kind, "p": p, "rot": rot, "s": s})


## Add a prop only if it does not land inside a building footprint.
func _try_prop(kind: String, p: Vector2, rot: float, s: float = 1.0) -> void:
	var c := m.world_to_cell(p)
	if not m.in_bounds(c.x, c.y):
		return
	if not _occ.is_empty() and _occ[c.y * m.width + c.x] != 0:
		return
	_add_prop(kind, p, rot, s)


func _rand_point(r: Rect2) -> Vector2:
	return Vector2(rng.range_f(r.position.x, r.end.x), rng.range_f(r.position.y, r.end.y))

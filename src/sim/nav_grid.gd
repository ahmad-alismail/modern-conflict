extends RefCounted
## Derived simulation grids built from a MapDef:
##  - base layer: obstacle bitmask per movement class, LOS obstacle height, building index, cover sources
##  - derived layer: inflated solids for vehicles, path weights, cover values
##  - one AStarGrid2D per ground movement class (pathfinding runs in C++)
## Supports runtime changes (building collapse -> rubble, vehicle wrecks).
class_name NavGrid

const B_FOOT := 1
const B_WHEELED := 2
const B_TRACKED := 4
const B_ALL := 7
const RUBBLE_H := 1.6
const CLASS_BIT := [B_FOOT, B_WHEELED, B_TRACKED]

var map: MapDef
var w := 0
var h := 0
var cell := MapDef.CELL
# base layer
var block := PackedByteArray()        # bitmask of blocked classes (raw, uninflated)
var height := PackedFloat32Array()    # LOS obstacle top height (m)
var bld := PackedInt32Array()         # building index (into map.buildings) or -1
var cover_src := PackedByteArray()    # cover provided by an object in this cell
# derived layer
var solid := PackedByteArray()        # bitmask of classes that cannot enter (inflated for vehicles)
var cover := PackedByteArray()        # 0 none, 1 light, 2 heavy
var astar: Array[AStarGrid2D] = []


func _init(m: MapDef) -> void:
	map = m
	w = m.width
	h = m.height
	var n := w * h
	block.resize(n)
	height.resize(n)
	bld.resize(n)
	bld.fill(-1)
	cover_src.resize(n)
	solid.resize(n)
	cover.resize(n)
	for i in 3:
		var a := AStarGrid2D.new()
		a.region = Rect2i(0, 0, w, h)
		a.cell_size = Vector2.ONE
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.update()
		astar.append(a)
	_build_base()
	_derive(0, 0, w - 1, h - 1)


func _build_base() -> void:
	for i in w * h:
		if map.terrain[i] == MapDef.T_WATER:
			block[i] = B_ALL
	for bi in map.buildings.size():
		var b: Dictionary = map.buildings[bi]
		var bh := map.building_height(b)
		for c in map.footprint_cells(b["c"], b["size"], b["rot"]):
			var i := c.y * w + c.x
			block[i] = B_ALL
			height[i] = maxf(height[i], bh)
			bld[i] = bi
	for wl in map.walls:
		var kind: int = wl["kind"]
		var mask := B_ALL
		var cv := 0
		match kind:
			MapDef.W_LOW:
				mask = B_WHEELED | B_TRACKED
				cv = 2
			MapDef.W_SANDBAG:
				mask = B_WHEELED
				cv = 2
			MapDef.W_HESCO:
				mask = B_ALL
		_raster_segment(wl["a"], wl["b"], func(i: int):
			block[i] |= mask
			height[i] = maxf(height[i], wl["h"])
			cover_src[i] = maxi(cover_src[i], cv))
	for p in map.props:
		var spec: Dictionary = MapDef.PROPS.get(p["kind"], {})
		if spec.is_empty():
			continue
		var dims: Vector2 = spec["dims"] * float(p["s"])
		var cells := map.footprint_cells(p["p"], dims, p["rot"])
		if cells.is_empty():
			var c := map.world_to_cell(p["p"])
			if map.in_bounds(c.x, c.y):
				cells.append(c)
		for c in cells:
			var i := c.y * w + c.x
			block[i] |= int(spec["block"])
			height[i] = maxf(height[i], float(spec["h"]))
			cover_src[i] = maxi(cover_src[i], int(spec["cover"]))


func _raster_segment(a: Vector2, b: Vector2, fn: Callable) -> void:
	var length := a.distance_to(b)
	var steps := maxi(1, int(ceil(length / (cell * 0.4))))
	var last := -1
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		var c := map.world_to_cell(p)
		if not map.in_bounds(c.x, c.y):
			continue
		var i := c.y * w + c.x
		if i != last:
			fn.call(i)
			last = i


## Recompute derived data (solids with vehicle clearance, weights, cover) in a cell region.
func _derive(x0: int, y0: int, x1: int, y1: int) -> void:
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, w - 1)
	y1 = mini(y1, h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * w + x
			var raw := block[i]
			var s := raw & B_FOOT
			# vehicles need one cell of clearance from anything that blocks them
			var veh := raw & (B_WHEELED | B_TRACKED)
			var cv := cover_src[i]
			for dy in range(-1, 2):
				var yy := y + dy
				if yy < 0 or yy >= h:
					veh |= B_WHEELED | B_TRACKED
					continue
				for dx in range(-1, 2):
					var xx := x + dx
					if xx < 0 or xx >= w:
						veh |= B_WHEELED | B_TRACKED
						continue
					var j := yy * w + xx
					veh |= block[j] & (B_WHEELED | B_TRACKED)
					if j != i:
						if block[j] & B_FOOT and height[j] > 1.5:
							cv = 2
						elif cover_src[j] > cv:
							cv = cover_src[j]
			if map.terrain[i] == MapDef.T_RUBBLE and cv < 1:
				cv = 1
			if raw & B_FOOT:
				cv = 0
			s |= veh
			solid[i] = s
			cover[i] = cv
			var t := map.terrain[i]
			var pos := Vector2i(x, y)
			for k in 3:
				var blocked: bool = (s & CLASS_BIT[k]) != 0
				astar[k].set_point_solid(pos, blocked)
				if not blocked:
					astar[k].set_point_weight_scale(pos, _weight(k, t))


static func _weight(k: int, t: int) -> float:
	match k:
		Defs.MOVE_FOOT:
			if t == MapDef.T_RUBBLE: return 1.35
			if t == MapDef.T_FIELD: return 1.1
			return 1.0
		Defs.MOVE_WHEELED:
			match t:
				MapDef.T_ROAD: return 1.0
				MapDef.T_PAVED: return 1.1
				MapDef.T_FIELD: return 2.0
				MapDef.T_GRASS: return 1.7
				MapDef.T_RUBBLE: return 3.0
				_: return 1.5
		_:
			if t == MapDef.T_RUBBLE: return 1.3
			if t == MapDef.T_ROAD: return 1.0
			return 1.1


## Speed multiplier for a movement class on the terrain under `p`.
func speed_mult(k: int, p: Vector2) -> float:
	if k == Defs.MOVE_AIR:
		return 1.0
	var c := map.world_to_cell(p)
	if not map.in_bounds(c.x, c.y):
		return 1.0
	var t := map.terrain[c.y * w + c.x]
	match k:
		Defs.MOVE_WHEELED:
			if t == MapDef.T_ROAD or t == MapDef.T_PAVED: return 1.0
			if t == MapDef.T_RUBBLE: return 0.45
			return 0.7
		Defs.MOVE_TRACKED:
			return 0.85 if t == MapDef.T_RUBBLE else 1.0
		_:
			return 0.8 if t == MapDef.T_RUBBLE else 1.0


# ----------------------------------------------------------------- queries ----

func idx_of(p: Vector2) -> int:
	var cx := clampi(int(p.x / cell), 0, w - 1)
	var cy := clampi(int(p.y / cell), 0, h - 1)
	return cy * w + cx


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / cell), 0, w - 1), clampi(int(p.y / cell), 0, h - 1))


func is_open(k: int, p: Vector2) -> bool:
	if k == Defs.MOVE_AIR:
		return true
	return (solid[idx_of(p)] & CLASS_BIT[k]) == 0


func is_open_cell(k: int, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return false
	return (solid[c.y * w + c.x] & CLASS_BIT[k]) == 0


func cover_at(p: Vector2) -> int:
	return cover[idx_of(p)]


func building_at(p: Vector2) -> int:
	return bld[idx_of(p)]


func obstacle_height(p: Vector2) -> float:
	return height[idx_of(p)]


func nearest_open(k: int, c: Vector2i, max_r: int = 14) -> Vector2i:
	if is_open_cell(k, c):
		return c
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cc := c + Vector2i(dx, dy)
				if is_open_cell(k, cc):
					return cc
	return c


func nearest_open_point(k: int, p: Vector2) -> Vector2:
	if k == Defs.MOVE_AIR or is_open(k, p):
		return p
	return map.cell_center(nearest_open(k, cell_of(p)))


## World-space path from `from` to `to` for movement class k (smoothed). Empty if unreachable.
func find_path(k: int, from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if k == Defs.MOVE_AIR:
		out.append(to)
		return out
	var fc := nearest_open(k, cell_of(from))
	var tc := nearest_open(k, cell_of(to))
	var target := to if is_open(k, to) else map.cell_center(tc)
	if fc == tc:
		out.append(target)
		return out
	var ids := astar[k].get_id_path(fc, tc, true)
	if ids.is_empty():
		return out
	var pts := PackedVector2Array()
	for c in ids:
		pts.append(map.cell_center(c))
	pts[pts.size() - 1] = target if ids[ids.size() - 1] == tc else pts[pts.size() - 1]
	# greedy string pulling
	var cur := from
	var i := 0
	while i < pts.size():
		var best := i
		var j := mini(pts.size() - 1, i + 24)
		while j > i:
			if line_open(k, cur, pts[j]):
				best = j
				break
			j -= 1
		out.append(pts[best])
		cur = pts[best]
		i = best + 1
	return out


## True if a straight move from a to b stays in open cells for class k.
func line_open(k: int, a: Vector2, b: Vector2) -> bool:
	var bit: int = CLASS_BIT[k]
	var dist := a.distance_to(b)
	var steps := maxi(1, int(ceil(dist / (cell * 0.5))))
	for s in range(1, steps + 1):
		var p := a.lerp(b, float(s) / steps)
		if solid[idx_of(p)] & bit:
			return false
	return true


## Grid line of sight between two points with eye/target heights.
## Cells belonging to buildings `ign_a` / `ign_b` are ignored (garrisoned units).
func los(a: Vector2, ha: float, b: Vector2, hb: float, ign_a: int = -1, ign_b: int = -1) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 0.01:
		return true
	var x := int(a.x / cell)
	var y := int(a.y / cell)
	var tx := int(b.x / cell)
	var ty := int(b.y / cell)
	var step_x := 1 if d.x > 0 else -1
	var step_y := 1 if d.y > 0 else -1
	var inv_x := INF if absf(d.x) < 1e-6 else absf(cell / d.x)
	var inv_y := INF if absf(d.y) < 1e-6 else absf(cell / d.y)
	var next_x := INF if absf(d.x) < 1e-6 else (((x + (1 if step_x > 0 else 0)) * cell - a.x) / d.x)
	var next_y := INF if absf(d.y) < 1e-6 else (((y + (1 if step_y > 0 else 0)) * cell - a.y) / d.y)
	var guard := 0
	while guard < 1024:
		guard += 1
		var t := minf(next_x, next_y)
		if next_x < next_y:
			x += step_x
			next_x += inv_x
		else:
			y += step_y
			next_y += inv_y
		if t >= 1.0 or (x == tx and y == ty):
			return true
		if x < 0 or y < 0 or x >= w or y >= h:
			return true
		var i := y * w + x
		var oh := height[i]
		if oh <= 0.0:
			continue
		var bi := bld[i]
		if bi >= 0 and (bi == ign_a or bi == ign_b):
			continue
		var line_h := ha + (hb - ha) * t
		if oh > line_h:
			return false
	return true


# ------------------------------------------------------------- dynamic edits --

## Building collapse: footprint becomes rubble (passable on foot/tracks, low LOS block).
func collapse_building(bi: int) -> void:
	var b: Dictionary = map.buildings[bi]
	var cells := map.footprint_cells(b["c"], b["size"], b["rot"])
	var x0 := w
	var y0 := h
	var x1 := 0
	var y1 := 0
	for c in cells:
		var i := c.y * w + c.x
		block[i] = B_WHEELED
		height[i] = RUBBLE_H
		bld[i] = -1
		cover_src[i] = 1
		map.terrain[i] = MapDef.T_RUBBLE
		x0 = mini(x0, c.x)
		y0 = mini(y0, c.y)
		x1 = maxi(x1, c.x)
		y1 = maxi(y1, c.y)
	if cells.size() > 0:
		_derive(x0 - 2, y0 - 2, x1 + 2, y1 + 2)


## Vehicle wreck: blocks vehicles, provides heavy cover, partially blocks LOS.
func add_wreck(p: Vector2, radius: float) -> void:
	var c0 := cell_of(p - Vector2.ONE * radius)
	var c1 := cell_of(p + Vector2.ONE * radius)
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			if map.cell_center(Vector2i(x, y)).distance_to(p) <= radius + cell * 0.5:
				var i := y * w + x
				block[i] |= B_WHEELED | B_TRACKED
				height[i] = maxf(height[i], 1.8)
				cover_src[i] = 2
	_derive(c0.x - 2, c0.y - 2, c1.x + 2, c1.y + 2)

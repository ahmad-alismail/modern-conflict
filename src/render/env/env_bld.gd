extends RefCounted
## Per-building construction context for BuildingBuilder. Builds facades as a wall skin
## (bands + piers, `r` m thick) over a dark core, so every opening is a real recess with
## reveals, sill and lintel; then fills openings (glazing, shutters, doors, shopfronts,
## arches, balconies) and dresses roofs. Deterministic from b.seed: `rng` drives the
## intact design, `drng` only damage, so a damaged rebuild matches the intact building.
## Facade frame: side 0 faces +Z, 1 +X, 2 -Z, 3 -X; u runs left to right seen from
## outside, y up, d outward from the wall plane (negative = into the recess).
class_name EnvBld

const FH := MapDef.FLOOR_H

# facade-local face bits for fbox()
const FRONT := 1
const BACK := 2
const LEFT := 4
const RIGHT := 8
const TOP := 16
const BOT := 32
const BOX5 := 61   # all but BACK

# opening kinds
const O_WIN := 0
const O_DOOR := 1
const O_SHOP := 2
const O_BALC := 3
const O_ARCH := 4
const O_ARCHDOOR := 5
const O_GARAGE := 6
const O_RIBBON := 7
const O_LOBBY := 8

# facade planners
const P_OLD := 0
const P_APT := 1
const P_SHOP := 2
const P_VILLA := 3
const P_RIBBON := 4
const P_PODIUM := 5
const P_WORKSHOP := 6
const P_MOSQUE := 7
const P_KIOSK := 8
const P_BLANK := 9

const _SIDE_BITS := [[EnvGeo.PZ, EnvGeo.NZ, EnvGeo.NX, EnvGeo.PX], [EnvGeo.PX, EnvGeo.NX, EnvGeo.PZ, EnvGeo.NZ],
	[EnvGeo.NZ, EnvGeo.PZ, EnvGeo.PX, EnvGeo.NX], [EnvGeo.NX, EnvGeo.PX, EnvGeo.NZ, EnvGeo.PZ]]

const PLASTER_COLS := [Color(0.8, 0.76, 0.68), Color(0.78, 0.68, 0.54), Color(0.74, 0.62, 0.46), Color(0.76, 0.58, 0.38),
	Color(0.68, 0.66, 0.62), Color(0.82, 0.74, 0.58), Color(0.76, 0.62, 0.54), Color(0.7, 0.66, 0.52)]
const STONE_COLS := [Color(0.8, 0.72, 0.58), Color(0.78, 0.68, 0.52), Color(0.74, 0.64, 0.48), Color(0.78, 0.64, 0.44),
	Color(0.7, 0.67, 0.61), Color(0.82, 0.75, 0.6), Color(0.75, 0.65, 0.55), Color(0.68, 0.64, 0.55)]
const SHUTTER_COLS := [Color(0.38, 0.52, 0.42), Color(0.36, 0.46, 0.58), Color(0.56, 0.57, 0.56), Color(0.56, 0.34, 0.27),
	Color(0.74, 0.65, 0.38), Color(0.76, 0.76, 0.73), Color(0.3, 0.5, 0.52), Color(0.45, 0.45, 0.47)]
const SIGN_COLS := [Color(0.78, 0.2, 0.16), Color(0.16, 0.52, 0.27), Color(0.17, 0.32, 0.66), Color(0.92, 0.76, 0.18),
	Color(0.92, 0.92, 0.9), Color(0.92, 0.52, 0.16), Color(0.14, 0.14, 0.15), Color(0.55, 0.2, 0.45)]
const GLASS_COLS := [Color(0.3, 0.35, 0.38), Color(0.31, 0.37, 0.36), Color(0.26, 0.31, 0.37), Color(0.35, 0.36, 0.37)]
const CURTAIN_COLS := [Color(0.85, 0.82, 0.74), Color(0.8, 0.72, 0.6), Color(0.7, 0.3, 0.25), Color(0.4, 0.5, 0.65),
	Color(0.9, 0.88, 0.84), Color(0.6, 0.65, 0.45)]
const FRAME_COLS := [Color(0.86, 0.86, 0.83), Color(0.62, 0.64, 0.65), Color(0.27, 0.19, 0.13), Color(0.14, 0.14, 0.14)]
const WOOD_COLS := [Color(0.36, 0.23, 0.13), Color(0.22, 0.36, 0.27), Color(0.22, 0.31, 0.46), Color(0.45, 0.3, 0.17),
	Color(0.3, 0.42, 0.42)]
const TANK_COLS := [Color(0.08, 0.08, 0.085), Color(0.08, 0.08, 0.085), Color(0.86, 0.86, 0.84), Color(0.2, 0.33, 0.58),
	Color(0.82, 0.74, 0.45), Color(0.08, 0.08, 0.085)]
const CLOTH_COLS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.8), Color(0.95, 0.95, 0.92), Color(0.9, 0.75, 0.2),
	Color(0.3, 0.6, 0.35), Color(0.6, 0.3, 0.6), Color(0.15, 0.15, 0.18)]

var b: Dictionary
var rng: Rng
var drng: Rng
var damage := 0
var g := EnvGeo.new()     # main mesh
var dt := EnvGeo.new()    # small clutter, visibility-ranged
## Discard buffer: damage-removed parts are still generated here so the design rng
## sequence (and thus the intact building) is identical in damaged rebuilds.
var junk := EnvGeo.new()
var W := 10.0
var D := 10.0
var F := 1
var H := 4.2
var style := 0
var plan_mode := P_APT
var rh := FH              # row (floor) height of the current body
var y_base := 0.0         # bottom of the current body

# look
var r := 0.22
var wall_rgb := Color(0.8, 0.75, 0.65)
var wall_surf := EnvGeo.PLASTER
var wall := Color()
var trim := Color()
var base_c := Color()
var roof_c := Color()
var void_c := Color()
var frame_c := Color()
var glass_rgb := Color()
var shutter_rgb := Color()
var wood_rgb := Color()
var metal_c := Color()
var win_style := 0        # 0 aluminium + roller shutter, 1 wooden louvre shutters, 2 plain
var win_w := 1.3
var sill := 0.9
var head := 2.3
var bay := 3.3
var balc_p := 0.0
var shutter_p := 0.6
var grime_p := 0.5
var ac_p := 0.2
var grille_p := 0.0
var lintels := false       # protruding lintel / hood over rectangular windows
var mashra_p := 0.0
var arch_p := 0.0
var slab_lines := false
var blank_sides := 0      # sides without openings (party walls)
var shop_sides := 0       # SHOP: sides with shopfronts
var entry_side := 0
## Sides that may carry deep protrusions (balconies, bays, goods). Attached row buildings
## keep their party-wall sides flush so nothing pokes into the neighbour.
var street := 15
var ablaq := false

var ops_log: Array = []   # [Rect2, side, u0, u1, y0, y1, kind]
var holes_cut := 0        # real shell holes cut by damaged bodies
var _holes := {}          # side -> Array[Rect2] (u, y) of the current body
var roofs: Array = []     # [Rect2, roof_y]
var _cols_cache := {}
var _side_rng := {}
var _balc_cache := {}
static var _md: MapDef

# current frame
var _rect := Rect2()
var _o: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _t: Array = [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]
var _n: Array = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
var _w := PackedFloat32Array([1, 1, 1, 1])


func _init(bd: Dictionary, dmg: int = 0) -> void:
	b = bd
	damage = dmg
	var sd: int = b.get("seed", 1)
	rng = Rng.new(sd)
	drng = Rng.new(sd ^ 0x5bd1e995)
	var sz: Vector2 = b["size"]
	W = sz.x
	D = sz.y
	F = maxi(1, int(b.get("floors", 1)))
	style = int(b.get("style", 0))
	if _md == null:
		_md = MapDef.new(1, 1)
	H = _md.building_height(b)


# ------------------------------------------------------------------ helpers ----

static func enc(rgb: Color, surf: int) -> Color:
	return EnvGeo.c(rgb, surf)


static func shade(col: Color, k: float) -> Color:
	return Color(col.r * k, col.g * k, col.b * k, col.a)


func jit(col: Color, amt: float) -> Color:
	var k := 1.0 + rng.range_f(-amt, amt)
	return Color(clampf(col.r * k, 0, 1), clampf(col.g * k, 0, 1), clampf(col.b * k, 0, 1), col.a)


func pick_col(arr: Array) -> Color:
	return arr[rng.range_i(0, arr.size() - 1)]


func set_frame(rect: Rect2) -> void:
	_rect = rect
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.end.x
	var z1 := rect.end.y
	_o = [Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x0, 0, z0)]
	_w = PackedFloat32Array([rect.size.x, rect.size.y, rect.size.x, rect.size.y])


func fw(s: int) -> float:
	return _w[s]


func fp(s: int, u: float, y: float, d: float) -> Vector3:
	return (_o[s] as Vector3) + (_t[s] as Vector3) * u + (_n[s] as Vector3) * d + Vector3(0, y, 0)


func fnormal(s: int) -> Vector3:
	return _n[s]


## Facade-space box: u0..u1 along, y0..y1 up, d0..d1 outward. fm: FRONT/BACK/LEFT/RIGHT/TOP/BOT.
func fbox(geo: EnvGeo, s: int, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, col: Color, fm: int) -> void:
	var bits: Array = _SIDE_BITS[s]
	var m := 0
	if fm & FRONT: m |= int(bits[0])
	if fm & BACK: m |= int(bits[1])
	if fm & LEFT: m |= int(bits[2])
	if fm & RIGHT: m |= int(bits[3])
	if fm & TOP: m |= EnvGeo.PY
	if fm & BOT: m |= EnvGeo.NY
	geo.boxmm(fp(s, u0, y0, d0), fp(s, u1, y1, d1), col, m)


## Facade-space quad facing outward at depth d.
func fquad(geo: EnvGeo, s: int, u0: float, u1: float, y0: float, y1: float, d: float, col: Color) -> void:
	geo.quad(fp(s, u0, y0, d), fp(s, u1, y0, d), fp(s, u1, y1, d), fp(s, u0, y1, d), col)


## Quad oriented so its normal points toward `toward`.
static func quadf(geo: EnvGeo, a: Vector3, bb: Vector3, c: Vector3, d: Vector3, col: Color, toward: Vector3) -> void:
	if (bb - a).cross(c - a).dot(toward) >= 0.0:
		geo.quad(a, bb, c, d, col)
	else:
		geo.quad(a, d, c, bb, col)


## Jagged star-shaped patch on a facade (holes, soot, exposed masonry).
func fstar(geo: EnvGeo, s: int, uc: float, yc: float, ru: float, ry: float, d: float, col: Color, n: int, jag: float, ytop: float) -> void:
	var pts := PackedVector3Array()
	var w := fw(s)
	pts.append(fp(s, clampf(uc, 0.05, w - 0.05), clampf(yc, 0.05, ytop), d))
	var first := Vector3.ZERO
	for i in n:
		var a := TAU * float(i) / n
		var k := 1.0 + drng.range_f(-jag, jag)
		var u := clampf(uc + cos(a) * ru * k, 0.03, w - 0.03)
		var y := clampf(yc + sin(a) * ry * k, 0.03, ytop)
		var pnt := fp(s, u, y, d)
		if i == 0:
			first = pnt
		pts.append(pnt)
	pts.append(first)
	geo.poly(pts, col)


func occupied(rects: Array, rc: Rect2) -> bool:
	for o in rects:
		if (o as Rect2).intersects(rc):
			return true
	return false


# ------------------------------------------------------------------ look -------

## Default palette for plastered / stone-clad concrete buildings.
func setup_look(stone_p: float) -> void:
	var ci: int = int(b.get("color", 0)) % 8
	if rng.chance(stone_p):
		wall_surf = EnvGeo.STONE
		wall_rgb = jit(STONE_COLS[ci], 0.04)
	else:
		wall_surf = EnvGeo.PLASTER
		wall_rgb = jit(PLASTER_COLS[ci], 0.04)
	wall = enc(wall_rgb, wall_surf)
	var tr := wall_rgb.lerp(Color(0.9, 0.88, 0.84), 0.45) if rng.chance(0.6) else wall_rgb.darkened(0.12)
	trim = enc(tr, EnvGeo.CONCRETE if wall_surf == EnvGeo.PLASTER else EnvGeo.STONE)
	base_c = enc(wall_rgb.darkened(rng.range_f(0.25, 0.4)), EnvGeo.STONE)
	var rpick := rng.range_i(0, 9)
	var rcol: Color = [Color(0.66, 0.63, 0.58), Color(0.66, 0.63, 0.58), Color(0.62, 0.6, 0.57), Color(0.76, 0.74, 0.7),
		Color(0.7, 0.64, 0.54), Color(0.36, 0.34, 0.32), Color(0.58, 0.56, 0.54), Color(0.68, 0.6, 0.5),
		Color(0.72, 0.69, 0.63), Color(0.64, 0.58, 0.5)][rpick]
	roof_c = enc(jit(rcol, 0.05), EnvGeo.ROOF | (EnvGeo.FLAG if rpick >= 7 else 0))
	void_c = enc(Color(0.05, 0.045, 0.04), EnvGeo.VOID)
	frame_c = enc(pick_col(FRAME_COLS), EnvGeo.METAL)
	glass_rgb = pick_col(GLASS_COLS)
	shutter_rgb = pick_col(SHUTTER_COLS)
	wood_rgb = pick_col(WOOD_COLS)
	metal_c = enc(Color(0.2, 0.2, 0.21), EnvGeo.METAL)


# ------------------------------------------------------------------ body -------

## Wall skin with recessed openings over a dark core plus a roof slab, `floors` rows of
## height `row_h` from `y0`, parapet `par` above the roof. Returns the roof height.
func body(rect: Rect2, y0: float, floors: int, par: float, mode: int, row_h: float = FH) -> float:
	set_frame(rect)
	plan_mode = mode
	rh = row_h
	y_base = y0
	_cols_cache = {}
	_balc_cache = {}
	var roof_y := y0 + floors * row_h
	var top := roof_y + par
	var ctr := rect.get_center()
	var cx := rect.size.x - 2.0 * r
	var cz := rect.size.y - 2.0 * r
	g.box(Vector3(ctr.x, (y0 + roof_y) * 0.5, ctr.y), Vector3(cx, roof_y - y0, cz), void_c, EnvGeo.SIDES)
	g.box(Vector3(ctr.x, roof_y - 0.05, ctr.y), Vector3(cx + 0.01, 0.1, cz + 0.01), roof_c, EnvGeo.PY)
	_holes = {}
	if damage > 0:
		_plan_holes(y0, roof_y)
	for s in 4:
		var rows: Array = []
		for k in floors:
			rows.append(_plan(s, k))
		_skin(s, y0, rows, roof_y, top)
		if slab_lines:
			for k in range(1, floors):
				var ys := y0 + k * row_h
				wbox(s, 0.0, fw(s), ys - 0.12, ys + 0.06, 0.0, 0.05, trim, BOX5)
		for h in _holes.get(s, []):
			_hole_dressing(s, h, y0, floors)
	roofs.append([Rect2(rect.position + Vector2(r, r), rect.size - Vector2(2.0 * r, 2.0 * r)), roof_y])
	return roof_y


func _skin(s: int, y0: float, rows: Array, roof_y: float, top: float) -> void:
	var w := fw(s)
	var band0 := y0
	for k in rows.size():
		var yb := y0 + k * rh
		var row: Dictionary = rows[k]
		var ops: Array = row["ops"]
		var hd: float = row["head"]
		var sp := hd
		for op in ops:
			sp = minf(sp, float(op["y0"]))
		if yb + sp > band0 + 0.005:
			wbox(s, 0.0, w, band0, yb + sp, -r, 0.0, wall, FRONT | TOP | (BOT if band0 > y0 + 0.01 else 0))
		if ops.is_empty():
			band0 = maxf(band0, yb + hd)
			continue
		var cu := 0.0
		for op in ops:
			var u0: float = op["u0"]
			var u1: float = op["u1"]
			if u0 > cu + 0.005:
				wbox(s, cu, u0, yb + sp, yb + hd, -r, 0.0, wall, FRONT | RIGHT | (LEFT if cu > 0.0 else 0))
			var oy: float = op["y0"]
			if oy > sp + 0.005:
				wbox(s, u0, u1, yb + sp, yb + oy, -r, 0.0, wall, FRONT | TOP)
			var kind: int = op["kind"]
			if kind == O_ARCH or kind == O_ARCHDOOR:
				_arch_fill(s, u0, u1, yb + hd)
			cu = u1
		if cu < w - 0.005:
			wbox(s, cu, w, yb + sp, yb + hd, -r, 0.0, wall, FRONT | LEFT)
		for op in ops:
			var in_hole := _in_hole(s, (float(op["u0"]) + float(op["u1"])) * 0.5, yb + (float(op["y0"]) + hd) * 0.5)
			var keep_g := g
			var keep_dt := dt
			if in_hole:
				g = junk
				dt = junk
			_fill(s, op, yb, hd)
			g = keep_g
			dt = keep_dt
		band0 = yb + hd
	_parapet(s, band0, roof_y, top)


func _parapet(s: int, y_from: float, roof_y: float, top: float) -> void:
	var w := fw(s)
	if top <= y_from + 0.005:
		return
	var bot := BOT if y_from > y_base + 0.01 else 0
	if damage == 0 or top - roof_y < 0.3:
		fbox(g, s, 0.0, w, y_from, top, -r, 0.0, wall, FRONT | BACK | TOP | bot)
		if top - roof_y > 0.2:
			fbox(g, s, 0.0, w, top, top + 0.07, -r - 0.03, 0.04, trim, FRONT | BACK | TOP | BOT)
		return
	if roof_y > y_from + 0.005:
		wbox(s, 0.0, w, y_from, roof_y, -r, 0.0, wall, FRONT | bot)
	var u := 0.0
	while u < w - 0.01:
		var sw := minf(drng.range_f(0.7, 2.6), w - u)
		var roll := drng.next_float()
		var ht := top
		if roll < 0.2:
			ht = roof_y + 0.04
		elif roll < 0.5:
			ht = roof_y + (top - roof_y) * drng.range_f(0.2, 0.7)
		fbox(g, s, u, u + sw, roof_y, ht, -r, 0.0, wall, FRONT | BACK | TOP | LEFT | RIGHT)
		if ht >= top - 0.01:
			fbox(g, s, u, u + sw, top, top + 0.07, -r - 0.03, 0.04, trim, FRONT | BACK | TOP | BOT | LEFT | RIGHT)
		u += sw


# ------------------------------------------------------------------ shell holes -

## Choose blown-out shell holes per side for a damaged body (drng only).
func _plan_holes(y0: float, roof_y: float) -> void:
	for s in 4:
		var w := fw(s)
		var hh := roof_y - y0
		if w < 4.0 or hh < 2.5:
			continue
		var n := drng.range_i(0, clampi(int(w * hh / 70.0), 1, 3) + (damage - 1))
		var list: Array = []
		for i in n:
			var hw := drng.range_f(1.3, minf(3.2, w * 0.35))
			var ht := drng.range_f(1.2, minf(2.6, hh * 0.6))
			var u := drng.range_f(0.9, maxf(1.0, w - hw - 0.9))
			var y := drng.range_f(y0 + 0.6, maxf(y0 + 0.7, roof_y - ht - 0.2))
			var rc := Rect2(u, y, hw, ht)
			var ok := true
			for o in list:
				if (o as Rect2).grow(0.6).intersects(rc):
					ok = false
			if ok:
				list.append(rc)
		if not list.is_empty():
			_holes[s] = list
			holes_cut += list.size()


func _in_hole(s: int, u: float, y: float) -> bool:
	for h in _holes.get(s, []):
		if (h as Rect2).grow(0.25).has_point(Vector2(u, y)):
			return true
	return false


## Wall-skin box that leaves this side's shell holes open (with reveal faces).
func wbox(s: int, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, col: Color, fm: int, hi: int = 0) -> void:
	var hs: Array = _holes.get(s, [])
	for i in range(hi, hs.size()):
		var h: Rect2 = hs[i]
		if u1 <= h.position.x or u0 >= h.end.x or y1 <= h.position.y or y0 >= h.end.y:
			continue
		var hu0 := maxf(u0, h.position.x)
		var hu1 := minf(u1, h.end.x)
		var hy0 := maxf(y0, h.position.y)
		var hy1 := minf(y1, h.end.y)
		var keep_l := fm & LEFT if hu0 <= u0 + 0.001 else 0
		var keep_r := fm & RIGHT if hu1 >= u1 - 0.001 else 0
		var mid := fm & ~(LEFT | RIGHT | TOP | BOT)
		if hu0 > u0 + 0.001:
			wbox(s, u0, hu0, y0, y1, d0, d1, col, fm | RIGHT, i + 1)
		if hu1 < u1 - 0.001:
			wbox(s, hu1, u1, y0, y1, d0, d1, col, fm | LEFT, i + 1)
		if hy0 > y0 + 0.001:
			wbox(s, hu0, hu1, y0, hy0, d0, d1, col, mid | (fm & BOT) | TOP | keep_l | keep_r, i + 1)
		if hy1 < y1 - 0.001:
			wbox(s, hu0, hu1, hy1, y1, d0, d1, col, mid | (fm & TOP) | BOT | keep_l | keep_r, i + 1)
		return
	fbox(g, s, u0, u1, y0, y1, d0, d1, col, fm)


static func _rect_r(hw: float, hh: float, a: float) -> float:
	var cx := absf(cos(a))
	var sy := absf(sin(a))
	return minf(hw / maxf(cx, 1e-3), hh / maxf(sy, 1e-3))


## Jagged broken edge, soot, broken slab, rebar and debris around a shell hole.
func _hole_dressing(s: int, h: Rect2, y0: float, floors: int) -> void:
	var c := h.get_center()
	var hw := h.size.x * 0.5
	var hh := h.size.y * 0.5
	var n := 18
	var exposed := enc(Color(0.6, 0.56, 0.5), EnvGeo.RUBBLE)
	var soot := enc(Color(0.07, 0.065, 0.06), EnvGeo.VOID)
	var w := fw(s)
	var pin: Array = []
	var pout: Array = []
	var psoot: Array = []
	for i in n:
		var a := TAU * i / n
		var rr := _rect_r(hw, hh, a)
		var dir := Vector2(cos(a), sin(a))
		var up := 1.0 + 0.7 * maxf(sin(a), 0.0)
		pin.append(c + dir * rr * drng.range_f(0.82, 0.98))
		pout.append(c + dir * rr * drng.range_f(1.02, 1.22))
		psoot.append(c + dir * rr * drng.range_f(1.5, 1.9) * up)
	for i in n:
		var j := (i + 1) % n
		var a0: Vector2 = pin[i]
		var a1: Vector2 = pin[j]
		var b0: Vector2 = pout[i]
		var b1: Vector2 = pout[j]
		var s0: Vector2 = psoot[i]
		var s1: Vector2 = psoot[j]
		quadf(g, _fpc(s, a0, 0.03), _fpc(s, a1, 0.03), _fpc(s, b1, 0.03), _fpc(s, b0, 0.03), exposed, fnormal(s))
		var q := [_fpc(s, b0, 0.02), _fpc(s, b1, 0.02), _fpc(s, s1, 0.02), _fpc(s, s0, 0.02)]
		if ((q[1] as Vector3) - q[0]).cross((q[2] as Vector3) - q[0]).dot(fnormal(s)) >= 0.0:
			g.quad4(q[0], q[1], q[2], q[3], soot, soot, wall, wall)
		else:
			g.quad4(q[0], q[3], q[2], q[1], soot, wall, wall, soot)
	# broken floor slab across the hole
	for k in range(1, floors + 1):
		var yf := y0 + k * rh
		if yf > h.position.y + 0.3 and yf < h.end.y - 0.3:
			var cc := enc(Color(0.6, 0.59, 0.56), EnvGeo.CONCRETE)
			var u := h.position.x
			while u < h.end.x - 0.2:
				var pw := minf(drng.range_f(0.5, 1.2), h.end.x - u)
				if drng.chance(0.65):
					var sag := drng.range_f(-0.35, 0.05)
					var bas := Basis(_t[s] as Vector3, drng.range_f(-0.25, 0.25))
					var ctr := fp(s, u + pw * 0.5, yf - 0.1 + sag * 0.5, -r * 0.5 + 0.05)
					g.obox(Transform3D(bas, ctr), Vector3(absf((_t[s] as Vector3).x) * pw + absf((_n[s] as Vector3).x) * (r + 0.35),
						0.2, absf((_t[s] as Vector3).z) * pw + absf((_n[s] as Vector3).z) * (r + 0.35)), cc, EnvGeo.ALL)
				u += pw
	var rc := enc(Color(0.3, 0.17, 0.1), EnvGeo.RUST)
	for k in drng.range_i(3, 6):
		var a := drng.range_f(0, TAU)
		var p2 := c + Vector2(cos(a), sin(a)) * _rect_r(hw, hh, a) * 0.92
		var pa := _fpc(s, p2, 0.0)
		var tip := pa + fnormal(s) * drng.range_f(0.05, 0.3) + Vector3(0, -drng.range_f(0.2, 0.7), 0) + (_t[s] as Vector3) * (-cos(a) * 0.25)
		dt.beam(pa, tip, 0.022, 0.022, rc)
	_debris(s, clampf(c.x, 0.5, w - 0.5), hw * 1.4)


func _fpc(s: int, p: Vector2, d: float) -> Vector3:
	return fp(s, clampf(p.x, 0.02, fw(s) - 0.02), clampf(p.y, y_base + 0.02, H + 0.5), d)


## Solid wall fill between an arch curve and the row head (front face + intrados).
func _arch_fill(s: int, u0: float, u1: float, yh: float) -> void:
	var R := (u1 - u0) * 0.5
	var uc := (u0 + u1) * 0.5
	var ys := yh - R
	var seg := 8
	var ctr := fp(s, uc, ys, -r * 0.5)
	for i in seg:
		var t0 := PI - PI * float(i) / seg
		var t1 := PI - PI * float(i + 1) / seg
		var ua := uc + cos(t0) * R
		var ub := uc + cos(t1) * R
		var ya := ys + sin(t0) * R
		var yb := ys + sin(t1) * R
		g.quad(fp(s, ua, ya, 0.0), fp(s, ub, yb, 0.0), fp(s, ub, yh, 0.0), fp(s, ua, yh, 0.0), wall)
		quadf(g, fp(s, ua, ya, 0.0), fp(s, ub, yb, 0.0), fp(s, ub, yb, -r), fp(s, ua, ya, -r), wall,
			ctr - fp(s, (ua + ub) * 0.5, (ya + yb) * 0.5, -r * 0.5))


## Ring of voussoirs around an arch (alternating colors = ablaq).
func _voussoirs(s: int, u0: float, u1: float, yh: float, ca: Color, cb: Color) -> void:
	var R := (u1 - u0) * 0.5
	var uc := (u0 + u1) * 0.5
	var ys := yh - R
	var seg := 9
	var wr := clampf(R * 0.35, 0.16, 0.32)
	for i in seg:
		var t0 := PI - PI * float(i) / seg
		var t1 := PI - PI * float(i + 1) / seg
		var col := ca if i % 2 == 0 else cb
		quadf(g, fp(s, uc + cos(t0) * R, ys + sin(t0) * R, 0.02), fp(s, uc + cos(t1) * R, ys + sin(t1) * R, 0.02),
			fp(s, uc + cos(t1) * (R + wr), ys + sin(t1) * (R + wr), 0.02),
			fp(s, uc + cos(t0) * (R + wr), ys + sin(t0) * (R + wr), 0.02), col, fnormal(s))
	# reveal edges of the voussoir ring
	fbox(g, s, u0 - wr, u0, ys - 0.12, ys, 0.0, 0.02, ca, FRONT | TOP)
	fbox(g, s, u1, u1 + wr, ys - 0.12, ys, 0.0, 0.02, ca, FRONT | TOP)


## Semicircular fan (fanlights, tympana) facing outward.
func _fan(geo: EnvGeo, s: int, uc: float, ys: float, R: float, d: float, col: Color) -> void:
	var pts := PackedVector3Array()
	pts.append(fp(s, uc, ys, d))
	var seg := 8
	for i in seg + 1:
		var t := PI * float(i) / seg
		pts.append(fp(s, uc + cos(t) * R, ys + sin(t) * R, d))
	geo.poly(pts, col)


# ------------------------------------------------------------------ planners ---

func _op(uc: float, w: float, y0: float, kind: int) -> Dictionary:
	return {"u0": uc - w * 0.5, "u1": uc + w * 0.5, "y0": y0, "kind": kind}


## Regular bay centers on a side (cached so every floor lines up).
func bay_cols(s: int, bw: float, margin: float, ww: float) -> Array:
	if _cols_cache.has(s):
		return _cols_cache[s]
	var w := fw(s)
	var out: Array = []
	var avail := w - 2.0 * margin
	if avail >= ww + 0.4:
		var n := maxi(1, int(floor(avail / bw)))
		var step := avail / n
		for i in n:
			out.append(margin + step * (i + 0.5))
	_cols_cache[s] = out
	return out


## Per-side stable random stream (balcony columns etc.), independent of floor order.
func side_rng(s: int) -> Rng:
	if not _side_rng.has(s):
		_side_rng[s] = Rng.new(int(b.get("seed", 1)) * 7 + s * 131 + plan_mode * 17)
	return _side_rng[s]


func _plan(s: int, k: int) -> Dictionary:
	if blank_sides & (1 << s):
		return {"ops": [], "head": rh * 0.7}
	match plan_mode:
		P_OLD: return _plan_old(s, k)
		P_APT: return _plan_apt(s, k)
		P_SHOP: return _plan_shop(s, k)
		P_VILLA: return _plan_villa(s, k)
		P_RIBBON: return {"ops": [{"u0": 0.6, "u1": fw(s) - 0.6, "y0": 0.95, "kind": O_RIBBON}], "head": 2.95}
		P_PODIUM: return _plan_podium(s, k)
		P_WORKSHOP: return _plan_workshop(s, k)
		P_MOSQUE: return _plan_mosque(s, k)
		P_KIOSK: return _plan_kiosk(s)
	return {"ops": [], "head": rh * 0.7}


func _plan_apt(s: int, k: int) -> Dictionary:
	var cols := bay_cols(s, bay, 0.9, win_w)
	var ops: Array = []
	var ground := k == 0 and y_base < 0.01
	if not _balc_cache.has(s):
		var sr := side_rng(s)
		var bc := {}
		var long_side := fw(s) >= maxf(W, D) - 0.5
		for i in cols.size():
			bc[i] = sr.chance(balc_p * (1.0 if long_side else 0.4))
		_balc_cache[s] = bc
	var balc: Dictionary = _balc_cache[s]
	var entry := -1
	if ground and s == entry_side and not cols.is_empty():
		entry = cols.size() / 2
	for i in cols.size():
		var uc: float = cols[i]
		if i == entry:
			var op := _op(uc, 1.5, 0.0, O_DOOR)
			op["canopy"] = true
			ops.append(op)
		elif ground:
			var op := _op(uc, win_w, sill + 0.25, O_WIN)
			op["grille"] = rng.chance(0.6)
			ops.append(op)
		elif balc.get(i, false):
			var op := _op(uc, 1.0, 0.0, O_BALC)
			op["bw"] = minf(bay - 0.5, 3.0)
			op["french"] = not (street & (1 << s))
			ops.append(op)
		else:
			ops.append(_op(uc, win_w, sill, O_WIN))
	return {"ops": ops, "head": head}


func _plan_shop(s: int, k: int) -> Dictionary:
	if k > 0 or y_base > 0.01 or not (shop_sides & (1 << s)):
		return _plan_apt(s, k)
	var w := fw(s)
	var ops: Array = []
	var n := maxi(1, int(floor((w - 0.8) / 3.6)))
	var step := (w - 0.8) / n
	var door_i := rng.range_i(0, n - 1) if s == entry_side else -1
	for i in n:
		var uc := 0.4 + step * (i + 0.5)
		if i == door_i:
			ops.append(_op(uc, 1.2, 0.0, O_DOOR))
			continue
		var op := _op(uc, step - 0.55, 0.0, O_SHOP)
		ops.append(op)
	return {"ops": ops, "head": 2.9}


func _plan_old(s: int, k: int) -> Dictionary:
	var w := fw(s)
	var ops: Array = []
	if k == 0 and y_base < 0.01:
		var hd := 2.9
		var used: Array = []
		if s == entry_side and w > 3.0:
			var dw := rng.range_f(1.2, 1.6)
			var uc := rng.range_f(0.8 + dw * 0.5, w - 0.8 - dw * 0.5)
			var op := _op(uc, dw, 0.0, O_ARCHDOOR)
			hd = 2.1 + dw * 0.5
			ops.append(op)
			used.append(Vector2(uc - dw * 0.5 - 0.6, uc + dw * 0.5 + 0.6))
		elif rng.chance(0.3) and w > 4.0 and (street & (1 << s)) != 0:
			var sw := rng.range_f(2.2, 3.0)
			var uc := rng.range_f(0.6 + sw * 0.5, w - 0.6 - sw * 0.5)
			var op := _op(uc, sw, 0.0, O_SHOP)
			ops.append(op)
			used.append(Vector2(uc - sw * 0.5 - 0.5, uc + sw * 0.5 + 0.5))
		for j in rng.range_i(0, 2):
			var ww := rng.range_f(0.55, 0.8)
			var uc := rng.range_f(0.6 + ww, w - 0.6 - ww)
			var bad := false
			for u in used:
				if uc + ww > (u as Vector2).x and uc - ww < (u as Vector2).y:
					bad = true
			if bad:
				continue
			var op := _op(uc, ww, hd - rng.range_f(0.75, 1.0), O_WIN)
			op["grille"] = true
			ops.append(op)
			used.append(Vector2(uc - ww - 0.4, uc + ww + 0.4))
		ops.sort_custom(func(a, c): return a["u0"] < c["u0"])
		return {"ops": ops, "head": hd}
	var hd2 := head
	var used2: Array = []
	var nwin := rng.range_i(1, maxi(1, int(w / 3.2)))
	for j in nwin:
		var ww := rng.range_f(0.75, 1.1)
		var uc := rng.range_f(0.7 + ww, w - 0.7 - ww)
		var bad := false
		for u in used2:
			if uc + ww * 1.2 > (u as Vector2).x and uc - ww * 1.2 < (u as Vector2).y:
				bad = true
		if bad:
			continue
		var arch := rng.chance(arch_p)
		var op := _op(uc, ww, hd2 - rng.range_f(1.15, 1.5) - (ww * 0.5 if arch else 0.0), O_ARCH if arch else O_WIN)
		op["mashra"] = rng.chance(mashra_p) and (street & (1 << s)) != 0
		ops.append(op)
		used2.append(Vector2(uc - ww, uc + ww))
	ops.sort_custom(func(a, c): return a["u0"] < c["u0"])
	return {"ops": ops, "head": hd2}


func _plan_villa(s: int, k: int) -> Dictionary:
	var cols := bay_cols(s, bay, 1.0, win_w)
	var ops: Array = []
	var ground := k == 0 and y_base < 0.01
	var entry := cols.size() / 2 if ground and s == entry_side and not cols.is_empty() else -1
	var arch := arch_p > 0.5
	for i in cols.size():
		var uc: float = cols[i]
		if i == entry:
			var op := _op(uc, 1.6, 0.0, O_ARCHDOOR if arch else O_DOOR)
			op["portico"] = true
			ops.append(op)
		elif not ground and s == entry_side and i == cols.size() / 2 and balc_p > 0.0:
			var op := _op(uc, 1.2, 0.0, O_BALC)
			op["bw"] = minf(bay - 0.3, 3.4)
			op["dep"] = 1.2
			ops.append(op)
		else:
			ops.append(_op(uc, win_w, sill, O_ARCH if arch else O_WIN))
	return {"ops": ops, "head": 2.6}


func _plan_podium(s: int, k: int) -> Dictionary:
	var w := fw(s)
	var ops: Array = []
	if k == 0:
		var n := maxi(1, int(floor((w - 0.8) / 3.0)))
		var step := (w - 0.8) / n
		for i in n:
			ops.append(_op(0.4 + step * (i + 0.5), step - 0.45, 0.0, O_LOBBY))
		return {"ops": ops, "head": 2.95}
	ops.append({"u0": 0.5, "u1": w - 0.5, "y0": 0.9, "kind": O_RIBBON})
	return {"ops": ops, "head": 2.8}


func _plan_workshop(s: int, k: int) -> Dictionary:
	var w := fw(s)
	var ops: Array = []
	if k == 0 and (s == entry_side or s == (entry_side + 2) % 4) and w > 6.0:
		var n := clampi(int(w / 9.0), 1, 3)
		var step := w / n
		for i in n:
			var uc := step * (i + 0.5)
			ops.append(_op(uc, minf(4.2, step - 1.6), 0.0, O_GARAGE))
		return {"ops": ops, "head": 3.9}
	var cols := bay_cols(s, 4.0, 1.0, 1.4)
	for uc in cols:
		ops.append(_op(uc, 1.6, 2.4 if k == 0 else 1.2, O_WIN))
	return {"ops": ops, "head": 3.5}


func _plan_mosque(s: int, k: int) -> Dictionary:
	var cols := bay_cols(s, 3.0, 1.2, 1.2)
	var ops: Array = []
	var mid := cols.size() / 2
	for i in cols.size():
		var uc: float = cols[i]
		if k == 0 and s == entry_side and i == mid:
			ops.append(_op(uc, 2.0, 0.0, O_ARCHDOOR))
		elif k == 0:
			var op := _op(uc, 1.1, 0.7, O_WIN)
			op["grille"] = true
			ops.append(op)
		elif k == 1:
			ops.append(_op(uc, 1.2, 0.3, O_ARCH))
		else:
			ops.append(_op(uc, 0.8, 0.9, O_ARCH))
	return {"ops": ops, "head": 3.0 if k == 0 else 2.7}


func _plan_kiosk(s: int) -> Dictionary:
	var w := fw(s)
	if s == entry_side and w > 1.6:
		return {"ops": [_op(w * 0.5, 0.9, 0.0, O_DOOR)], "head": 2.1}
	if w > 2.4 and rng.chance(0.4):
		return {"ops": [_op(w * 0.5, 0.6, 1.3, O_WIN)], "head": 1.9}
	return {"ops": [], "head": 2.1}


# ------------------------------------------------------------------ openings ---

func _fill(s: int, op: Dictionary, yb: float, hd: float) -> void:
	var u0: float = op["u0"]
	var u1: float = op["u1"]
	var y0: float = yb + float(op["y0"])
	var y1: float = yb + hd
	var kind: int = op["kind"]
	ops_log.append([_rect, s, u0, u1, y0, y1, kind])
	match kind:
		O_WIN: _window(s, u0, u1, y0, y1, op)
		O_ARCH: _arch_window(s, u0, u1, y0, y1)
		O_DOOR: _door(s, u0, u1, y0, y1, op)
		O_ARCHDOOR: _arch_door(s, u0, u1, y0, y1, op)
		O_SHOP: _shop(s, u0, u1, y0, y1)
		O_BALC: _balcony(s, u0, u1, y0, y1, op)
		O_GARAGE: _garage(s, u0, u1, y0, y1)
		O_RIBBON: _ribbon(s, u0, u1, y0, y1)
		O_LOBBY: _lobby(s, u0, u1, y0, y1)


## Glazing; some panes show drawn curtains (lighter, tinted glass over the fabric).
func _glass(geo: EnvGeo, s: int, u0: float, u1: float, y0: float, y1: float, d: float) -> void:
	var gr := glass_rgb.lightened(rng.range_f(-0.08, 0.1))
	var gc := enc(gr, EnvGeo.GLASS)
	var roll := rng.next_float()
	if roll > 0.5 or y1 - y0 < 0.4:
		fquad(geo, s, u0, u1, y0, y1, d, gc)
		return
	var cc := enc(gr.lerp(pick_col(CURTAIN_COLS), 0.55), EnvGeo.GLASS)
	if roll < 0.2:
		fquad(geo, s, u0, u1, y0, y1, d, cc)
	elif roll < 0.35:
		var ym := lerpf(y0, y1, rng.range_f(0.3, 0.7))
		fquad(geo, s, u0, u1, y0, ym, d, gc)
		fquad(geo, s, u0, u1, ym, y1, d, cc)
	else:
		var um := lerpf(u0, u1, rng.range_f(0.3, 0.7))
		fquad(geo, s, u0, um, y0, y1, d, cc)
		fquad(geo, s, um, u1, y0, y1, d, gc)


func _sill(s: int, u0: float, u1: float, y0: float) -> void:
	fbox(g, s, u0 - 0.06, u1 + 0.06, y0 - 0.05, y0, -r, 0.05, trim, BOX5)


## Soft V-shaped grime stain running down from a sill.
func _streak(s: int, uc: float, wd: float, ytop: float, len: float) -> void:
	var dark := shade(wall, rng.range_f(0.68, 0.8))
	var ybot := maxf(ytop - len, y_base + 0.05)
	var d := 0.006
	var hw := wd * 0.5
	g.quad4(fp(s, uc - hw, ybot, d), fp(s, uc, ybot, d), fp(s, uc, ytop, d), fp(s, uc - hw, ytop, d), wall, wall, dark, wall)
	g.quad4(fp(s, uc, ybot, d), fp(s, uc + hw, ybot, d), fp(s, uc + hw, ytop, d), fp(s, uc, ytop, d), wall, wall, wall, dark)


## Soot plume rising from an opening (damage).
func _soot_up(s: int, uc: float, wd: float, ybot: float, len: float) -> void:
	var dark := enc(Color(0.06, 0.055, 0.05), EnvGeo.VOID)
	var clear := wall
	var d := 0.008
	var hw := wd * 0.5
	var ytop := minf(ybot + len, H)
	g.quad4(fp(s, uc - hw, ybot, d), fp(s, uc, ybot, d), fp(s, uc, ytop, d), fp(s, uc - hw * 0.6, ytop, d), clear, dark, clear, clear)
	g.quad4(fp(s, uc, ybot, d), fp(s, uc + hw, ybot, d), fp(s, uc + hw * 0.6, ytop, d), fp(s, uc, ytop, d), dark, clear, clear, clear)


func _window(s: int, u0: float, u1: float, y0: float, y1: float, op: Dictionary) -> void:
	var broken := damage > 0 and drng.chance(0.7)
	var uc := (u0 + u1) * 0.5
	if op.get("mashra", false):
		_mashrabiya(s, u0, u1, y0, y1)
		return
	fquad(g, s, u0, u1, y0, y1, -r + 0.015, frame_c)
	_glass(junk if broken else g, s, u0 + 0.06, u1 - 0.06, y0 + 0.06, y1 - 0.06, -r + 0.03)
	if u1 - u0 > 0.85:
		fquad(g, s, uc - 0.025, uc + 0.025, y0, y1, -r + 0.04, frame_c)
	_sill(s, u0, u1, y0)
	if lintels:
		fbox(g, s, u0 - 0.08, u1 + 0.08, y1, y1 + 0.11, 0.0, 0.045, trim, BOX5)
	match win_style:
		0:
			if rng.chance(shutter_p):
				fbox(g, s, u0, u1, y1 - 0.2, y1, -r, -0.025, shade(enc(shutter_rgb, EnvGeo.METAL), 0.9), FRONT | BOT)
				var f: float = [0.0, 0.15, 0.3, 0.55, 0.85, 1.0][rng.range_i(0, 5)]
				if f > 0.01:
					fquad(g, s, u0 + 0.01, u1 - 0.01, y1 - 0.2 - (y1 - 0.2 - y0) * f, y1 - 0.2, -r + 0.09, enc(shutter_rgb, EnvGeo.SHUTTER))
		1:
			var st := rng.next_float()
			var hw := (u1 - u0) * 0.5
			var wc := enc(wood_rgb, EnvGeo.SHUTTER)
			if st < 0.45:
				fbox(g, s, u0 - hw - 0.03, u0 - 0.03, y0, y1, 0.0, 0.035, wc, BOX5)
				fbox(g, s, u1 + 0.03, u1 + hw + 0.03, y0, y1, 0.0, 0.035, wc, BOX5)
			elif st < 0.78:
				fquad(g, s, u0 + 0.03, u1 - 0.03, y0 + 0.02, y1 - 0.02, -r + 0.07, wc)
				fquad(g, s, uc - 0.012, uc + 0.012, y0 + 0.02, y1 - 0.02, -r + 0.075, shade(wc, 0.4))
	if op.get("grille", false) or rng.chance(grille_p):
		_grille(s, u0, u1, y0, y1)
	if wall_surf != EnvGeo.CONCRETE and rng.chance(grime_p):
		_streak(s, uc, u1 - u0 + 0.25, y0 - 0.05, rng.range_f(0.7, 1.8))
	if rng.chance(ac_p) and y0 > 1.5:
		_ac_facade(s, uc + rng.range_f(-0.2, 0.2) + (u1 - u0) * 0.5 + 0.55 * (1.0 if rng.chance(0.5) else -1.0), y0 - 0.15)
	if damage > 0 and broken and drng.chance(0.35):
		_soot_up(s, uc, u1 - u0 + 0.6, y1, drng.range_f(1.2, 2.6))


func _grille(s: int, u0: float, u1: float, y0: float, y1: float) -> void:
	var n := maxi(2, int((u1 - u0) / 0.13))
	var gc := enc(Color(0.12, 0.12, 0.12), EnvGeo.METAL)
	for i in n:
		var u := u0 + (u1 - u0) * (i + 0.5) / n
		fbox(dt, s, u - 0.012, u + 0.012, y0, y1, -0.07, -0.045, gc, FRONT | LEFT | RIGHT)
	for y in [y0 + 0.12, y1 - 0.12]:
		fbox(dt, s, u0, u1, y - 0.015, y + 0.015, -0.075, -0.04, gc, FRONT | TOP | BOT)


func _mashrabiya(s: int, u0: float, u1: float, y0: float, y1: float) -> void:
	var wc := enc(wood_rgb.darkened(0.25), EnvGeo.WOOD)
	var lat := enc(wood_rgb.darkened(0.1), EnvGeo.MESH | EnvGeo.FLAG)
	var a0 := u0 - 0.3
	var a1 := u1 + 0.3
	var yb := y0 - 0.25
	var yt := minf(y1 + 0.35, yb + 2.6)
	var dp := 0.55
	fquad(g, s, u0, u1, y0, y1, -r + 0.015, void_c)
	fbox(g, s, a0, a1, yb, yt, 0.0, dp, wc, FRONT | LEFT | RIGHT | BOT)
	fquad(g, s, a0 + 0.07, a1 - 0.07, yb + 0.35, yt - 0.12, dp + 0.005, lat)
	fbox(g, s, a0 - 0.06, a1 + 0.06, yt, yt + 0.1, -0.02, dp + 0.08, wc, BOX5)
	fbox(g, s, a0, a1, yb + 0.28, yb + 0.33, dp, dp + 0.03, wc, BOX5)
	for k in 3:
		var u := a0 + 0.15 + (a1 - a0 - 0.3) * k / 2.0
		g.taper(fp(s, u, yb - 0.45, 0.0) + fnormal(s) * 0.02, 0.1, 0.1, 0.1, 0.1, 0.45, wc, EnvGeo.ALL)
		fbox(g, s, u - 0.05, u + 0.05, yb - 0.12, yb, 0.0, dp * 0.8, wc, BOX5)


func _arch_window(s: int, u0: float, u1: float, y0: float, y1: float) -> void:
	var R := (u1 - u0) * 0.5
	var uc := (u0 + u1) * 0.5
	var ys := y1 - R
	var broken := damage > 0 and drng.chance(0.7)
	fquad(g, s, u0, u1, y0, ys, -r + 0.015, frame_c)
	_fan(g, s, uc, ys, R, -r + 0.015, frame_c)
	var gc := enc(glass_rgb.lightened(rng.range_f(0.0, 0.12)), EnvGeo.GLASS)
	var gg := junk if broken else g
	_glass(gg, s, u0 + 0.06, u1 - 0.06, y0 + 0.06, ys, -r + 0.03)
	_fan(gg, s, uc, ys, R - 0.06, -r + 0.03, gc)
	fquad(g, s, u0, u1, ys - 0.025, ys + 0.025, -r + 0.04, frame_c)
	_sill(s, u0, u1, y0)
	if win_style == 1 and rng.chance(0.4):
		var wc := enc(wood_rgb, EnvGeo.SHUTTER)
		fquad(g, s, u0 + 0.03, u1 - 0.03, y0 + 0.02, ys, -r + 0.07, wc)
	if wall_surf == EnvGeo.STONE or ablaq:
		_voussoirs(s, u0, u1, y1, trim, base_c if ablaq and u1 - u0 > 1.4 else trim)
	elif rng.chance(0.6):
		_voussoirs(s, u0, u1, y1, trim, trim)
	if wall_surf != EnvGeo.CONCRETE and rng.chance(grime_p):
		_streak(s, uc, u1 - u0 + 0.25, y0 - 0.05, rng.range_f(0.7, 1.6))


func _door(s: int, u0: float, u1: float, y0: float, y1: float, op: Dictionary) -> void:
	var leaf_top := minf(y1 - 0.06, y0 + 2.2)
	var dc := enc(wood_rgb if win_style == 1 else Color(0.32, 0.3, 0.28).lerp(wood_rgb, 0.3), EnvGeo.WOOD if win_style == 1 else EnvGeo.METAL)
	fquad(g, s, u0, u1, y0, y1, -r + 0.015, frame_c)
	if y1 - leaf_top > 0.25:
		_glass(g, s, u0 + 0.06, u1 - 0.06, leaf_top + 0.05, y1 - 0.06, -r + 0.03)
	fquad(g, s, u0 + 0.05, u1 - 0.05, y0, leaf_top, -r + 0.04, dc)
	var uc := (u0 + u1) * 0.5
	if u1 - u0 > 1.1:
		fquad(g, s, uc - 0.015, uc + 0.015, y0, leaf_top, -r + 0.045, shade(dc, 0.4))
		_glass(g, s, u0 + 0.15, uc - 0.12, y0 + 1.1, leaf_top - 0.15, -r + 0.045)
		_glass(g, s, uc + 0.12, u1 - 0.15, y0 + 1.1, leaf_top - 0.15, -r + 0.045)
	else:
		fquad(g, s, u0 + 0.15, u1 - 0.15, y0 + 0.2, y0 + 0.9, -r + 0.045, shade(dc, 0.82))
		fquad(g, s, u0 + 0.15, u1 - 0.15, y0 + 1.1, leaf_top - 0.15, -r + 0.045, shade(dc, 0.82))
	if y0 < 0.05:
		fbox(g, s, u0 - 0.25, u1 + 0.25, 0.0, 0.16, 0.0, 0.5, base_c, FRONT | TOP | LEFT | RIGHT)
	if op.get("canopy", false):
		fbox(g, s, u0 - 0.5, u1 + 0.5, y1 + 0.12, y1 + 0.28, 0.0, 1.1, trim, BOX5)
	if op.get("portico", false):
		_portico(s, u0, u1, y1)


func _portico(s: int, u0: float, u1: float, y1: float) -> void:
	var dp := 1.45
	var top := y1 + 0.5
	fbox(g, s, u0 - 0.9, u1 + 0.9, top, top + 0.3, 0.0, dp, trim, BOX5)
	fbox(g, s, u0 - 1.0, u1 + 1.0, top + 0.3, top + 0.38, 0.0, dp + 0.08, trim, BOX5)
	for u in [u0 - 0.65, u1 + 0.65]:
		var p := fp(s, u, 0.0, dp - 0.3)
		g.box(p + Vector3(0, 0.1, 0), Vector3(0.45, 0.2, 0.45), base_c, EnvGeo.NO_BOTTOM)
		g.cyl(p + Vector3(0, 0.2, 0), 0.16, top - 0.4, trim, 10, 0)
		g.box(p + Vector3(0, top - 0.1, 0), Vector3(0.38, 0.2, 0.38), trim, EnvGeo.NO_BOTTOM | EnvGeo.NY)
	fbox(g, s, u0 - 0.9, u1 + 0.9, 0.0, 0.18, 0.0, dp + 0.15, base_c, FRONT | TOP | LEFT | RIGHT)


func _arch_door(s: int, u0: float, u1: float, y0: float, y1: float, op: Dictionary) -> void:
	var R := (u1 - u0) * 0.5
	var uc := (u0 + u1) * 0.5
	var ys := y1 - R
	var dc := enc(wood_rgb, EnvGeo.WOOD)
	fquad(g, s, u0, u1, y0, ys, -r + 0.015, shade(dc, 0.55))
	_fan(g, s, uc, ys, R, -r + 0.015, enc(wood_rgb.darkened(0.2), EnvGeo.MESH | EnvGeo.FLAG))
	fquad(g, s, u0 + 0.05, u1 - 0.05, y0, ys - 0.05, -r + 0.04, dc)
	fquad(g, s, uc - 0.015, uc + 0.015, y0, ys - 0.05, -r + 0.045, shade(dc, 0.35))
	# studded panels
	for y in [y0 + 0.5, y0 + 1.3]:
		fquad(g, s, u0 + 0.15, uc - 0.1, y, y + 0.6, -r + 0.045, shade(dc, 0.8))
		fquad(g, s, uc + 0.1, u1 - 0.15, y, y + 0.6, -r + 0.045, shade(dc, 0.8))
	var ca := trim
	var cb := base_c if (ablaq or wall_surf == EnvGeo.STONE) else trim
	_voussoirs(s, u0, u1, y1, ca, cb)
	if y0 < 0.05:
		fbox(g, s, u0 - 0.3, u1 + 0.3, 0.0, 0.14, 0.0, 0.45, base_c, FRONT | TOP | LEFT | RIGHT)
	if op.get("portico", false):
		_portico(s, u0, u1, y1)


func _shop(s: int, u0: float, u1: float, y0: float, y1: float) -> void:
	var sc := pick_col(SHUTTER_COLS).lerp(Color(0.6, 0.6, 0.58), rng.range_f(0.1, 0.45))
	var hb := 0.32
	fbox(g, s, u0, u1, y1 - hb, y1, -r, -0.02, enc(sc.darkened(0.15), EnvGeo.METAL), FRONT | BOT)
	var f: float = [0.0, 0.0, 0.3, 0.6, 1.0, 1.0, 1.0][rng.range_i(0, 6)]
	if damage > 0 and drng.chance(0.4):
		f = 0.0
	var ybot := y1 - hb - (y1 - hb - y0) * f
	if f > 0.01:
		fquad(g, s, u0 + 0.02, u1 - 0.02, ybot, y1 - hb, -r + 0.1, enc(sc, EnvGeo.SHUTTER))
	if f < 0.95:
		fquad(g, s, u0 + 0.02, u1 - 0.02, y0, ybot, -r + 0.02, enc(Color(0.07, 0.06, 0.05), EnvGeo.VOID))
	# goods stacked out on the pavement (always rolled so the rng stream is stable)
	var shop_dt := dt if f < 0.95 and damage == 0 else junk
	var crate := enc(Color(0.55, 0.42, 0.28), EnvGeo.WOOD)
	for i in rng.range_i(1, 4):
		var gw := rng.range_f(0.45, 0.7)
		var gu := rng.range_f(u0 + gw * 0.5, u1 - gw * 0.5)
		var gh := rng.range_f(0.3, 0.8)
		var gd := rng.range_f(0.5, 0.8)
		fbox(shop_dt, s, gu - gw * 0.5, gu + gw * 0.5, 0.0, gh, 0.15, gd, crate, BOX5 | BACK)
		fbox(shop_dt, s, gu - gw * 0.5 + 0.03, gu + gw * 0.5 - 0.03, gh, gh + 0.08, 0.18, gd - 0.03,
			enc(pick_col([Color(0.85, 0.45, 0.1), Color(0.75, 0.12, 0.1), Color(0.4, 0.6, 0.2), Color(0.85, 0.75, 0.3)]), EnvGeo.VOID), TOP | FRONT)
	# signboard with suggestive lettering
	if rng.chance(0.85):
		var sh := rng.range_f(0.55, 0.85)
		var sgc := pick_col(SIGN_COLS).lerp(Color(0.7, 0.68, 0.62), rng.range_f(0.05, 0.35))
		var ya := y1 + 0.1
		fbox(g, s, u0 - 0.1, u1 + 0.1, ya, ya + sh, 0.0, 0.1, enc(sgc, EnvGeo.METAL), BOX5)
		var lc := enc(Color(0.95, 0.95, 0.92) if sgc.get_luminance() < 0.55 else Color(0.1, 0.1, 0.1), EnvGeo.METAL)
		var u := u0 + rng.range_f(0.1, 0.4)
		var lh := sh * rng.range_f(0.35, 0.55)
		while u < u1 - 0.3:
			var lw := rng.range_f(0.12, 0.45)
			fquad(dt, s, u, minf(u + lw, u1 - 0.1), ya + (sh - lh) * 0.5, ya + (sh + lh) * 0.5, 0.104, lc)
			u += lw + rng.range_f(0.06, 0.2)
	if damage > 0 and drng.chance(0.4):
		_soot_up(s, (u0 + u1) * 0.5, u1 - u0, y1, drng.range_f(1.5, 3.0))


func _garage(s: int, u0: float, u1: float, y0: float, y1: float) -> void:
	var sc := pick_col(SHUTTER_COLS).lerp(Color(0.55, 0.56, 0.55), 0.4)
	fbox(g, s, u0, u1, y1 - 0.4, y1, -r, -0.03, enc(sc.darkened(0.2), EnvGeo.METAL), FRONT | BOT)
	var f: float = [1.0, 1.0, 0.7, 0.3][rng.range_i(0, 3)]
	if damage > 0 and drng.chance(0.5):
		f = drng.range_f(0.0, 0.5)
	var ybot := y1 - 0.4 - (y1 - 0.4 - y0) * f
	fquad(g, s, u0 + 0.02, u1 - 0.02, ybot, y1 - 0.4, -r + 0.1, enc(sc, EnvGeo.SHUTTER))
	var yc := enc(Color(0.85, 0.7, 0.15), EnvGeo.METAL)
	fbox(g, s, u0 - 0.12, u0, y0, y1, 0.0, 0.08, yc, BOX5)
	fbox(g, s, u1, u1 + 0.12, y0, y1, 0.0, 0.08, yc, BOX5)


func _ribbon(s: int, u0: float, u1: float, y0: float, y1: float) -> void:
	var gc := enc(glass_rgb, EnvGeo.GLASS | EnvGeo.FLAG)
	if damage == 0:
		fquad(g, s, u0, u1, y0, y1, -r + 0.03, gc)
		return
	var u := u0
	while u < u1 - 0.01:
		var pw := minf(1.5, u1 - u)
		if not drng.chance(0.45):
			fquad(g, s, u, u + pw, y0, y1, -r + 0.03, gc)
		u += pw


func _lobby(s: int, u0: float, u1: float, y0: float, y1: float) -> void:
	var gc := enc(glass_rgb.lightened(0.12), EnvGeo.GLASS)
	fquad(g, s, u0, u1, y0, y1, -r + 0.015, enc(Color(0.12, 0.12, 0.13), EnvGeo.METAL))
	if damage == 0 or not drng.chance(0.6):
		fquad(g, s, u0 + 0.05, u1 - 0.05, y0 + 0.05, y1 - 0.05, -r + 0.03, gc)
	fquad(g, s, u0, u1, y0 + 2.3, y0 + 2.36, -r + 0.04, enc(Color(0.12, 0.12, 0.13), EnvGeo.METAL))
	if rng.chance(0.3):
		var sgc := pick_col(SIGN_COLS)
		fbox(g, s, u0, u1, y1 + 0.1, y1 + 0.6, 0.0, 0.08, enc(sgc, EnvGeo.METAL), BOX5)


func _balcony(s: int, u0: float, u1: float, y0: float, y1: float, op: Dictionary) -> void:
	var uc := (u0 + u1) * 0.5
	var bw: float = op.get("bw", 2.4)
	var dep: float = op.get("dep", rng.range_f(0.9, 1.25))
	var b0 := uc - bw * 0.5
	var b1 := uc + bw * 0.5
	fquad(g, s, u0, u1, y0, y1, -r + 0.015, frame_c)
	_glass(g if damage == 0 or drng.chance(0.4) else junk, s, u0 + 0.06, u1 - 0.06, y0 + 0.05, y1 - 0.06, -r + 0.03)
	fquad(g, s, uc - 0.025, uc + 0.025, y0, y1, -r + 0.04, frame_c)
	if win_style == 0 and rng.chance(shutter_p * 0.6):
		fbox(g, s, u0, u1, y1 - 0.2, y1, -r, -0.025, shade(enc(shutter_rgb, EnvGeo.METAL), 0.9), FRONT | BOT)
		fquad(g, s, u0 + 0.01, u1 - 0.01, y1 - 0.2 - (y1 - 0.2 - y0) * rng.range_f(0.1, 0.6), y1 - 0.2, -r + 0.09, enc(shutter_rgb, EnvGeo.SHUTTER))
	if op.get("french", false):
		# flush "French" balcony on a party-wall side: railing across the opening only
		var fc := enc(Color(0.16, 0.16, 0.17), EnvGeo.METAL)
		fbox(g, s, u0 - 0.05, u1 + 0.05, y0 + 0.95, y0 + 1.0, 0.0, 0.05, fc, BOX5)
		fbox(g, s, u0 - 0.05, u1 + 0.05, y0 - 0.05, y0 + 0.02, 0.0, 0.06, trim, BOX5)
		for i in 5:
			var u := u0 + (u1 - u0) * (i + 0.5) / 5.0
			fbox(dt, s, u - 0.015, u + 0.015, y0, y0 + 0.95, 0.01, 0.04, fc, FRONT | LEFT | RIGHT)
		return
	fbox(g, s, b0, b1, y0 - 0.17, y0, 0.0, dep, trim, BOX5)
	var kind := rng.range_i(0, 2) if style != MapDef.S_VILLA else 1
	var lost := damage > 0 and drng.chance(0.3)
	var keep_g := g
	var keep_dt := dt
	if lost:
		g = junk
		dt = junk
	var rt := y0 + 1.05
	match kind:
		0:  # solid parapet
			fbox(g, s, b0, b1, y0, rt, dep - 0.1, dep, wall, BOX5 | BACK)
			fbox(g, s, b0, b0 + 0.1, y0, rt, 0.0, dep - 0.1, wall, LEFT | RIGHT | TOP)
			fbox(g, s, b1 - 0.1, b1, y0, rt, 0.0, dep - 0.1, wall, LEFT | RIGHT | TOP)
			fbox(g, s, b0 - 0.02, b1 + 0.02, rt, rt + 0.05, dep - 0.12, dep + 0.02, trim, BOX5 | BACK)
		1:  # metal railing / balustrade
			var rc := enc(Color(0.16, 0.16, 0.17), EnvGeo.METAL) if style != MapDef.S_VILLA else trim
			fbox(g, s, b0, b1, rt - 0.05, rt, dep - 0.06, dep, rc, BOX5 | BACK)
			fbox(g, s, b0, b0 + 0.05, rt - 0.05, rt, 0.0, dep - 0.06, rc, LEFT | RIGHT | TOP | BOT)
			fbox(g, s, b1 - 0.05, b1, rt - 0.05, rt, 0.0, dep - 0.06, rc, LEFT | RIGHT | TOP | BOT)
			var n := maxi(3, int(bw / 0.22))
			for i in n + 1:
				var u := b0 + 0.025 + (bw - 0.05) * i / n
				fbox(dt, s, u - 0.018, u + 0.018, y0, rt - 0.05, dep - 0.05, dep - 0.015, rc, FRONT | LEFT | RIGHT)
			for i in 3:
				var dd := 0.15 + (dep - 0.3) * i / 2.0
				fbox(dt, s, b0 + 0.01, b0 + 0.04, y0, rt - 0.05, dd - 0.015, dd + 0.015, rc, LEFT | RIGHT | FRONT | BACK)
				fbox(dt, s, b1 - 0.04, b1 - 0.01, y0, rt - 0.05, dd - 0.015, dd + 0.015, rc, LEFT | RIGHT | FRONT | BACK)
		2:  # enclosed with aluminium glazing
			fbox(g, s, b0, b1, y0, rt, dep - 0.1, dep, wall, BOX5 | BACK)
			fbox(g, s, b0, b0 + 0.1, y0, rt, 0.0, dep - 0.1, wall, LEFT | RIGHT | TOP)
			fbox(g, s, b1 - 0.1, b1, y0, rt, 0.0, dep - 0.1, wall, LEFT | RIGHT | TOP)
			var yt := y0 + rh - 0.17
			var gc := enc(glass_rgb.lightened(0.1), EnvGeo.GLASS)
			var fc2 := enc(Color(0.75, 0.76, 0.76), EnvGeo.METAL)
			fbox(g, s, b0, b1, rt, yt, dep - 0.08, dep - 0.04, gc, FRONT | LEFT | RIGHT)
			var np := maxi(2, int(bw / 0.9))
			for i in np + 1:
				var u := b0 + bw * i / np
				fbox(g, s, u - 0.03, u + 0.03, rt, yt, dep - 0.09, dep - 0.03, fc2, FRONT | LEFT | RIGHT)
			fbox(g, s, b0, b1, rt, rt + 0.05, dep - 0.1, dep - 0.02, fc2, FRONT | TOP)
			for u in [b0 + 0.04, b1 - 0.04]:
				fbox(g, s, u - 0.04, u + 0.04, rt, yt, 0.0, dep - 0.08, gc, LEFT | RIGHT)
	# balcony life
	if damage > 0:
		dt = junk
	if kind != 2:
		var roll := rng.next_float()
		if roll < 0.3:
			for i in rng.range_i(2, 5):
				var cu := rng.range_f(b0 + 0.2, b1 - 0.3)
				var cc := enc(pick_col(CLOTH_COLS), EnvGeo.FABRIC)
				fbox(dt, s, cu, cu + rng.range_f(0.25, 0.5), rt - 0.55, rt + 0.02, dep + 0.01, dep + 0.03, cc, FRONT | BACK)
		elif roll < 0.5:
			for i in rng.range_i(1, 3):
				var pu := rng.range_f(b0 + 0.3, b1 - 0.3)
				var pp := fp(s, pu, y0, dep * 0.6)
				dt.cyl(pp, 0.16, 0.3, enc(Color(0.55, 0.3, 0.2), EnvGeo.CONCRETE), 6, 1, 0.2)
				dt.sphere(pp + Vector3(0, 0.5, 0), Vector3(0.28, 0.3, 0.28), enc(Color(0.3, 0.45, 0.22), EnvGeo.FOLIAGE), 4, 6)
		elif roll < 0.62:
			_dish(fp(s, rng.range_f(b0 + 0.3, b1 - 0.3), rt - 0.25, dep + 0.25), 0.35)
	g = keep_g
	dt = keep_dt


func _ac_facade(s: int, uc: float, ytop: float) -> void:
	var w := fw(s)
	if uc < 0.6 or uc > w - 0.6:
		return
	var ac := enc(Color(0.84, 0.84, 0.82), EnvGeo.METAL)
	fbox(dt, s, uc - 0.4, uc + 0.4, ytop - 0.55, ytop, 0.03, 0.31, ac, BOX5)
	fquad(dt, s, uc - 0.28, uc + 0.12, ytop - 0.48, ytop - 0.08, 0.315, enc(Color(0.12, 0.12, 0.12), EnvGeo.MESH))
	fbox(dt, s, uc - 0.35, uc - 0.3, ytop - 0.62, ytop - 0.55, 0.05, 0.27, metal_c, FRONT | TOP)
	fbox(dt, s, uc + 0.3, uc + 0.35, ytop - 0.62, ytop - 0.55, 0.05, 0.27, metal_c, FRONT | TOP)


## Darker base course around a body, interrupted by ground-level doors and shopfronts.
func plinth(rect: Rect2, h: float) -> void:
	set_frame(rect)
	for s in 4:
		var cuts: Array = []
		for e in ops_log:
			if e[0] == rect and int(e[1]) == s and float(e[4]) < h:
				cuts.append(Vector2(float(e[2]) - 0.02, float(e[3]) + 0.02))
		cuts.sort_custom(func(a, c): return a.x < c.x)
		var u := 0.0
		for cut in cuts:
			if cut.x > u + 0.01:
				fbox(g, s, u, cut.x, 0.0, h, 0.0, 0.03, base_c, FRONT | TOP | LEFT | RIGHT)
			u = maxf(u, cut.y)
		if u < fw(s) - 0.01:
			fbox(g, s, u, fw(s), 0.0, h, 0.0, 0.03, base_c, FRONT | TOP | LEFT | RIGHT)


## Dark basalt course across every facade at height y (Damascene ablaq banding).
func stripe(rect: Rect2, y: float, h: float, col: Color) -> void:
	set_frame(rect)
	for s in 4:
		fquad(g, s, 0.0, fw(s), y, y + h, 0.007, col)


# ------------------------------------------------------------------ roofs ------

func cornice(rect: Rect2, y: float, levels: int, sides: int = 15) -> void:
	set_frame(rect)
	for s in 4:
		if not (sides & (1 << s)):
			continue
		var w := fw(s)
		var d := 0.0
		var yy := y
		for k in levels:
			d += 0.1
			var hh := 0.14 if k == 0 else 0.09
			fbox(g, s, -d, w + d, yy, yy + hh, -0.02, d, trim, FRONT | TOP | BOT)
			yy += hh


## Stairwell kiosk on a roof (main mesh, it shapes the silhouette).
func kiosk(rr: Rect2, y: float, occ: Array) -> void:
	var kw := rng.range_f(2.6, 3.4)
	var kd := rng.range_f(2.8, 3.8)
	if rr.size.x < kw + 2.0 or rr.size.y < kd + 2.0:
		return
	var corner := rng.range_i(0, 3)
	var x := rr.position.x + 0.3 if corner % 2 == 0 else rr.end.x - kw - 0.3
	var z := rr.position.y + 0.3 if corner < 2 else rr.end.y - kd - 0.3
	var kr := Rect2(x, z, kw, kd)
	occ.append(kr.grow(0.6))
	var saved := [entry_side, blank_sides]
	entry_side = rng.range_i(0, 3)
	blank_sides = 0
	body(kr, y, 1, 0.35, P_KIOSK, 2.6)
	entry_side = saved[0]
	blank_sides = saved[1]


## Informal rooftop room (block or plaster walls, corrugated sheet roof).
func rooftop_room(rr: Rect2, y: float, occ: Array) -> void:
	var kw := minf(rr.size.x - 1.0, rng.range_f(3.0, 5.5))
	var kd := minf(rr.size.y - 1.0, rng.range_f(2.8, 4.5))
	if kw < 2.6 or kd < 2.6:
		return
	var x := rng.range_f(rr.position.x + 0.3, rr.end.x - kw - 0.3)
	var z := rng.range_f(rr.position.y + 0.3, rr.end.y - kd - 0.3)
	var kr := Rect2(x, z, kw, kd)
	if occupied(occ, kr):
		return
	occ.append(kr.grow(0.5))
	var saved := [entry_side, blank_sides, wall, wall_rgb]
	entry_side = rng.range_i(0, 3)
	blank_sides = 0
	var block := rng.chance(0.5)
	if block:
		wall_rgb = Color(0.62, 0.6, 0.57).lerp(wall_rgb, 0.3)
		wall = enc(wall_rgb, EnvGeo.CONCRETE | EnvGeo.FLAG)
	var sheet := rng.chance(0.55)
	body(kr, y, 1, 0.0 if sheet else 0.3, P_KIOSK, 2.5)
	if sheet:
		roofs.pop_back()
		var sc := enc(Color(0.55, 0.5, 0.45).lerp(Color(0.6, 0.62, 0.62), rng.next_float()), EnvGeo.CORRUGATED)
		var tilt := Basis(Vector3.RIGHT, 0.08)
		g.obox(Transform3D(tilt, Vector3(kr.get_center().x, y + 2.62, kr.get_center().y)), Vector3(kw + 0.4, 0.05, kd + 0.4), sc, EnvGeo.ALL)
	entry_side = saved[0]
	blank_sides = saved[1]
	wall = saved[2]
	wall_rgb = saved[3]


## Roof clutter: water tanks, solar heaters, dishes, AC units, antennas, laundry.
func roof_clutter(rr: Rect2, y: float, density: float, occ: Array) -> void:
	if rr.size.x < 1.5 or rr.size.y < 1.5:
		return
	var area := rr.size.x * rr.size.y
	var lost := damage > 0
	# water tanks: one or two clusters, often sharing a rusty steel stand
	var nt := clampi(int(area / 22.0 * density) + rng.range_i(0, 2), 1, 14)
	var groups := 1 if nt <= 4 else 2
	for gi in groups:
		var cnt := nt / groups + (nt % groups if gi == 0 else 0)
		var ncol := int(ceil(sqrt(float(cnt))))
		var nrow := int(ceil(float(cnt) / ncol))
		var tr := rng.range_f(0.45, 0.62)
		var th := rng.range_f(0.95, 1.4)
		var pitch := tr * 2.0 + 0.15
		var p := _roof_spot(rr, Vector2(ncol * pitch + 0.2, nrow * pitch + 0.2), occ)
		var stand := rng.range_f(0.5, 1.4) if rng.chance(0.55) else 0.0
		var main_col := pick_col(TANK_COLS)
		var tints: Array = []
		for i in cnt:
			tints.append(pick_col(TANK_COLS) if rng.chance(0.3) else main_col)
		if p == Vector2.INF:
			continue
		var x0 := p.x - (ncol - 1) * pitch * 0.5
		var z0 := p.y - (nrow - 1) * pitch * 0.5
		if stand > 0.0:
			var sw := ncol * pitch
			var sd := nrow * pitch
			var mc := enc(Color(0.24, 0.21, 0.19), EnvGeo.RUST)
			for cx in [-0.5, 0.5]:
				for cz in [-0.5, 0.5]:
					dt.box(Vector3(p.x + cx * (sw - 0.1), y + stand * 0.5, p.y + cz * (sd - 0.1)), Vector3(0.06, stand, 0.06), mc, EnvGeo.SIDES)
			dt.box(Vector3(p.x, y + stand - 0.04, p.y), Vector3(sw, 0.08, sd), mc, EnvGeo.ALL)
		for i in cnt:
			var tp := Vector3(x0 + (i % ncol) * pitch, y + stand, z0 + (i / ncol) * pitch)
			var col := enc(tints[i], EnvGeo.METAL)
			if lost and drng.chance(0.35):
				dt.cyl(Vector3(tp.x - th * 0.5, y + tr, tp.z), tr, th, col, 10, 3, -1.0, Basis(Vector3.BACK, -PI * 0.5))
				continue
			tank(dt, tp, col, tr, th, 0.0)
	# solar water heaters
	for i in (rng.range_i(0, 2) if density > 0.5 else 0):
		var p := _roof_spot(rr, Vector2(2.3, 1.8), occ)
		if p != Vector2.INF and not (lost and drng.chance(0.5)):
			solar(dt, Vector3(p.x, y, p.y))
	# satellite dishes
	for i in rng.range_i(1, clampi(int(area / 30.0) + 1, 1, 6)):
		var p := _roof_spot(rr, Vector2(0.9, 0.9), occ)
		var dr := rng.range_f(0.35, 0.55)
		var dyaw := rng.range_f(-0.5, 0.5)
		if p != Vector2.INF and not (lost and drng.chance(0.4)):
			dish(dt, Vector3(p.x, y + 0.9, p.y), dr, dyaw)
			dt.box(Vector3(p.x, y + 0.45, p.y), Vector3(0.05, 0.9, 0.05), metal_c, EnvGeo.SIDES)
	# AC units
	for i in rng.range_i(0, clampi(int(area / 40.0), 0, 5)):
		var p := _roof_spot(rr, Vector2(1.0, 0.8), occ)
		if p != Vector2.INF:
			var yaw := rng.pick([0.0, PI * 0.5]) as float
			ac_unit(dt, Vector3(p.x, y, p.y), yaw)
	# antenna
	if rng.chance(0.5):
		var p := _roof_spot(rr, Vector2(0.6, 0.6), occ)
		if p != Vector2.INF:
			var ah := rng.range_f(2.0, 3.5)
			dt.box(Vector3(p.x, y + ah * 0.5, p.y), Vector3(0.04, ah, 0.04), metal_c, EnvGeo.SIDES)
			for k in 3:
				var yy := y + ah - 0.2 - k * 0.35
				var wl := 1.0 - k * 0.2
				dt.box(Vector3(p.x, yy, p.y), Vector3(wl, 0.025, 0.025), metal_c, EnvGeo.ALL)
	# laundry line
	if rng.chance(0.3 * density) and rr.size.x > 4.0:
		var p := _roof_spot(rr, Vector2(3.4, 0.6), occ)
		if p != Vector2.INF:
			laundry(dt if damage == 0 else junk, Vector3(p.x, y, p.y), 3.0)


func _roof_spot(rr: Rect2, sz: Vector2, occ: Array) -> Vector2:
	if rr.size.x < sz.x + 0.3 or rr.size.y < sz.y + 0.3:
		return Vector2.INF
	for attempt in 6:
		var x := rng.range_f(rr.position.x + sz.x * 0.5 + 0.15, rr.end.x - sz.x * 0.5 - 0.15)
		var z := rng.range_f(rr.position.y + sz.y * 0.5 + 0.15, rr.end.y - sz.y * 0.5 - 0.15)
		var rc := Rect2(x - sz.x * 0.5, z - sz.y * 0.5, sz.x, sz.y)
		if not occupied(occ, rc):
			occ.append(rc)
			return Vector2(x, z)
	return Vector2.INF


static func tank(geo: EnvGeo, p: Vector3, col: Color, tr: float, th: float, stand: float) -> void:
	var mc := enc(Color(0.22, 0.2, 0.19), EnvGeo.RUST)
	if stand > 0.05:
		var e := tr * 0.75
		for c in [Vector2(-e, -e), Vector2(e, -e), Vector2(e, e), Vector2(-e, e)]:
			geo.box(p + Vector3(c.x, stand * 0.5, c.y), Vector3(0.05, stand, 0.05), mc, EnvGeo.SIDES)
		geo.box(p + Vector3(0, stand - 0.03, 0), Vector3(tr * 1.9, 0.06, tr * 1.9), mc, EnvGeo.ALL)
	var base := p + Vector3(0, stand, 0)
	geo.cyl(base, tr, th, col, 10, 1)
	geo.cyl(base + Vector3(0, th, 0), tr * 0.38, 0.09, col, 8, 1)
	geo.cyl(base + Vector3(0, th * 0.33, 0), tr * 1.035, 0.05, shade(col, 0.85), 10, 0)
	geo.cyl(base + Vector3(0, th * 0.66, 0), tr * 1.035, 0.05, shade(col, 0.85), 10, 0)


static func solar(geo: EnvGeo, p: Vector3) -> void:
	var mc := enc(Color(0.55, 0.56, 0.57), EnvGeo.METAL)
	var tilt := deg_to_rad(40.0)
	var pw := 2.0
	var pl := 1.3
	var bas := Basis(Vector3.RIGHT, -tilt)
	var lo := 0.35
	var ctr := p + Vector3(0, lo + sin(tilt) * pl * 0.5, 0)
	geo.obox(Transform3D(bas, ctr), Vector3(pw, 0.05, pl), enc(Color(0.1, 0.13, 0.22), EnvGeo.GLASS), EnvGeo.ALL)
	var back_z := ctr.z - cos(tilt) * pl * 0.5
	var top_y := ctr.y + sin(tilt) * pl * 0.5
	geo.cyl(Vector3(p.x - pw * 0.5, top_y + 0.25, back_z - 0.05), 0.24, pw, enc(Color(0.85, 0.86, 0.86), EnvGeo.METAL), 10, 3, -1.0, Basis(Vector3.BACK, -PI * 0.5))
	for x in [-pw * 0.45, pw * 0.45]:
		geo.beam(Vector3(p.x + x, p.y, back_z), Vector3(p.x + x, top_y + 0.05, back_z), 0.04, 0.04, mc)
		geo.beam(Vector3(p.x + x, p.y, ctr.z + cos(tilt) * pl * 0.5), Vector3(p.x + x, p.y + lo, ctr.z + cos(tilt) * pl * 0.5), 0.04, 0.04, mc)
		geo.beam(Vector3(p.x + x, p.y + 0.05, back_z), Vector3(p.x + x, p.y + 0.05, ctr.z + cos(tilt) * pl * 0.5), 0.04, 0.04, mc)


func _dish(p: Vector3, rad: float) -> void:
	dish(dt, p, rad, rng.range_f(-0.5, 0.5))


static func dish(geo: EnvGeo, p: Vector3, rad: float, yaw: float) -> void:
	var wc := enc(Color(0.88, 0.88, 0.86), EnvGeo.METAL)
	var bas := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(55.0))
	geo.cyl(p, rad, 0.025, wc, 10, 1, -1.0, bas)
	geo.sphere(p, Vector3(rad, rad * 0.28, rad), wc, 4, 10, true, bas * Basis(Vector3.RIGHT, PI))
	var axis := bas.y
	geo.beam(p + bas.z * -rad * 0.9, p + axis * rad * 0.85, 0.025, 0.025, enc(Color(0.3, 0.3, 0.3), EnvGeo.METAL))
	geo.box(p + axis * rad * 0.85, Vector3(0.07, 0.07, 0.07), enc(Color(0.25, 0.25, 0.25), EnvGeo.METAL), EnvGeo.ALL)


static func ac_unit(geo: EnvGeo, p: Vector3, yaw: float) -> void:
	var ac := enc(Color(0.82, 0.82, 0.8), EnvGeo.METAL)
	var bas := Basis(Vector3.UP, yaw)
	geo.obox(Transform3D(bas, p + Vector3(0, 0.35, 0)), Vector3(0.9, 0.6, 0.35), ac, EnvGeo.NO_BOTTOM)
	var f := bas * Vector3(0, 0, 0.176)
	geo.obox(Transform3D(bas, p + Vector3(0, 0.35, 0) + f + bas * Vector3(-0.12, 0, 0)), Vector3(0.42, 0.42, 0.01), enc(Color(0.1, 0.1, 0.1), EnvGeo.MESH), EnvGeo.PZ)
	geo.obox(Transform3D(bas, p + Vector3(0, 0.025, 0)), Vector3(0.8, 0.05, 0.4), enc(Color(0.3, 0.3, 0.3), EnvGeo.METAL), EnvGeo.NO_BOTTOM)


static func laundry(geo: EnvGeo, p: Vector3, len: float) -> void:
	var mc := enc(Color(0.3, 0.3, 0.3), EnvGeo.METAL)
	var a := p + Vector3(-len * 0.5, 0, 0)
	var bb := p + Vector3(len * 0.5, 0, 0)
	geo.beam(a, a + Vector3(0, 1.8, 0), 0.04, 0.04, mc)
	geo.beam(bb, bb + Vector3(0, 1.8, 0), 0.04, 0.04, mc)
	geo.beam(a + Vector3(0, 1.75, 0), bb + Vector3(0, 1.75, 0), 0.015, 0.015, mc)
	var x := -len * 0.5 + 0.2
	var i := 0
	while x < len * 0.5 - 0.4:
		var w := 0.3 + 0.25 * fposmod(sin(x * 12.9898 + p.x) * 43758.5, 1.0)
		var hh := 0.4 + 0.4 * fposmod(sin(x * 78.233 + p.z) * 12345.6, 1.0)
		var cc := enc(CLOTH_COLS[(i + int(absf(p.x * 3.0))) % CLOTH_COLS.size()], EnvGeo.FABRIC)
		var q0 := p + Vector3(x, 1.75 - hh, 0)
		geo.quad2(q0, q0 + Vector3(w, 0, 0), q0 + Vector3(w, hh, 0), q0 + Vector3(0, hh, 0), cc)
		x += w + 0.12
		i += 1


## Columns with exposed rebar on an unfinished extra storey.
func rebar_columns(rr: Rect2, y: float, hgt: float) -> void:
	var cc := enc(Color(0.62, 0.61, 0.58), EnvGeo.CONCRETE)
	var nx := maxi(2, int(rr.size.x / 4.0) + 1)
	var nz := maxi(2, int(rr.size.y / 4.0) + 1)
	for i in nx:
		for j in nz:
			if i != 0 and i != nx - 1 and j != 0 and j != nz - 1:
				continue
			var x := rr.position.x + 0.15 + (rr.size.x - 0.3) * i / (nx - 1)
			var z := rr.position.y + 0.15 + (rr.size.y - 0.3) * j / (nz - 1)
			var ch := hgt * rng.range_f(0.3, 1.0)
			g.box(Vector3(x, y + ch * 0.5, z), Vector3(0.3, ch, 0.3), cc, EnvGeo.NO_BOTTOM)
			rebar(dt, Vector3(x, y + ch, z), rng.range_f(0.6, 1.1), rng)


static func rebar(geo: EnvGeo, p: Vector3, len: float, rr: Rng) -> void:
	var rc := enc(Color(0.3, 0.17, 0.1), EnvGeo.RUST)
	for c in [Vector2(-0.09, -0.09), Vector2(0.09, -0.09), Vector2(0.09, 0.09), Vector2(-0.09, 0.09)]:
		var a := p + Vector3(c.x, 0, c.y)
		var m := a + Vector3(rr.range_f(-0.05, 0.05), len * 0.6, rr.range_f(-0.05, 0.05))
		var e := m + Vector3(rr.range_f(-0.2, 0.2), len * 0.4, rr.range_f(-0.2, 0.2))
		geo.beam(a, m, 0.022, 0.022, rc)
		geo.beam(m, e, 0.022, 0.022, rc)


# ------------------------------------------------------------------ damage -----

## Fallback damage for buildings without wall-skin bodies (warehouse sheet walls, curtain
## walls, concrete frames): blown-out patches with soot and exposed masonry at recorded
## openings, debris at the foot of the walls. Bodies cut real shell holes instead.
func damage_overlays(count: int) -> void:
	if ops_log.is_empty():
		return
	var soot := enc(Color(0.09, 0.085, 0.08), EnvGeo.VOID)
	var soot2 := shade(wall, 0.45)
	var exposed := enc(Color(0.66, 0.6, 0.52), EnvGeo.RUBBLE)
	var hole := enc(Color(0.025, 0.022, 0.02), EnvGeo.VOID)
	for i in count:
		var e: Array = ops_log[drng.range_i(0, ops_log.size() - 1)]
		set_frame(e[0])
		var s: int = e[1]
		var u0: float = e[2]
		var u1: float = e[3]
		var y0: float = e[4]
		var y1: float = e[5]
		var uc := (u0 + u1) * 0.5 + drng.range_f(-0.5, 0.5)
		var yc := (y0 + y1) * 0.5 + drng.range_f(-0.3, 0.3)
		var rad := drng.range_f(0.9, 1.8)
		fstar(g, s, uc, yc + rad * 0.6, rad * 1.9, rad * 2.2, 0.012, soot2, 12, 0.25, H)
		fstar(g, s, uc, yc + rad * 0.3, rad * 1.45, rad * 1.5, 0.016, soot, 12, 0.3, H)
		fstar(g, s, uc, yc, rad * 1.12, rad * 1.02, 0.022, exposed, 12, 0.3, H)
		fstar(g, s, uc, yc, rad, rad * 0.9, 0.028, hole, 12, 0.35, H)
		for k in drng.range_i(2, 4):
			var a := drng.range_f(0, TAU)
			var pa := fp(s, uc + cos(a) * rad * 0.95, yc + sin(a) * rad * 0.85, 0.02)
			dt.beam(pa, pa + fnormal(s) * drng.range_f(0.1, 0.4) + Vector3(cos(a), sin(a), 0) * 0.3, 0.025, 0.025, enc(Color(0.3, 0.17, 0.1), EnvGeo.RUST))
		_debris(s, uc, rad * 1.6)


func _debris(s: int, uc: float, spread: float) -> void:
	var w := fw(s)
	var rc := enc(wall_rgb.darkened(0.15), EnvGeo.RUBBLE)
	var cc := enc(Color(0.6, 0.58, 0.54), EnvGeo.RUBBLE)
	for k in drng.range_i(5, 10):
		var u := clampf(uc + drng.range_f(-spread, spread), 0.2, w - 0.2)
		var p := fp(s, u, 0.0, drng.range_f(0.2, 2.2))
		var sz := Vector3(drng.range_f(0.2, 0.7), drng.range_f(0.12, 0.4), drng.range_f(0.2, 0.6))
		var bas := Basis.from_euler(Vector3(drng.range_f(-0.4, 0.4), drng.range_f(0, TAU), drng.range_f(-0.4, 0.4)))
		g.obox(Transform3D(bas, p + Vector3(0, sz.y * 0.35, 0)), sz, rc if drng.chance(0.6) else cc, EnvGeo.ALL)

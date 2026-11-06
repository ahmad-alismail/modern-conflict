extends RefCounted
## Prop mesh library for PropBuilder: one cached ArrayMesh per MapDef.PROPS kind, built
## facing +X with the origin at the ground center. Parts flagged with EnvGeo.FLAG take the
## per-instance tint (MultiMesh custom data RGB); custom alpha is a 0..1 variation value
## (foliage hue, burn amount).
class_name EnvProps

static var _meshes: Dictionary = {}

const CAR_COLS := [Color(0.9, 0.9, 0.88), Color(0.9, 0.9, 0.88), Color(0.72, 0.73, 0.74), Color(0.72, 0.73, 0.74),
	Color(0.12, 0.12, 0.13), Color(0.6, 0.12, 0.1), Color(0.18, 0.28, 0.52), Color(0.95, 0.76, 0.12),
	Color(0.95, 0.76, 0.12), Color(0.22, 0.36, 0.26), Color(0.76, 0.69, 0.56), Color(0.4, 0.41, 0.42)]
const AWNING_COLS := [Color(0.8, 0.2, 0.18), Color(0.2, 0.38, 0.7), Color(0.2, 0.55, 0.3), Color(0.9, 0.55, 0.15),
	Color(0.9, 0.8, 0.25), Color(0.85, 0.85, 0.82)]
const BARREL_COLS := [Color(0.2, 0.32, 0.62), Color(0.62, 0.16, 0.1), Color(0.45, 0.3, 0.2), Color(0.24, 0.45, 0.28),
	Color(0.85, 0.7, 0.2), Color(0.5, 0.52, 0.53)]
const DUMPSTER_COLS := [Color(0.22, 0.42, 0.27), Color(0.2, 0.32, 0.55), Color(0.5, 0.52, 0.53), Color(0.85, 0.48, 0.15),
	Color(0.45, 0.3, 0.22)]
const CONTAINER_COLS := [Color(0.58, 0.2, 0.15), Color(0.16, 0.32, 0.58), Color(0.22, 0.48, 0.32), Color(0.85, 0.47, 0.15),
	Color(0.55, 0.57, 0.58), Color(0.88, 0.75, 0.2), Color(0.85, 0.85, 0.83)]
const BUS_COLS := [Color(0.85, 0.85, 0.82), Color(0.25, 0.45, 0.7), Color(0.3, 0.55, 0.35), Color(0.9, 0.75, 0.2)]
const BOARD_COLS := [Color(0.85, 0.2, 0.15), Color(0.15, 0.35, 0.75), Color(0.95, 0.8, 0.2), Color(0.2, 0.6, 0.35),
	Color(0.9, 0.9, 0.88), Color(0.5, 0.2, 0.55)]


static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var g := EnvGeo.new()
	var rng := Rng.new(hash(kind))
	match kind:
		"palm": _palm(g, rng)
		"tree": _tree(g, rng)
		"bush": _bush(g, rng)
		"car": _car(g, false)
		"car_wreck": _car(g, true)
		"bus_wreck": _bus(g)
		"lamp": _lamp(g)
		"pole": _pole(g)
		"stall": _stall(g, rng)
		"barrels": _barrels(g)
		"barrier": _barrier(g)
		"dumpster": _dumpster(g, rng)
		"container": _container(g)
		"rubble": _rubble(g, rng)
		"tires": _tires(g)
		"crates": _crates(g)
		"billboard": _billboard(g)
		"tank_trap": _tank_trap(g)
		_:
			g.box(Vector3(0, 0.5, 0), Vector3(1, 1, 1), EnvGeo.c(Color(0.5, 0.5, 0.5), EnvGeo.CONCRETE))
	var m := g.commit(EnvMaterials.props())
	_meshes[kind] = m
	return m


## Per-instance tint for a kind (RGB) chosen from its palette.
static func tint(kind: String, rng: Rng) -> Color:
	match kind:
		"car": return CAR_COLS[rng.range_i(0, CAR_COLS.size() - 1)]
		"car_wreck": return CAR_COLS[rng.range_i(0, CAR_COLS.size() - 1)]
		"bus_wreck": return BUS_COLS[rng.range_i(0, BUS_COLS.size() - 1)]
		"stall": return AWNING_COLS[rng.range_i(0, AWNING_COLS.size() - 1)]
		"barrels": return BARREL_COLS[rng.range_i(0, BARREL_COLS.size() - 1)]
		"dumpster": return DUMPSTER_COLS[rng.range_i(0, DUMPSTER_COLS.size() - 1)]
		"container": return CONTAINER_COLS[rng.range_i(0, CONTAINER_COLS.size() - 1)]
		"billboard": return BOARD_COLS[rng.range_i(0, BOARD_COLS.size() - 1)]
	return Color.WHITE


# ------------------------------------------------------------------ helpers ----

## Cylinder from a to b (radius r0 at a, r1 at b).
static func cyl_ab(g: EnvGeo, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, seg: int = 8, caps: int = 1) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return
	var y := d / len
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	g.cyl(a, r0, len, col, seg, caps, r1, Basis(x, y, z))


## Frond / leaf strip along a polyline with a V cross-section, double-sided.
static func frond(g: EnvGeo, pts: Array, widths: Array, side_dir: Vector3, col_a: Color, col_b: Color) -> void:
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var fwd := (p1 - p0).normalized()
		var sd := side_dir - fwd * side_dir.dot(fwd)
		sd = sd.normalized()
		var up := sd.cross(fwd).normalized()
		if up.y < 0.0:
			up = -up
		var w0: float = widths[i]
		var w1: float = widths[i + 1]
		var l0 := p0 + sd * w0 + up * w0 * 0.35
		var l1 := p1 + sd * w1 + up * w1 * 0.35
		var r0 := p0 - sd * w0 + up * w0 * 0.35
		var r1 := p1 - sd * w1 + up * w1 * 0.35
		var c := col_a if i % 2 == 0 else col_b
		g.quad2(p0, p1, l1, l0, c)
		g.quad2(p0, r0, r1, p1, c)


# ------------------------------------------------------------------ vegetation -

static func _palm(g: EnvGeo, rng: Rng) -> void:
	var bark := EnvGeo.c(Color(0.5, 0.42, 0.32), EnvGeo.BARK)
	var h := 7.5
	var n := 9
	var bend := 0.7
	var prev := Vector3.ZERO
	for k in range(1, n + 1):
		var t := float(k) / n
		var p := Vector3(bend * t * t, h * t, 0)
		cyl_ab(g, prev, p, lerpf(0.3, 0.2, t - 1.0 / n), lerpf(0.3, 0.2, t), bark, 8, 0)
		prev = p
	var top := prev
	g.sphere(top + Vector3(0, 0.1, 0), Vector3(0.32, 0.45, 0.32), EnvGeo.c(Color(0.45, 0.38, 0.25), EnvGeo.BARK), 5, 8)
	var green := EnvGeo.c(Color(0.36, 0.47, 0.22), EnvGeo.FOLIAGE)
	var green2 := EnvGeo.c(Color(0.3, 0.42, 0.2), EnvGeo.FOLIAGE)
	var dry := EnvGeo.c(Color(0.5, 0.4, 0.24), EnvGeo.FOLIAGE)
	var nf := 18
	for i in nf:
		var phi := TAU * i / nf + rng.range_f(-0.1, 0.1)
		var dirh := Vector3(cos(phi), 0, sin(phi))
		var lift := rng.range_f(0.2, 0.9) if i % 3 != 0 else rng.range_f(-0.3, 0.2)
		var L := rng.range_f(2.6, 3.4)
		var pts: Array = []
		var ws: Array = []
		for j in 7:
			var t := j / 6.0
			pts.append(top + dirh * L * t + Vector3(0, (lift * t - 1.1 * t * t) * L * 0.6 + 0.15, 0))
			ws.append(0.04 + 0.42 * pow(sin(PI * minf(t * 1.1, 1.0)), 0.7) * (1.0 - t * 0.4))
		var side := Vector3(-dirh.z, 0, dirh.x)
		frond(g, pts, ws, side, green if i % 2 == 0 else green2, green2)
	# dead fronds hanging under the crown
	for i in 7:
		var phi := TAU * i / 7.0 + 0.3
		var dirh := Vector3(cos(phi), 0, sin(phi))
		var pts: Array = [top - Vector3(0, 0.2, 0), top + dirh * 0.5 - Vector3(0, 0.9, 0), top + dirh * 0.7 - Vector3(0, 1.8, 0)]
		var ws: Array = [0.05, 0.22, 0.08]
		frond(g, pts, ws, Vector3(-dirh.z, 0, dirh.x), dry, dry)
	# date clusters
	var dates := EnvGeo.c(Color(0.75, 0.42, 0.12), EnvGeo.VOID)
	for i in 3:
		var phi := TAU * i / 3.0 + 0.5
		g.sphere(top + Vector3(cos(phi) * 0.35, -0.35, sin(phi) * 0.35), Vector3(0.18, 0.3, 0.18), dates, 4, 6)


static func _tree(g: EnvGeo, rng: Rng) -> void:
	var bark := EnvGeo.c(Color(0.38, 0.33, 0.27), EnvGeo.BARK)
	var p1 := Vector3(0.15, 1.3, 0.05)
	cyl_ab(g, Vector3.ZERO, p1, 0.24, 0.18, bark, 8, 0)
	var tips: Array = []
	for i in 4:
		var phi := TAU * i / 4.0 + 0.4
		var tip := p1 + Vector3(cos(phi) * 1.1, rng.range_f(1.0, 1.6), sin(phi) * 1.1)
		cyl_ab(g, p1, tip, 0.14, 0.07, bark, 6, 1)
		tips.append(tip)
	var leaf := EnvGeo.c(Color(0.45, 0.52, 0.34), EnvGeo.FOLIAGE)
	var leaf2 := EnvGeo.c(Color(0.38, 0.46, 0.29), EnvGeo.FOLIAGE)
	var leaf3 := EnvGeo.c(Color(0.5, 0.55, 0.4), EnvGeo.FOLIAGE)
	g.sphere(Vector3(0.1, 3.0, 0), Vector3(1.3, 0.8, 1.25), leaf2, 5, 9)
	for i in tips.size():
		var tp: Vector3 = tips[i]
		g.sphere(tp + Vector3(0, 0.2, 0), Vector3(1.0, 0.7, 0.95) * rng.range_f(0.85, 1.1), leaf2 if i % 2 == 0 else leaf, 5, 9)
	for i in 11:
		var phi := TAU * i / 11.0 + rng.range_f(-0.2, 0.2)
		var rr := rng.range_f(0.7, 1.9)
		var cy := rng.range_f(2.6, 4.3) - rr * 0.25
		var rad := rng.range_f(0.45, 0.8)
		g.sphere(Vector3(cos(phi) * rr, cy, sin(phi) * rr), Vector3(rad, rad * 0.75, rad), [leaf, leaf2, leaf3][i % 3], 4, 7)


static func _bush(g: EnvGeo, rng: Rng) -> void:
	var leaf := EnvGeo.c(Color(0.32, 0.42, 0.22), EnvGeo.FOLIAGE)
	var leaf2 := EnvGeo.c(Color(0.38, 0.46, 0.25), EnvGeo.FOLIAGE)
	g.sphere(Vector3(0, 0.45, 0), Vector3(0.75, 0.6, 0.7), leaf, 5, 9)
	for i in 4:
		var phi := TAU * i / 4.0 + rng.range_f(0, 0.5)
		g.sphere(Vector3(cos(phi) * 0.4, 0.35 + rng.range_f(0, 0.3), sin(phi) * 0.4), Vector3(0.45, 0.42, 0.45), leaf2, 4, 8)


# ------------------------------------------------------------------ vehicles ---

static func _car(g: EnvGeo, wreck: bool) -> void:
	var paint := EnvGeo.c(Color(1, 1, 1), (EnvGeo.RUST if wreck else EnvGeo.METAL) | EnvGeo.FLAG)
	var dark := EnvGeo.c(Color(0.07, 0.07, 0.07), EnvGeo.VOID)
	var trim := EnvGeo.c(Color(0.18, 0.18, 0.19), EnvGeo.METAL if not wreck else EnvGeo.RUST)
	var glass := EnvGeo.c(Color(0.22, 0.27, 0.3), EnvGeo.GLASS) if not wreck else EnvGeo.c(Color(0.03, 0.03, 0.03), EnvGeo.VOID)
	var lo := 0.0 if not wreck else -0.14
	var roll := 0.0 if not wreck else 0.04
	var y0 := 0.3 + lo
	var y1 := 0.9 + lo
	var y2 := 1.42 + lo - (0.06 if wreck else 0.0)
	# wheels
	for x in [-1.35, 1.38]:
		for z in [-0.78, 0.78]:
			var zr: float = z
			if not wreck:
				g.cyl(Vector3(x, 0.32, zr - 0.11), 0.32, 0.22, dark, 10, 3, -1.0, Basis(Vector3.RIGHT, PI * 0.5))
				g.cyl(Vector3(x, 0.32, zr + (0.115 if zr > 0 else -0.115) - 0.01), 0.17, 0.02, EnvGeo.c(Color(0.7, 0.7, 0.7), EnvGeo.METAL), 8, 1, -1.0, Basis(Vector3.RIGHT, PI * 0.5 if zr > 0 else -PI * 0.5))
			else:
				g.cyl(Vector3(x, 0.2, zr - 0.08), 0.21, 0.16, trim, 8, 3, -1.0, Basis(Vector3.RIGHT, PI * 0.5))
	var dz := roll
	var body := [Vector3(-2.2, y0, -0.92 + dz), Vector3(2.2, y0, -0.92 + dz), Vector3(2.2, y0, 0.92 + dz), Vector3(-2.2, y0, 0.92 + dz),
		Vector3(-2.16, y1, -0.9), Vector3(2.1, y1 - 0.06, -0.9), Vector3(2.1, y1 - 0.06, 0.9), Vector3(-2.16, y1, 0.9)]
	g.hexa(body, paint, EnvGeo.ALL)
	var cab := [Vector3(-1.3, y1, -0.86), Vector3(0.95, y1 - 0.03, -0.86), Vector3(0.95, y1 - 0.03, 0.86), Vector3(-1.3, y1, 0.86),
		Vector3(-0.9, y2, -0.74), Vector3(0.3, y2, -0.74), Vector3(0.3, y2, 0.74), Vector3(-0.9, y2, 0.74)]
	g.hexa(cab, paint, EnvGeo.NO_BOTTOM)
	# glazing inset on the cabin faces
	_face_inset(g, cab[1], cab[5], cab[6], cab[2], 0.1, glass)   # windshield (+X)
	_face_inset(g, cab[0], cab[3], cab[7], cab[4], 0.1, glass)   # rear window (-X)
	var mid_b := (cab[0] as Vector3).lerp(cab[1], 0.5)
	var mid_t := (cab[4] as Vector3).lerp(cab[5], 0.5)
	_face_inset(g, cab[0], mid_b, mid_t, cab[4], 0.08, glass)    # -Z side
	_face_inset(g, mid_b, cab[1], cab[5], mid_t, 0.08, glass)
	var mid_b2 := (cab[3] as Vector3).lerp(cab[2], 0.5)
	var mid_t2 := (cab[7] as Vector3).lerp(cab[6], 0.5)
	_face_inset(g, cab[2], mid_b2, mid_t2, cab[6], 0.08, glass)   # +Z side
	_face_inset(g, mid_b2, cab[3], cab[7], mid_t2, 0.08, glass)
	# bumpers, lights, plates, mirrors
	g.box(Vector3(2.22, y0 + 0.1, 0), Vector3(0.1, 0.2, 1.84), trim, EnvGeo.ALL)
	g.box(Vector3(-2.22, y0 + 0.1, 0), Vector3(0.1, 0.2, 1.84), trim, EnvGeo.ALL)
	if not wreck:
		var hl := EnvGeo.c(Color(0.9, 0.9, 0.85), EnvGeo.GLASS)
		var tl := EnvGeo.c(Color(0.7, 0.08, 0.06), EnvGeo.GLASS)
		for z in [-0.65, 0.65]:
			g.box(Vector3(2.19, y1 - 0.17, z), Vector3(0.04, 0.12, 0.34), hl, EnvGeo.PX)
			g.box(Vector3(-2.2, y1 - 0.15, z), Vector3(0.04, 0.12, 0.3), tl, EnvGeo.NX)
		g.box(Vector3(2.28, y0 + 0.12, 0), Vector3(0.02, 0.12, 0.42), EnvGeo.c(Color(0.92, 0.92, 0.9), EnvGeo.METAL), EnvGeo.PX)
		g.box(Vector3(-2.28, y0 + 0.12, 0), Vector3(0.02, 0.12, 0.42), EnvGeo.c(Color(0.92, 0.92, 0.9), EnvGeo.METAL), EnvGeo.NX)
		for z in [-0.95, 0.95]:
			g.box(Vector3(0.75, y1 + 0.12, z), Vector3(0.12, 0.1, 0.1), paint, EnvGeo.ALL)
	else:
		# scorched interior seen through empty windows, sprung hood
		g.box(Vector3(-0.2, y1 + 0.05, 0), Vector3(1.9, 0.1, 1.6), dark, EnvGeo.PY)
		var hood := Basis(Vector3.BACK, -0.12)
		g.obox(Transform3D(hood, Vector3(1.55, y1 + 0.05, 0)), Vector3(1.2, 0.05, 1.7), paint, EnvGeo.ALL)


## Window pane inset into a hexahedron face, offset outward (away from `inside`).
static func _face_inset(g: EnvGeo, a: Vector3, b: Vector3, c: Vector3, d: Vector3, k: float, col: Color,
		inside: Vector3 = Vector3(0, 0.9, 0)) -> void:
	var ctr := (a + b + c + d) * 0.25
	var out := ctr - inside
	var n := (b - a).cross(c - a).normalized()
	if n.dot(out) < 0.0:
		n = -n
	var off := n * 0.012
	EnvBld.quadf(g, a.lerp(ctr, k * 2.0) + off, b.lerp(ctr, k * 2.0) + off, c.lerp(ctr, k * 2.0) + off, d.lerp(ctr, k * 2.0) + off, col, n)


static func _bus(g: EnvGeo) -> void:
	var paint := EnvGeo.c(Color(1, 1, 1), EnvGeo.RUST | EnvGeo.FLAG)
	var dark := EnvGeo.c(Color(0.025, 0.025, 0.025), EnvGeo.VOID)
	var rim := EnvGeo.c(Color(0.2, 0.18, 0.16), EnvGeo.RUST)
	var L := 10.8
	var Wd := 2.5
	var y0 := 0.3
	var y1 := 2.95
	for x in [-3.6, 3.4]:
		for z in [-1.05, 1.05]:
			var zr: float = z
			g.cyl(Vector3(x, 0.3, zr - 0.1), 0.34, 0.2, rim, 8, 3, -1.0, Basis(Vector3.RIGHT, PI * 0.5))
	g.boxmm(Vector3(-L * 0.5, y0, -Wd * 0.5), Vector3(L * 0.5, 1.3, Wd * 0.5), paint, EnvGeo.ALL)
	# window band with pillars, roof partly caved
	var n := 8
	for i in n + 1:
		var x := -L * 0.5 + 0.1 + (L - 0.2) * i / n
		for z in [-Wd * 0.5 + 0.04, Wd * 0.5 - 0.04]:
			g.box(Vector3(x, 1.95, z), Vector3(0.14, 1.3, 0.08), paint, EnvGeo.ALL)
	for z in [-Wd * 0.5 + 0.06, Wd * 0.5 - 0.06]:
		g.box(Vector3(0, 1.95, z), Vector3(L - 0.2, 1.28, 0.02), dark, EnvGeo.PZ | EnvGeo.NZ)
	g.box(Vector3(L * 0.5 - 0.05, 1.95, 0), Vector3(0.04, 1.2, Wd - 0.2), dark, EnvGeo.PX | EnvGeo.NX)
	g.box(Vector3(-L * 0.5 + 0.05, 1.95, 0), Vector3(0.04, 1.2, Wd - 0.2), dark, EnvGeo.PX | EnvGeo.NX)
	g.boxmm(Vector3(-L * 0.5, 2.6, -Wd * 0.5), Vector3(0.8, y1, Wd * 0.5), paint, EnvGeo.ALL)
	g.obox(Transform3D(Basis(Vector3.BACK, 0.12), Vector3(2.9, 2.5, 0)), Vector3(4.4, 0.08, Wd - 0.1), paint, EnvGeo.ALL)
	g.box(Vector3(0, 1.4, 0), Vector3(L - 0.4, 0.1, Wd - 0.3), dark, EnvGeo.PY)
	g.box(Vector3(L * 0.5 + 0.04, y0 + 0.15, 0), Vector3(0.1, 0.3, Wd), rim, EnvGeo.ALL)


# ------------------------------------------------------------------ street -----

static func _lamp(g: EnvGeo) -> void:
	var mc := EnvGeo.c(Color(0.45, 0.46, 0.47), EnvGeo.METAL)
	var dark := EnvGeo.c(Color(0.2, 0.2, 0.21), EnvGeo.METAL)
	g.cyl(Vector3.ZERO, 0.22, 0.55, EnvGeo.c(Color(0.62, 0.6, 0.56), EnvGeo.CONCRETE), 8, 1)
	g.cyl(Vector3(0, 0.55, 0), 0.11, 8.0, mc, 8, 1, 0.06)
	for sx in [-1.0, 1.0]:
		var a := Vector3(0, 7.9, 0)
		var m := Vector3(sx * 0.9, 8.45, 0)
		var e := Vector3(sx * 1.7, 8.5, 0)
		g.beam(a, m, 0.07, 0.07, mc)
		g.beam(m, e, 0.06, 0.06, mc)
		g.box(e + Vector3(sx * 0.2, -0.02, 0), Vector3(0.65, 0.14, 0.28), dark, EnvGeo.ALL)
		g.box(e + Vector3(sx * 0.2, -0.1, 0), Vector3(0.5, 0.02, 0.2), EnvGeo.c(Color(0.95, 0.9, 0.7), EnvGeo.GLASS), EnvGeo.NY)


static func _pole(g: EnvGeo) -> void:
	var cc := EnvGeo.c(Color(0.62, 0.6, 0.57), EnvGeo.CONCRETE)
	var mc := EnvGeo.c(Color(0.3, 0.3, 0.3), EnvGeo.METAL)
	var ins := EnvGeo.c(Color(0.75, 0.75, 0.72), EnvGeo.GLASS)
	var wire := EnvGeo.c(Color(0.06, 0.06, 0.06), EnvGeo.VOID)
	g.taper(Vector3.ZERO, 0.3, 0.3, 0.17, 0.17, 9.0, cc, EnvGeo.NO_BOTTOM | EnvGeo.PY)
	g.box(Vector3(0, 8.4, 0), Vector3(0.1, 0.1, 2.0), mc, EnvGeo.ALL)
	for z in [-0.85, 0.0, 0.85]:
		g.cyl(Vector3(0, 8.45, z), 0.05, 0.18, ins, 6, 1)
		# sagging wire stubs toward the next poles
		for sx in [-1.0, 1.0]:
			var a := Vector3(0, 8.6, z)
			var m := Vector3(sx * 1.6, 8.2, z)
			var e := Vector3(sx * 3.0, 7.95, z)
			g.beam(a, m, 0.02, 0.02, wire)
			g.beam(m, e, 0.02, 0.02, wire)
	g.box(Vector3(0.22, 6.2, 0), Vector3(0.3, 0.55, 0.4), EnvGeo.c(Color(0.55, 0.56, 0.55), EnvGeo.METAL), EnvGeo.ALL)
	g.beam(Vector3(0.1, 8.3, 0.2), Vector3(0.6, 6.8, 0.3), 0.03, 0.03, wire)
	g.beam(Vector3(0.1, 8.3, -0.2), Vector3(-0.4, 7.2, -0.6), 0.03, 0.03, wire)


static func _stall(g: EnvGeo, rng: Rng) -> void:
	var wood := EnvGeo.c(Color(0.5, 0.36, 0.22), EnvGeo.WOOD)
	var post := EnvGeo.c(Color(0.35, 0.33, 0.3), EnvGeo.METAL)
	var awn := EnvGeo.c(Color(1, 1, 1), EnvGeo.FABRIC | EnvGeo.FLAG)
	g.boxmm(Vector3(-1.45, 0, -0.2), Vector3(1.45, 0.85, 1.05), wood, EnvGeo.NO_BOTTOM)
	for p in [Vector2(-1.45, -1.05), Vector2(1.45, -1.05), Vector2(-1.45, 1.05), Vector2(1.45, 1.05)]:
		g.box(Vector3(p.x, 1.15, p.y), Vector3(0.06, 2.3, 0.06), post, EnvGeo.SIDES)
	var a := [Vector3(-1.6, 2.35, -1.2), Vector3(1.6, 2.35, -1.2), Vector3(1.6, 1.95, 1.3), Vector3(-1.6, 1.95, 1.3)]
	g.quad2(a[0], a[3], a[2], a[1], awn)
	g.quad2(a[3], Vector3(-1.6, 1.65, 1.32), Vector3(1.6, 1.65, 1.32), a[2], awn)
	# produce on the counter
	var fruit := [Color(0.9, 0.5, 0.1), Color(0.8, 0.12, 0.1), Color(0.45, 0.65, 0.2), Color(0.92, 0.8, 0.25), Color(0.5, 0.2, 0.35)]
	for i in 5:
		var x := -1.15 + i * 0.58
		var fc := EnvGeo.c(fruit[i % fruit.size()], EnvGeo.VOID)
		g.boxmm(Vector3(x - 0.25, 0.85, -0.05), Vector3(x + 0.25, 0.95, 0.9), wood, EnvGeo.NO_BOTTOM)
		g.sphere(Vector3(x, 0.95, 0.42), Vector3(0.24, 0.12, 0.42), fc, 4, 8, true)
	for i in 3:
		var x := rng.range_f(-1.2, 1.2)
		g.boxmm(Vector3(x - 0.25, 0, 1.15), Vector3(x + 0.25, 0.32, 1.55), wood, EnvGeo.NO_BOTTOM)
	g.sphere(Vector3(0.9, 0, -0.65), Vector3(0.3, 0.45, 0.3), EnvGeo.c(Color(0.7, 0.62, 0.45), EnvGeo.VOID), 4, 8, true)


static func _barrels(g: EnvGeo) -> void:
	var paint := EnvGeo.c(Color(1, 1, 1), EnvGeo.METAL | EnvGeo.FLAG)
	var lid := EnvGeo.c(Color(0.7, 0.7, 0.7), EnvGeo.METAL | EnvGeo.FLAG)
	for p in [Vector2(-0.3, -0.3), Vector2(0.32, -0.25), Vector2(-0.05, 0.3)]:
		var b := Vector3(p.x, 0, p.y)
		g.cyl(b, 0.29, 0.88, paint, 10, 1)
		g.cyl(b + Vector3(0, 0.29, 0), 0.3, 0.03, lid, 10, 0)
		g.cyl(b + Vector3(0, 0.59, 0), 0.3, 0.03, lid, 10, 0)
		g.cyl(b + Vector3(0, 0.88, 0), 0.22, 0.012, EnvGeo.c(Color(0.35, 0.35, 0.35), EnvGeo.METAL), 8, 1)
	g.cyl(Vector3(0.55, 0.29, 0.45), 0.29, 0.88, paint, 10, 3, -1.0, Basis(Vector3.UP, 0.6) * Basis(Vector3.BACK, PI * 0.5))


static func _barrier(g: EnvGeo) -> void:
	var cc := EnvGeo.c(Color(0.7, 0.68, 0.64), EnvGeo.CONCRETE)
	var L := 3.55
	g.taper(Vector3.ZERO, L, 0.62, L, 0.62, 0.08, cc, EnvGeo.SIDES)
	g.taper(Vector3(0, 0.08, 0), L, 0.62, L, 0.4, 0.25, cc, EnvGeo.SIDES)
	g.taper(Vector3(0, 0.33, 0), L, 0.4, L, 0.2, 0.62, cc, EnvGeo.ALL)
	var stripe := EnvGeo.c(Color(0.75, 0.2, 0.15), EnvGeo.CONCRETE)
	for x in [-1.2, 0.0, 1.2]:
		g.taper(Vector3(x, 0.55, 0), 0.35, 0.33, 0.35, 0.25, 0.25, stripe, EnvGeo.PZ | EnvGeo.NZ)
	g.box(Vector3(0, 0.95, 0), Vector3(0.3, 0.02, 0.21), EnvGeo.c(Color(0.25, 0.2, 0.15), EnvGeo.RUST), EnvGeo.PY)


static func _dumpster(g: EnvGeo, rng: Rng) -> void:
	var paint := EnvGeo.c(Color(1, 1, 1), EnvGeo.METAL | EnvGeo.FLAG)
	var lid := EnvGeo.c(Color(0.7, 0.7, 0.7), EnvGeo.METAL | EnvGeo.FLAG)
	var dark := EnvGeo.c(Color(0.08, 0.08, 0.08), EnvGeo.VOID)
	g.taper(Vector3(0, 0.18, 0), 1.75, 1.1, 1.95, 1.3, 1.05, paint, EnvGeo.ALL)
	g.obox(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 1.28, -0.02)), Vector3(1.98, 0.05, 1.34), lid, EnvGeo.ALL)
	for x in [-0.75, 0.75]:
		for z in [-0.45, 0.45]:
			g.cyl(Vector3(x, 0.09, z - 0.04), 0.09, 0.08, dark, 6, 3, -1.0, Basis(Vector3.RIGHT, PI * 0.5))
	for x in [-1.0, 1.0]:
		g.box(Vector3(x, 0.95, 0), Vector3(0.1, 0.08, 0.5), dark, EnvGeo.ALL)
	var bag := EnvGeo.c(Color(0.06, 0.06, 0.07), EnvGeo.METAL)
	for i in 3:
		g.sphere(Vector3(rng.range_f(-0.9, 0.9), 0.0, rng.range_f(0.75, 0.95)), Vector3(0.3, 0.35, 0.28), bag, 4, 7, true)


static func _container(g: EnvGeo) -> void:
	var paint := EnvGeo.c(Color(1, 1, 1), EnvGeo.CORRUGATED | EnvGeo.FLAG)
	var flat := EnvGeo.c(Color(0.85, 0.85, 0.85), EnvGeo.METAL | EnvGeo.FLAG)
	var dark := EnvGeo.c(Color(0.12, 0.12, 0.12), EnvGeo.METAL)
	var L := 6.06
	var Wd := 2.44
	var Hh := 2.59
	g.box(Vector3(0, Hh * 0.5, 0), Vector3(L - 0.1, Hh - 0.1, Wd - 0.04), paint, EnvGeo.PZ | EnvGeo.NZ | EnvGeo.NX)
	g.box(Vector3(0, Hh * 0.5, 0), Vector3(L - 0.08, Hh - 0.1, Wd - 0.04), flat, EnvGeo.PX)
	g.box(Vector3(0, Hh - 0.04, 0), Vector3(L, 0.08, Wd), flat, EnvGeo.ALL)
	g.box(Vector3(0, 0.06, 0), Vector3(L, 0.12, Wd), dark, EnvGeo.SIDES)
	for x in [-L * 0.5 + 0.06, L * 0.5 - 0.06]:
		for z in [-Wd * 0.5 + 0.06, Wd * 0.5 - 0.06]:
			g.box(Vector3(x, Hh * 0.5, z), Vector3(0.14, Hh, 0.14), flat, EnvGeo.SIDES)
	for z in [-0.75, -0.35, 0.35, 0.75]:
		g.box(Vector3(L * 0.5 - 0.02, Hh * 0.5, z), Vector3(0.04, Hh - 0.3, 0.04), dark, EnvGeo.ALL)
	g.box(Vector3(L * 0.5 - 0.03, Hh * 0.5, 0), Vector3(0.02, Hh - 0.2, 0.02), dark, EnvGeo.PX)


static func _rubble(g: EnvGeo, rng: Rng) -> void:
	var rc := EnvGeo.c(Color(0.62, 0.58, 0.52), EnvGeo.RUBBLE)
	var cc := EnvGeo.c(Color(0.6, 0.59, 0.56), EnvGeo.CONCRETE)
	var pc := EnvGeo.c(Color(0.75, 0.68, 0.56), EnvGeo.RUBBLE)
	g.sphere(Vector3(0, -0.15, 0), Vector3(1.9, 1.1, 1.8), rc, 8, 12, true)
	g.sphere(Vector3(0.7, -0.1, -0.5), Vector3(1.1, 0.9, 1.0), pc, 6, 10, true)
	for i in 22:
		var a := rng.range_f(0, TAU)
		var rr := sqrt(rng.next_float()) * 1.7
		var x := cos(a) * rr
		var z := sin(a) * rr
		var y := maxf(0.0, 0.95 * (1.0 - (rr / 1.9) * (rr / 1.9)))
		var sz := Vector3(rng.range_f(0.2, 0.75), rng.range_f(0.12, 0.4), rng.range_f(0.2, 0.6))
		var bas := Basis.from_euler(Vector3(rng.range_f(-0.7, 0.7), rng.range_f(0, TAU), rng.range_f(-0.7, 0.7)))
		g.obox(Transform3D(bas, Vector3(x, y, z)), sz, cc if i % 3 == 0 else pc, EnvGeo.ALL)
	var slab := Basis.from_euler(Vector3(0.35, 0.6, 0.2))
	g.obox(Transform3D(slab, Vector3(-0.5, 0.6, 0.4)), Vector3(1.8, 0.18, 1.2), cc, EnvGeo.ALL)
	EnvBld.rebar(g, Vector3(-0.3, 0.7, 0.9), 0.8, rng)


static func _tires(g: EnvGeo) -> void:
	var rub := EnvGeo.c(Color(0.08, 0.08, 0.08), EnvGeo.VOID)
	var hole := EnvGeo.c(Color(0.015, 0.015, 0.015), EnvGeo.VOID)
	for k in 3:
		var p := Vector3(-0.25, k * 0.23, -0.15)
		g.cyl(p, 0.34, 0.22, rub, 12, 1)
		g.cyl(p + Vector3(0, 0.221, 0), 0.17, 0.002, hole, 10, 1)
	for p in [Vector3(0.4, 0, 0.35), Vector3(-0.35, 0, 0.45)]:
		g.cyl(p, 0.34, 0.22, rub, 12, 1)
		g.cyl(p + Vector3(0, 0.221, 0), 0.17, 0.002, hole, 10, 1)
	g.cyl(Vector3(0.45, 0.34, -0.35), 0.34, 0.22, rub, 12, 3, -1.0, Basis(Vector3.BACK, 1.3))


static func _crates(g: EnvGeo) -> void:
	var wood := EnvGeo.c(Color(0.58, 0.45, 0.3), EnvGeo.WOOD)
	var wood2 := EnvGeo.c(Color(0.5, 0.38, 0.25), EnvGeo.WOOD)
	g.boxmm(Vector3(-0.85, 0, -0.65), Vector3(0.85, 0.12, 0.65), wood2, EnvGeo.NO_BOTTOM)
	g.boxmm(Vector3(-0.8, 0.12, -0.6), Vector3(0.0, 0.66, 0.0), wood, EnvGeo.NO_BOTTOM)
	g.boxmm(Vector3(0.02, 0.12, -0.6), Vector3(0.8, 0.66, 0.0), wood2, EnvGeo.NO_BOTTOM)
	g.boxmm(Vector3(-0.8, 0.12, 0.02), Vector3(0.0, 0.66, 0.6), wood2, EnvGeo.NO_BOTTOM)
	g.obox(Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.35, 0.93, -0.25)), Vector3(0.75, 0.54, 0.58), wood, EnvGeo.NO_BOTTOM)
	g.box(Vector3(0.45, 0.25, 0.35), Vector3(0.5, 0.5, 0.45), EnvGeo.c(Color(0.62, 0.52, 0.38), EnvGeo.VOID), EnvGeo.NO_BOTTOM)


static func _billboard(g: EnvGeo) -> void:
	var mc := EnvGeo.c(Color(0.32, 0.32, 0.33), EnvGeo.METAL)
	var face := EnvGeo.c(Color(1, 1, 1), EnvGeo.METAL | EnvGeo.FLAG)
	for x in [-1.3, 1.3]:
		g.box(Vector3(x, 2.6, -0.1), Vector3(0.16, 5.2, 0.16), mc, EnvGeo.SIDES)
	g.box(Vector3(0, 4.05, 0), Vector3(4.0, 2.2, 0.12), mc, EnvGeo.ALL)
	for zs in [1.0, -1.0]:
		var z: float = zs * 0.065
		var m := EnvGeo.PZ if zs > 0 else EnvGeo.NZ
		g.box(Vector3(0, 4.05, z), Vector3(3.85, 2.05, 0.01), face, m)
		g.box(Vector3(-0.8, 4.3, z * 1.15), Vector3(1.8, 0.9, 0.01), EnvGeo.c(Color(0.95, 0.95, 0.92), EnvGeo.METAL), m)
		g.box(Vector3(1.0, 3.75, z * 1.15), Vector3(1.4, 1.1, 0.01), EnvGeo.c(Color(0.3, 0.3, 0.32), EnvGeo.METAL | EnvGeo.FLAG), m)
		g.box(Vector3(-0.9, 3.5, z * 1.15), Vector3(1.6, 0.25, 0.01), EnvGeo.c(Color(0.15, 0.15, 0.15), EnvGeo.METAL), m)
	g.box(Vector3(0, 2.9, 0.35), Vector3(4.0, 0.06, 0.6), mc, EnvGeo.ALL)
	g.box(Vector3(1.4, 4.9, 0.075), Vector3(0.7, 0.5, 0.01), EnvGeo.c(Color(0.03, 0.03, 0.03), EnvGeo.VOID), EnvGeo.PZ)


static func _tank_trap(g: EnvGeo) -> void:
	var st := EnvGeo.c(Color(0.3, 0.28, 0.26), EnvGeo.RUST)
	var L := 1.75
	var up := Vector3(1, 1, 1).normalized()
	var rot := Basis(up.cross(Vector3.UP).normalized(), up.angle_to(Vector3.UP))
	var c := Vector3(0, L / (2.0 * sqrt(3.0)) + 0.04, 0)
	for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var d: Vector3 = Basis(Vector3.UP, 0.4) * (rot * (ax as Vector3))
		g.beam(c - d * L * 0.5, c + d * L * 0.5, 0.13, 0.13, st)

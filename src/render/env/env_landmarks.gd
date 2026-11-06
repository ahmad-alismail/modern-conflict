extends RefCounted
## Special building types for BuildingBuilder: mosque (prayer hall, drum + dome,
## minarets, arcade, courtyard), industrial warehouses/workshops, unfinished concrete
## frames and collapsed ruins.
class_name EnvLandmarks

const FH := MapDef.FLOOR_H


# ------------------------------------------------------------------ mosque -----

static func mosque(c: EnvBld) -> void:
	var rng := c.rng
	var W := c.W
	var D := c.D
	c.wall_rgb = c.jit(Color(0.84, 0.79, 0.69), 0.03)
	c.wall_surf = EnvGeo.STONE
	c.wall = EnvGeo.c(c.wall_rgb, EnvGeo.STONE)
	c.trim = EnvGeo.c(Color(0.9, 0.87, 0.8), EnvGeo.STONE)
	c.base_c = EnvGeo.c(Color(0.22, 0.21, 0.2), EnvGeo.STONE)
	c.roof_c = EnvGeo.c(Color(0.7, 0.68, 0.64), EnvGeo.ROOF)
	c.void_c = EnvGeo.c(Color(0.05, 0.045, 0.04), EnvGeo.VOID)
	c.frame_c = EnvGeo.c(Color(0.2, 0.22, 0.2), EnvGeo.METAL)
	c.glass_rgb = Color(0.2, 0.3, 0.32)
	c.wood_rgb = Color(0.36, 0.24, 0.14)
	c.metal_c = EnvGeo.c(Color(0.2, 0.2, 0.21), EnvGeo.METAL)
	c.ablaq = true
	c.r = 0.35
	c.win_style = 2
	c.grime_p = 0.35
	c.entry_side = 0
	var dome_pick := rng.range_i(0, 2)
	var dome_c := EnvGeo.c([Color(0.42, 0.47, 0.46), Color(0.26, 0.44, 0.38), Color(0.84, 0.8, 0.72)][dome_pick],
		EnvGeo.PLASTER if dome_pick == 2 else EnvGeo.METAL)
	var lead := EnvGeo.c(Color(0.5, 0.56, 0.55), EnvGeo.METAL)
	var gold := EnvGeo.c(Color(0.85, 0.7, 0.3), EnvGeo.METAL)
	# layout: prayer hall at the back (-Z), arcade + courtyard toward +Z
	var hall_d := clampf(D * 0.55, 8.0, D - 6.0)
	var z_h := -D * 0.5 + hall_d
	var hall := Rect2(-W * 0.5, -D * 0.5, W, hall_d)
	var roof_y := c.body(hall, 0.0, c.F, 1.0, EnvBld.P_MOSQUE)
	c.plinth(hall, 0.6)
	for k in range(1, c.F):
		c.stripe(hall, k * FH - 0.17, 0.34, c.base_c)
	c.cornice(hall, roof_y - 0.2, 2)
	# drum + dome
	var R := minf(W, hall_d) * 0.34
	var dc := Vector3(0, roof_y, hall.get_center().y)
	var drum_h := 1.9
	c.g.cyl(dc, R + 0.35, 0.35, c.trim, 16, 1)
	c.g.cyl(dc + Vector3(0, 0.35, 0), R + 0.2, drum_h, c.wall, 16, 1)
	var seg := 16
	for i in seg:
		if i % 2 == 1:
			continue
		var a0 := TAU * (i + 0.25) / seg
		var a1 := TAU * (i + 0.75) / seg
		var rr := R + 0.22
		var p0 := dc + Vector3(cos(a0) * rr, 0.75, sin(a0) * rr)
		var p1 := dc + Vector3(cos(a1) * rr, 0.75, sin(a1) * rr)
		var nrm := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		EnvBld.quadf(c.g, p0, p1, p1 + Vector3(0, 0.95, 0), p0 + Vector3(0, 0.95, 0), EnvGeo.c(Color(0.06, 0.06, 0.06), EnvGeo.VOID), nrm)
	c.g.cyl(dc + Vector3(0, 0.35 + drum_h, 0), R + 0.32, 0.18, c.trim, 16, 1)
	var dbase := dc + Vector3(0, 0.53 + drum_h, 0)
	c.g.sphere(dbase, Vector3(R, R * 1.12, R), dome_c, 14, 18, true)
	_finial(c, dbase + Vector3(0, R * 1.12, 0), 1.0, gold)
	# minarets at the front corners of the hall
	var two := rng.chance(0.5)
	var mr := 1.25
	var bx := W * 0.5 - mr - 0.05
	var bz := z_h + mr + 0.05
	_minaret(c, Vector3(bx, 0, bz), roof_y, lead, gold)
	if two:
		_minaret(c, Vector3(-bx, 0, bz), roof_y, lead, gold)
	# arcade (riwaq) in front of the hall, crowned by small domes
	var ax0 := -bx + mr + 0.1 if two else -W * 0.5 + 0.3
	var ax1 := bx - mr - 0.1
	var adep := minf(4.0, D * 0.5 - z_h - 1.0)
	_arcade(c, Rect2(ax0, z_h, ax1 - ax0, adep), dome_c, gold)
	# courtyard: paving, low enclosure with gate, ablution fountain
	var cz0 := z_h + adep
	var cz1 := D * 0.5
	if cz1 - cz0 > 2.0:
		var pc := EnvGeo.c(Color(0.82, 0.8, 0.74), EnvGeo.STONE)
		c.g.box(Vector3(0, 0.04, (cz0 + cz1) * 0.5), Vector3(W, 0.08, cz1 - cz0), pc, EnvGeo.NO_BOTTOM)
		var wc := c.wall
		var wh := 1.7
		c.g.boxmm(Vector3(-W * 0.5, 0, cz0), Vector3(-W * 0.5 + 0.4, wh, cz1), wc, EnvGeo.NO_BOTTOM)
		c.g.boxmm(Vector3(W * 0.5 - 0.4, 0, cz0), Vector3(W * 0.5, wh, cz1), wc, EnvGeo.NO_BOTTOM)
		c.g.boxmm(Vector3(-W * 0.5, 0, cz1 - 0.4), Vector3(-1.4, wh, cz1), wc, EnvGeo.NO_BOTTOM)
		c.g.boxmm(Vector3(1.4, 0, cz1 - 0.4), Vector3(W * 0.5, wh, cz1), wc, EnvGeo.NO_BOTTOM)
		for x in [-W * 0.5 - 0.02, W * 0.5 - 0.38]:
			c.g.boxmm(Vector3(x, wh, cz0), Vector3(x + 0.4, wh + 0.08, cz1), c.trim, EnvGeo.ALL)
		for x in [-1.4, 1.4]:
			c.g.boxmm(Vector3(x - 0.3, 0, cz1 - 0.5), Vector3(x + 0.3, 3.0, cz1 + 0.0), c.wall, EnvGeo.NO_BOTTOM)
			c.g.boxmm(Vector3(x - 0.36, 3.0, cz1 - 0.56), Vector3(x + 0.36, 3.15, cz1 + 0.06), c.trim, EnvGeo.ALL)
		var fz := (cz0 + cz1) * 0.5
		if cz1 - cz0 > 4.0:
			c.g.cyl(Vector3(0, 0.05, fz), 1.5, 0.55, c.trim, 8, 1)
			c.g.cyl(Vector3(0, 0.05, fz), 1.32, 0.52, EnvGeo.c(Color(0.12, 0.25, 0.27), EnvGeo.GLASS), 8, 1)
			c.g.cyl(Vector3(0, 0.05, fz), 0.25, 1.1, c.trim, 8, 1)
			c.g.sphere(Vector3(0, 1.15, fz), Vector3(0.3, 0.3, 0.3), c.trim, 6, 8)


static func _finial(c: EnvBld, p: Vector3, s: float, gold: Color) -> void:
	c.g.cyl(p, 0.09 * s, 0.6 * s, gold, 6, 1)
	c.g.sphere(p + Vector3(0, 0.35 * s, 0), Vector3(0.2, 0.2, 0.2) * s, gold, 6, 8)
	c.g.sphere(p + Vector3(0, 0.62 * s, 0), Vector3(0.13, 0.13, 0.13) * s, gold, 6, 8)
	# crescent: an arc of short beams
	var cc := p + Vector3(0, 1.0 * s, 0)
	var prev := Vector3.ZERO
	for i in 7:
		var a := deg_to_rad(-60.0 + 240.0 * i / 6.0)
		var q := cc + Vector3(cos(a) * 0.24 * s, sin(a) * 0.24 * s, 0)
		if i > 0:
			c.g.beam(prev, q, 0.05 * s, 0.05 * s, gold)
		prev = q
	c.g.beam(p + Vector3(0, 0.62 * s, 0), cc + Vector3(0, -0.24 * s, 0), 0.05 * s, 0.05 * s, gold)


static func _minaret(c: EnvBld, p: Vector3, hall_top: float, lead: Color, gold: Color) -> void:
	var g := c.g
	var w := c.wall
	var t := c.trim
	var bh := hall_top + 1.4
	g.box(p + Vector3(0, bh * 0.5, 0), Vector3(2.5, bh, 2.5), w, EnvGeo.SIDES)
	for y in [bh * 0.33, bh * 0.66]:
		g.box(p + Vector3(0, y, 0), Vector3(2.54, 0.32, 2.54), c.base_c, EnvGeo.SIDES)
	g.box(p + Vector3(0, bh + 0.1, 0), Vector3(2.62, 0.2, 2.62), t, EnvGeo.ALL)
	var void_c := EnvGeo.c(Color(0.05, 0.05, 0.05), EnvGeo.VOID)
	for s in 4:
		var n := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][s] as Vector3
		var side := Vector3(n.z, 0, -n.x)
		var q := p + n * 1.26 + Vector3(0, bh * 0.5, 0)
		EnvBld.quadf(g, q - side * 0.18 - Vector3(0, 0.6, 0), q + side * 0.18 - Vector3(0, 0.6, 0), q + side * 0.18 + Vector3(0, 0.6, 0),
			q - side * 0.18 + Vector3(0, 0.6, 0), void_c, n)
	var y := bh + 0.2
	g.cyl(p + Vector3(0, y, 0), 1.2, 0.7, w, 8, 1, 0.92)
	y += 0.7
	var shaft_r := 0.9
	var sh := 9.5
	g.cyl(p + Vector3(0, y, 0), shaft_r, sh, w, 12, 0)
	for k in 3:
		g.cyl(p + Vector3(0, y + sh * (0.25 + 0.25 * k), 0), shaft_r + 0.04, 0.22, c.base_c, 12, 0)
	y += sh
	# balcony (sherefe): muqarnas-like corbel, floor, lattice parapet
	g.cyl(p + Vector3(0, y - 0.7, 0), shaft_r, 0.7, t, 12, 0, 1.2)
	g.cyl(p + Vector3(0, y, 0), 1.24, 0.12, t, 16, 3)
	g.cyl(p + Vector3(0, y + 0.12, 0), 1.2, 0.95, EnvGeo.c(c.wall_rgb.lerp(Color(1, 1, 1), 0.2), EnvGeo.MESH | EnvGeo.FLAG), 16, 0)
	g.cyl(p + Vector3(0, y + 1.07, 0), 1.24, 0.08, t, 16, 1)
	var uh := 3.6
	g.cyl(p + Vector3(0, y + 0.12, 0), 0.72, uh, w, 12, 1)
	y += 0.12 + uh
	g.cyl(p + Vector3(0, y, 0), 0.86, 0.22, t, 12, 1)
	y += 0.22
	g.cyl(p + Vector3(0, y, 0), 0.82, 4.0, lead, 12, 2, 0.0)
	_finial(c, p + Vector3(0, y + 3.85, 0), 0.8, gold)


static func _arcade(c: EnvBld, rect: Rect2, dome_c: Color, gold: Color) -> void:
	var g := c.g
	var top := 5.6
	var t := 0.55
	c.set_frame(rect)
	var w := c.fw(0)
	var n := maxi(3, int(round(w / 3.4)))
	var step := w / n
	var pier := 0.6
	var head := 4.6
	var saved_r := c.r
	c.r = t
	# floor platform and roof slab
	g.boxmm(Vector3(rect.position.x, 0, rect.position.y), Vector3(rect.end.x, 0.3, rect.end.y), c.base_c, EnvGeo.NO_BOTTOM)
	g.boxmm(Vector3(rect.position.x, top - 0.35, rect.position.y), Vector3(rect.end.x, top, rect.end.y), c.wall, EnvGeo.ALL)
	g.boxmm(Vector3(rect.position.x - 0.05, top, rect.position.y), Vector3(rect.end.x + 0.05, top + 0.12, rect.end.y + 0.08), c.trim, EnvGeo.ALL)
	# front arcade wall (side 0 faces +Z)
	c.fbox(g, 0, 0.0, w, head, top - 0.35, -t, 0.0, c.wall, EnvBld.FRONT | EnvBld.BACK | EnvBld.BOT)
	for i in n + 1:
		var uc := step * i
		var u0 := maxf(0.0, uc - pier * 0.5)
		var u1 := minf(w, uc + pier * 0.5)
		c.fbox(g, 0, u0, u1, 0.3, head, -t, 0.0, c.wall, EnvBld.FRONT | EnvBld.BACK | EnvBld.LEFT | EnvBld.RIGHT)
		c.fbox(g, 0, u0 - 0.06, u1 + 0.06, 3.05, 3.25, -t - 0.06, 0.06, c.trim, EnvBld.BOX5 | EnvBld.BACK)
	for i in n:
		var a0 := step * i + pier * 0.5
		var a1 := step * (i + 1) - pier * 0.5
		var R := (a1 - a0) * 0.5
		var hh := 3.25 + R
		if hh > head:
			hh = head
		c.fbox(g, 0, a0, a1, hh, head, -t, 0.0, c.wall, EnvBld.FRONT | EnvBld.BACK | EnvBld.BOT)
		c._arch_fill(0, a0, a1, hh)
		_arch_back(c, a0, a1, hh, -t)
		c._voussoirs(0, a0, a1, hh, c.trim, c.base_c)
		# small dome over each bay
		var bc := c.fp(0, (a0 + a1) * 0.5, top + 0.12, -rect.size.y * 0.5)
		var dr := minf(step, rect.size.y) * 0.36
		g.cyl(bc, dr + 0.1, 0.35, c.wall, 12, 1)
		g.sphere(bc + Vector3(0, 0.35, 0), Vector3(dr, dr, dr), dome_c, 10, 12, true)
		g.cyl(bc + Vector3(0, 0.35 + dr, 0), 0.05, 0.4, gold, 6, 1)
	# side ends of the arcade
	for s in [1, 3]:
		c.fbox(g, s, 0.0, c.fw(s), 0.3, top - 0.35, -t, 0.0, c.wall, EnvBld.FRONT | EnvBld.BACK)
	c.r = saved_r


## Back face of an arch fill (arcades are seen from both sides).
static func _arch_back(c: EnvBld, u0: float, u1: float, yh: float, d: float) -> void:
	var R := (u1 - u0) * 0.5
	var uc := (u0 + u1) * 0.5
	var ys := yh - R
	var seg := 8
	var back := -c.fnormal(0)
	for i in seg:
		var t0 := PI - PI * float(i) / seg
		var t1 := PI - PI * float(i + 1) / seg
		var ua := uc + cos(t0) * R
		var ub := uc + cos(t1) * R
		EnvBld.quadf(c.g, c.fp(0, ua, ys + sin(t0) * R, d), c.fp(0, ub, ys + sin(t1) * R, d), c.fp(0, ub, yh, d), c.fp(0, ua, yh, d), c.wall, back)


# ------------------------------------------------------------------ industrial -

static func industrial(c: EnvBld) -> void:
	if c.rng.chance(0.65):
		_warehouse(c)
	else:
		_workshop(c)


static func _warehouse(c: EnvBld) -> void:
	var rng := c.rng
	var g := c.g
	var W := c.W
	var D := c.D
	var H := c.H
	var ridge_x := W >= D
	var span := D if ridge_x else W
	var rise := clampf(span * 0.08, 0.6, 1.6)
	var eave := H - rise
	var plinth_h := 1.2
	var wall_rgb: Color = [Color(0.7, 0.72, 0.72), Color(0.78, 0.72, 0.6), Color(0.38, 0.47, 0.58), Color(0.47, 0.56, 0.49),
		Color(0.56, 0.32, 0.26), Color(0.86, 0.86, 0.84), Color(0.72, 0.66, 0.55), Color(0.6, 0.62, 0.62)][int(c.b.get("color", 0)) % 8]
	wall_rgb = c.jit(wall_rgb, 0.05)
	var wc := EnvGeo.c(wall_rgb, EnvGeo.CORRUGATED)
	var roof_rgb := c.jit(Color(0.62, 0.63, 0.63) if rng.chance(0.6) else Color(0.55, 0.45, 0.38), 0.05)
	var rc := EnvGeo.c(roof_rgb, EnvGeo.CORRUGATED | (0 if ridge_x else EnvGeo.FLAG))
	var pc := EnvGeo.c(c.jit(Color(0.62, 0.6, 0.56), 0.05), EnvGeo.CONCRETE | EnvGeo.FLAG)
	var steel := EnvGeo.c(Color(0.25, 0.26, 0.27), EnvGeo.METAL)
	c.r = 0.15
	c.void_c = EnvGeo.c(Color(0.05, 0.045, 0.04), EnvGeo.VOID)
	c.shutter_rgb = c.pick_col(EnvBld.SHUTTER_COLS)
	c.wall = wc
	c.wall_rgb = wall_rgb
	c.wall_surf = EnvGeo.CORRUGATED
	var rect := Rect2(-W * 0.5, -D * 0.5, W, D)
	c.set_frame(rect)
	g.box(Vector3(0, eave * 0.5, 0), Vector3(W - 0.3, eave, D - 0.3), c.void_c, EnvGeo.SIDES)
	for s in 4:
		var w := c.fw(s)
		var gable := (s == 1 or s == 3) if ridge_x else (s == 0 or s == 2)
		var doors: Array = []
		if (gable and rng.chance(0.85)) or (not gable and rng.chance(0.35)):
			var nd := 2 if w > 18.0 and rng.chance(0.5) else 1
			var dw := minf(5.0, w * 0.32)
			for i in nd:
				var uc := w * (i + 1) / (nd + 1)
				doors.append([uc - dw * 0.5, uc + dw * 0.5, minf(eave - 0.7, 4.6), 0])
		if not gable and rng.chance(0.6) and w > 6.0:
			var uc := rng.range_f(1.5, w - 1.5)
			var ok := true
			for d in doors:
				if uc + 0.6 > float(d[0]) - 0.5 and uc - 0.6 < float(d[1]) + 0.5:
					ok = false
			if ok:
				doors.append([uc - 0.5, uc + 0.5, 2.1, 1])
		doors.sort_custom(func(a, bb): return a[0] < bb[0])
		var cu := 0.0
		var max_door := 0.0
		for d in doors:
			var u0: float = d[0]
			var u1: float = d[1]
			var dh: float = d[2]
			max_door = maxf(max_door, dh)
			_wall_seg(c, s, cu, u0, eave, plinth_h, wc, pc, cu > 0.0, true)
			c.fbox(g, s, u0, u1, dh, eave, -c.r, 0.0, wc, EnvBld.FRONT | EnvBld.BOT)
			c.ops_log.append([rect, s, u0, u1, 0.0, dh, EnvBld.O_GARAGE])
			if int(d[3]) == 0:
				c._garage(s, u0, u1, 0.0, dh)
			else:
				c.fquad(g, s, u0, u1, 0.0, dh, -c.r + 0.03, EnvGeo.c(Color(0.35, 0.37, 0.38), EnvGeo.METAL))
			cu = u1
		_wall_seg(c, s, cu, w, eave, plinth_h, wc, pc, cu > 0.0, false)
		if doors.is_empty():
			c.ops_log.append([rect, s, w * 0.3, w * 0.7, 1.0, eave - 0.5, EnvBld.O_WIN])
		# translucent panel band under the eave
		var band0 := maxf(max_door + 0.3, eave - 1.4)
		if rng.chance(0.65) and eave - band0 > 0.5:
			c.fquad(g, s, 0.3, w - 0.3, band0, eave - 0.3, 0.012, EnvGeo.c(Color(0.82, 0.84, 0.8), EnvGeo.CORRUGATED))
		if gable:
			g.tri(c.fp(s, 0.0, eave, 0.0), c.fp(s, w, eave, 0.0), c.fp(s, w * 0.5, H, 0.0), wc)
		c.fbox(g, s, 0.0, 0.2, 0.0, eave, 0.0, 0.1, steel, EnvBld.BOX5)
		c.fbox(c.dt, s, 0.3, 0.42, 0.0, eave, 0.02, 0.14, steel, EnvBld.BOX5)
	# roof: two corrugated slopes with overhang, ridge cap, skylights, vents
	var ov := 0.3
	var hs := span * 0.5
	var th := atan(rise / hs)
	var lw := (hs + ov) / cos(th)
	var length := (W if ridge_x else D) + 2.0 * ov
	var hole := EnvGeo.c(Color(0.03, 0.03, 0.03), EnvGeo.VOID)
	var sky := EnvGeo.c(Color(0.86, 0.88, 0.84), EnvGeo.CORRUGATED | (0 if ridge_x else EnvGeo.FLAG))
	for side in [-1.0, 1.0]:
		var bas: Basis
		var ctr: Vector3
		var mid := (hs + ov) * 0.5
		var y_mid := eave + rise * 0.5 - ov * tan(th) * 0.5
		if ridge_x:
			bas = Basis(Vector3.RIGHT, -th * side)
			ctr = Vector3(0, y_mid, -side * mid)
		else:
			bas = Basis(Vector3.BACK, th * side)
			ctr = Vector3(-side * mid, y_mid, 0)
		ctr += bas.y * 0.04
		var sz := Vector3(length, 0.08, lw) if ridge_x else Vector3(lw, 0.08, length)
		g.obox(Transform3D(bas, ctr), sz, rc, EnvGeo.ALL)
		var nsky := rng.range_i(0, 3)
		for k in nsky:
			var off := (k + 1.0) / (nsky + 1.0) - 0.5
			var ssz := Vector3(1.2, 0.02, lw * 0.75) if ridge_x else Vector3(lw * 0.75, 0.02, 1.2)
			var sofs := Vector3(off * length * 0.9, 0, 0) if ridge_x else Vector3(0, 0, off * length * 0.9)
			g.obox(Transform3D(bas, ctr + bas.y * 0.05 + sofs), ssz, sky, EnvGeo.PY)
		if c.damage > 0:
			for k in c.drng.range_i(1, 3):
				var off := c.drng.range_f(-0.4, 0.4)
				var along := c.drng.range_f(-0.3, 0.3)
				var hsz := Vector3(c.drng.range_f(1.5, 4.0), 0.02, c.drng.range_f(1.0, 2.5))
				if not ridge_x:
					hsz = Vector3(hsz.z, 0.02, hsz.x)
				var hofs := Vector3(off * length, 0, along * lw) if ridge_x else Vector3(along * lw, 0, off * length)
				g.obox(Transform3D(bas, ctr + bas.y * 0.06 + bas * hofs), hsz, hole, EnvGeo.PY)
	var rl := length
	g.box(Vector3(0, H + 0.06, 0), Vector3(rl, 0.12, 0.45) if ridge_x else Vector3(0.45, 0.12, rl), EnvGeo.c(roof_rgb.darkened(0.15), EnvGeo.METAL), EnvGeo.ALL)
	for k in rng.range_i(1, 4):
		var t := rng.range_f(-0.4, 0.4) * rl
		var vp := Vector3(t, H + 0.1, 0) if ridge_x else Vector3(0, H + 0.1, t)
		c.dt.cyl(vp, 0.22, 0.45, EnvGeo.c(Color(0.7, 0.71, 0.72), EnvGeo.METAL), 8, 0)
		c.dt.sphere(vp + Vector3(0, 0.45, 0), Vector3(0.25, 0.2, 0.25), EnvGeo.c(Color(0.7, 0.71, 0.72), EnvGeo.METAL), 6, 8, true)


static func _wall_seg(c: EnvBld, s: int, u0: float, u1: float, top: float, ph: float, wc: Color, pc: Color, lft: bool, rgt: bool) -> void:
	if u1 <= u0 + 0.005:
		return
	var fm := EnvBld.FRONT | (EnvBld.LEFT if lft else 0) | (EnvBld.RIGHT if rgt else 0)
	c.fbox(c.g, s, u0, u1, 0.0, ph, -c.r, 0.03, pc, fm | EnvBld.TOP)
	c.fbox(c.g, s, u0, u1, ph, top, -c.r, 0.0, wc, fm)


static func _workshop(c: EnvBld) -> void:
	var rng := c.rng
	c.setup_look(0.0)
	c.wall_rgb = c.wall_rgb.lerp(Color(0.8, 0.8, 0.78), 0.3)
	c.wall_surf = EnvGeo.CONCRETE if rng.chance(0.5) else EnvGeo.PLASTER
	c.wall = EnvGeo.c(c.wall_rgb, c.wall_surf | (EnvGeo.FLAG if c.wall_surf == EnvGeo.CONCRETE else 0))
	c.r = 0.22
	c.win_style = 0
	c.shutter_p = 0.3
	c.grime_p = 0.4
	c.ac_p = 0.1
	var ls := EnvStyles.long_sides(c)
	c.entry_side = ls[rng.range_i(0, 1)]
	var rect := EnvStyles.footprint(c)
	var roof_y := c.body(rect, 0.0, c.F, 1.0, EnvBld.P_WORKSHOP, 4.5)
	c.plinth(rect, 0.6)
	# company sign band over the doors
	c.set_frame(rect)
	var s := c.entry_side
	var w := c.fw(s)
	var sgc := EnvGeo.c(c.pick_col(EnvBld.SIGN_COLS).lerp(Color(0.7, 0.68, 0.62), 0.3), EnvGeo.METAL)
	c.fbox(c.g, s, w * 0.2, w * 0.8, 3.95, 4.4, 0.0, 0.08, sgc, EnvBld.BOX5)
	var occ: Array = []
	c.roof_clutter(c.roofs[0][0], roof_y, 0.25, occ)
	# exhaust stack
	if rng.chance(0.5):
		var rr: Rect2 = c.roofs[0][0]
		var p := Vector3(rr.end.x - 1.0, roof_y, rr.position.y + 1.0)
		c.g.cyl(p, 0.35, rng.range_f(3.0, 6.0), EnvGeo.c(Color(0.45, 0.4, 0.36), EnvGeo.RUST), 10, 1)


# ------------------------------------------------------------------ unfinished -

static func unfinished(c: EnvBld) -> void:
	var rng := c.rng
	var g := c.g
	var W := c.W
	var D := c.D
	var F := c.F
	var cc := EnvGeo.c(c.jit(Color(0.63, 0.62, 0.59), 0.04), EnvGeo.CONCRETE)
	var bc := EnvGeo.c(c.jit(Color(0.6, 0.58, 0.55), 0.05), EnvGeo.CONCRETE | EnvGeo.FLAG)
	var dark := EnvGeo.c(Color(0.06, 0.055, 0.05), EnvGeo.VOID)
	var st := 0.22
	var cs := 0.36
	var nx := maxi(2, int(round(W / 4.2)) + 1)
	var nz := maxi(2, int(round(D / 4.2)) + 1)
	var xs: Array = []
	var zs: Array = []
	for i in nx:
		xs.append(-W * 0.5 + cs * 0.5 + (W - cs) * i / (nx - 1))
	for j in nz:
		zs.append(-D * 0.5 + cs * 0.5 + (D - cs) * j / (nz - 1))
	c.wall = bc
	c.wall_rgb = Color(0.6, 0.58, 0.55)
	c.wall_surf = EnvGeo.CONCRETE
	g.box(Vector3(0, 0.075, 0), Vector3(W, 0.15, D), cc, EnvGeo.NO_BOTTOM)
	var ruin := F <= 1
	var top_partial := (F >= 2 and rng.chance(0.5)) or ruin
	var rect := Rect2(-W * 0.5, -D * 0.5, W, D)
	c.set_frame(rect)
	for k in F:
		var y0 := 0.15 if k == 0 else k * FH
		var y1 := (k + 1) * FH - st
		var last := k == F - 1
		# slab above this storey
		if last and top_partial:
			var frac := rng.range_f(0.35, 0.75)
			if W >= D:
				g.boxmm(Vector3(-W * 0.5, y1, -D * 0.5), Vector3(-W * 0.5 + W * frac, y1 + st, D * 0.5), cc, EnvGeo.ALL)
			else:
				g.boxmm(Vector3(-W * 0.5, y1, -D * 0.5), Vector3(W * 0.5, y1 + st, -D * 0.5 + D * frac), cc, EnvGeo.ALL)
		else:
			g.box(Vector3(0, y1 + st * 0.5, 0), Vector3(W, st, D), cc, EnvGeo.ALL)
		for x in xs:
			for z in zs:
				g.box(Vector3(x, (y0 + y1) * 0.5, z), Vector3(cs, y1 - y0, cs), cc, EnvGeo.SIDES)
		# block infill on perimeter bays, more on lower floors
		var fill_p := clampf(0.65 - 0.18 * k, 0.1, 0.65) if not ruin else 0.25
		for s in 4:
			var w := c.fw(s)
			var n := (nx if s % 2 == 0 else nz) - 1
			var step := (w - cs) / n
			for i in n:
				if not rng.chance(fill_p):
					continue
				var u0 := cs * 0.5 + step * i + cs * 0.5
				var u1 := u0 + step - cs
				var d0 := -cs * 0.5 - 0.1
				var d1 := -cs * 0.5 + 0.1
				if rng.chance(0.55) and u1 - u0 > 2.0:
					var wu := rng.range_f(1.0, minf(1.8, u1 - u0 - 0.8))
					var wc := rng.range_f(u0 + wu * 0.5 + 0.4, u1 - wu * 0.5 - 0.4)
					var sy := y0 + 0.9
					var hy := minf(y1 - 0.3, y0 + 2.3)
					c.fbox(g, s, u0, wc - wu * 0.5, y0, y1, d0, d1, bc, EnvBld.FRONT | EnvBld.BACK | EnvBld.RIGHT)
					c.fbox(g, s, wc + wu * 0.5, u1, y0, y1, d0, d1, bc, EnvBld.FRONT | EnvBld.BACK | EnvBld.LEFT)
					c.fbox(g, s, wc - wu * 0.5, wc + wu * 0.5, y0, sy, d0, d1, bc, EnvBld.FRONT | EnvBld.BACK | EnvBld.TOP)
					c.fbox(g, s, wc - wu * 0.5, wc + wu * 0.5, hy, y1, d0, d1, bc, EnvBld.FRONT | EnvBld.BACK | EnvBld.BOT)
					c.ops_log.append([rect, s, wc - wu * 0.5, wc + wu * 0.5, sy, hy, EnvBld.O_WIN])
				else:
					c.fbox(g, s, u0, u1, y0, y1, d0, d1, bc, EnvBld.FRONT | EnvBld.BACK)
		# building materials and debris on the slab
		for i in rng.range_i(1, 3):
			var p := Vector3(rng.range_f(-W * 0.4, W * 0.4), y0, rng.range_f(-D * 0.4, D * 0.4))
			if rng.chance(0.5):
				g.sphere(p, Vector3(rng.range_f(0.6, 1.2), rng.range_f(0.25, 0.5), rng.range_f(0.6, 1.2)),
					EnvGeo.c(Color(0.7, 0.62, 0.5), EnvGeo.RUBBLE), 6, 8, true)
			else:
				g.box(p + Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 1.0), bc, EnvGeo.NO_BOTTOM)
				g.box(p + Vector3(0, 0.06, 0), Vector3(1.25, 0.12, 1.05), EnvGeo.c(Color(0.45, 0.33, 0.2), EnvGeo.WOOD), EnvGeo.SIDES)
		# shoring props under fresh slabs
		if (last or k == F - 2) and rng.chance(0.5):
			for i in rng.range_i(4, 10):
				var px := rng.range_f(-W * 0.4, W * 0.4)
				var pz := rng.range_f(-D * 0.4, D * 0.4)
				c.dt.box(Vector3(px, (y0 + y1) * 0.5, pz), Vector3(0.06, y1 - y0, 0.06), EnvGeo.c(Color(0.5, 0.4, 0.25), EnvGeo.RUST), EnvGeo.SIDES)
	# stair core
	var sx := rng.range_f(-W * 0.25, W * 0.25)
	var sz := rng.range_f(-D * 0.25, D * 0.25)
	var core_h := F * FH + (2.4 if not ruin else 0.0)
	if not ruin:
		g.box(Vector3(sx, core_h * 0.5, sz), Vector3(2.6, core_h, 3.4), cc, EnvGeo.NO_BOTTOM)
		g.box(Vector3(sx + 1.31, core_h - 1.3, sz), Vector3(0.02, 2.0, 1.0), dark, EnvGeo.PX)
	# columns started above the top slab, with rebar everywhere on top
	var ty := F * FH
	for x in xs:
		for z in zs:
			var on_slab := true
			if top_partial:
				on_slab = (x as float) < -W * 0.5 + W * 0.35 if W >= D else (z as float) < -D * 0.5 + D * 0.35
			var stub := rng.range_f(0.3, 1.6) if rng.chance(0.4) else 0.0
			var base_y := ty if on_slab else ty - st
			if stub > 0.0:
				g.box(Vector3(x, base_y + stub * 0.5, z), Vector3(cs, stub, cs), cc, EnvGeo.NO_BOTTOM)
			EnvBld.rebar(c.dt, Vector3(x, base_y + stub, z), rng.range_f(0.6, 1.2), rng)
	# partial block parapet
	if not ruin:
		for s in 4:
			if rng.chance(0.4):
				var w := c.fw(s)
				c.fbox(g, s, 0.0, w * rng.range_f(0.3, 1.0), ty, ty + 1.0, -0.2, 0.0, bc, EnvBld.FRONT | EnvBld.BACK | EnvBld.TOP | EnvBld.LEFT | EnvBld.RIGHT)
	# debris and sand around the site
	for i in rng.range_i(2, 5):
		var a := rng.range_f(0, TAU)
		var p := Vector3(cos(a) * W * 0.55, 0, sin(a) * D * 0.55)
		p.x = clampf(p.x, -W * 0.5 - 1.0, W * 0.5 + 1.0)
		p.z = clampf(p.z, -D * 0.5 - 1.0, D * 0.5 + 1.0)
		g.sphere(p, Vector3(rng.range_f(0.8, 1.6), rng.range_f(0.3, 0.7), rng.range_f(0.8, 1.6)),
			EnvGeo.c(Color(0.72, 0.64, 0.5), EnvGeo.RUBBLE), 6, 8, true)
	if ruin:
		_rubble_field(c, Rect2(-W * 0.5, -D * 0.5, W, D), 0.9, 25)
	if c.damage > 0:
		for i in c.drng.range_i(1, 3):
			var p := Vector3(c.drng.range_f(-W * 0.3, W * 0.3), c.drng.range_f(1.0, maxf(1.5, ty - 1.0)), c.drng.range_f(-D * 0.3, D * 0.3))
			var bas := Basis.from_euler(Vector3(c.drng.range_f(-0.5, 0.5), c.drng.range_f(0, TAU), c.drng.range_f(-0.5, 0.5)))
			g.obox(Transform3D(bas, p), Vector3(c.drng.range_f(2.0, 4.0), st, c.drng.range_f(1.5, 3.0)), cc, EnvGeo.ALL)
		_rubble_field(c, Rect2(-W * 0.5, -D * 0.5, W, D), 0.6, 15)


# ------------------------------------------------------------------ ruins ------

## Collapsed building: faceted rubble mound (~1.6 m) over the footprint, broken slabs,
## jagged ground-floor wall stubs, column stumps and rebar.
static func ruin(c: EnvBld) -> void:
	var rng := c.rng
	var g := c.g
	var W := c.W
	var D := c.D
	match c.style:
		MapDef.S_OLD, MapDef.S_MOSQUE:
			c.setup_look(0.7)
		MapDef.S_INDUSTRIAL, MapDef.S_UNFINISHED:
			c.setup_look(0.0)
			c.wall_rgb = Color(0.62, 0.61, 0.58)
		_:
			c.setup_look(0.3)
	var wall_rgb := c.wall_rgb
	var conc := Color(0.6, 0.59, 0.56)
	var base_tint := wall_rgb.darkened(0.12).lerp(conc, 0.45)
	var hm := 1.85
	var cell := 1.25
	var ext := 0.6
	var nx := maxi(3, int(ceil((W + 2.0 * ext) / cell)))
	var nz := maxi(3, int(ceil((D + 2.0 * ext) / cell)))
	var hx := W * 0.5 + ext
	var hz := D * 0.5 + ext
	var hts := PackedFloat32Array()
	hts.resize((nx + 1) * (nz + 1))
	var heaps: Array = []
	for k in clampi(int(W * D / 45.0), 2, 6):
		heaps.append(Vector3(rng.range_f(-W * 0.35, W * 0.35), rng.range_f(0.5, 1.0), rng.range_f(-D * 0.35, D * 0.35)))
	for j in nz + 1:
		for i in nx + 1:
			var u := -1.0 + 2.0 * i / nx
			var v := -1.0 + 2.0 * j / nz
			var e := maxf(absf(u), absf(v))
			var shape := clampf(1.0 - pow(e, 3.0), 0.0, 1.0)
			var x := u * hx
			var z := v * hz
			var bump := 0.0
			for hp in heaps:
				var dd := Vector2(x - hp.x, z - hp.z).length()
				bump = maxf(bump, hp.y * exp(-dd * dd / 9.0))
			var hh := clampf(hm * shape * (0.7 + 0.5 * bump) * rng.range_f(0.8, 1.15), 0.0, 2.1)
			if i == 0 or j == 0 or i == nx or j == nz:
				hh = 0.0
			hts[j * (nx + 1) + i] = hh
	for j in nz:
		for i in nx:
			var x0 := -hx + 2.0 * hx * i / nx
			var x1 := -hx + 2.0 * hx * (i + 1) / nx
			var z0 := -hz + 2.0 * hz * j / nz
			var z1 := -hz + 2.0 * hz * (j + 1) / nz
			var hmid := hts[j * (nx + 1) + i]
			var tint := base_tint.lerp(wall_rgb, clampf(hmid / hm, 0.0, 1.0) * 0.35).darkened(rng.range_f(-0.03, 0.07))
			var col := EnvGeo.c(tint, EnvGeo.RUBBLE)
			var a := Vector3(x0, hts[j * (nx + 1) + i], z0)
			var bb := Vector3(x0, hts[(j + 1) * (nx + 1) + i], z1)
			var cc := Vector3(x1, hts[(j + 1) * (nx + 1) + i + 1], z1)
			var d := Vector3(x1, hts[j * (nx + 1) + i + 1], z0)
			if (i + j) % 2 == 0:
				g.tri(a, bb, cc, col)
				g.tri(a, cc, d, col)
			else:
				g.tri(a, bb, d, col)
				g.tri(bb, cc, d, col)
	# jagged stubs of the ground-floor walls
	var wc := EnvGeo.c(wall_rgb, c.wall_surf)
	c.set_frame(Rect2(-W * 0.5, -D * 0.5, W, D))
	for s in 4:
		var w := c.fw(s)
		var u := 0.0
		while u < w - 0.05:
			var sw := minf(rng.range_f(0.5, 1.6), w - u)
			if rng.chance(0.72):
				var hh := rng.range_f(0.3, 2.2) * (1.0 if rng.chance(0.7) else 0.4)
				c.fbox(g, s, u, u + sw, 0.0, hh, -0.3, 0.0, wc, EnvBld.FRONT | EnvBld.BACK | EnvBld.TOP | EnvBld.LEFT | EnvBld.RIGHT)
			u += sw
	# one standing corner remnant with an empty window
	if rng.chance(0.7) and W > 6.0 and D > 6.0:
		var s0 := rng.range_i(0, 3)
		var s1 := (s0 + 1) % 4
		var ch := rng.range_f(2.4, 3.6)
		var w0 := c.fw(s0)
		var lw := rng.range_f(1.6, minf(4.0, w0 * 0.5))
		c.fbox(g, s0, w0 - lw, w0, 0.0, ch, -0.3, 0.0, wc, EnvBld.FRONT | EnvBld.BACK | EnvBld.TOP | EnvBld.LEFT)
		c.fquad(g, s0, w0 - lw * 0.6, w0 - lw * 0.6 + 0.8, 1.0, 2.2, 0.012, EnvGeo.c(Color(0.05, 0.045, 0.04), EnvGeo.VOID))
		var lw1 := rng.range_f(1.2, minf(3.0, c.fw(s1) * 0.4))
		var ch1 := ch * rng.range_f(0.5, 0.9)
		c.fbox(g, s1, 0.0, lw1, 0.0, ch1, -0.3, 0.0, wc, EnvBld.FRONT | EnvBld.BACK | EnvBld.TOP | EnvBld.RIGHT)
		var cp := c.fp(s0, w0 - 0.15, 0.0, -0.15)
		EnvBld.rebar(c.dt, cp + Vector3(0, ch, 0), rng.range_f(0.4, 0.8), rng)
	# broken slabs, partly buried and tilted
	var slab_c := EnvGeo.c(conc, EnvGeo.CONCRETE)
	for i in clampi(int(W * D / 30.0), 2, 7):
		var p := Vector3(rng.range_f(-W * 0.35, W * 0.35), 0.0, rng.range_f(-D * 0.35, D * 0.35))
		p.y = _mound_h(hts, nx, nz, hx, hz, p.x, p.z) * 0.7
		var bas := Basis.from_euler(Vector3(rng.range_f(-0.6, 0.6), rng.range_f(0, TAU), rng.range_f(-0.6, 0.6)))
		var sz := Vector3(rng.range_f(1.5, 3.5), 0.22, rng.range_f(1.2, 2.8))
		g.obox(Transform3D(bas, p), sz, slab_c, EnvGeo.ALL)
		EnvBld.rebar(c.dt, p + bas.x * sz.x * 0.5, rng.range_f(0.4, 0.9), rng)
	_rubble_field(c, Rect2(-W * 0.5, -D * 0.5, W, D), 1.2, clampi(int(W * D / 2.2), 30, 180), hts, nx, nz, hx, hz)
	# column stumps
	for i in rng.range_i(1, 4):
		var p := Vector3(rng.range_f(-W * 0.4, W * 0.4), 0.0, rng.range_f(-D * 0.4, D * 0.4))
		var ch := rng.range_f(1.2, 2.6)
		g.box(p + Vector3(0, ch * 0.5, 0), Vector3(0.36, ch, 0.36), slab_c, EnvGeo.NO_BOTTOM)
		EnvBld.rebar(c.dt, p + Vector3(0, ch, 0), rng.range_f(0.5, 1.0), rng)
	# a few personal things: water tank, door leaf
	if rng.chance(0.6):
		var p := Vector3(rng.range_f(-W * 0.3, W * 0.3), 0.0, rng.range_f(-D * 0.3, D * 0.3))
		p.y = _mound_h(hts, nx, nz, hx, hz, p.x, p.z) + 0.4
		g.cyl(p, 0.5, 1.1, EnvGeo.c(Color(0.08, 0.08, 0.085), EnvGeo.METAL), 10, 3, -1.0,
			Basis.from_euler(Vector3(rng.range_f(1.0, 1.6), rng.range_f(0, TAU), 0)))


static func _mound_h(hts: PackedFloat32Array, nx: int, nz: int, hx: float, hz: float, x: float, z: float) -> float:
	if hts.is_empty():
		return 0.0
	var i := clampi(int((x + hx) / (2.0 * hx) * nx + 0.5), 0, nx)
	var j := clampi(int((z + hz) / (2.0 * hz) * nz + 0.5), 0, nz)
	return hts[j * (nx + 1) + i]


## Scatter of concrete/plaster chunks (on a mound when heights are given).
static func _rubble_field(c: EnvBld, rect: Rect2, scale: float, count: int, hts: PackedFloat32Array = PackedFloat32Array(),
		nx: int = 0, nz: int = 0, hx: float = 1.0, hz: float = 1.0) -> void:
	var rng := c.rng
	var conc := Color(0.6, 0.59, 0.56)
	for i in count:
		var x := rng.range_f(rect.position.x, rect.end.x)
		var z := rng.range_f(rect.position.y, rect.end.y)
		if not hts.is_empty() and rng.chance(0.5):
			# pull toward the highest neighbouring ground so chunks pile up on the heaps
			var best := Vector2(x, z)
			var bh := _mound_h(hts, nx, nz, hx, hz, x, z)
			for t in 3:
				var q := Vector2(x + rng.range_f(-2.0, 2.0), z + rng.range_f(-2.0, 2.0))
				var qh := _mound_h(hts, nx, nz, hx, hz, q.x, q.y)
				if qh > bh and rect.has_point(q):
					best = q
					bh = qh
			x = best.x
			z = best.y
		var y := _mound_h(hts, nx, nz, hx, hz, x, z) if not hts.is_empty() else 0.0
		var sz := Vector3(rng.range_f(0.25, 1.1), rng.range_f(0.15, 0.6), rng.range_f(0.25, 0.9)) * scale
		var bas := Basis.from_euler(Vector3(rng.range_f(-0.6, 0.6), rng.range_f(0, TAU), rng.range_f(-0.6, 0.6)))
		var tint := c.wall_rgb.darkened(rng.range_f(0.0, 0.3)) if rng.chance(0.5) else conc.darkened(rng.range_f(0.0, 0.3))
		c.g.obox(Transform3D(bas, Vector3(x, y + sz.y * 0.25, z)), sz, EnvGeo.c(tint, EnvGeo.RUBBLE if rng.chance(0.5) else EnvGeo.CONCRETE), EnvGeo.ALL)

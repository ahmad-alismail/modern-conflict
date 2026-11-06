extends RefCounted
## Wall segment builders for PropBuilder.build_walls: plastered compound walls with
## coping and pilasters, low garden walls, HESCO bastions (wire mesh + sand), sandbags.
## Variation is hashed from the endpoints so it is stable across rebuilds.
class_name EnvWalls


static func wall(g: EnvGeo, a: Vector2, b: Vector2, h: float, kind: int) -> void:
	var d := b - a
	var len := d.length()
	var bas := Basis(Vector3.UP, -d.angle())
	var o := Vector3(a.x, 0, a.y)
	var rng := Rng.new(int(a.x * 31.0) * 7349 + int(a.y * 17.0) * 3203 + int(b.x * 13.0) + kind)
	match kind:
		MapDef.W_COMPOUND: _compound(g, o, bas, len, h, rng)
		MapDef.W_LOW: _low(g, o, bas, len, h, rng)
		MapDef.W_HESCO: _hesco(g, o, bas, len, h, rng)
		MapDef.W_SANDBAG: _sandbags(g, o, bas, len, h, rng)
		_: _compound(g, o, bas, len, h, rng)


## Box in wall-local space: x along the wall from its start, y up, z across.
static func _lbox(g: EnvGeo, o: Vector3, bas: Basis, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
		col: Color, mask: int = EnvGeo.NO_BOTTOM) -> void:
	var c := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	g.obox(Transform3D(bas, o + bas * c), Vector3(x1 - x0, y1 - y0, z1 - z0), col, mask)


static func _compound(g: EnvGeo, o: Vector3, bas: Basis, len: float, h: float, rng: Rng) -> void:
	var rgb: Color = EnvBld.PLASTER_COLS[rng.range_i(0, 7)]
	rgb = rgb.darkened(rng.range_f(0.0, 0.1))
	var stone := rng.chance(0.3)
	var wc := EnvGeo.c(rgb, EnvGeo.STONE if stone else (EnvGeo.PLASTER | (EnvGeo.FLAG if rng.chance(0.5) else 0)))
	var trim := EnvGeo.c(rgb.lerp(Color(0.9, 0.88, 0.84), 0.4), EnvGeo.CONCRETE)
	var base := EnvGeo.c(rgb.darkened(0.3), EnvGeo.STONE)
	var t := 0.24
	_lbox(g, o, bas, 0.0, len, 0.0, h - 0.07, -t * 0.5, t * 0.5, wc, EnvGeo.ALL & ~EnvGeo.NY & ~EnvGeo.PY)
	_lbox(g, o, bas, -0.03, len + 0.03, h - 0.07, h, -t * 0.5 - 0.05, t * 0.5 + 0.05, trim, EnvGeo.ALL)
	_lbox(g, o, bas, 0.0, len, 0.0, 0.4, -t * 0.5 - 0.03, t * 0.5 + 0.03, base, EnvGeo.SIDES | EnvGeo.PY)
	var n := maxi(1, int(round(len / 3.2)))
	for i in n + 1:
		var x := clampf(len * i / n, 0.2, len - 0.2)
		_lbox(g, o, bas, x - 0.2, x + 0.2, 0.0, h + 0.12, -0.2, 0.2, wc, EnvGeo.NO_BOTTOM)
		_lbox(g, o, bas, x - 0.24, x + 0.24, h + 0.12, h + 0.2, -0.24, 0.24, trim, EnvGeo.ALL)
	# rust streaks / stains under the coping on some walls
	if rng.chance(0.4):
		var dark := EnvBld.shade(wc, 0.78)
		for i in rng.range_i(1, 3):
			var x := rng.range_f(0.5, maxf(0.6, len - 0.5))
			for side in [-1.0, 1.0]:
				var z: float = side * (t * 0.5 + 0.004)
				var p0 := o + bas * Vector3(x - 0.3, h - 0.07, z)
				var p1 := o + bas * Vector3(x + 0.3, h - 0.07, z)
				var p2 := o + bas * Vector3(x + 0.15, h - 1.2, z)
				var p3 := o + bas * Vector3(x - 0.15, h - 1.2, z)
				var nrm := bas * Vector3(0, 0, side)
				if (p1 - p0).cross(p2 - p0).dot(nrm) > 0.0:
					g.quad4(p3, p2, p1, p0, wc, wc, dark, dark)
				else:
					g.quad4(p2, p3, p0, p1, wc, wc, dark, dark)


static func _low(g: EnvGeo, o: Vector3, bas: Basis, len: float, h: float, rng: Rng) -> void:
	var rgb: Color = EnvBld.STONE_COLS[rng.range_i(0, 7)]
	var wc := EnvGeo.c(rgb, EnvGeo.STONE)
	var trim := EnvGeo.c(rgb.lerp(Color(0.9, 0.88, 0.84), 0.35), EnvGeo.CONCRETE)
	_lbox(g, o, bas, 0.0, len, 0.0, h - 0.06, -0.16, 0.16, wc, EnvGeo.SIDES)
	_lbox(g, o, bas, -0.02, len + 0.02, h - 0.06, h, -0.2, 0.2, trim, EnvGeo.ALL)
	if rng.chance(0.4):
		var mc := EnvGeo.c(Color(0.15, 0.15, 0.15), EnvGeo.METAL)
		_lbox(g, o, bas, 0.0, len, h + 0.75, h + 0.79, -0.02, 0.02, mc, EnvGeo.ALL)
		var n := maxi(2, int(len / 0.25))
		for i in n + 1:
			var x := len * i / n
			_lbox(g, o, bas, x - 0.012, x + 0.012, h, h + 0.85, -0.012, 0.012, mc, EnvGeo.SIDES | EnvGeo.PY)


static func _hesco(g: EnvGeo, o: Vector3, bas: Basis, len: float, h: float, rng: Rng) -> void:
	var cloth := EnvGeo.c(Color(0.74, 0.67, 0.52), EnvGeo.MESH)
	var sand := EnvGeo.c(Color(0.7, 0.62, 0.48), EnvGeo.RUBBLE)
	var post := EnvGeo.c(Color(0.28, 0.28, 0.27), EnvGeo.METAL)
	var cell := 1.06
	var n := maxi(1, int(round(len / cell)))
	var cw := len / n
	var dep := 1.06
	for i in n:
		var x0 := cw * i + 0.015
		var x1 := cw * (i + 1) - 0.015
		var hh := h - rng.range_f(0.0, 0.06)
		# slightly bulging fabric: wider at mid height
		_lbox(g, o, bas, x0, x1, 0.0, hh * 0.5, -dep * 0.5, dep * 0.5, cloth, EnvGeo.SIDES)
		_lbox(g, o, bas, x0 + 0.01, x1 - 0.01, hh * 0.5, hh, -dep * 0.5 + 0.02, dep * 0.5 - 0.02, cloth, EnvGeo.SIDES)
		_lbox(g, o, bas, x0 - 0.01, x1 + 0.01, hh * 0.2, hh * 0.62, -dep * 0.5 - 0.025, dep * 0.5 + 0.025, cloth, EnvGeo.SIDES)
		_lbox(g, o, bas, x0 + 0.03, x1 - 0.03, 0.0, hh - 0.12, -dep * 0.5 + 0.03, dep * 0.5 - 0.03, sand, EnvGeo.PY)
		for z in [-dep * 0.5, dep * 0.5]:
			_lbox(g, o, bas, x0 - 0.02, x0 + 0.02, 0.0, hh + 0.02, z - 0.02, z + 0.02, post, EnvGeo.NO_BOTTOM)
		# sagging tops: inner rim visible above the fill
		_lbox(g, o, bas, x0 + 0.01, x1 - 0.01, hh - 0.12, hh, -dep * 0.5 + 0.01, dep * 0.5 - 0.01, cloth,
			EnvGeo.SIDES)
	_lbox(g, o, bas, len - 0.02, len + 0.02, 0.0, h, -dep * 0.5 - 0.02, dep * 0.5 + 0.02, post, EnvGeo.NO_BOTTOM)


static func _sandbags(g: EnvGeo, o: Vector3, bas: Basis, len: float, h: float, rng: Rng) -> void:
	var cols := [Color(0.62, 0.55, 0.4), Color(0.56, 0.5, 0.38), Color(0.68, 0.6, 0.45), Color(0.5, 0.47, 0.36)]
	var bl := 0.56
	var bh := 0.15
	var bd := 0.34
	var rows := maxi(1, int(round(h / bh)))
	for r in rows:
		var y := r * bh
		var off := (bl * 0.5) if r % 2 == 1 else 0.0
		var x := -off
		while x < len - 0.05:
			var x0 := maxf(x, 0.0)
			var x1 := minf(x + bl, len)
			if x1 - x0 > 0.12:
				for zc in [-bd * 0.5, bd * 0.5]:
					var c := EnvGeo.c(cols[rng.range_i(0, 3)].darkened(rng.range_f(0.0, 0.1)), EnvGeo.VOID)
					var ctr := o + bas * Vector3((x0 + x1) * 0.5, y, zc + rng.range_f(-0.02, 0.02))
					g.taper(ctr, x1 - x0 - 0.02, bd - 0.03, x1 - x0 - 0.1, bd - 0.1, bh, c, EnvGeo.NO_BOTTOM, 0.0, 0.0,
						bas.get_euler().y + rng.range_f(-0.05, 0.05))
			x += bl

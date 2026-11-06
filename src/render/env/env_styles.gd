extends RefCounted
## Style compositions for BuildingBuilder: picks the look and massing for each MapDef.S_*
## style and drives EnvBld (generic facades) or EnvLandmarks (special buildings).
class_name EnvStyles


static func build(c: EnvBld) -> void:
	match c.style:
		MapDef.S_OLD: _old(c)
		MapDef.S_APARTMENT: _apartment(c, false)
		MapDef.S_SHOP: _apartment(c, true)
		MapDef.S_VILLA: _villa(c)
		MapDef.S_MOSQUE: EnvLandmarks.mosque(c)
		MapDef.S_INDUSTRIAL: EnvLandmarks.industrial(c)
		MapDef.S_UNFINISHED: EnvLandmarks.unfinished(c)
		MapDef.S_TOWER: _tower(c)
		_: _apartment(c, false)
	if c.damage > 0 and c.holes_cut < 2:
		var area := c.W * c.D
		c.damage_overlays(clampi(int(area / 90.0) + c.damage, 1, 5) - c.holes_cut)


static func footprint(c: EnvBld) -> Rect2:
	return Rect2(-c.W * 0.5, -c.D * 0.5, c.W, c.D)


## Long sides: 0/2 when the X extent is longer, else 1/3.
static func long_sides(c: EnvBld) -> Array:
	return [0, 2] if c.W >= c.D else [1, 3]


## Street-facing sides. Row-attached styles (old quarter, downtown shops) come from
## perimeter blocks of fixed depth (CityGenerator: 11 m / 17 m), so the lot axis closest
## to that depth runs street-to-courtyard and the faces across it are the open ones.
## Falls back to the long sides when the footprint does not match.
static func street_sides(c: EnvBld) -> Array:
	var d0 := 17.0 if c.style == MapDef.S_SHOP else (11.0 if c.style == MapDef.S_OLD else -1.0)
	if d0 > 0.0:
		var ex := absf(c.W - d0)
		var ez := absf(c.D - d0)
		if minf(ex, ez) < 1.5 and absf(ex - ez) > 0.3:
			return [1, 3] if ex < ez else [0, 2]
	return long_sides(c)


static func _set_street(c: EnvBld, sides: Array) -> void:
	c.street = 0
	for s in sides:
		c.street |= 1 << int(s)


static func _roof(c: EnvBld, roof_idx: int, kiosk_p: float, density: float) -> void:
	var rr: Rect2 = c.roofs[roof_idx][0]
	var y: float = c.roofs[roof_idx][1]
	var occ: Array = []
	var nroofs := c.roofs.size()
	if c.rng.chance(kiosk_p):
		c.kiosk(rr, y, occ)
	if c.rng.chance(0.3) and (c.style == MapDef.S_OLD or c.style == MapDef.S_APARTMENT or c.style == MapDef.S_SHOP):
		c.rooftop_room(rr, y, occ)
	c.roof_clutter(rr, y, density, occ)
	if c.roofs.size() > nroofs:
		var kr: Rect2 = c.roofs[nroofs][0]
		var ky: float = c.roofs[nroofs][1]
		c.roof_clutter(kr, ky, 0.35, [])


# ------------------------------------------------------------------ old quarter -

static func _old(c: EnvBld) -> void:
	var rng := c.rng
	c.setup_look(0.6)
	if c.wall_surf == EnvGeo.PLASTER:
		c.wall = EnvGeo.c(c.wall_rgb, EnvGeo.PLASTER | EnvGeo.FLAG)
	c.r = 0.3
	c.win_style = 1 if rng.chance(0.75) else 2
	c.head = rng.range_f(2.35, 2.6)
	c.grime_p = 0.75
	c.lintels = rng.chance(0.5)
	c.ac_p = 0.1
	c.mashra_p = 0.3
	c.arch_p = 0.25
	c.ablaq = c.wall_surf == EnvGeo.STONE and rng.chance(0.45)
	c.trim = EnvGeo.c(c.wall_rgb.lerp(Color(0.92, 0.89, 0.82), 0.4), EnvGeo.STONE)
	c.base_c = EnvGeo.c(Color(0.24, 0.23, 0.22) if c.ablaq else c.wall_rgb.darkened(0.3), EnvGeo.STONE)
	var ls := street_sides(c)
	_set_street(c, ls)
	c.entry_side = ls[rng.range_i(0, 1)]
	for s in [int(ls[0]) + 1, (int(ls[0]) + 3) % 4]:
		if rng.chance(0.45):
			c.blank_sides |= 1 << s
	var rect := footprint(c)
	var roof_y := c.body(rect, 0.0, c.F, 1.0, EnvBld.P_OLD)
	c.plinth(rect, 0.5)
	if c.ablaq:
		for k in range(1, c.F):
			c.stripe(rect, k * EnvBld.FH - 0.16, 0.32, c.base_c)
	c.cornice(rect, roof_y - 0.12, 1, c.street)
	_roof(c, 0, 0.25, 0.8)
	if rng.chance(0.25) and c.damage == 0:
		_pergola(c, c.roofs[0][0], roof_y)


static func _pergola(c: EnvBld, rr: Rect2, y: float) -> void:
	var rng := c.rng
	var pw := minf(rr.size.x - 0.6, rng.range_f(2.5, 4.0))
	var pd := minf(rr.size.y - 0.6, rng.range_f(2.5, 3.5))
	if pw < 2.0 or pd < 2.0:
		return
	var x0 := rr.end.x - pw - 0.3
	var z0 := rr.end.y - pd - 0.3
	var wc := EnvGeo.c(Color(0.35, 0.25, 0.16), EnvGeo.WOOD)
	for p in [Vector2(x0, z0), Vector2(x0 + pw, z0), Vector2(x0 + pw, z0 + pd), Vector2(x0, z0 + pd)]:
		c.dt.box(Vector3(p.x, y + 1.1, p.y), Vector3(0.08, 2.2, 0.08), wc, EnvGeo.SIDES)
	for i in 6:
		var z := z0 + pd * i / 5.0
		c.dt.box(Vector3(x0 + pw * 0.5, y + 2.25, z), Vector3(pw + 0.2, 0.06, 0.05), wc, EnvGeo.ALL)
	var lc := EnvGeo.c(Color(0.32, 0.46, 0.22), EnvGeo.FOLIAGE)
	for i in rng.range_i(2, 4):
		c.dt.sphere(Vector3(rng.range_f(x0, x0 + pw), y + 2.35, rng.range_f(z0, z0 + pd)),
			Vector3(rng.range_f(0.7, 1.3), 0.3, rng.range_f(0.7, 1.3)), lc, 4, 8)


# ------------------------------------------------------------------ apartments --

static func _apartment(c: EnvBld, shops: bool) -> void:
	var rng := c.rng
	c.setup_look(0.3)
	c.r = 0.2
	c.win_style = 0 if rng.chance(0.8) else 1
	c.win_w = rng.range_f(1.2, 1.6)
	c.bay = rng.range_f(3.0, 3.8)
	c.sill = 0.9
	c.head = 2.3
	c.balc_p = rng.range_f(0.25, 0.65)
	c.shutter_p = 0.7
	c.grime_p = 0.55
	c.lintels = rng.chance(0.3)
	c.ac_p = 0.28
	c.slab_lines = rng.chance(0.6)
	var ls := street_sides(c) if shops else long_sides(c)
	if shops:
		_set_street(c, ls)
	c.entry_side = ls[rng.range_i(0, 1)]
	if shops:
		for s in 4:
			if s in ls:
				c.shop_sides |= 1 << s
	var unfinished_top := c.F >= 3 and rng.chance(0.15 if shops else 0.25)
	var rect := footprint(c)
	var roof_y := c.body(rect, 0.0, c.F, 0.3 if unfinished_top else 1.0, EnvBld.P_SHOP if shops else EnvBld.P_APT)
	c.plinth(rect, 0.45)
	if unfinished_top:
		c.rebar_columns(c.roofs[0][0], roof_y, 2.6)
		_roof(c, 0, 0.6, 0.5)
	else:
		_roof(c, 0, 0.8, 1.0)
	if shops and rng.chance(0.2) and c.damage == 0:
		_roof_billboard(c, c.roofs[0][0], roof_y)


static func _roof_billboard(c: EnvBld, rr: Rect2, y: float) -> void:
	var rng := c.rng
	var bw := minf(rr.size.x - 1.0, rng.range_f(4.0, 7.0))
	if bw < 3.0:
		return
	var z := rr.position.y + 0.6
	var mc := EnvGeo.c(Color(0.25, 0.22, 0.2), EnvGeo.RUST)
	var pc := EnvGeo.c(EnvBld.SIGN_COLS[rng.range_i(0, 7)].lerp(Color(0.7, 0.68, 0.62), 0.25), EnvGeo.METAL)
	for x in [-bw * 0.4, 0.0, bw * 0.4]:
		c.g.box(Vector3(rr.get_center().x + x, y + 1.6, z), Vector3(0.12, 3.2, 0.12), mc, EnvGeo.SIDES)
	c.g.box(Vector3(rr.get_center().x, y + 3.2, z), Vector3(bw, 1.8, 0.12), pc, EnvGeo.ALL)
	c.g.box(Vector3(rr.get_center().x - bw * 0.2, y + 3.3, z - 0.07), Vector3(bw * 0.45, 0.9, 0.02),
		EnvGeo.c(Color(0.92, 0.9, 0.85), EnvGeo.METAL), EnvGeo.NZ)


# ------------------------------------------------------------------ villas ------

static func _villa(c: EnvBld) -> void:
	var rng := c.rng
	c.setup_look(0.3)
	if c.wall_surf == EnvGeo.PLASTER:
		c.wall_rgb = c.wall_rgb.lerp(Color(0.88, 0.85, 0.78), 0.2)
		c.wall = EnvGeo.c(c.wall_rgb, EnvGeo.PLASTER)
	c.trim = EnvGeo.c(c.wall_rgb.lerp(Color(0.96, 0.95, 0.92), 0.6), EnvGeo.STONE)
	c.r = 0.18
	c.win_style = 1 if rng.chance(0.45) else 2
	c.win_w = rng.range_f(1.4, 1.9)
	c.bay = rng.range_f(3.4, 4.4)
	c.sill = rng.range_f(0.5, 0.8)
	c.arch_p = 1.0 if rng.chance(0.35) else 0.0
	c.balc_p = 1.0 if rng.chance(0.55) else 0.0
	c.grime_p = 0.2
	c.lintels = rng.chance(0.7)
	c.ac_p = 0.15
	c.entry_side = rng.range_i(0, 3)
	var rect := footprint(c)
	var setback := c.F >= 2 and rng.chance(0.5)
	var top_rect := rect
	var roof_y: float
	if setback:
		var y1 := c.body(rect, 0.0, c.F - 1, 1.0, EnvBld.P_VILLA)
		c.cornice(rect, y1 - 0.25, 2)
		var inset_x := rng.range_f(2.0, 3.5) if rect.size.x > 9.0 else 0.0
		var inset_z := rng.range_f(2.0, 3.5) if rect.size.y > 9.0 else 0.0
		top_rect = Rect2(rect.position.x + (inset_x if rng.chance(0.5) else 0.0), rect.position.y,
			rect.size.x - inset_x, rect.size.y - inset_z)
		if rng.chance(0.5):
			top_rect.position.y += inset_z
		c.roof_clutter(c.roofs[0][0], y1, 0.25, [top_rect.grow(0.3)])
		roof_y = c.body(top_rect, y1, 1, 1.0, EnvBld.P_VILLA)
	else:
		roof_y = c.body(rect, 0.0, c.F, 1.0, EnvBld.P_VILLA)
	c.plinth(rect, 0.6)
	c.cornice(top_rect, roof_y - 0.25, 2)
	var occ: Array = []
	var ri := c.roofs.size() - 1
	c.roof_clutter(c.roofs[ri][0], roof_y, 0.6, occ)


# ------------------------------------------------------------------ towers ------

static func _tower(c: EnvBld) -> void:
	var rng := c.rng
	c.setup_look(0.6)
	var variant := rng.range_i(0, 2)
	var rect := footprint(c)
	var light_wall := c.wall
	var light_rgb := c.wall_rgb
	var light_surf := c.wall_surf
	c.r = 0.25
	c.wall_rgb = Color(0.34, 0.31, 0.29).lerp(c.wall_rgb, rng.range_f(0.0, 0.4))
	c.wall = EnvGeo.c(c.wall_rgb, EnvGeo.STONE)
	c.wall_surf = EnvGeo.STONE
	c.glass_rgb = [Color(0.14, 0.22, 0.3), Color(0.16, 0.26, 0.24), Color(0.24, 0.2, 0.15), Color(0.2, 0.22, 0.25)][rng.range_i(0, 3)]
	var pf := 2 if c.F >= 6 else 1
	var ins := rng.range_f(0.0, 1.2) if rect.size.x > 12.0 and rect.size.y > 12.0 else 0.0
	var y1 := c.body(rect, 0.0, pf, 0.6 if ins > 0.3 else 0.0, EnvBld.P_PODIUM)
	c.plinth(rect, 0.4)
	c.wall = light_wall
	c.wall_rgb = light_rgb
	c.wall_surf = light_surf
	var shaft := rect.grow(-ins)
	var floors := c.F - pf
	var roof_y: float
	match variant:
		0:
			roof_y = _curtain(c, shaft, y1, floors)
		1:
			c.slab_lines = false
			roof_y = c.body(shaft, y1, floors, 1.0, EnvBld.P_RIBBON)
		_:
			c.balc_p = 0.6
			c.win_style = 0
			c.win_w = 1.5
			c.bay = 3.2
			c.slab_lines = true
			c.grime_p = 0.3
			roof_y = c.body(shaft, y1, floors, 1.0, EnvBld.P_APT)
	var rr: Rect2 = c.roofs[c.roofs.size() - 1][0]
	var occ: Array = []
	# mechanical penthouse
	var pw := rr.size.x * rng.range_f(0.35, 0.55)
	var pd := rr.size.y * rng.range_f(0.35, 0.55)
	var pr := Rect2(rr.get_center() - Vector2(pw, pd) * 0.5 + Vector2(rng.range_f(-1, 1), rng.range_f(-1, 1)), Vector2(pw, pd))
	occ.append(pr.grow(0.5))
	var ph_rgb := light_rgb.darkened(0.1)
	var saved := c.wall
	c.wall = EnvGeo.c(ph_rgb, EnvGeo.CONCRETE)
	c.body(pr, roof_y, 1, 0.4, EnvBld.P_BLANK, 3.4)
	c.wall = saved
	c.set_frame(pr)
	var lv := EnvGeo.c(Color(0.5, 0.52, 0.53), EnvGeo.SHUTTER)
	for s in 4:
		var w := c.fw(s)
		if w > 2.0:
			c.fquad(c.g, s, 0.6, w - 0.6, roof_y + 0.8, roof_y + 2.8, 0.012, lv)
	c.roof_clutter(rr, roof_y, 0.5, occ)
	# antenna mast with warning light
	var ap := Vector3(pr.get_center().x, roof_y + 3.8, pr.get_center().y)
	var mh := rng.range_f(6.0, 10.0)
	var mc := EnvGeo.c(Color(0.75, 0.75, 0.74), EnvGeo.METAL)
	c.dt.cyl(ap, 0.12, mh, mc, 6, 1, 0.05)
	for k in 3:
		c.dt.box(ap + Vector3(0, mh * (0.3 + k * 0.22), 0), Vector3(1.2 - k * 0.3, 0.04, 0.04), mc, EnvGeo.ALL)
	c.dt.sphere(ap + Vector3(0, mh + 0.08, 0), Vector3(0.12, 0.12, 0.12), EnvGeo.c(Color(0.9, 0.1, 0.08), EnvGeo.GLASS), 4, 6)


## Glass curtain wall shaft (mullion grid and spandrels drawn by the shader).
static func _curtain(c: EnvBld, rect: Rect2, y0: float, floors: int) -> float:
	var rng := c.rng
	c.set_frame(rect)
	var roof_y := y0 + floors * EnvBld.FH
	var top := roof_y + 1.0
	var gc := EnvGeo.c(c.glass_rgb, EnvGeo.GLASS | EnvGeo.FLAG)
	var mc := EnvGeo.c(Color(0.62, 0.64, 0.66), EnvGeo.METAL)
	var hole := EnvGeo.c(Color(0.03, 0.03, 0.03), EnvGeo.VOID)
	var fins := rng.chance(0.5)
	for s in 4:
		var w := c.fw(s)
		c.fquad(c.g, s, 0.0, w, y0, top, 0.0, gc)
		c.fbox(c.g, s, 0.0, 0.4, y0, top + 0.1, 0.0, 0.14, mc, EnvBld.BOX5)
		for k in floors + 1:
			var yy := y0 + k * EnvBld.FH
			c.fbox(c.g, s, 0.4, w, yy - 0.06, yy + 0.06, 0.0, 0.07, mc, EnvBld.FRONT | EnvBld.TOP | EnvBld.BOT)
		if fins:
			var u := 3.0
			while u < w - 1.0:
				c.fbox(c.g, s, u - 0.04, u + 0.04, y0, top, 0.0, 0.3, mc, EnvBld.BOX5)
				u += 3.0
		c.fbox(c.g, s, 0.0, w, roof_y, top, -0.15, 0.0, c.wall, EnvBld.BACK | EnvBld.TOP)
		c.fbox(c.g, s, 0.0, w, top, top + 0.1, -0.2, 0.05, mc, EnvBld.FRONT | EnvBld.BACK | EnvBld.TOP)
		for k in floors:
			c.ops_log.append([rect, s, w * 0.3, w * 0.7, y0 + k * EnvBld.FH + 0.9, y0 + k * EnvBld.FH + 2.9, EnvBld.O_RIBBON])
			if c.damage > 0:
				var u2 := 0.0
				while u2 < w - 1.5:
					if c.drng.chance(0.18):
						c.fquad(c.g, s, u2 + 0.04, u2 + 1.46, y0 + k * EnvBld.FH + 0.9, y0 + (k + 1) * EnvBld.FH - 0.08, 0.012, hole)
					u2 += 1.5
	var ctr := rect.get_center()
	c.g.box(Vector3(ctr.x, roof_y - 0.05, ctr.y), Vector3(rect.size.x - 0.3, 0.1, rect.size.y - 0.3), c.roof_c, EnvGeo.PY)
	c.roofs.append([rect.grow(-0.15), roof_y])
	return roof_y

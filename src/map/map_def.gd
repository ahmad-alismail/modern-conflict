extends RefCounted
## Map data: the single schema shared by the city generator, image importer,
## map editor, simulation (nav/LOS grids) and renderer. World units are meters;
## the map spans [0, width*CELL] x [0, height*CELL] on the XZ plane.
class_name MapDef

const CELL := 2.0
const VERSION := 1

# terrain types (per cell)
const T_SAND := 0
const T_DIRT := 1
const T_GRASS := 2
const T_ROAD := 3
const T_PAVED := 4
const T_WATER := 5
const T_FIELD := 6
const T_RUBBLE := 7

# building styles
const S_OLD := 0          # old-quarter stone/plaster, 1-3 floors
const S_APARTMENT := 1    # concrete apartment block, 4-9 floors
const S_SHOP := 2         # mixed-use with ground-floor shops
const S_VILLA := 3        # detached house, usually walled compound
const S_MOSQUE := 4       # dome + minaret landmark
const S_INDUSTRIAL := 5   # warehouse / workshop
const S_UNFINISHED := 6   # concrete frame, exposed columns
const S_TOWER := 7        # tall office/hotel block

const FLOOR_H := 3.2

# wall kinds
const W_COMPOUND := 0     # 2.6 m masonry
const W_LOW := 1          # 1.1 m garden wall (cover, vehicles blocked)
const W_HESCO := 2        # 2.1 m barrier, blocks vehicles
const W_SANDBAG := 3      # 0.9 m, cover
const WALL_HEIGHT := {W_COMPOUND: 2.6, W_LOW: 1.1, W_HESCO: 2.1, W_SANDBAG: 0.9}

## Prop footprint (m, x = length along rot, y = width), blocking and cover.
## block: bitmask of movement classes blocked (1 foot, 2 wheeled, 4 tracked)
## cover: 0 none, 1 light, 2 heavy;  h: LOS obstacle height
const PROPS := {
	"palm": {"dims": Vector2(0.8, 0.8), "block": 0, "cover": 0, "h": 0.0},
	"tree": {"dims": Vector2(1.0, 1.0), "block": 0, "cover": 1, "h": 0.0},
	"bush": {"dims": Vector2(1.6, 1.6), "block": 0, "cover": 1, "h": 1.2},
	"car": {"dims": Vector2(4.4, 1.9), "block": 2, "cover": 1, "h": 1.4},
	"car_wreck": {"dims": Vector2(4.4, 1.9), "block": 2, "cover": 1, "h": 1.2},
	"bus_wreck": {"dims": Vector2(11.0, 2.6), "block": 6, "cover": 2, "h": 3.0},
	"lamp": {"dims": Vector2(0.4, 0.4), "block": 0, "cover": 0, "h": 0.0},
	"pole": {"dims": Vector2(0.4, 0.4), "block": 0, "cover": 0, "h": 0.0},
	"stall": {"dims": Vector2(3.0, 2.2), "block": 2, "cover": 1, "h": 0.0},
	"barrels": {"dims": Vector2(1.6, 1.6), "block": 2, "cover": 1, "h": 1.0},
	"barrier": {"dims": Vector2(3.6, 0.7), "block": 6, "cover": 2, "h": 1.0},
	"dumpster": {"dims": Vector2(2.0, 1.4), "block": 2, "cover": 1, "h": 1.4},
	"container": {"dims": Vector2(6.1, 2.5), "block": 7, "cover": 2, "h": 2.6},
	"rubble": {"dims": Vector2(4.0, 4.0), "block": 2, "cover": 1, "h": 1.3},
	"tires": {"dims": Vector2(1.4, 1.4), "block": 2, "cover": 1, "h": 0.8},
	"crates": {"dims": Vector2(1.8, 1.4), "block": 2, "cover": 1, "h": 1.1},
	"billboard": {"dims": Vector2(4.0, 0.5), "block": 0, "cover": 0, "h": 0.0},
	"tank_trap": {"dims": Vector2(1.6, 1.6), "block": 6, "cover": 1, "h": 0.9},
}

var name := "Untitled"
var description := ""
var map_seed := 0
var width := 240
var height := 240
var terrain := PackedByteArray()
## {id, c: Vector2, size: Vector2, rot: float (rad), floors: int, style: int, color: int, seed: int}
var buildings: Array = []
## {a: Vector2, b: Vector2, h: float, kind: int}
var walls: Array = []
## {kind: String, p: Vector2, rot: float, s: float}
var props: Array = []
## {a: Vector2, b: Vector2, w: float, kind: int (0 avenue, 1 street, 2 alley)}
var roads: Array = []
## {team: int, rect: Rect2}
var spawns: Array = []
## {id: String, name: String, p: Vector2, r: float}
var objectives: Array = []
## Named areas for briefing / LLM observations: {name: String, rect: Rect2}
var districts: Array = []


func _init(w: int = 240, h: int = 240) -> void:
	resize(w, h)


func resize(w: int, h: int) -> void:
	width = w
	height = h
	terrain = PackedByteArray()
	terrain.resize(w * h)
	terrain.fill(T_SAND)


func size_m() -> Vector2:
	return Vector2(width * CELL, height * CELL)


func in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < width and cy < height


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func get_terrain(cx: int, cy: int) -> int:
	if not in_bounds(cx, cy):
		return T_SAND
	return terrain[cy * width + cx]


func set_terrain(cx: int, cy: int, t: int) -> void:
	if in_bounds(cx, cy):
		terrain[cy * width + cx] = t


func fill_rect_terrain(r: Rect2, t: int) -> void:
	var c0 := world_to_cell(r.position)
	var c1 := world_to_cell(r.end)
	for y in range(maxi(c0.y, 0), mini(c1.y + 1, height)):
		for x in range(maxi(c0.x, 0), mini(c1.x + 1, width)):
			var cc := cell_center(Vector2i(x, y))
			if r.has_point(cc):
				terrain[y * width + x] = t


## Paint a road segment into the terrain grid (road core + paved shoulders).
func paint_road(a: Vector2, b: Vector2, w: float, sidewalk: float) -> void:
	var minp := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (w * 0.5 + sidewalk + CELL)
	var maxp := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (w * 0.5 + sidewalk + CELL)
	var c0 := world_to_cell(minp)
	var c1 := world_to_cell(maxp)
	for y in range(maxi(c0.y, 0), mini(c1.y + 1, height)):
		for x in range(maxi(c0.x, 0), mini(c1.x + 1, width)):
			var p := cell_center(Vector2i(x, y))
			var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
			var idx := y * width + x
			if d <= w * 0.5:
				terrain[idx] = T_ROAD
			elif d <= w * 0.5 + sidewalk and terrain[idx] != T_ROAD:
				terrain[idx] = T_PAVED


## Cells covered by a (possibly rotated) rectangle footprint.
func footprint_cells(c: Vector2, size: Vector2, rot: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var half := size * 0.5
	var ext := half.length() + CELL
	var c0 := world_to_cell(c - Vector2.ONE * ext)
	var c1 := world_to_cell(c + Vector2.ONE * ext)
	var cs := cos(-rot)
	var sn := sin(-rot)
	for y in range(maxi(c0.y, 0), mini(c1.y + 1, height)):
		for x in range(maxi(c0.x, 0), mini(c1.x + 1, width)):
			var d := cell_center(Vector2i(x, y)) - c
			var lx := d.x * cs - d.y * sn
			var ly := d.x * sn + d.y * cs
			if absf(lx) <= half.x and absf(ly) <= half.y:
				out.append(Vector2i(x, y))
	return out


func building_height(b: Dictionary) -> float:
	var h: float = b["floors"] * FLOOR_H + 1.0
	if b["style"] == S_INDUSTRIAL:
		h = b["floors"] * 4.5 + 1.0
	return h


func team_spawn(team: int) -> Rect2:
	for s in spawns:
		if s["team"] == team:
			return s["rect"]
	var m := size_m()
	return Rect2(Vector2(0, 0) if team == 0 else m - Vector2(40, 40), Vector2(40, 40))


func district_at(p: Vector2) -> String:
	for d in districts:
		if (d["rect"] as Rect2).has_point(p):
			return d["name"]
	return ""


# --- serialization -------------------------------------------------------------

static func _v2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


static func _r2(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


static func _to_v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _to_r2(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


func to_dict() -> Dictionary:
	var bl := []
	for b in buildings:
		bl.append({"id": b["id"], "c": _v2(b["c"]), "size": _v2(b["size"]), "rot": snappedf(b["rot"], 0.0001),
			"floors": b["floors"], "style": b["style"], "color": b["color"], "seed": b["seed"]})
	var wl := []
	for w in walls:
		wl.append({"a": _v2(w["a"]), "b": _v2(w["b"]), "h": w["h"], "kind": w["kind"]})
	var pl := []
	for p in props:
		pl.append({"kind": p["kind"], "p": _v2(p["p"]), "rot": snappedf(p["rot"], 0.001), "s": snappedf(p["s"], 0.01)})
	var rl := []
	for r in roads:
		rl.append({"a": _v2(r["a"]), "b": _v2(r["b"]), "w": r["w"], "kind": r["kind"]})
	var sl := []
	for s in spawns:
		sl.append({"team": s["team"], "rect": _r2(s["rect"])})
	var ol := []
	for o in objectives:
		ol.append({"id": o["id"], "name": o["name"], "p": _v2(o["p"]), "r": o["r"]})
	var dl := []
	for d in districts:
		dl.append({"name": d["name"], "rect": _r2(d["rect"])})
	return {"version": VERSION, "name": name, "description": description, "seed": map_seed, "width": width, "height": height,
		"terrain": Marshalls.raw_to_base64(terrain), "buildings": bl, "walls": wl, "props": pl, "roads": rl,
		"spawns": sl, "objectives": ol, "districts": dl}


static func from_dict(d: Dictionary) -> MapDef:
	var m := MapDef.new(int(d["width"]), int(d["height"]))
	m.name = d.get("name", "Untitled")
	m.description = d.get("description", "")
	m.map_seed = int(d.get("seed", 0))
	var t := Marshalls.base64_to_raw(d["terrain"])
	if t.size() == m.width * m.height:
		m.terrain = t
	for b in d.get("buildings", []):
		m.buildings.append({"id": int(b["id"]), "c": _to_v2(b["c"]), "size": _to_v2(b["size"]), "rot": float(b["rot"]),
			"floors": int(b["floors"]), "style": int(b["style"]), "color": int(b["color"]), "seed": int(b["seed"])})
	for w in d.get("walls", []):
		m.walls.append({"a": _to_v2(w["a"]), "b": _to_v2(w["b"]), "h": float(w["h"]), "kind": int(w["kind"])})
	for p in d.get("props", []):
		m.props.append({"kind": String(p["kind"]), "p": _to_v2(p["p"]), "rot": float(p["rot"]), "s": float(p["s"])})
	for r in d.get("roads", []):
		m.roads.append({"a": _to_v2(r["a"]), "b": _to_v2(r["b"]), "w": float(r["w"]), "kind": int(r["kind"])})
	for s in d.get("spawns", []):
		m.spawns.append({"team": int(s["team"]), "rect": _to_r2(s["rect"])})
	for o in d.get("objectives", []):
		m.objectives.append({"id": String(o["id"]), "name": String(o["name"]), "p": _to_v2(o["p"]), "r": float(o["r"])})
	for di in d.get("districts", []):
		m.districts.append({"name": String(di["name"]), "rect": _to_r2(di["rect"])})
	return m


func save_json(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


static func load_json(path: String) -> MapDef:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)

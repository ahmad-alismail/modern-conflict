extends RefCounted
## Deterministic battle simulation. Fixed 20 Hz tick, seeded RNG, no engine nodes.
## The presentation layer reads state + drains `events`; commanders submit commands
## via `issue()`. Identical setup + command stream => identical battle (replays).
class_name SimWorld

const TICK_RATE := 20
const DT := 1.0 / TICK_RATE
const SPATIAL_CELL := 16.0

var map: MapDef
var nav: NavGrid
var rng: Rng
var tick := 0
var time := 0.0
var units: Array = []                 # SimUnit, ordered by id (deterministic iteration)
var by_id: Dictionary = {}            # id -> SimUnit
var projectiles: Array = []           # see Combat
var smokes: Array = []                # {p: Vector2, r: float, t: float, max_t: float}
var mines: Array = []                 # {p: Vector2, team: int}
var strikes: Array = []               # pending support strikes
var reveals: Array = []               # {team, p, r, t}
var wrecks: Array = []                # {p: Vector2, def_id: String, facing: float, burn: float}
var buildings: Array = []             # {hp, max_hp, state (0 ok,1 damaged,2 collapsed), garrison: Array[int]}
var objectives: Array = []            # {id, name, p, r, owner, progress}
var teams: Array = []                 # see _make_team
var events: Array = []
var pending: Array = []
var command_log: Array = []
var outcome: Dictionary = {}          # {winner: int, reason: String} once decided
var env := {"night": false, "weather": "clear"}
var mode := "vp"                      # vp | annihilation | hold
var time_limit := 0.0                 # seconds, 0 = none
var hold_team := -1                   # mode "hold": team that must hold objectives
var scenario_id := ""
var _next_id := 1
var next_proj := 1
var _grid: Dictionary = {}
var _ticket_acc := 0.0


# ================================================================== setup =====

## scenario: {map: MapDef, seed: int, mode, tickets, time_limit, env: {...},
##   teams: [{faction: String, forces: Array (def ids) | null for faction default,
##            placed: Array [{def, p: Vector2, facing}] (optional)}]}
func setup(scenario: Dictionary) -> void:
	map = scenario["map"]
	rng = Rng.new(int(scenario.get("seed", 1)))
	nav = NavGrid.new(map)
	mode = scenario.get("mode", "vp")
	time_limit = float(scenario.get("time_limit", 0.0))
	hold_team = int(scenario.get("hold_team", -1))
	scenario_id = scenario.get("id", "")
	env = scenario.get("env", env).duplicate()
	for b in map.buildings:
		var area: float = b["size"].x * b["size"].y
		var mhp := clampf(area * b["floors"] * 4.0, 500.0, 9000.0)
		if b["style"] == MapDef.S_MOSQUE:
			mhp *= 1.5
		buildings.append({"hp": mhp, "max_hp": mhp, "state": 0, "garrison": []})
	for o in map.objectives:
		objectives.append({"id": o["id"], "name": o["name"], "p": o["p"], "r": o["r"], "owner": -1, "progress": 0.0})
	var tickets: int = scenario.get("tickets", 500)
	var tdefs: Array = scenario["teams"]
	for ti in tdefs.size():
		var td: Dictionary = tdefs[ti]
		teams.append(_make_team(ti, td, tickets))
	for ti in tdefs.size():
		var td: Dictionary = tdefs[ti]
		if td.has("placed"):
			for pu in td["placed"]:
				spawn_unit(ti, pu["def"], pu["p"], pu.get("facing", 0.0))
		var forces = td.get("forces")
		if forces == null and not td.has("placed"):
			forces = Defs.FACTIONS[td["faction"]]["forces"]
		if forces != null:
			_deploy_forces(ti, forces)
	Detection.update(self)


func _make_team(ti: int, td: Dictionary, tickets: int) -> Dictionary:
	var fac: Dictionary = Defs.FACTIONS[td["faction"]]
	var support := {}
	var sup_src: Dictionary = td.get("support", fac["support"])
	for k in sup_src:
		support[k] = {"charges": int(sup_src[k]), "cd": 0.0}
	var waves: Array = td.get("reinforcements", fac["reinforcements"]).duplicate(true)
	return {"id": ti, "faction": td["faction"], "tickets": float(td.get("tickets", tickets)), "support": support,
		"waves": waves, "wave_cd": 0.0, "last_known": {}, "stats": {"lost": 0, "killed": 0, "shots": 0},
		"name": td.get("name", fac["name"])}


func _deploy_forces(ti: int, forces: Array) -> void:
	var rect := map.team_spawn(ti)
	var face := 0.0 if rect.get_center().x < map.size_m().x * 0.5 else PI
	var n := forces.size()
	var cols := maxi(2, int(ceil(sqrt(n * rect.size.y / maxf(rect.size.x, 1.0)))))
	var rows := int(ceil(float(n) / cols))
	for i in n:
		var c := i % cols
		var r := i / cols
		var p := rect.position + Vector2((r + 0.5) / rows * rect.size.x, (c + 0.5) / cols * rect.size.y)
		var def := Defs.unit(forces[i])
		p = nav.nearest_open_point(def["move"], p)
		spawn_unit(ti, forces[i], p, face)


func spawn_unit(team: int, def_id: String, p: Vector2, facing: float) -> SimUnit:
	var u := SimUnit.new()
	u.setup(_next_id, team, def_id, p, facing)
	u.spawn_tick = tick
	_next_id += 1
	units.append(u)
	by_id[u.id] = u
	emit({"t": "spawn", "u": u.id})
	return u


# =============================================================== commands =====

## Submit a command. It is validated and applied at the start of the next tick.
## {type, team, ids: Array[int], pos: Vector2, target: int, bld: int, queue: bool, ...}
func issue(cmd: Dictionary) -> void:
	pending.append(cmd)


func _apply_commands() -> void:
	if pending.is_empty():
		return
	var batch := pending
	pending = []
	for cmd in batch:
		if _apply(cmd):
			command_log.append({"tick": tick, "cmd": cmd})


func _own_units(cmd: Dictionary) -> Array:
	var out := []
	for id in cmd.get("ids", []):
		var u: SimUnit = by_id.get(int(id))
		if u != null and u.alive and u.team == int(cmd["team"]):
			out.append(u)
	return out


func _apply(cmd: Dictionary) -> bool:
	var type: String = cmd.get("type", "")
	var team: int = int(cmd.get("team", -1))
	if team < 0 or team >= teams.size() or not outcome.is_empty():
		return false
	match type:
		"support":
			return Support.request(self, team, cmd.get("power", ""), cmd.get("pos", Vector2.ZERO), cmd.get("dir", Vector2.RIGHT))
		"reinforce":
			return Support.reinforce(self, team)
	var sel := _own_units(cmd)
	if sel.is_empty():
		return false
	var queue: bool = cmd.get("queue", false)
	match type:
		"move", "attack_move":
			var goals := formation_goals(sel, cmd["pos"])
			for i in sel.size():
				_push_order(sel[i], {"o": "move", "pos": goals[i], "am": type == "attack_move"}, queue)
		"attack":
			var tgt: SimUnit = by_id.get(int(cmd.get("target", -1)))
			if tgt == null or not tgt.alive or tgt.team == team:
				return false
			for u in sel:
				_push_order(u, {"o": "attack", "target": tgt.id}, queue)
		"attack_ground":
			for u in sel:
				_push_order(u, {"o": "attack_ground", "pos": cmd["pos"], "t": 0.0}, queue)
		"garrison":
			var bi := int(cmd.get("bld", -1))
			if bi < 0 or bi >= buildings.size() or buildings[bi]["state"] == 2:
				return false
			for u in sel:
				if u.def.get("garrison", false):
					_push_order(u, {"o": "garrison", "bld": bi}, queue)
		"board":
			var tr: SimUnit = by_id.get(int(cmd.get("target", -1)))
			if tr == null or not tr.alive or tr.team != team or tr.def.get("transport", 0) <= 0:
				return false
			for u in sel:
				if u.is_squad() and u.def.get("garrison", false):
					_push_order(u, {"o": "board", "target": tr.id}, queue)
		"unload":
			for u in sel:
				if u.cargo.size() > 0:
					_push_order(u, {"o": "unload"}, queue)
		"ungarrison":
			for u in sel:
				if u.state == SimUnit.State.GARRISONED:
					_exit_building(u)
		"stop":
			for u in sel:
				_clear_orders(u)
				for ws in u.weapons:
					ws["target"] = -1
					ws["forced"] = false
		"hold":
			var v: bool = cmd.get("value", true)
			for u in sel:
				u.hold_pos = v
		"stance":
			for u in sel:
				u.stance = int(cmd.get("value", 0))
		"smoke":
			for u in sel:
				Support.unit_smoke(self, u, cmd.get("pos", u.pos))
		"retreat":
			var spawn := map.team_spawn(team).get_center()
			for u in sel:
				if u.state == SimUnit.State.GARRISONED:
					_exit_building(u)
				_clear_orders(u)
				_push_order(u, {"o": "retreat", "pos": nav.nearest_open_point(u.move_class, spawn + rng.unit_vector() * 8.0)}, false)
		_:
			return false
	return true


func _push_order(u: SimUnit, order: Dictionary, queue: bool) -> void:
	if u.broken:
		return
	if not queue:
		_clear_orders(u)
	u.orders.append(order)
	if u.orders.size() == 1:
		_start_order(u)


func _clear_orders(u: SimUnit) -> void:
	u.orders.clear()
	u.path = PackedVector2Array()
	u.path_i = 0
	u.attack_move = false
	if u.state == SimUnit.State.MOVING:
		u.state = SimUnit.State.IDLE
	for ws in u.weapons:
		if ws["forced"]:
			ws["forced"] = false
			ws["target"] = -1


func _start_order(u: SimUnit) -> void:
	var o := u.current_order()
	if o.is_empty():
		return
	match o["o"]:
		"move", "retreat":
			if u.state == SimUnit.State.GARRISONED:
				_exit_building(u)
			u.attack_move = o.get("am", false)
			_set_move(u, o["pos"])
		"attack":
			for ws in u.weapons:
				ws["target"] = o["target"]
				ws["forced"] = true
		"attack_ground":
			pass
		"garrison":
			if u.state == SimUnit.State.GARRISONED:
				_exit_building(u)
			_set_move(u, building_entry_point(o["bld"], u.pos))
		"board":
			var tr: SimUnit = by_id.get(o["target"])
			if tr != null:
				if u.state == SimUnit.State.GARRISONED:
					_exit_building(u)
				_set_move(u, tr.pos)


func _finish_order(u: SimUnit) -> void:
	if u.orders.size() > 0:
		u.orders.pop_front()
	u.attack_move = false
	u.path = PackedVector2Array()
	if u.state == SimUnit.State.MOVING:
		u.state = SimUnit.State.IDLE
	if u.orders.size() > 0:
		_start_order(u)


func _set_move(u: SimUnit, goal: Vector2) -> void:
	if u.mobility >= 2:
		return
	u.move_goal = goal
	u.path = nav.find_path(u.move_class, u.pos, goal)
	u.path_i = 0
	u.stuck_t = 0.0
	u.stuck_ref = u.pos
	if u.path.size() > 0:
		u.state = SimUnit.State.MOVING


## Spread destinations around `pos` in a formation facing the move direction.
func formation_goals(sel: Array, pos: Vector2) -> Array:
	var n := sel.size()
	if n == 1:
		return [nav.nearest_open_point(sel[0].move_class, pos)]
	var center := Vector2.ZERO
	var spacing := 6.0
	for u in sel:
		center += u.pos
		spacing = maxf(spacing, u.def["radius"] * 2.0 + 3.0)
	center /= n
	var dir := (pos - center)
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	var right := Vector2(-dir.y, dir.x)
	var cols := int(ceil(sqrt(n * 2.0)))
	var order := sel.duplicate()
	order.sort_custom(func(a, b): return (a.pos - center).dot(right) < (b.pos - center).dot(right))
	var out := []
	out.resize(n)
	for k in n:
		var row := k / cols
		var col := k % cols
		var in_row := mini(cols, n - row * cols)
		var lateral := (col - (in_row - 1) * 0.5) * spacing
		var p := pos + right * lateral - dir * row * spacing
		var u: SimUnit = order[k]
		out[sel.find(u)] = nav.nearest_open_point(u.move_class, p)
	return out


# =================================================================== tick =====

func step() -> void:
	if not outcome.is_empty():
		return
	_apply_commands()
	_rebuild_spatial()
	for u in units:
		u.prev_pos = u.pos
		u.prev_facing = u.facing
		u.prev_turret = u.turret
		u.prev_alt = u.alt
	for u in units:
		if u.alive:
			_update_unit(u)
	_separate()
	if tick % 5 == 0:
		Detection.update(self)
	Combat.update(self)
	Support.update(self)
	_update_smoke()
	if tick % 10 == 0:
		_update_objectives(10 * DT)
		_check_victory()
	tick += 1
	time += DT


func emit(ev: Dictionary) -> void:
	events.append(ev)


func drain_events() -> Array:
	var e := events
	events = []
	return e


func message(text: String, team: int = -1, kind: String = "info") -> void:
	emit({"t": "message", "text": text, "team": team, "kind": kind})


# ============================================================ unit update =====

func _update_unit(u: SimUnit) -> void:
	u.fired_t += DT
	u.attacked_t += DT
	u.suppressed_t += DT
	u.shaken_t = maxf(0.0, u.shaken_t - DT)
	u.jammed_t = maxf(0.0, u.jammed_t - DT)
	_update_morale(u)
	if u.state == SimUnit.State.EMBARKED:
		var tr: SimUnit = by_id.get(u.transport_id)
		if tr != null:
			u.pos = tr.pos
		return
	_update_orders(u)
	if u.is_air():
		_move_air(u)
	elif u.state == SimUnit.State.MOVING and not (u.attack_move and u.engaging) and u.jammed_t <= 0.0:
		_move_ground(u)
	else:
		u.cur_speed = 0.0
	if u.cur_speed < 0.3 and not u.is_air():
		u.stationary_t += DT
	else:
		u.stationary_t = 0.0
	# turret returns forward when idle
	if u.def.get("turret", 0.0) > 0.0:
		var tgt := u.facing
		var aim = Combat.aim_angle(self, u)
		if aim != null:
			tgt = aim
		u.turret = _rotate_toward(u.turret, tgt, u.def["turret"] * DT)
	else:
		u.turret = u.facing
	if u.burn_t > 0.0:
		u.burn_t -= DT
		u.members_hp[0] -= 6.0 * DT
		if u.members_hp[0] <= 0.0:
			Combat.destroy_unit(self, u, -1)


func _update_orders(u: SimUnit) -> void:
	var o := u.current_order()
	if o.is_empty():
		return
	match o["o"]:
		"move":
			if u.state != SimUnit.State.MOVING and (u.path.is_empty() or u.path_i >= u.path.size()):
				_finish_order(u)
		"retreat":
			if u.state != SimUnit.State.MOVING:
				u.broken = false
				u.morale = maxf(u.morale, u.def["base_morale"] * 0.6)
				u.suppression = 0.0
				_finish_order(u)
		"attack":
			var tgt: SimUnit = by_id.get(o["target"])
			if tgt == null or not tgt.alive:
				_finish_order(u)
				return
			var visible := (tgt.vis_mask & (1 << u.team)) != 0
			var goal := tgt.pos
			if not visible:
				var lk: Dictionary = teams[u.team]["last_known"].get(tgt.id, {})
				if lk.is_empty():
					_finish_order(u)
					return
				goal = lk["p"]
			var rng_ok := Combat.best_range(u, tgt) * 0.85
			var close := u.pos.distance_to(goal) <= rng_ok and visible and (u.is_air() or has_los_units(u, tgt))
			if u.has_special("kamikaze"):
				close = false
			if close or u.state == SimUnit.State.GARRISONED:
				if u.state == SimUnit.State.MOVING:
					u.state = SimUnit.State.IDLE
					u.path = PackedVector2Array()
			else:
				u.repath_t -= DT
				if u.state != SimUnit.State.MOVING or u.repath_t <= 0.0:
					u.repath_t = 2.0
					_set_move(u, goal)
		"attack_ground":
			o["t"] += DT
			if o["t"] > 30.0:
				_finish_order(u)
		"garrison":
			var bi: int = o["bld"]
			if buildings[bi]["state"] == 2:
				_finish_order(u)
				return
			if building_distance(bi, u.pos) <= 3.5:
				_enter_building(u, bi)
				_finish_order(u)
			elif u.state != SimUnit.State.MOVING:
				u.repath_t -= DT
				if u.repath_t <= 0.0:
					u.repath_t = 3.0
					_set_move(u, building_entry_point(bi, u.pos))
					if u.state != SimUnit.State.MOVING:
						_finish_order(u)
		"board":
			var tr: SimUnit = by_id.get(o["target"])
			if tr == null or not tr.alive:
				_finish_order(u)
				return
			if u.pos.distance_to(tr.pos) <= tr.def["radius"] + 4.0:
				_embark(u, tr)
				_finish_order(u)
			else:
				u.repath_t -= DT
				if u.repath_t <= 0.0 or u.state != SimUnit.State.MOVING:
					u.repath_t = 1.5
					_set_move(u, tr.pos)
		"unload":
			unload_all(u)
			_finish_order(u)


func _move_ground(u: SimUnit) -> void:
	if u.path_i >= u.path.size():
		u.state = SimUnit.State.IDLE
		u.cur_speed = 0.0
		return
	var speed: float = u.def["speed"] * nav.speed_mult(u.move_class, u.pos)
	if u.pinned:
		speed *= 0.45
	if u.mobility == 1:
		speed *= 0.5
	elif u.mobility >= 2:
		speed = 0.0
	if u.current_order().get("o", "") == "retreat":
		speed *= 1.25
	if u.is_squad() and u.alive_members() <= 0:
		speed = 0.0
	var target := u.path[u.path_i]
	var to := target - u.pos
	var d := to.length()
	var last := u.path_i == u.path.size() - 1
	var arrive := (0.6 if last else 1.6) if u.cat == Defs.CAT_INF else (1.2 if last else 3.0)
	if d <= arrive:
		u.path_i += 1
		if u.path_i >= u.path.size():
			u.state = SimUnit.State.IDLE
			u.cur_speed = 0.0
		return
	var desired := to.angle()
	var step_len := 0.0
	if u.cat == Defs.CAT_VEH:
		var diff := absf(angle_difference(u.facing, desired))
		u.facing = _rotate_toward(u.facing, desired, u.def["turn"] * DT)
		var f := 1.0
		if u.move_class == Defs.MOVE_TRACKED:
			f = 0.0 if diff > 1.0 else cos(diff)
		else:
			f = clampf(1.0 - diff / 1.6, 0.25, 1.0)
		if last:
			f = minf(f, clampf(d / 6.0, 0.3, 1.0))
		u.cur_speed = move_toward(u.cur_speed, speed * f, 6.0 * DT)
		step_len = u.cur_speed * DT
		_try_step(u, Vector2.from_angle(u.facing) * step_len)
	else:
		u.facing = _rotate_toward(u.facing, desired, u.def["turn"] * DT)
		u.cur_speed = speed
		step_len = minf(speed * DT, d)
		_try_step(u, to / d * step_len)
	# stuck detection
	u.stuck_t += DT
	if u.stuck_t > 2.5:
		if u.pos.distance_to(u.stuck_ref) < 1.0 and speed > 0.0:
			_set_move(u, u.move_goal)
			if u.path.size() <= 1 and u.pos.distance_to(u.move_goal) < 6.0:
				u.state = SimUnit.State.IDLE
				u.path = PackedVector2Array()
		u.stuck_t = 0.0
		u.stuck_ref = u.pos


func _try_step(u: SimUnit, delta: Vector2) -> void:
	var np := u.pos + delta
	if nav.is_open(u.move_class, np):
		u.pos = np
		return
	var nx := u.pos + Vector2(delta.x, 0)
	if nav.is_open(u.move_class, nx):
		u.pos = nx
		return
	var ny := u.pos + Vector2(0, delta.y)
	if nav.is_open(u.move_class, ny):
		u.pos = ny


func _move_air(u: SimUnit) -> void:
	var size := map.size_m()
	var o := u.current_order()
	var speed: float = u.def["speed"]
	var target_alt: float = u.def.get("alt", 30.0)
	if u.jammed_t > 0.0:
		# jammed drones drift and lose altitude
		u.alt = maxf(2.0, u.alt - 6.0 * DT)
		u.cur_speed = 0.0
		return
	var goal := u.pos
	var hover := true
	if u.state == SimUnit.State.MOVING and u.path_i < u.path.size():
		goal = u.path[u.path_i]
		hover = false
	var loiter := u.has_special("loiter")
	if loiter and hover:
		# fixed-wing drones orbit their station
		var rel := u.pos - u.loiter_center
		var ang := rel.angle() + 0.45
		goal = u.loiter_center + Vector2.from_angle(ang) * 70.0
		hover = false
	elif loiter:
		u.loiter_center = goal
	if u.has_special("kamikaze") and o.get("o", "") == "attack":
		var tgt: SimUnit = by_id.get(o["target"])
		if tgt != null and tgt.alive:
			goal = tgt.pos
			hover = false
			var d := u.pos.distance_to(goal)
			target_alt = lerpf(1.5, u.def["alt"], clampf((d - 5.0) / 50.0, 0.0, 1.0))
			if d < 4.5 and u.alt < 4.0:
				Combat.kamikaze(self, u, tgt)
				return
	u.alt = move_toward(u.alt, target_alt, 8.0 * DT)
	var to := goal - u.pos
	var d := to.length()
	if hover or d < 1.0:
		u.cur_speed = move_toward(u.cur_speed, 0.0, 8.0 * DT)
		if not loiter and u.state == SimUnit.State.MOVING and u.path_i >= u.path.size() - 1 and d < 2.0:
			u.path_i = u.path.size()
			u.state = SimUnit.State.IDLE
		# face current target when hovering
		var aim = Combat.aim_angle(self, u)
		if aim != null and not loiter:
			u.facing = _rotate_toward(u.facing, aim, u.def["turn"] * DT)
	else:
		var desired := to.angle()
		u.facing = _rotate_toward(u.facing, desired, u.def["turn"] * DT)
		var f := 1.0
		if loiter:
			f = 1.0
		else:
			f = clampf(d / 25.0, 0.25, 1.0) * clampf(1.0 - absf(angle_difference(u.facing, desired)) / PI, 0.3, 1.0)
		u.cur_speed = move_toward(u.cur_speed, speed * f, 10.0 * DT)
		var dirv := Vector2.from_angle(u.facing) if loiter else to / d
		u.pos += dirv * minf(u.cur_speed * DT, d)
		if not loiter and d < 3.0:
			u.path_i += 1
			if u.path_i >= u.path.size():
				u.state = SimUnit.State.IDLE
	u.pos = u.pos.clamp(Vector2.ZERO, size)


static func _rotate_toward(a: float, b: float, max_step: float) -> float:
	var diff := angle_difference(a, b)
	if absf(diff) <= max_step:
		return b
	return a + signf(diff) * max_step


func _rebuild_spatial() -> void:
	_grid.clear()
	for u in units:
		if not u.is_active():
			continue
		var key := int(u.pos.x / SPATIAL_CELL) * 4096 + int(u.pos.y / SPATIAL_CELL)
		if _grid.has(key):
			_grid[key].append(u)
		else:
			_grid[key] = [u]


## Active units within radius r of p (any team). Uses the per-tick spatial hash.
func units_near(p: Vector2, r: float) -> Array:
	var out := []
	var x0 := int((p.x - r) / SPATIAL_CELL)
	var x1 := int((p.x + r) / SPATIAL_CELL)
	var y0 := int((p.y - r) / SPATIAL_CELL)
	var y1 := int((p.y + r) / SPATIAL_CELL)
	var r2 := r * r
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var arr = _grid.get(x * 4096 + y)
			if arr == null:
				continue
			for u in arr:
				if u.alive and u.pos.distance_squared_to(p) <= r2:
					out.append(u)
	return out


func _separate() -> void:
	for u in units:
		if not u.is_active() or u.is_air() or u.state == SimUnit.State.GARRISONED:
			continue
		var ru: float = u.def["radius"] * (0.45 if u.is_squad() else 0.8)
		var push := Vector2.ZERO
		for o in units_near(u.pos, ru + 5.0):
			if o == u or o.is_air() or o.state == SimUnit.State.GARRISONED or not o.is_active():
				continue
			var ro: float = o.def["radius"] * (0.45 if o.is_squad() else 0.8)
			var dv: Vector2 = u.pos - o.pos
			var d := dv.length()
			var min_d := ru + ro
			if d < min_d:
				var dir := dv / d if d > 0.01 else Vector2.from_angle(u.id * 2.39)
				var w := 0.5
				if u.cat != o.cat:
					w = 0.85 if u.cat == Defs.CAT_INF else 0.15
				push += dir * (min_d - d) * w
		if push.length_squared() > 0.0001:
			_try_step(u, push.limit_length(2.5 * DT * 4.0))


# ====================================================== garrison/transport =====

func building_rect(bi: int) -> Rect2:
	var b: Dictionary = map.buildings[bi]
	return Rect2(b["c"] - b["size"] * 0.5, b["size"])


func building_distance(bi: int, p: Vector2) -> float:
	var r := building_rect(bi)
	var cp := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return cp.distance_to(p)


func building_entry_point(bi: int, from: Vector2) -> Vector2:
	var r := building_rect(bi).grow(1.2)
	var cp := Vector2(clampf(from.x, r.position.x, r.end.x), clampf(from.y, r.position.y, r.end.y))
	if r.has_point(from):
		cp = r.get_center()
	return nav.nearest_open_point(Defs.MOVE_FOOT, cp)


func building_capacity(bi: int) -> int:
	var b: Dictionary = map.buildings[bi]
	return clampi(int(b["size"].x * b["size"].y * b["floors"] / 220.0), 1, 4)


func _enter_building(u: SimUnit, bi: int) -> void:
	var bs: Dictionary = buildings[bi]
	if bs["garrison"].size() >= building_capacity(bi):
		message("Building is full", u.team, "warn")
		return
	bs["garrison"].append(u.id)
	u.garrison_bld = bi
	u.state = SimUnit.State.GARRISONED
	u.path = PackedVector2Array()
	u.pos = map.buildings[bi]["c"]
	u.cur_speed = 0.0
	emit({"t": "garrison", "u": u.id, "b": bi})


func _exit_building(u: SimUnit) -> void:
	var bi := u.garrison_bld
	if bi < 0:
		return
	buildings[bi]["garrison"].erase(u.id)
	u.garrison_bld = -1
	u.state = SimUnit.State.IDLE
	u.pos = building_entry_point(bi, u.move_goal if u.move_goal != Vector2.ZERO else u.pos + Vector2(0, 30))
	u.prev_pos = u.pos
	emit({"t": "ungarrison", "u": u.id, "b": bi})


func garrison_eye(u: SimUnit) -> float:
	if u.garrison_bld < 0:
		return u.eye_height()
	return clampf(map.building_height(map.buildings[u.garrison_bld]) - 2.2, 1.6, 14.0)


## Firing / viewing origin for a garrisoned unit: building edge nearest the target.
func unit_origin(u: SimUnit, toward: Vector2) -> Vector2:
	if u.garrison_bld < 0:
		return u.pos
	var r := building_rect(u.garrison_bld).grow(-0.3)
	return Vector2(clampf(toward.x, r.position.x, r.end.x), clampf(toward.y, r.position.y, r.end.y))


func _cargo_members(tr: SimUnit) -> int:
	var n := 0
	for id in tr.cargo:
		var c: SimUnit = by_id.get(id)
		if c != null:
			n += c.alive_members()
	return n


func _embark(u: SimUnit, tr: SimUnit) -> void:
	if _cargo_members(tr) + u.alive_members() > tr.def.get("transport", 0):
		message("Transport is full", u.team, "warn")
		return
	tr.cargo.append(u.id)
	u.transport_id = tr.id
	u.state = SimUnit.State.EMBARKED
	u.path = PackedVector2Array()
	emit({"t": "embark", "u": u.id, "tr": tr.id})


func unload_all(tr: SimUnit) -> void:
	var back := Vector2.from_angle(tr.facing + PI)
	var i := 0
	for id in tr.cargo.duplicate():
		var c: SimUnit = by_id.get(id)
		tr.cargo.erase(id)
		if c == null or not c.alive:
			continue
		c.transport_id = -1
		c.state = SimUnit.State.IDLE
		var side := Vector2(-back.y, back.x) * (i - 0.5) * 3.0
		c.pos = nav.nearest_open_point(Defs.MOVE_FOOT, tr.pos + back * (tr.def["radius"] + 2.5) + side)
		c.prev_pos = c.pos
		c.facing = tr.facing + PI
		i += 1
		emit({"t": "disembark", "u": c.id, "tr": tr.id})


# ================================================================= morale =====

func add_suppression(u: SimUnit, amount: float, attacker: SimUnit) -> void:
	if not u.alive:
		return
	if u.cat != Defs.CAT_INF:
		if amount > 25.0 and u.cat == Defs.CAT_VEH and rng.chance(0.08):
			u.shaken_t = maxf(u.shaken_t, 2.0)
		return
	var mult := 0.25 if u.is_robot() else 1.0
	if u.current_order().get("o", "") == "retreat":
		mult *= 0.3
	if u.state == SimUnit.State.GARRISONED:
		mult *= 0.6
	u.suppression = minf(100.0, u.suppression + amount * mult)
	u.suppressed_t = 0.0
	if attacker != null:
		u.last_attacker = attacker.id
		u.attacked_t = 0.0


func _update_morale(u: SimUnit) -> void:
	if u.cat != Defs.CAT_INF:
		return
	var decay := 14.0 if u.suppressed_t > 2.0 else 3.0
	u.suppression = maxf(0.0, u.suppression - decay * DT)
	if u.is_robot():
		u.pinned = false
		return
	var was_pinned := u.pinned
	u.pinned = u.suppression >= (60.0 if not was_pinned else 40.0)
	if u.suppression > 80.0:
		u.morale -= 5.0 * DT
	elif u.suppression < 20.0:
		u.morale = minf(u.def["base_morale"], u.morale + 1.5 * DT)
	if not u.broken and u.morale <= 18.0 and u.state != SimUnit.State.GARRISONED:
		u.broken = true
		_clear_orders(u)
		var spawn := map.team_spawn(u.team).get_center()
		u.orders.append({"o": "retreat", "pos": nav.nearest_open_point(u.move_class, spawn + rng.unit_vector() * 10.0)})
		_start_order(u)
		message("%s is breaking and falling back!" % u.def["name"], u.team, "warn")
		emit({"t": "broken", "u": u.id})


func on_member_lost(u: SimUnit) -> void:
	if u.is_robot():
		return
	u.morale -= 10.0
	for o in units_near(u.pos, 25.0):
		if o.team == u.team and o != u and o.is_squad():
			o.morale -= 2.5


# ============================================================ environment =====

func _update_smoke() -> void:
	var keep := []
	for s in smokes:
		s["t"] -= DT
		if s["t"] > 0.0:
			keep.append(s)
	smokes = keep
	var keep_r := []
	for r in reveals:
		r["t"] -= DT
		if r["t"] > 0.0:
			keep_r.append(r)
	reveals = keep_r


func add_smoke(p: Vector2, r: float, duration: float) -> void:
	smokes.append({"p": p, "r": r, "t": duration, "max_t": duration})
	emit({"t": "smoke", "p": p, "r": r, "dur": duration})


## Smoke opacity along a ground-level segment (0 = clear, >=1 = blocked).
func smoke_opacity(a: Vector2, b: Vector2, ha: float, hb: float) -> float:
	if smokes.is_empty() or (ha > 14.0 and hb > 14.0):
		return 0.0
	var acc := 0.0
	for s in smokes:
		var c: Vector2 = s["p"]
		var life: float = s["t"] / s["max_t"]
		var r: float = s["r"] * (0.6 + 0.4 * minf(1.0, (1.0 - life) * 6.0))
		var cp := Geometry2D.get_closest_point_to_segment(c, a, b)
		var d := cp.distance_to(c)
		if d < r:
			var chord := 2.0 * sqrt(r * r - d * d)
			acc += chord / 7.0 * clampf(life * 3.0, 0.0, 1.0)
	return acc


func sight_mult(viewer: SimUnit) -> float:
	var m := 1.0
	if env.get("night", false) and not viewer.def.get("thermal", false):
		m *= 0.5
	match env.get("weather", "clear"):
		"haze": m *= 0.85
		"dust": m *= 0.55 if not viewer.def.get("thermal", false) else 0.75
		"rain": m *= 0.8
	return m


func has_los(a: Vector2, ha: float, b: Vector2, hb: float, ign_a: int = -1, ign_b: int = -1, thermal: bool = false) -> bool:
	if not nav.los(a, ha, b, hb, ign_a, ign_b):
		return false
	var op := smoke_opacity(a, b, ha, hb)
	return op * (0.6 if thermal else 1.0) < 1.0


func has_los_units(viewer: SimUnit, tgt: SimUnit) -> bool:
	var a := unit_origin(viewer, tgt.pos)
	var b := unit_origin(tgt, viewer.pos)
	var ha := garrison_eye(viewer)
	var hb := tgt.body_height() if tgt.garrison_bld < 0 else garrison_eye(tgt)
	return has_los(a, ha, b, hb, viewer.garrison_bld, tgt.garrison_bld, viewer.def.get("thermal", false))


# ============================================================= objectives =====

func _update_objectives(dt: float) -> void:
	for o in objectives:
		var counts := [0, 0]
		for u in units_near(o["p"], o["r"] + 4.0):
			if u.team > 1 or not u.def.get("capture", false) or u.broken or u.state == SimUnit.State.EMBARKED:
				continue
			counts[u.team] += 1
		for bi in _buildings_near(o["p"], o["r"]):
			for id in buildings[bi]["garrison"]:
				var gu: SimUnit = by_id.get(id)
				if gu != null and gu.team <= 1:
					counts[gu.team] += 1
		var prev_owner: int = o["owner"]
		var rate := 0.0
		if counts[0] > 0 and counts[1] == 0:
			rate = 0.07 * mini(counts[0], 3)
		elif counts[1] > 0 and counts[0] == 0:
			rate = -0.07 * mini(counts[1], 3)
		o["contested"] = counts[0] > 0 and counts[1] > 0
		if rate != 0.0:
			var p: float = o["progress"] + rate * dt
			o["progress"] = clampf(p, -1.0, 1.0)
			if o["progress"] >= 1.0:
				o["owner"] = 0
			elif o["progress"] <= -1.0:
				o["owner"] = 1
			elif (prev_owner == 0 and o["progress"] < 0.0) or (prev_owner == 1 and o["progress"] > 0.0):
				o["owner"] = -1
		if o["owner"] != prev_owner:
			emit({"t": "capture", "obj": o["id"], "team": o["owner"], "prev": prev_owner})
			if o["owner"] >= 0:
				message("%s captured %s" % [teams[o["owner"]]["name"], o["name"]], o["owner"], "good")
			else:
				message("%s neutralized" % o["name"], prev_owner, "warn")
	# ticket bleed (VP mode)
	if mode == "vp" and teams.size() >= 2:
		var owned := [0, 0]
		for o in objectives:
			if o["owner"] >= 0:
				owned[o["owner"]] += 1
		var diff: int = owned[0] - owned[1]
		if diff != 0:
			var loser := 1 if diff > 0 else 0
			teams[loser]["tickets"] -= absi(diff) * 0.6 * dt


func _buildings_near(p: Vector2, r: float) -> Array:
	var out := []
	for bi in buildings.size():
		if buildings[bi]["garrison"].size() > 0 and building_distance(bi, p) <= r:
			out.append(bi)
	return out


func on_unit_lost(u: SimUnit) -> void:
	var t: Dictionary = teams[u.team]
	t["stats"]["lost"] += 1
	if mode == "vp":
		t["tickets"] -= float(u.def["points"]) * 0.75


func _check_victory() -> void:
	if not outcome.is_empty():
		return
	var alive_count := []
	for ti in teams.size():
		alive_count.append(0)
	for u in units:
		if u.alive and u.team < teams.size():
			alive_count[u.team] += 1
	for ti in teams.size():
		var other := 1 - ti
		if teams[ti]["tickets"] <= 0.0 and mode == "vp":
			_end(other, "%s ran out of tickets" % teams[ti]["name"])
			return
		if alive_count[ti] == 0 and teams[ti]["waves"].is_empty():
			_end(other, "%s was annihilated" % teams[ti]["name"])
			return
	if mode == "hold" and hold_team >= 0 and time_limit > 0.0:
		var owned := 0
		for o in objectives:
			if o["owner"] == 1 - hold_team:
				owned += 1
		if owned == objectives.size() and objectives.size() > 0:
			_end(1 - hold_team, "All objectives taken")
			return
	if time_limit > 0.0 and time >= time_limit:
		if mode == "hold":
			_end(hold_team, "Held out until the deadline")
		else:
			var w := 0 if teams[0]["tickets"] >= teams[1]["tickets"] else 1
			_end(w, "Time limit reached")


func _end(winner: int, reason: String) -> void:
	outcome = {"winner": winner, "reason": reason, "time": time}
	emit({"t": "game_over", "winner": winner, "reason": reason})


# =============================================================== utilities ====

func enemies_of(team: int) -> Array:
	var out := []
	for u in units:
		if u.alive and u.team != team:
			out.append(u)
	return out


func team_units(team: int) -> Array:
	var out := []
	for u in units:
		if u.alive and u.team == team:
			out.append(u)
	return out


func is_visible_to(u: SimUnit, team: int) -> bool:
	return u.team == team or (u.vis_mask & (1 << team)) != 0


## Stable hash of core state, used by determinism tests.
func state_hash() -> int:
	var s := PackedFloat64Array()
	for u in units:
		s.append(u.id)
		s.append(u.pos.x)
		s.append(u.pos.y)
		s.append(u.hp())
		s.append(1.0 if u.alive else 0.0)
	for t in teams:
		s.append(t["tickets"])
	s.append(rng.state)
	return hash(s)

extends Node
## One running battle. Owns the SimWorld and its presentation, steps the simulation
## at a fixed rate scaled by game speed, implements tactical pause (the sim stops,
## camera/orders/UI keep working; orders queue and execute on resume), and routes
## events to the view, audio and HUD.
class_name GameSession

signal ended(outcome: Dictionary)

const SPEEDS := [0.5, 1.0, 2.0, 3.0, 4.0]
const MAX_STEPS_PER_FRAME := 10

var config: Dictionary
var sim: SimWorld
var view: WorldView
var cam: CameraRig
var env_rig: EnvironmentRig
var fx: Effects
var audio: Node
var hud: Node
var input: Node
var commanders: Array = []
var player_team := 0
var paused := false
var speed := 1.0
var replay: Dictionary = {}       # when set, the session plays back a recorded command log
var initial_map: Dictionary = {}  # pristine map (before battle damage) for replays
var _acc := 0.0
var _last_us := 0
var _game_over := false
var _replay_i := 0
var _battle_level := 0.0


## config: see GameConfig.make_* helpers (mode, map, seed, teams, player_team, env, tickets, ...).
func start(p_config: Dictionary) -> void:
	config = p_config
	process_mode = Node.PROCESS_MODE_ALWAYS
	var map: MapDef = config.get("map")
	if map == null:
		var gen_opts := {"war_damage": config.get("war_damage", 0.25)}
		if String(config.get("map_name", "")) != "":
			gen_opts["name"] = config["map_name"]
		map = CityGenerator.generate(int(config.get("map_seed", 1)), gen_opts)
	initial_map = config.get("initial_map", map.to_dict())
	var teams := []
	for t in config["teams"]:
		var td := {"faction": t["faction"], "name": t.get("name", Defs.FACTIONS[t["faction"]]["name"])}
		for k in ["forces", "placed", "support", "reinforcements", "tickets"]:
			if t.has(k):
				td[k] = t[k]
		teams.append(td)
	var env: Dictionary = config.get("env", {"tod": "day", "weather": "clear"})
	sim = SimWorld.new()
	sim.setup({"map": map, "seed": int(config.get("seed", 1)), "mode": config.get("victory", "vp"),
		"tickets": int(config.get("tickets", 500)), "time_limit": float(config.get("time_limit", 0.0)),
		"hold_team": int(config.get("hold_team", -1)), "id": config.get("scenario_id", ""), "sandbox": config.get("sandbox", false),
		"env": {"night": env.get("tod", "day") == "night", "weather": env.get("weather", "clear")}, "teams": teams})
	if config.has("state"):
		Serializer.restore(sim, config["state"])
	_build_presentation(env)
	_setup_commanders()
	set_speed(float(DevHarness.arg("speed", str(Settings.get_value("gameplay", "default_speed")))))
	_last_us = Time.get_ticks_usec()
	if config.has("replay"):
		replay = config["replay"]


func _build_presentation(env: Dictionary) -> void:
	player_team = int(config.get("player_team", 0))
	env_rig = EnvironmentRig.new()
	add_child(env_rig)
	env_rig.set_conditions(env.get("tod", "day"), env.get("weather", "clear"))
	fx = Effects.new()
	add_child(fx)
	audio = AudioManager.new()
	add_child(audio)
	view = WorldView.new()
	add_child(view)
	view.setup(sim, player_team, fx, audio)
	cam = CameraRig.new()
	add_child(cam)
	var size := sim.map.size_m()
	var start_team := maxi(player_team, 0)
	var sp := sim.map.team_spawn(start_team).get_center()
	var own := sim.team_units(start_team)
	if not own.is_empty():
		var c := Vector2.ZERO
		for u in own:
			c += u.pos
		sp = c / own.size()
	var toward := (size * 0.5 - sp).normalized()
	cam.setup(Rect2(Vector2.ZERO, size), Vector3(sp.x, 0, sp.y) + Vector3(toward.x, 0, toward.y) * 12.0, toward.angle(), float(DevHarness.arg("cam-dist", "120")))
	cam.view_changed.connect(_on_view_changed)
	cam.height_query = func(p: Vector2) -> float:
		if p.x < 0.0 or p.y < 0.0 or p.x >= size.x or p.y >= size.y:
			return 0.0
		return sim.nav.obstacle_height(p)
	env_rig.follow(cam.camera)
	view.fog.attach_to_camera(cam.camera)
	view.set_shake_callback(cam.shake)
	if fx.has_signal("shake"):
		fx.connect("shake", cam.shake)
	input = PlayerInput.new()
	add_child(input)
	input.setup(self)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	if config.get("sandbox", false):
		view.fog.set_enabled(false)
		var panel := SandboxPanel.new()
		hud.root.add_child(panel)
		panel.setup(self)
	if audio.has_method("set_ambience"):
		audio.set_ambience(env.get("weather", "clear"), 0.2)
	_warm_up_shaders()
	if DevHarness.has_arg("input-test"):
		var t: Node = load("res://tools/input_test.gd").new()
		t.set("session", self)
		add_child(t)
	if DevHarness.has_arg("follow"):
		get_tree().create_timer(1.0).timeout.connect(func():
			var want := DevHarness.arg("follow")
			for u in sim.team_units(maxi(player_team, 0)):
				if want == "true" or u.def_id == want:
					var v: UnitView = view.unit_views.get(u.id)
					if v:
						cam.follow(v)
						break)


## Draw one of every unit model (and its wreck) for a moment behind the loading overlay,
## so shader compilation does not hitch when a new unit type first appears mid-battle.
func _warm_up_shaders() -> void:
	var warm := Node3D.new()
	add_child(warm)
	var i := 0
	var f := cam.focus
	for id in Defs.UNITS:
		var m := UnitModels.create(id, Color.WHITE)
		m.position = f + Vector3((i % 6) * 3.0 - 7.5, 0.0, (i / 6) * 3.0 - 7.5)
		warm.add_child(m)
		var wr := UnitModels.create_wreck(id)
		wr.position = m.position + Vector3(0, 0, 1.5)
		warm.add_child(wr)
		i += 1
	get_tree().create_timer(0.4).timeout.connect(warm.queue_free)


func _setup_commanders() -> void:
	commanders.clear()
	for ti in config["teams"].size():
		var t: Dictionary = config["teams"][ti]
		var c = null
		match t.get("controller", "human" if ti == player_team else "ai"):
			"replay", "human":
				c = null
			"ai":
				c = ClassicAI.new(ti, t.get("difficulty", "medium"))
			"llm":
				c = LLMCommander.new(ti, self)
		commanders.append(c)


func _on_view_changed(d: float) -> void:
	env_rig.set_view_distance(d)
	env_rig.set_dof(d < 22.0, d)
	view.camera_pos = cam.camera.global_position
	if audio.has_method("set_listener_height"):
		audio.set_listener_height(d)


# ================================================================ main loop ===

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.1)
	_last_us = now
	if not paused and not _game_over:
		_acc += dt * speed
		var steps := 0
		while _acc >= SimWorld.DT and steps < MAX_STEPS_PER_FRAME:
			_tick()
			_acc -= SimWorld.DT
			steps += 1
		if steps == MAX_STEPS_PER_FRAME:
			_acc = 0.0
	var alpha := clampf(_acc / SimWorld.DT, 0.0, 1.0) if not paused else 1.0
	view.sync(alpha, dt if not paused else 0.0)
	var events := sim.drain_events()
	view.handle_events(events)
	hud.handle_events(events)
	_track_battle_level(events, dt)
	for e in events:
		if e["t"] == "game_over":
			_on_game_over(e)
	if DevHarness.has_arg("fps-log") and Engine.get_process_frames() % 300 == 0:
		print("[perf] fps=%d units=%d proj=%d draw_calls=%d prims=%dk sim_t=%ds" % [Engine.get_frames_per_second(), sim.units.size(), sim.projectiles.size(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000, int(sim.time)])


func _tick() -> void:
	if not replay.is_empty():
		var log: Array = replay["commands"]
		while _replay_i < log.size() and int(log[_replay_i]["tick"]) <= sim.tick:
			sim.issue(log[_replay_i]["cmd"])
			_replay_i += 1
	else:
		for ti in commanders.size():
			if commanders[ti] != null and ai_enabled[ti]:
				commanders[ti].think(sim)
	sim.step()


func _track_battle_level(events: Array, dt: float) -> void:
	var n := 0
	for e in events:
		if e["t"] in ["shot", "impact", "launch"]:
			n += 1
	_battle_level = lerpf(_battle_level, clampf(n / 6.0, 0.0, 1.0), clampf(dt * 0.6, 0.0, 1.0))
	if Engine.get_process_frames() % 30 == 0 and audio.has_method("set_ambience"):
		audio.set_ambience(env_rig.weather, _battle_level)


## Player (or UI) command entry point.
func issue(cmd: Dictionary) -> void:
	if not replay.is_empty() or _game_over:
		return
	cmd["team"] = maxi(player_team, 0)
	sim.issue(cmd)


# ================================================================= sandbox ===

var ai_enabled := [true, true]


func set_ai_enabled(team: int, on: bool) -> void:
	ai_enabled[team] = on


## Sandbox: take control of the other side (fog, selection and orders follow).
func switch_control(team: int) -> void:
	player_team = team
	ai_enabled[team] = false
	view.player_team = team
	view.fog.team = team
	view.fog.set_enabled(view.fog.enabled)
	input.set_selection([])


func set_conditions(tod: String, weather: String) -> void:
	env_rig.set_conditions(tod, weather)
	issue({"type": "set_env", "tod": tod, "weather": weather})


func set_paused(p: bool) -> void:
	paused = p
	view.set_paused(p)
	hud.on_pause_changed(p)


func toggle_pause() -> void:
	set_paused(not paused)


func set_speed(s: float) -> void:
	speed = clampf(s, 0.25, 8.0)
	if hud:
		hud.on_speed_changed(speed)


func step_speed(dir: int) -> void:
	var idx := SPEEDS.find(speed)
	if idx < 0:
		idx = 1
	set_speed(SPEEDS[clampi(idx + dir, 0, SPEEDS.size() - 1)])


func _on_game_over(e: Dictionary) -> void:
	if _game_over:
		return
	_game_over = true
	var outcome := sim.outcome.duplicate()
	outcome["player_team"] = player_team
	outcome["stats"] = [sim.teams[0]["stats"].duplicate(), sim.teams[1]["stats"].duplicate()]
	outcome["replay"] = make_replay()
	hud.show_end_screen(outcome)
	ended.emit(outcome)


func make_replay() -> Dictionary:
	var cfg := config.duplicate()
	cfg.erase("map")
	cfg.erase("state")
	cfg.erase("replay")
	cfg.erase("initial_map")
	return {"version": 1, "config": cfg, "map": initial_map, "commands": sim.command_log.duplicate(true), "ticks": sim.tick,
		"title": "%s — %s vs %s" % [sim.map.name, sim.teams[0]["name"], sim.teams[1]["name"]]}


func quit_to_menu() -> void:
	Events.navigate.emit("menu", {})

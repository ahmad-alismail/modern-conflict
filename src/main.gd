extends Node
## App root: owns the active top-level screen (menu, game, editor, preview).
## Dev shortcuts (after `--`): --screen=skirmish|aivai|scenario:<id>|editor, --seed=N,
## --faction=cdf --enemy=pdb, --tod=, --weather=, --preview=<id>.

var _screen: Node
var _toast_layer: CanvasLayer


func _ready() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 50
	add_child(_toast_layer)
	Events.notice.connect(_on_notice)
	var preview := DevHarness.arg("preview")
	if preview != "":
		var path := "res://tools/preview_%s.gd" % preview
		if ResourceLoader.exists(path):
			_set_screen(load(path).new())
			return
		push_error("No preview script at " + path)
	Events.navigate.connect(_on_navigate)
	var screen := DevHarness.arg("screen", "menu")
	if DevHarness.has_arg("replay"):
		var cfg := SaveSystem.load_replay(DevHarness.arg("replay"))
		if not cfg.is_empty():
			call_deferred("_on_navigate", "game", cfg)
			return
	call_deferred("_on_navigate", screen, {})


func _set_screen(n: Node) -> void:
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = n
	add_child(n)


func _on_navigate(screen: String, params: Dictionary) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	match screen:
		"menu":
			_set_screen(MainMenu.new())
		"game":
			await _show_loading(params)
			var s := GameSession.new()
			_set_screen(s)
			s.start(params)
			_hide_loading()
		"editor":
			_set_screen(MapEditor.new())
		"skirmish", "aivai":
			_set_screen_quick(screen)
		_:
			if screen.begins_with("scenario:"):
				_on_navigate("game", Scenarios.build(screen.substr(9), DevHarness.arg("difficulty", "medium")))
			else:
				_set_screen(MainMenu.new())


var _loading: CanvasLayer


func _show_loading(params: Dictionary) -> void:
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
		_screen = null
	_loading = CanvasLayer.new()
	_loading.layer = 40
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.055, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-300, -60)
	vb.custom_minimum_size = Vector2(600, 0)
	var title := UITheme.label(String(params.get("title", "Preparing the battlefield")), 30, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var tips := ["Infantry inside buildings are far harder to hit — and to see.", "Tanks are weakest from the sides, rear and above.",
		"Suppressed squads get pinned; broken squads run for the rear.", "Smoke blocks line of sight for both sides.",
		"Every unit you lose costs tickets. Retreat is not defeat.", "Press Space for tactical pause and plan your next move.",
		"Helix robots lose accuracy when cut off from their network.", "Thermal sights see through darkness and thin smoke."]
	var tip := UITheme.label(tips[randi() % tips.size()], 15, UITheme.TEXT_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)
	_loading.add_child(vb)
	add_child(_loading)
	await get_tree().process_frame
	await get_tree().process_frame


func _hide_loading() -> void:
	if _loading:
		var l := _loading
		_loading = null
		var tw := create_tween()
		for c in l.get_children():
			if c is CanvasItem:
				tw.parallel().tween_property(c, "modulate:a", 0.0, 0.6)
		tw.tween_callback(l.queue_free)


func _set_screen_quick(kind: String) -> void:
	var seed_v := int(DevHarness.arg("seed", "7"))
	var opts := {"tod": DevHarness.arg("tod", "day"), "weather": DevHarness.arg("weather", "clear")}
	var f0 := DevHarness.arg("faction", "cdf")
	var f1 := DevHarness.arg("enemy", "pdb")
	var cfg: Dictionary
	if kind == "aivai":
		var c1 := {"controller": "ai", "difficulty": "hard"}
		var llm := DevHarness.arg("llm")   # e.g. ollama:qwen3.5:9b (session only, not saved)
		if llm != "":
			var prov := llm.get_slice(":", 0)
			var model := llm.substr(prov.length() + 1)
			Settings.set_value("llm", "enabled", true, false)
			Settings.set_value("llm", "provider", prov, false)
			Settings.set_value("llm", prov + "_model" if prov != "openai_compat" else "openai_model", model, false)
			c1 = {"controller": "llm"}
		cfg = GameConfig.ai_vs_ai(f0, f1, {"controller": "ai", "difficulty": "hard"}, c1, seed_v, opts)
	else:
		cfg = GameConfig.skirmish(f0, f1, DevHarness.arg("difficulty", "medium"), seed_v, opts)
	_on_navigate("game", cfg)


func _on_notice(text: String, kind: String) -> void:
	var l := UITheme.label(text, 18, UITheme.ALERT if kind == "alert" else UITheme.ACCENT)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(-300, 60)
	l.size = Vector2(600, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_layer.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

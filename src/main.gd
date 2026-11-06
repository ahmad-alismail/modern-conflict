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
			var s := GameSession.new()
			_set_screen(s)
			s.start(params)
		"editor":
			_set_screen(MapEditor.new())
		"skirmish", "aivai":
			_set_screen_quick(screen)
		_:
			if screen.begins_with("scenario:"):
				_on_navigate("game", Scenarios.build(screen.substr(9), DevHarness.arg("difficulty", "medium")))
			else:
				_set_screen(MainMenu.new())


func _set_screen_quick(kind: String) -> void:
	var seed_v := int(DevHarness.arg("seed", "7"))
	var opts := {"tod": DevHarness.arg("tod", "day"), "weather": DevHarness.arg("weather", "clear")}
	var f0 := DevHarness.arg("faction", "cdf")
	var f1 := DevHarness.arg("enemy", "pdb")
	var cfg: Dictionary
	if kind == "aivai":
		cfg = GameConfig.ai_vs_ai(f0, f1, {"controller": "ai", "difficulty": "hard"}, {"controller": "ai", "difficulty": "hard"}, seed_v, opts)
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

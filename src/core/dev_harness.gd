extends Node
## Developer harness driven by command-line user args (after `--`):
##   --shot=<abs path.png>   save a screenshot after --shot-delay seconds (real time), then quit
##   --shot-delay=<sec>      default 4
##   --quit-after=<sec>      quit after N seconds (no screenshot)
## Other args (e.g. --skirmish, --map=...) are read by Main via `arg()`.

var args: Dictionary = {}
var _start_ms := 0
var _shot_path := ""
var _shot_delay := 4.0
var _quit_after := -1.0
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_ms = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if not s.begins_with("--"):
			continue
		s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			args[s] = "true"
	_shot_path = args.get("shot", "")
	_shot_delay = float(args.get("shot-delay", "4"))
	_quit_after = float(args.get("quit-after", "-1"))
	set_process(_shot_path != "" or _quit_after > 0.0)
	if args.has("window-test"):
		_window_test()


## Dev check: report window mode at startup, toggle with F11 twice, report again, quit.
func _window_test() -> void:
	await get_tree().create_timer(1.5).timeout
	_report("startup")
	for i in 2:
		var k := InputEventKey.new()
		k.keycode = KEY_F11
		k.pressed = true
		Input.parse_input_event(k)
		await get_tree().create_timer(1.0).timeout
		_report("after F11 #%d" % (i + 1))
	get_tree().quit()


func _report(when: String) -> void:
	var names := {DisplayServer.WINDOW_MODE_WINDOWED: "windowed", DisplayServer.WINDOW_MODE_FULLSCREEN: "fullscreen (borderless)",
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: "exclusive fullscreen", DisplayServer.WINDOW_MODE_MAXIMIZED: "maximized"}
	print("[window-test] %s: %s, window %s, screen %s" % [when, names.get(DisplayServer.window_get_mode(), "other"),
		DisplayServer.window_get_size(), DisplayServer.screen_get_size()])


func has_arg(key: String) -> bool:
	return args.has(key)


func arg(key: String, default_value: String = "") -> String:
	return args.get(key, default_value)


func _process(_delta: float) -> void:
	if _done:
		return
	var t := (Time.get_ticks_msec() - _start_ms) / 1000.0
	if _shot_path != "" and t >= _shot_delay:
		_done = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_shot_path)
		print("[DevHarness] screenshot -> %s (%s)" % [_shot_path, error_string(err)])
		get_tree().quit()
	elif _quit_after > 0.0 and t >= _quit_after:
		_done = true
		get_tree().quit()

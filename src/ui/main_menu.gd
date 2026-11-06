extends Node
## Title screen: cinematic city backdrop and the main navigation.
class_name MainMenu

var _ui: Control
var _content: Control


func _ready() -> void:
	add_child(MenuBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.get_theme()
	layer.add_child(_ui)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.custom_minimum_size = Vector2(520, 0)
	shade.size = Vector2(520, 0)
	shade.color = Color(0.03, 0.035, 0.03, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	var vb := VBoxContainer.new()
	vb.position = Vector2(70, 120)
	vb.custom_minimum_size = Vector2(380, 0)
	vb.add_theme_constant_override("separation", 10)
	_ui.add_child(vb)
	var title := UITheme.label("MODERN CONFLICT", 46, UITheme.ACCENT)
	vb.add_child(title)
	vb.add_child(UITheme.label("Command the battle. No factories. No mercy for poor decisions.", 14, UITheme.TEXT_DIM))
	vb.add_child(_spacer(26))
	var items := [
		["Skirmish", "Battle a classic AI opponent on a generated city.", func(): _open(SetupScreen.new("skirmish"))],
		["Scenarios", "Fictional missions with objectives and fixed forces.", func(): _open(ScenarioScreen.new())],
		["Sandbox", "Place any units, set conditions, experiment.", func(): _open(SetupScreen.new("sandbox"))],
		["AI vs AI", "Watch classic or LLM commanders fight it out.", func(): _open(SetupScreen.new("aivai"))],
		["Map Editor", "Build maps by hand or from an uploaded plan image.", func(): Events.navigate.emit("editor", {})],
		["Load Game", "Continue a saved battle.", func(): _open(FileListScreen.new("load"))],
		["Replays", "Watch recorded battles.", func(): _open(FileListScreen.new("replay"))],
		["Settings", "Graphics, audio, gameplay, LLM commanders.", func(): _open(SettingsMenu.new())],
		["Quit", "", func(): get_tree().quit()],
	]
	for it in items:
		var b := UITheme.button(it[0], it[2], it[1])
		b.custom_minimum_size = Vector2(320, 42)
		b.add_theme_font_size_override("font_size", 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vb.add_child(b)
	match DevHarness.arg("menu-open"):
		"skirmish", "sandbox", "aivai": _open(SetupScreen.new(DevHarness.arg("menu-open")))
		"forces":
			var ss := SetupScreen.new("skirmish")
			_open(ss)
			ss.call_deferred("_open_force_builder")
		"scenarios": _open(ScenarioScreen.new())
		"settings": _open(SettingsMenu.new())
		"load": _open(FileListScreen.new("load"))
	var ver := UITheme.label("v%s · offline · no paid services required" % ProjectSettings.get_setting("application/config/version"), 12, UITheme.TEXT_DIM)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(70, -40)
	_ui.add_child(ver)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _open(screen: Control) -> void:
	if _content and is_instance_valid(_content):
		_content.queue_free()
	_content = screen
	_ui.add_child(screen)

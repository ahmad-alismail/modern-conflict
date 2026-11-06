extends Node
## Persistent user settings (graphics, audio, gameplay, optional LLM commander).
## Stored in user://settings.cfg. Other systems read values and listen to `changed`.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

const QUALITY_LOW := 0
const QUALITY_MEDIUM := 1
const QUALITY_HIGH := 2
const QUALITY_ULTRA := 3

const DEFAULTS := {
	"graphics": {
		"quality": QUALITY_HIGH,
		"fullscreen": false,
		"vsync": true,
		"render_scale": 1.0,
		"max_fps": 0,
		"show_fps": false,
	},
	"audio": {
		"master": 0.8,
		"sfx": 0.9,
		"ambience": 0.6,
		"ui": 0.7,
	},
	"gameplay": {
		"edge_scroll": true,
		"scroll_speed": 1.0,
		"rotate_speed": 1.0,
		"invert_zoom": false,
		"always_show_health": false,
		"pause_on_contact": false,
		"default_speed": 1.0,
	},
	"llm": {
		# Optional LLM commander. Never enabled automatically.
		"enabled": false,
		"provider": "ollama", # ollama | openai_compat | anthropic
		"ollama_url": "http://localhost:11434",
		"ollama_model": "llama3.1",
		"openai_url": "http://localhost:1234/v1",
		"openai_model": "local-model",
		"anthropic_model": "claude-haiku-5-5",
		"remember_keys": false,
		"openai_key": "",
		"anthropic_key": "",
		"paid_consent": false,
		"think_interval": 8.0,
	},
}

var _data: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_display()


func get_value(section: String, key: String) -> Variant:
	if _data.has(section) and _data[section].has(key):
		return _data[section][key]
	return DEFAULTS.get(section, {}).get(key)


func set_value(section: String, key: String, value: Variant, save := true) -> void:
	if not _data.has(section):
		_data[section] = {}
	_data[section][key] = value
	if save:
		save_settings()
	changed.emit(section, key)
	if section == "graphics" and key in ["fullscreen", "vsync", "max_fps"]:
		apply_display()


func load_settings() -> void:
	_data = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in cfg.get_sections():
		if not _data.has(section):
			continue
		for key in cfg.get_section_keys(section):
			_data[section][key] = cfg.get_value(section, key)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section in _data:
		for key in _data[section]:
			var v = _data[section][key]
			# API keys are only persisted when the user explicitly opts in.
			if section == "llm" and key.ends_with("_key") and not _data["llm"].get("remember_keys", false):
				v = ""
			cfg.set_value(section, key, v)
	cfg.save(PATH)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fs: bool = get_value("graphics", "fullscreen")
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("graphics", "vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("graphics", "max_fps"))


func quality() -> int:
	return int(get_value("graphics", "quality"))

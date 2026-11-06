extends PanelContainer
## Settings: graphics, audio, gameplay and the optional LLM commander.
## Paid cloud providers require explicit consent; nothing activates automatically.
class_name SettingsMenu


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-380, -330)
	custom_minimum_size = Vector2(760, 660)
	var vb := VBoxContainer.new()
	add_child(vb)
	vb.add_child(UITheme.label("SETTINGS", 26, UITheme.ACCENT))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(720, 540)
	vb.add_child(tabs)
	tabs.add_child(_graphics())
	tabs.add_child(_audio())
	tabs.add_child(_gameplay())
	tabs.add_child(_llm())
	var close := UITheme.button("Close", queue_free)
	vb.add_child(close)


func _grid(name: String) -> GridContainer:
	var g := GridContainer.new()
	g.name = name
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 10)
	return g


func _label(g: GridContainer, text: String) -> void:
	g.add_child(UITheme.label(text, 14, UITheme.TEXT_DIM))


func _option(g: GridContainer, text: String, section: String, key: String, items: Array, values: Array) -> void:
	_label(g, text)
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	var cur = Settings.get_value(section, key)
	var idx := values.find(cur)
	o.select(maxi(idx, 0))
	o.item_selected.connect(func(i): Settings.set_value(section, key, values[i]))
	g.add_child(o)


func _check(g: GridContainer, text: String, section: String, key: String) -> CheckBox:
	_label(g, text)
	var c := CheckBox.new()
	c.button_pressed = bool(Settings.get_value(section, key))
	c.toggled.connect(func(v): Settings.set_value(section, key, v))
	g.add_child(c)
	return c


func _slider(g: GridContainer, text: String, section: String, key: String, lo: float, hi: float, step: float) -> void:
	_label(g, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(section, key))
	s.custom_minimum_size = Vector2(260, 20)
	s.value_changed.connect(func(v): Settings.set_value(section, key, v))
	g.add_child(s)


func _text(g: GridContainer, text: String, section: String, key: String, secret: bool = false) -> void:
	_label(g, text)
	var e := LineEdit.new()
	e.text = str(Settings.get_value(section, key))
	e.secret = secret
	e.custom_minimum_size = Vector2(360, 0)
	e.text_changed.connect(func(v): Settings.set_value(section, key, v))
	g.add_child(e)


func _graphics() -> Control:
	var g := _grid("Graphics")
	_option(g, "Quality preset", "graphics", "quality", ["Low", "Medium", "High", "Ultra (SDFGI)"], [0, 1, 2, 3])
	_check(g, "Fullscreen", "graphics", "fullscreen")
	_check(g, "V-Sync", "graphics", "vsync")
	_slider(g, "Render scale", "graphics", "render_scale", 0.5, 1.0, 0.05)
	_option(g, "FPS limit", "graphics", "max_fps", ["Unlimited", "30", "60", "120", "144"], [0, 30, 60, 120, 144])
	_check(g, "Show FPS", "graphics", "show_fps")
	return g


func _audio() -> Control:
	var g := _grid("Audio")
	_slider(g, "Master volume", "audio", "master", 0.0, 1.0, 0.05)
	_slider(g, "Effects", "audio", "sfx", 0.0, 1.0, 0.05)
	_slider(g, "Ambience", "audio", "ambience", 0.0, 1.0, 0.05)
	_slider(g, "Interface", "audio", "ui", 0.0, 1.0, 0.05)
	return g


func _gameplay() -> Control:
	var g := _grid("Gameplay")
	_check(g, "Edge scrolling", "gameplay", "edge_scroll")
	_slider(g, "Scroll speed", "gameplay", "scroll_speed", 0.3, 3.0, 0.1)
	_slider(g, "Rotate speed", "gameplay", "rotate_speed", 0.3, 3.0, 0.1)
	_check(g, "Invert zoom", "gameplay", "invert_zoom")
	_check(g, "Always show health bars", "gameplay", "always_show_health")
	_check(g, "Auto-pause on enemy contact", "gameplay", "pause_on_contact")
	_option(g, "Default game speed", "gameplay", "default_speed", ["0.5×", "1×", "2×"], [0.5, 1.0, 2.0])
	return g


func _llm() -> Control:
	var vb := VBoxContainer.new()
	vb.name = "LLM Commander"
	var info := UITheme.label("Optional. Lets a language model command a faction (AI vs AI or as your opponent).\nThe game never needs this and never contacts any service unless you enable it here.", 13, UITheme.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(info)
	var g := _grid("llm")
	vb.add_child(g)
	_check(g, "Enable LLM commanders", "llm", "enabled")
	_option(g, "Provider", "llm", "provider", ["Ollama (local)", "OpenAI-compatible (LM Studio, local or cloud)", "Anthropic Claude (cloud, paid)"], ["ollama", "openai_compat", "anthropic"])
	_text(g, "Ollama URL", "llm", "ollama_url")
	_text(g, "Ollama model", "llm", "ollama_model")
	_text(g, "OpenAI-compatible URL", "llm", "openai_url")
	_text(g, "OpenAI-compatible model", "llm", "openai_model")
	_text(g, "OpenAI-compatible key", "llm", "openai_key", true)
	_text(g, "Anthropic model", "llm", "anthropic_model")
	_text(g, "Anthropic API key", "llm", "anthropic_key", true)
	_check(g, "Remember API keys on this PC", "llm", "remember_keys")
	_check(g, "I accept that cloud providers bill my account", "llm", "paid_consent")
	_slider(g, "Decision interval (s)", "llm", "think_interval", 4.0, 30.0, 1.0)
	var row := HBoxContainer.new()
	_test_label = UITheme.label("", 13, UITheme.TEXT_DIM)
	_test_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_test_label.custom_minimum_size = Vector2(520, 0)
	row.add_child(UITheme.button("Test connection", _test_connection, "Lists available models. Makes no paid generation request."))
	row.add_child(_test_label)
	vb.add_child(row)
	return vb


var _test_label: Label
var _http: HTTPRequest


func _test_connection() -> void:
	var prov: String = Settings.get_value("llm", "provider")
	var url := ""
	var headers := PackedStringArray()
	match prov:
		"ollama":
			url = String(Settings.get_value("llm", "ollama_url")).trim_suffix("/") + "/api/tags"
		"openai_compat":
			url = String(Settings.get_value("llm", "openai_url")).trim_suffix("/") + "/models"
			var key := String(Settings.get_value("llm", "openai_key")).strip_edges()
			if key != "":
				headers.append("Authorization: Bearer " + key)
		"anthropic":
			var key := String(Settings.get_value("llm", "anthropic_key")).strip_edges()
			if key == "":
				_test_label.text = "Enter an Anthropic API key first."
				return
			url = "https://api.anthropic.com/v1/models"
			headers.append("x-api-key: " + key)
			headers.append("anthropic-version: " + LLMCommander.ANTHROPIC_VERSION)
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 10.0
		add_child(_http)
		_http.request_completed.connect(_on_test_done)
	_test_label.text = "Contacting %s ..." % url
	if _http.request(url, headers) != OK:
		_test_label.text = "Could not start the request."


func _on_test_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_test_label.text = "No connection (is the server running?)."
		return
	if code != 200:
		_test_label.text = "HTTP %d: %s" % [code, body.get_string_from_utf8().substr(0, 120)]
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var names := []
	if typeof(data) == TYPE_DICTIONARY:
		for m in data.get("models", data.get("data", [])):
			names.append(String(m.get("name", m.get("id", "?"))))
	_test_label.text = "OK. Models: " + ", ".join(names.slice(0, 8)) if names.size() > 0 else "Connected, but no models listed."

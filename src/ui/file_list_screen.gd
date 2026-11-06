extends PanelContainer
## Lists save games or replays and starts the selected one.
class_name FileListScreen

var kind := "load"


func _init(p_kind: String) -> void:
	kind = p_kind


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	position = Vector2(-720, -300)
	custom_minimum_size = Vector2(640, 560)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	vb.add_child(UITheme.label("LOAD GAME" if kind == "load" else "REPLAYS", 26, UITheme.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 440)
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var files := SaveSystem.list(SaveSystem.SAVE_DIR, ".sav") if kind == "load" else SaveSystem.list(SaveSystem.REPLAY_DIR, ".replay")
	if files.is_empty():
		list.add_child(UITheme.label("Nothing here yet.", 14, UITheme.TEXT_DIM))
	for f in files:
		var b := UITheme.button(f.get_file(), func(): _open(f))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	vb.add_child(UITheme.button("Back", queue_free))


func _open(path: String) -> void:
	var cfg := SaveSystem.load_save(path) if kind == "load" else SaveSystem.load_replay(path)
	if cfg.is_empty():
		Events.notice.emit("Could not read " + path.get_file(), "alert")
		return
	Events.navigate.emit("game", cfg)

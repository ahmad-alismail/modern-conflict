extends Node
## App root: owns the active top-level screen (menu, game, editor).

var _screen: Node


func _ready() -> void:
	var label := Label.new()
	label.text = "MODERN CONFLICT"
	label.add_theme_font_size_override("font_size", 64)
	label.set_anchors_preset(Control.PRESET_CENTER)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
	_screen = layer

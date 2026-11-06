extends Node
## Map editor (placeholder; replaced by the full editor).
class_name MapEditor


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var b := UITheme.button("Map editor coming soon — Back", func(): Events.navigate.emit("menu", {}))
	b.position = Vector2(100, 100)
	layer.add_child(b)

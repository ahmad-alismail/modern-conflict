extends Node3D
## Slowly orbiting cinematic view over a small generated city: menu background.
class_name MenuBackdrop

var _cam: Camera3D
var _t := 0.0
var _center := Vector3.ZERO
var _rig: EnvironmentRig


func _ready() -> void:
	var m := CityGenerator.generate(int(Time.get_unix_time_from_system()) % 1000 + 3, {"size": 140, "war_damage": 0.35})
	_rig = EnvironmentRig.new()
	add_child(_rig)
	var tods := ["day", "dusk", "dawn"]
	_rig.set_conditions(tods[randi() % tods.size()], "haze")
	var terrain := TerrainBuilder.new()
	add_child(terrain)
	terrain.build(m)
	for b in m.buildings:
		var n := BuildingBuilder.build(b)
		n.position = Vector3(b["c"].x, 0, b["c"].y)
		n.rotation.y = -b["rot"]
		add_child(n)
	add_child(PropBuilder.build_walls(m.walls))
	add_child(PropBuilder.build_props(m.props))
	_center = Vector3(m.size_m().x * 0.5, 0, m.size_m().y * 0.5)
	_cam = Camera3D.new()
	_cam.fov = 45
	_cam.far = 3000
	add_child(_cam)
	_cam.current = true
	_process(0.0)


func _process(delta: float) -> void:
	_t += delta * 0.025
	var r := 150.0
	var pos := _center + Vector3(cos(_t) * r, 55.0 + sin(_t * 0.7) * 10.0, sin(_t) * r)
	_cam.look_at_from_position(pos, _center + Vector3(0, 6, 0), Vector3.UP)

extends RefCounted
## Helpers for showcase/preview scenes (tools/preview_*.gd) used to screenshot-test
## art modules in isolation: standard lighting, sandy ground and a camera.
class_name PreviewKit


## Adds environment + ground + camera. Camera looks at `focus` from `dist` meters,
## at `pitch_deg` elevation and `yaw_deg` around the Y axis.
static func setup(root: Node3D, focus: Vector3 = Vector3.ZERO, dist: float = 30.0, pitch_deg: float = 30.0,
		yaw_deg: float = 35.0, tod: String = "day", weather: String = "clear") -> Camera3D:
	var rig := EnvironmentRig.new()
	root.add_child(rig)
	rig.set_conditions(tod, weather)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.72, 0.64, 0.52)
	gm.roughness = 0.95
	ground.material_override = gm
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 4000.0
	root.add_child(cam)
	var dir := Vector3(cos(deg_to_rad(pitch_deg)) * cos(deg_to_rad(yaw_deg)), sin(deg_to_rad(pitch_deg)), cos(deg_to_rad(pitch_deg)) * sin(deg_to_rad(yaw_deg)))
	cam.look_at_from_position(focus + dir * dist, focus, Vector3.UP)
	cam.current = true
	return cam

extends Node3D
## Visual for a flying projectile (Defs.P_*), created by Effects.projectile(). The caller
## moves this node every frame; the visual orients itself along its motion. Smoke trails
## are emitted at fixed spacing into the shared world-space smoke batcher, so they keep
## drifting and fade naturally after Effects.release_projectile() frees the node.
class_name FxProjectile

const _FLARE := preload("res://src/render/fx/flare.gdshader")

var kind := 0
var fx: Effects

var _visual: Node3D
var _last := Vector3.ZERO
var _has_last := false
var _trail_acc := 0.0
var _released := false

static var _meshes: Dictionary = {}
static var _flares: Dictionary = {}


func setup(effects: Effects, projectile_kind: int) -> void:
	fx = effects
	kind = projectile_kind
	_visual = Node3D.new()
	add_child(_visual)
	match kind:
		Defs.P_SHELL, Defs.P_BULLET:
			_add_flare("slug", Vector3.ZERO)
		Defs.P_ROCKET:
			_add_mesh("rocket")
			_add_flare("rocket_motor", Vector3(0, 0, 0.5))
			_add_flare("rocket_plume", Vector3(0, 0, 0.95))
		Defs.P_MISSILE:
			_add_mesh("missile")
			_add_flare("missile_motor", Vector3(0, 0, 0.62))
		Defs.P_MORTAR:
			_add_mesh("mortar")
		Defs.P_BOMB:
			_add_mesh("bomb")


func release() -> void:
	if _released:
		return
	_released = true
	visible = false
	set_process(false)
	queue_free()


func _process(_delta: float) -> void:
	if _released or fx == null or not is_instance_valid(fx):
		return
	var p := global_position
	if not _has_last:
		_last = p
		_has_last = true
		return
	var seg := p - _last
	var dist := seg.length()
	if dist < 0.0001:
		return
	var dir := seg / dist
	if absf(dir.y) < 0.999:
		_visual.global_basis = Basis.looking_at(dir, Vector3.UP)
	else:
		_visual.global_basis = Basis.looking_at(dir, Vector3.FORWARD)
	if dist < 40.0 and not fx.is_paused():
		_emit_trail(_last, dir, dist)
	_last = p


func _emit_trail(from: Vector3, dir: Vector3, dist: float) -> void:
	var spacing := 0.0
	match kind:
		Defs.P_ROCKET:
			spacing = 0.55
		Defs.P_MISSILE:
			spacing = 0.45
		_:
			return
	var d := spacing - _trail_acc
	while d <= dist:
		var p := from + dir * d
		d += spacing
		var back := -dir * randf_range(0.5, 2.0)
		if kind == Defs.P_ROCKET:
			var g := randf_range(0.66, 0.8)
			fx.emit_smoke(p, back + Vector3.UP * 0.2, Color(g, g * 0.98, g * 0.95, 0.5), randf_range(2.5, 4.0),
					0.35, randf_range(1.7, 2.4), 1.6, 0.25, 0.6, 2.5, 0.08, 0.02, 0.3, 0.6, -50.0)
			if randf() < 0.5:
				fx.emit_glow(p, back * 2.0, Color(1.0, 0.75, 0.4, 3.0), 0.07, 0.35, 0.15, 0, 1)
		else:
			var g := randf_range(0.82, 0.92)
			fx.emit_smoke(p, back * 0.5 + Vector3.UP * 0.1, Color(g, g, g, 0.38), randf_range(3.0, 4.5),
					0.22, randf_range(0.9, 1.3), 1.4, 0.15, 0.5, 1.5, 0.06, 0.02, 0.35, 0.4, -50.0)
	_trail_acc = dist - (d - spacing)


## Advances the shared flare materials' flicker clock (called by Effects each frame).
static func set_time(t: float) -> void:
	for m in _flares.values():
		(m as ShaderMaterial).set_shader_parameter("fx_time", t)


func _add_flare(id: String, offset: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.material_override = _flare_mat(id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = offset
	mi.extra_cull_margin = 4.0
	_visual.add_child(mi)


func _add_mesh(id: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mi)


static func _flare_mat(id: String) -> ShaderMaterial:
	if _flares.has(id):
		return _flares[id]
	var m := ShaderMaterial.new()
	m.shader = _FLARE
	match id:
		"slug":
			m.set_shader_parameter("tint", Color(1.0, 0.72, 0.38))
			m.set_shader_parameter("energy", 9.0)
			m.set_shader_parameter("stretch_len", 2.6)
			m.set_shader_parameter("width", 0.22)
			m.set_shader_parameter("min_px", 3.0)
		"rocket_motor":
			m.set_shader_parameter("tint", Color(1.0, 0.7, 0.35))
			m.set_shader_parameter("energy", 12.0)
			m.set_shader_parameter("width", 0.7)
			m.set_shader_parameter("min_px", 5.0)
			m.set_shader_parameter("flicker", 0.35)
		"rocket_plume":
			m.set_shader_parameter("tint", Color(1.0, 0.5, 0.2))
			m.set_shader_parameter("energy", 5.0)
			m.set_shader_parameter("stretch_len", 0.9)
			m.set_shader_parameter("width", 0.3)
			m.set_shader_parameter("min_px", 2.0)
			m.set_shader_parameter("flicker", 0.5)
		"missile_motor":
			m.set_shader_parameter("tint", Color(1.0, 0.88, 0.7))
			m.set_shader_parameter("energy", 16.0)
			m.set_shader_parameter("width", 0.5)
			m.set_shader_parameter("min_px", 5.0)
			m.set_shader_parameter("flicker", 0.2)
	_flares[id] = m
	return m


## Small revolved meshes built along -Z (nose forward), cached per kind.
static func _mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.metallic = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	match id:
		"rocket":
			# (z, radius) from tail to nose.
			_lathe(st, [Vector2(0.45, 0.04), Vector2(0.1, 0.045), Vector2(-0.1, 0.045), Vector2(-0.18, 0.06),
					Vector2(-0.4, 0.06), Vector2(-0.55, 0.0)], Color(0.32, 0.34, 0.26))
			_fins(st, 0.45, 0.25, 0.12, Color(0.25, 0.26, 0.2))
		"missile":
			_lathe(st, [Vector2(0.6, 0.06), Vector2(-0.45, 0.06), Vector2(-0.58, 0.04), Vector2(-0.65, 0.0)], Color(0.55, 0.57, 0.52))
			_fins(st, 0.55, 0.2, 0.1, Color(0.4, 0.42, 0.38))
			_fins(st, -0.25, 0.12, 0.07, Color(0.4, 0.42, 0.38))
		"mortar":
			_lathe(st, [Vector2(0.24, 0.025), Vector2(0.12, 0.03), Vector2(0.0, 0.055), Vector2(-0.12, 0.05),
					Vector2(-0.2, 0.025), Vector2(-0.24, 0.0)], Color(0.17, 0.19, 0.15))
			_fins(st, 0.24, 0.1, 0.06, Color(0.15, 0.16, 0.13))
		_:
			_lathe(st, [Vector2(0.14, 0.02), Vector2(0.05, 0.04), Vector2(-0.08, 0.04), Vector2(-0.14, 0.0)], Color(0.2, 0.21, 0.18))
			_fins(st, 0.14, 0.06, 0.04, Color(0.18, 0.18, 0.16))
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, mat)
	_meshes[id] = m
	return m


static func _lathe(st: SurfaceTool, profile: Array, color: Color, seg: int = 10) -> void:
	st.set_color(color)
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for s in seg:
			var t0 := TAU * s / seg
			var t1 := TAU * (s + 1) / seg
			var p00 := Vector3(cos(t0) * a.y, sin(t0) * a.y, a.x)
			var p01 := Vector3(cos(t1) * a.y, sin(t1) * a.y, a.x)
			var p10 := Vector3(cos(t0) * b.y, sin(t0) * b.y, b.x)
			var p11 := Vector3(cos(t1) * b.y, sin(t1) * b.y, b.x)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(v)


static func _fins(st: SurfaceTool, z_tail: float, length: float, span: float, color: Color) -> void:
	st.set_color(color)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var d := Vector3(cos(a), sin(a), 0.0)
		var r0 := d * 0.03
		var r1 := d * (0.03 + span)
		var p0 := r0 + Vector3(0, 0, z_tail)
		var p1 := r1 + Vector3(0, 0, z_tail)
		var p2 := r1 + Vector3(0, 0, z_tail - length * 0.6)
		var p3 := r0 + Vector3(0, 0, z_tail - length)
		for v in [p0, p1, p2, p0, p2, p3]:
			st.add_vertex(v)

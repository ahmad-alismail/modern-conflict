extends Node3D
## Lighting, sky, atmosphere and weather for the battlefield, with quality presets.
## time_of_day: "dawn" | "day" | "dusk" | "night";  weather: "clear" | "haze" | "dust" | "rain"
class_name EnvironmentRig

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var cam_attr: CameraAttributesPractical
var time_of_day := "day"
var weather := "clear"
var _weather_fx: GPUParticles3D
var _follow: Node3D


func _ready() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	var clouds := NoiseTexture2D.new()
	clouds.width = 1024
	clouds.height = 512
	clouds.seamless = true
	var n := FastNoiseLite.new()
	n.frequency = 0.004
	n.fractal_octaves = 5
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clouds.noise = n
	clouds.color_ramp = Gradient.new()
	clouds.color_ramp.set_offset(0, 0.45)
	clouds.color_ramp.set_color(0, Color(0, 0, 0, 0))
	clouds.color_ramp.set_offset(1, 0.9)
	clouds.color_ramp.set_color(1, Color(1, 1, 1, 1))
	sky_mat.sky_cover = clouds
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 220.0
	env.fog_depth_end = 1400.0
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.7
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_length = 260.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_sky_affect = 0.15
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	world_env = WorldEnvironment.new()
	world_env.environment = env
	cam_attr = CameraAttributesPractical.new()
	world_env.camera_attributes = cam_attr
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 300.0
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	apply_quality(Settings.quality())
	set_conditions(time_of_day, weather)
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed(section: String, key: String) -> void:
	if section == "graphics" and key == "quality":
		apply_quality(Settings.quality())


func apply_quality(q: int) -> void:
	env.ssao_enabled = q >= Settings.QUALITY_MEDIUM
	env.ssil_enabled = q >= Settings.QUALITY_HIGH
	env.sdfgi_enabled = q >= Settings.QUALITY_ULTRA
	env.volumetric_fog_enabled = q >= Settings.QUALITY_HIGH
	env.glow_enabled = q >= Settings.QUALITY_LOW
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= Settings.QUALITY_MEDIUM else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.0 if q >= Settings.QUALITY_HIGH else 0.5
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_4X if q >= Settings.QUALITY_ULTRA else (Viewport.MSAA_2X if q >= Settings.QUALITY_HIGH else Viewport.MSAA_DISABLED)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q <= Settings.QUALITY_MEDIUM else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = false
		vp.scaling_3d_scale = float(Settings.get_value("graphics", "render_scale"))
	RenderingServer.directional_shadow_atlas_set_size(8192 if q >= Settings.QUALITY_HIGH else (4096 if q >= Settings.QUALITY_MEDIUM else 2048), true)


## Keep shadow cascade coverage proportional to how much of the battlefield is visible.
func set_view_distance(d: float) -> void:
	sun.directional_shadow_max_distance = clampf(d * 1.6, 90.0, 520.0)


func follow(node: Node3D) -> void:
	_follow = node


func _process(_delta: float) -> void:
	if _weather_fx and _follow:
		_weather_fx.global_position = _follow.global_position + Vector3(0, 20, 0)


func set_conditions(tod: String, wx: String) -> void:
	time_of_day = tod
	weather = wx
	var elev := 48.0
	var azim := 135.0
	var sun_col := Color(1.0, 0.95, 0.86)
	var sun_e := 1.25
	var top := Color(0.27, 0.45, 0.74)
	var hor := Color(0.72, 0.74, 0.76)
	var amb_e := 1.0
	var exposure := 1.0
	match tod:
		"dawn":
			elev = 14.0
			azim = 75.0
			sun_col = Color(1.0, 0.8, 0.62)
			sun_e = 1.0
			top = Color(0.32, 0.42, 0.62)
			hor = Color(0.88, 0.74, 0.62)
			amb_e = 0.85
		"dusk":
			elev = 11.0
			azim = 255.0
			sun_col = Color(1.0, 0.74, 0.52)
			sun_e = 1.0
			top = Color(0.26, 0.32, 0.52)
			hor = Color(0.86, 0.66, 0.52)
			amb_e = 0.85
			exposure = 1.05
		"night":
			elev = 38.0
			azim = 200.0
			sun_col = Color(0.55, 0.65, 1.0)
			sun_e = 0.16
			top = Color(0.01, 0.015, 0.035)
			hor = Color(0.05, 0.06, 0.1)
			amb_e = 0.25
			exposure = 1.6
	var fog_col := hor.lerp(Color(0.8, 0.75, 0.66), 0.4)
	var vol_density := 0.0028
	var depth_begin := 260.0
	var depth_end := 1500.0
	var vol_albedo := Color(0.86, 0.8, 0.7)
	match wx:
		"haze":
			vol_density = 0.006
			depth_begin = 150.0
			depth_end = 1000.0
			sun_e *= 0.9
			fog_col = fog_col.lerp(Color(0.8, 0.77, 0.7), 0.5)
		"dust":
			vol_density = 0.03
			depth_begin = 20.0
			depth_end = 380.0
			sun_e *= 0.55
			fog_col = Color(0.76, 0.6, 0.42)
			vol_albedo = Color(0.85, 0.66, 0.45)
			top = top.lerp(Color(0.72, 0.58, 0.42), 0.75)
			hor = hor.lerp(Color(0.8, 0.62, 0.42), 0.85)
		"rain":
			vol_density = 0.012
			depth_begin = 60.0
			depth_end = 700.0
			sun_e *= 0.45
			fog_col = Color(0.5, 0.53, 0.56)
			top = top.lerp(Color(0.35, 0.38, 0.42), 0.8)
			hor = hor.lerp(Color(0.55, 0.57, 0.6), 0.8)
	if tod == "night":
		fog_col = fog_col * 0.12
		vol_albedo = vol_albedo * 0.3
	sun.rotation_degrees = Vector3(-elev, azim, 0)
	sun.light_color = sun_col
	sun.light_energy = sun_e
	sun.light_volumetric_fog_energy = 1.0 if wx != "dust" else 0.6
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor.darkened(0.15)
	sky_mat.ground_bottom_color = hor.darkened(0.5)
	sky_mat.sky_cover_modulate = Color(1, 1, 1, 0.55 if wx in ["clear", "haze"] else 0.9)
	sky_mat.sun_angle_max = 18.0
	sky_mat.energy_multiplier = 1.0 if tod != "night" else 0.4
	env.ambient_light_energy = amb_e
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_exposure = exposure
	env.fog_light_color = fog_col
	env.fog_depth_begin = depth_begin
	env.fog_depth_end = depth_end
	env.fog_density = 0.0
	env.volumetric_fog_density = vol_density
	env.volumetric_fog_albedo = vol_albedo
	_setup_weather_fx(wx)


func _setup_weather_fx(wx: String) -> void:
	if _weather_fx:
		_weather_fx.queue_free()
		_weather_fx = null
	if wx != "rain" and wx != "dust":
		return
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(120, 10, 120)
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	if wx == "rain":
		p.amount = 6000
		p.lifetime = 1.4
		pm.direction = Vector3(0.1, -1, 0)
		pm.spread = 3.0
		pm.initial_velocity_min = 28.0
		pm.initial_velocity_max = 34.0
		pm.gravity = Vector3(0, -9.8, 0)
		pm.color = Color(0.75, 0.8, 0.9, 0.35)
		quad.size = Vector2(0.03, 0.9)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	else:
		p.amount = 2500
		p.lifetime = 4.0
		pm.direction = Vector3(1, 0.05, 0.3)
		pm.spread = 15.0
		pm.initial_velocity_min = 10.0
		pm.initial_velocity_max = 18.0
		pm.gravity = Vector3(0, -0.4, 0)
		pm.color = Color(0.8, 0.65, 0.45, 0.22)
		pm.scale_min = 0.5
		pm.scale_max = 2.5
		quad.size = Vector2(1.2, 0.5)
	quad.material = mat
	p.process_material = pm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-140, -40, -140), Vector3(280, 80, 280))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_weather_fx = p


## Cinematic depth of field (close zoom only).
func set_dof(enabled: bool, focus_dist: float) -> void:
	cam_attr.dof_blur_far_enabled = enabled
	cam_attr.dof_blur_far_distance = focus_dist * 2.2
	cam_attr.dof_blur_far_transition = focus_dist * 3.0
	cam_attr.dof_blur_amount = 0.06

shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// RGBA splat: r = asphalt road, g = paving, b = vegetation (1 grass, 0.5 field, 0.12 dirt), a = rubble
uniform sampler2D terrain_map : filter_linear, repeat_disable;
// r = white paint, g = yellow paint, b = darkening (curbs, oil, cracks)
uniform sampler2D marks_map : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform vec2 map_size = vec2(480.0);

const vec3 SAND = vec3(0.62, 0.53, 0.41);
const vec3 DIRT = vec3(0.49, 0.41, 0.31);
const vec3 ROAD = vec3(0.22, 0.22, 0.23);
const vec3 PAVED = vec3(0.55, 0.52, 0.48);
const vec3 GRASS = vec3(0.30, 0.36, 0.17);
const vec3 FIELD = vec3(0.47, 0.44, 0.25);
const vec3 RUBBLE = vec3(0.52, 0.49, 0.45);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / map_size;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec4 w = texture(terrain_map, clamp(uv, vec2(0.0), vec2(1.0))) * inside;
	float n1 = texture(noise_a, wpos.xz * 0.0025).r;
	float n2 = texture(noise_b, wpos.xz * 0.035).r;
	float n3 = texture(noise_a, wpos.xz * 0.21).r;
	float n4 = texture(noise_b, wpos.xz * 0.9).r;

	vec3 base = mix(SAND, DIRT, smoothstep(0.38, 0.68, n1));
	base *= 0.88 + 0.22 * n2;
	base *= 0.94 + 0.12 * n4;
	// outside the city: drier, lighter desert
	float outside = 1.0 - inside;
	base = mix(base, SAND * (0.95 + 0.1 * n2), outside * 0.5);

	float veg = w.b;
	float grassy = smoothstep(0.65, 0.95, veg);
	float field = smoothstep(0.3, 0.5, veg) * (1.0 - grassy);
	float dirt = smoothstep(0.05, 0.15, veg) * (1.0 - smoothstep(0.2, 0.3, veg));
	base = mix(base, DIRT * (0.85 + 0.25 * n3), dirt * 0.6);
	float rows = 0.85 + 0.15 * sin(wpos.x * 1.6 + n2 * 2.0);
	base = mix(base, FIELD * rows * (0.85 + 0.3 * n3), field);
	base = mix(base, GRASS * (0.75 + 0.5 * n3) * (0.85 + 0.2 * n4), grassy * smoothstep(0.25, 0.55, n3 + 0.2));

	// paving tiles
	vec2 tile = fract(wpos.xz * 1.6);
	float grout = smoothstep(0.0, 0.06, tile.x) * smoothstep(0.0, 0.06, tile.y);
	vec3 paved = PAVED * (0.9 + 0.12 * n3) * (0.82 + 0.18 * grout);
	base = mix(base, paved, w.g);

	vec3 road = ROAD * (0.82 + 0.3 * n2) * (0.93 + 0.12 * n4);
	road = mix(road, road * 1.25, smoothstep(0.62, 0.8, n3) * 0.6);
	base = mix(base, road, w.r);

	vec3 rubble = RUBBLE * (0.6 + 0.6 * n4) * (0.85 + 0.25 * n3);
	base = mix(base, rubble, w.a);

	vec4 mk = texture(marks_map, clamp(uv, vec2(0.0), vec2(1.0))) * inside;
	float wear = smoothstep(0.25, 0.7, n3 + n4 * 0.4);
	base = mix(base, vec3(0.82, 0.82, 0.78), mk.r * w.r * wear);
	base = mix(base, vec3(0.78, 0.62, 0.18), mk.g * w.r * wear);
	base *= 1.0 - mk.b * 0.45;

	ALBEDO = base;
	ROUGHNESS = mix(0.96, 0.82, w.r) - mk.r * 0.1;
	SPECULAR = 0.35;
	// cheap micro-normal from noise
	float nx = texture(noise_b, wpos.xz * 0.9 + vec2(0.01, 0.0)).r - n4;
	float nz = texture(noise_b, wpos.xz * 0.9 + vec2(0.0, 0.01)).r - n4;
	NORMAL_MAP = normalize(vec3(-nx * 6.0 * (1.0 + w.a * 2.0), -nz * 6.0 * (1.0 + w.a * 2.0), 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
}

// Draw pass for smoke_particles: camera-facing puff, lit by the scene (sun, sky, omni flashes)
// with a rounded fake normal, noise-eroded billowy edge, soft depth fade and an
// incandescent "heat" glow that cools to dark smoke.
// INSTANCE_CUSTOM = (angle, life_fraction, seed, heat); COLOR = albedo + opacity.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled,
		shadows_disabled, skip_vertex_transform;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform float fx_time = 0.0;
uniform float softness = 0.35;

varying vec2 v_ofs;
varying float v_size;
varying vec4 v_custom;

void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	float ang = INSTANCE_CUSTOM.x;
	vec2 q = VERTEX.xy * 2.0;
	vec2 cs = vec2(cos(ang), sin(ang));
	vec2 r = vec2(q.x * cs.x - q.y * cs.y, q.x * cs.y + q.y * cs.x);
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	VERTEX = c + vec3(r * size * 0.5, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 1.0, 0.0);
	v_ofs = r;
	v_size = size;
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	float f = v_custom.y;
	float seed = v_custom.z;
	float heat = v_custom.w;
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;

	vec2 base = UV * 0.42 + vec2(seed * 7.31, seed * 3.17);
	float n1 = texture(noise_tex, base + vec2(f * 0.06, -f * 0.09)).r;
	float n2 = texture(noise_tex, base * 2.7 + vec2(-f * 0.21, fx_time * 0.004)).r;
	float n = n1 * 0.62 + n2 * 0.38;

	// Round puff with a billowy, eroding rim. Older puffs get thinner and more broken up.
	float shape = 1.0 - r * r;
	float dens = clamp((shape + (n - 0.5) * 1.5 - f * 0.3) * 1.5, 0.0, 1.0);
	dens *= 1.0 - smoothstep(0.82, 1.0, r);
	dens = dens * dens * (3.0 - 2.0 * dens);

	// Soft particles: fade where the puff intersects geometry, and near the camera.
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	sp.xyz /= sp.w;
	float soft = clamp((VERTEX.z - sp.z) / max(v_size * softness, 0.05), 0.0, 1.0);
	float near = smoothstep(0.6, 0.6 + v_size * 0.7, -VERTEX.z);

	vec3 nrm = normalize(vec3(v_ofs * 0.85 + (vec2(n1, n2) - 0.5) * 0.6, 0.55));
	NORMAL = nrm;
	// Fake self-shadowing: the underside of each puff is darker.
	float under = mix(0.62, 1.0, smoothstep(-0.9, 0.6, v_ofs.y + (n - 0.5) * 0.5));
	ALBEDO = COLOR.rgb * (0.78 + 0.4 * n) * under;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	BACKLIGHT = COLOR.rgb * 0.35;
	float core = smoothstep(0.15, 0.85, dens) * (1.0 - r * 0.6);
	vec3 hot = mix(vec3(1.0, 0.24, 0.04), vec3(1.0, 0.6, 0.24), clamp(heat * 0.15, 0.0, 1.0));
	// Glowing pockets inside the cloud rather than a uniformly lit blob.
	EMISSION = hot * heat * core * (smoothstep(0.35, 0.8, n) * 1.6 + 0.1);
	ALPHA = clamp(COLOR.a * dens * soft * near, 0.0, 1.0);
}

// Draw pass for glow_particles (additive, unshaded, HDR so it feeds the glow post effect).
// Stretched modes build an axis-aligned billboard from the particle basis (x = axis * length,
// y = width). Widths are clamped to ~1.5 px so tracers and sparks still read from 200 m,
// with brightness reduced accordingly.
// INSTANCE_CUSTOM = (angle, life_fraction, seed, mode * 4 + texture).
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled,
		skip_vertex_transform, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform float fx_time = 0.0;

varying vec2 v_q;
varying vec2 v_lw;
varying float v_bright;
varying vec4 v_custom;

void vertex() {
	int code = int(INSTANCE_CUSTOM.w + 0.5);
	int mode = code / 4;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 cv = (VIEW_MATRIX * vec4(center, 1.0)).xyz;
	vec2 q = VERTEX.xy * 2.0;
	float px = 2.0 * max(-cv.z, 0.05) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	v_q = q;
	if (mode == 0) {
		float s = length(MODEL_MATRIX[0].xyz);
		float se = max(s, px * 3.0);
		v_bright = mix(1.0, (s * s) / (se * se), 0.7);
		float ang = INSTANCE_CUSTOM.x;
		vec2 cs = vec2(cos(ang), sin(ang));
		vec2 r = vec2(q.x * cs.x - q.y * cs.y, q.x * cs.y + q.y * cs.x);
		VERTEX = cv + vec3(r * se * 0.5, 0.0);
		v_lw = vec2(se, se);
	} else {
		vec3 axis = MODEL_MATRIX[0].xyz;
		float len = length(axis);
		axis /= max(len, 0.00001);
		float w = length(MODEL_MATRIX[1].xyz);
		float we = max(w, px * 1.6);
		v_bright = mix(1.0, w / we, 0.65);
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
		vec3 side = cross(axis, to_cam);
		float sl = length(side);
		side = sl > 0.0001 ? side / sl : vec3(0.0, 1.0, 0.0);
		float ext = mode == 3 ? len : len + we;
		vec3 wp = center + axis * (q.x * 0.5 * ext) + side * (q.y * 0.5 * we);
		VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
		v_lw = vec2(len, we);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	int code = int(v_custom.w + 0.5);
	int mode = code / 4;
	int tex = code - mode * 4;
	float f = v_custom.y;
	float seed = v_custom.z;
	vec3 col = COLOR.rgb;
	float a = 0.0;
	if (mode == 0) {
		float r = length(UV - 0.5) * 2.0;
		if (tex == 1) {
			a = (exp(-r * r * 5.0) * 0.7 + exp(-r * r * 28.0) * 0.6) * (1.0 - smoothstep(0.7, 1.0, r));
		} else {
			vec2 nuv = UV * 0.55 + vec2(seed * 5.3, seed * 2.9 + fx_time * 0.35);
			float n = texture(noise_tex, nuv).r * 0.6 + texture(noise_tex, nuv * 2.3 + vec2(0.0, fx_time * 0.8)).r * 0.4;
			float m = clamp((1.0 - r) * 1.7 - (1.0 - n) * 1.25 - f * 0.35 + 0.25, 0.0, 1.0);
			float t = m * (1.0 - 0.45 * f);
			vec3 ramp = mix(vec3(0.75, 0.13, 0.02), vec3(1.0, 0.42, 0.07), smoothstep(0.0, 0.45, t));
			ramp = mix(ramp, vec3(1.0, 0.86, 0.55), smoothstep(0.55, 0.95, t));
			col *= ramp;
			a = m;
		}
	} else if (mode == 3) {
		// Muzzle flash seen from the side: hot ball at the muzzle, ragged forward plume
		// with a pinched "diamond" and noisy petals, cooling to orange at the tip.
		float t = (v_q.x + 1.0) * 0.5;
		float n = texture(noise_tex, vec2(t * 0.6 - seed * 3.0 - f * 0.4, v_q.y * 0.45 + seed * 7.0)).r;
		float diamond = 0.75 + 0.25 * cos(t * 9.0 + seed * 6.0);
		float wdt = (0.95 * pow(1.0 - t, 0.9) + 0.05) * diamond * (0.75 + 0.5 * n);
		float y = v_q.y / max(wdt, 0.02);
		float ball = exp(-((t - 0.08) * (t - 0.08) * 60.0 + v_q.y * v_q.y * 3.0));
		float plume = exp(-y * y * 2.6) * pow(1.0 - t, 1.1) * smoothstep(0.0, 0.05, t) * smoothstep(0.25, 0.75, n + 0.2 * (1.0 - t));
		a = clamp(plume * 0.85 + ball * 0.9, 0.0, 1.0);
		col *= mix(vec3(1.0, 0.78, 0.45), vec3(1.0, 0.38, 0.1), smoothstep(0.05, 0.7, t));
	} else {
		float lh = v_lw.x / (v_lw.x + v_lw.y);
		float along = max(abs(v_q.x) - lh, 0.0) / max(1.0 - lh, 0.001);
		float d2 = along * along + v_q.y * v_q.y;
		float edge = 1.0 - smoothstep(0.85, 1.0, sqrt(d2));
		if (mode == 2) {
			// Tracer: whitish-hot thin core inside a saturated glowing halo, brighter head.
			float core = exp(-d2 * 22.0);
			float halo = exp(-d2 * 3.5) * 0.45;
			float head = mix(0.3, 1.0, clamp((v_q.x + 1.0) * 0.5, 0.0, 1.0));
			col = (mix(col, vec3(max(col.r, max(col.g, col.b))), 0.3) * core * 1.6 + col * halo) * head;
			a = edge;
		} else {
			a = exp(-d2 * 4.5) * edge;
			col = mix(col, col * vec3(1.0, 0.45, 0.2), f);
		}
	}
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	sp.xyz /= sp.w;
	float soft = clamp((VERTEX.z - sp.z) / max(v_lw.y * 0.25, 0.03), 0.0, 1.0);
	ALBEDO = col * COLOR.a * v_bright;
	ALPHA = clamp(a * soft, 0.0, 1.0);
}

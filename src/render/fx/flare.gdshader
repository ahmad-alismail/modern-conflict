// Additive glow sprite for projectiles (shell slugs, rocket/missile motors). Round billboard,
// or a capsule stretched along the node's forward (-Z) axis when stretch_len > 0.
// Width is clamped to min_px pixels so it stays visible from far away.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled,
		skip_vertex_transform, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform float energy = 6.0;
uniform float stretch_len = 0.0;
uniform float width = 0.3;
uniform float min_px = 3.0;
uniform float flicker = 0.0;
uniform float fx_time = 0.0;

varying vec2 v_q;
varying float v_bright;
varying float v_lh;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 cv = (VIEW_MATRIX * vec4(center, 1.0)).xyz;
	float px = 2.0 * max(-cv.z, 0.05) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vec2 q = VERTEX.xy * 2.0;
	v_q = q;
	float we = max(width, px * min_px);
	v_bright = mix(1.0, width / we, 0.5);
	float h = center.x * 3.1 + center.z * 1.7;
	v_bright *= 1.0 - flicker * (0.5 + 0.5 * sin(fx_time * 53.0 + h) * sin(fx_time * 29.0 + h * 0.7));
	if (stretch_len > 0.0) {
		vec3 axis = normalize(-MODEL_MATRIX[2].xyz);
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
		vec3 side = cross(axis, to_cam);
		float sl = length(side);
		side = sl > 0.0001 ? side / sl : vec3(0.0, 1.0, 0.0);
		float ext = stretch_len + we;
		vec3 wp = center + axis * (q.x * 0.5 * ext) + side * (q.y * 0.5 * we);
		VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
		v_lh = stretch_len / ext;
	} else {
		VERTEX = cv + vec3(q * we * 0.5, 0.0);
		v_lh = 0.0;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float along = max(abs(v_q.x) - v_lh, 0.0) / max(1.0 - v_lh, 0.001);
	float d2 = along * along + v_q.y * v_q.y;
	float a = (exp(-d2 * 4.0) * 0.8 + exp(-d2 * 18.0) * 0.5) * (1.0 - smoothstep(0.8, 1.0, sqrt(d2)));
	ALBEDO = tint.rgb * energy * v_bright;
	ALPHA = clamp(a, 0.0, 1.0);
}

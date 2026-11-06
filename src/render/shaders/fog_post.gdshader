shader_type spatial;
// Full-screen fog-of-war pass: reconstructs the world position of every pixel from the
// depth buffer and multiplies the frame by the fog visibility at that position.
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(480.0);
uniform float texel = 0.0083;

float fog_at(vec2 uv) {
	vec2 c = clamp(uv, vec2(0.0), vec2(1.0));
	float s = texture(fog_tex, c).r * 0.4;
	s += texture(fog_tex, c + vec2(texel, 0.0) * 0.8).r * 0.15;
	s += texture(fog_tex, c - vec2(texel, 0.0) * 0.8).r * 0.15;
	s += texture(fog_tex, c + vec2(0.0, texel) * 0.8).r * 0.15;
	s += texture(fog_tex, c - vec2(0.0, texel) * 0.8).r * 0.15;
	return s;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	world.xyz /= world.w;
	vec2 uv = world.xz / map_size;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float f = mix(0.55, fog_at(uv), inside);
	// sky / far plane stays clear
	f = depth <= 0.00001 ? 1.0 : f;
	// gentle edge glow between explored and visible
	vec3 tint = mix(vec3(0.42, 0.46, 0.55), vec3(1.0), f);
	ALBEDO = tint * mix(0.35, 1.0, f);
}

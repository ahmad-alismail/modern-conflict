shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.07, 0.15, 0.17);
uniform vec3 shallow_color : source_color = vec3(0.18, 0.3, 0.28);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.06 + vec2(TIME * 0.012, TIME * 0.008);
	vec2 uv2 = wpos.xz * 0.11 - vec2(TIME * 0.01, -TIME * 0.015);
	float n1 = texture(noise_tex, uv1).r;
	float n2 = texture(noise_tex, uv2).r;
	float e = 0.004;
	float nx = texture(noise_tex, uv1 + vec2(e, 0.0)).r - n1 + texture(noise_tex, uv2 + vec2(e, 0.0)).r - n2;
	float nz = texture(noise_tex, uv1 + vec2(0.0, e)).r - n1 + texture(noise_tex, uv2 + vec2(0.0, e)).r - n2;
	NORMAL_MAP = normalize(vec3(-nx * 5.0, -nz * 5.0, 1.0)) * 0.5 + 0.5;
	ALBEDO = mix(deep_color, shallow_color, n1 * 0.6);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.3, 1.0, 0.4, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.78, 0.86, r) * (1.0 - smoothstep(0.93, 1.0, r));
	float fill = (1.0 - smoothstep(0.0, 0.86, r)) * 0.12;
	ALBEDO = color.rgb * 1.4;
	ALPHA = (ring + fill) * color.a;
}

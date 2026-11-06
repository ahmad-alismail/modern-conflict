shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.85, 0.85, 0.85, 1.0);
uniform vec4 progress_color : source_color = vec4(1.0);
uniform float progress = 0.0;
uniform float contested = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.x, -p.y) / 6.2831853 + 0.5;
	float edge = smoothstep(0.93, 0.955, r) * (1.0 - smoothstep(0.975, 1.0, r));
	float dash = step(0.5, fract(ang * 36.0 + TIME * 0.05));
	float prog_band = smoothstep(0.86, 0.875, r) * (1.0 - smoothstep(0.905, 0.92, r)) * step(ang, progress);
	float fill = (1.0 - smoothstep(0.0, 0.92, r)) * 0.07;
	vec3 col = mix(color.rgb, progress_color.rgb, prog_band);
	float pulse = contested * (0.5 + 0.5 * sin(TIME * 6.0));
	col = mix(col, vec3(1.0, 0.85, 0.2), pulse * edge);
	ALBEDO = col * 0.9;
	ALPHA = clamp(edge * (0.35 + 0.35 * dash) + prog_band * 0.75 + fill * 0.6, 0.0, 1.0);
}

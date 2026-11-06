shader_type canvas_item;

uniform sampler2D fog_tex : filter_linear;
uniform float fog_enabled = 1.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float f = mix(1.0, texture(fog_tex, UV).r, fog_enabled);
	COLOR = vec4(base.rgb * mix(0.3, 1.0, f), 1.0);
}

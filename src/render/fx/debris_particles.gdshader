// Tumbling debris chunks with gravity, ground bounce and friction (drawn as lit opaque rocks).
// Emission packing (see Effects.emit_debris):
//   origin = position, velocity = initial velocity, color = albedo
//   custom = (lifetime, size, ground_y, seed)
//   basis.x = (gravity, bounce, spin)
shader_type particles;
render_mode disable_force, disable_velocity, keep_data;

// USERDATA1 = (life, size, ground_y, seed)
// USERDATA2 = (gravity, bounce, spin, age)
// USERDATA3 = (rotation axis, angle)
// USERDATA4 = (shape scale xyz, -)

mat3 axis_angle(vec3 a, float ang) {
	float s = sin(ang);
	float c = cos(ang);
	float oc = 1.0 - c;
	return mat3(
			vec3(oc * a.x * a.x + c, oc * a.x * a.y + a.z * s, oc * a.z * a.x - a.y * s),
			vec3(oc * a.x * a.y - a.z * s, oc * a.y * a.y + c, oc * a.y * a.z + a.x * s),
			vec3(oc * a.z * a.x + a.y * s, oc * a.y * a.z - a.x * s, oc * a.z * a.z + c));
}

void start() {
	USERDATA1 = CUSTOM;
	USERDATA2 = vec4(TRANSFORM[0].xyz, 0.0);
	float s = CUSTOM.w;
	vec3 ax = vec3(fract(s * 12.9898) * 2.0 - 1.0, fract(s * 78.233) * 2.0 - 1.0, fract(s * 37.719) * 2.0 - 1.0);
	USERDATA3 = vec4(normalize(ax + vec3(0.001, 0.002, 0.0)), s * 6.2831853);
	USERDATA4 = vec4(mix(0.6, 1.4, fract(s * 91.7)), mix(0.35, 0.9, fract(s * 53.1)), mix(0.55, 1.3, fract(s * 17.3)), 0.0);
	vec3 p = TRANSFORM[3].xyz;
	TRANSFORM = mat4(vec4(0.0), vec4(0.0), vec4(0.0), vec4(p, 1.0));
}

void process() {
	float life = max(USERDATA1.x, 0.01);
	float age = USERDATA2.w + DELTA;
	USERDATA2.w = age;
	if (age >= life) {
		ACTIVE = false;
	}
	float size = USERDATA1.y;
	vec3 sc = USERDATA4.xyz * size;
	float rest_y = USERDATA1.z + sc.y * 0.4;
	vec3 p = TRANSFORM[3].xyz;
	VELOCITY.y -= USERDATA2.x * DELTA;
	VELOCITY *= exp(-0.12 * DELTA);
	p += VELOCITY * DELTA;
	if (p.y <= rest_y) {
		p.y = rest_y;
		if (VELOCITY.y < -1.8) {
			VELOCITY.y = -VELOCITY.y * USERDATA2.y;
			VELOCITY.xz *= 0.55;
			USERDATA2.z *= 0.6;
		} else {
			VELOCITY.y = 0.0;
			float fr = exp(-7.0 * DELTA);
			VELOCITY.xz *= fr;
			USERDATA2.z *= fr;
		}
	}
	USERDATA3.w += USERDATA2.z * DELTA;
	float f = age / life;
	float shrink = 1.0 - smoothstep(0.82, 1.0, f);
	mat3 rot = axis_angle(USERDATA3.xyz, USERDATA3.w);
	sc *= shrink;
	TRANSFORM = mat4(vec4(rot[0] * sc.x, 0.0), vec4(rot[1] * sc.y, 0.0), vec4(rot[2] * sc.z, 0.0), vec4(p, 1.0));
}

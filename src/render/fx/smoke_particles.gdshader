// Lit smoke / dust puffs, emitted one by one from script via GPUParticles3D.emit_particle().
// Emission packing (see Effects.emit_smoke):
//   origin = position, velocity = initial velocity, color = albedo rgb + peak opacity
//   custom = (lifetime, size0, size1, seed)
//   basis.x = (drag, buoyancy, wind_factor)
//   basis.y = (heat, heat_time, fade_in)
//   basis.z = (spin, ground_y, fade_out_start)
shader_type particles;
render_mode disable_force, disable_velocity, keep_data;

uniform vec3 wind = vec3(2.4, 0.0, 1.0);
uniform float fx_time = 0.0;

// USERDATA1 = (life, size0, size1, seed)
// USERDATA2 = (drag, buoyancy, wind_factor, spin)
// USERDATA3 = (heat, heat_time, fade_in, fade_out_start)
// USERDATA4 = (age, angle, alpha0, ground_y)

void start() {
	USERDATA1 = CUSTOM;
	USERDATA2 = vec4(TRANSFORM[0].xyz, TRANSFORM[2].x);
	USERDATA3 = vec4(TRANSFORM[1].xyz, TRANSFORM[2].z);
	USERDATA4 = vec4(0.0, CUSTOM.w * 6.2831853, COLOR.a, TRANSFORM[2].y);
	vec3 p = TRANSFORM[3].xyz;
	float s = CUSTOM.y;
	TRANSFORM = mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(p, 1.0));
	COLOR.a = 0.0;
}

void process() {
	float life = max(USERDATA1.x, 0.01);
	float age = USERDATA4.x + DELTA;
	USERDATA4.x = age;
	if (age >= life) {
		ACTIVE = false;
	}
	float f = clamp(age / life, 0.0, 1.0);
	float seed = USERDATA1.w;
	vec3 p = TRANSFORM[3].xyz;
	float ground = USERDATA4.w;

	// Wind grows with height (shear), smoke relaxes toward it with its drag.
	float h = max(p.y - ground, 0.0);
	vec3 w = wind * USERDATA2.z * clamp(0.45 + h * 0.035, 0.45, 1.9);
	float k = 1.0 - exp(-USERDATA2.x * DELTA);
	VELOCITY.xz += (w.xz - VELOCITY.xz) * k;
	VELOCITY.y += -VELOCITY.y * k + USERDATA2.y * DELTA;

	// Cheap large-scale turbulence so columns meander instead of rising as a stick.
	float tt = fx_time * 0.55 + seed * 41.0;
	vec3 turb = vec3(sin(p.y * 0.19 + tt) + sin(p.z * 0.11 + tt * 1.31),
			0.35 * sin(p.x * 0.15 + tt * 0.77),
			cos(p.x * 0.17 - tt * 0.9) + cos(p.y * 0.13 + tt * 0.63));
	VELOCITY += turb * (0.45 * DELTA) * (0.3 + USERDATA2.z);
	p += VELOCITY * DELTA;

	float grow = 1.0 - pow(1.0 - f, 2.4);
	float size = mix(USERDATA1.y, USERDATA1.z, grow);
	float floor_y = ground + size * 0.2;
	if (p.y < floor_y) {
		p.y = floor_y;
		VELOCITY.y = max(VELOCITY.y, 0.0);
	}

	USERDATA4.y += USERDATA2.w * DELTA * (1.0 - 0.7 * f);
	float a = USERDATA4.z * smoothstep(0.0, max(USERDATA3.z, 0.001), f)
			* (1.0 - smoothstep(USERDATA3.w, 1.0, f));
	float heat = USERDATA3.x * exp(-age / max(USERDATA3.y, 0.001));

	TRANSFORM = mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(p, 1.0));
	COLOR.a = a;
	CUSTOM = vec4(USERDATA4.y, f, seed, heat);
}

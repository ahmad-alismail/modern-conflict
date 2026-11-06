// Additive glowing particles: flames, fireballs, flashes, muzzle flashes, sparks and tracers.
// Emission packing (see Effects.emit_glow):
//   origin = position, velocity = initial velocity, color = HDR rgb + intensity
//   custom = (lifetime, size0, size1, mode + seed * 0.98)
//   basis.x = (gravity, drag, stretch)        stretch: s of motion blur (sparks) or length/width (muzzle)
//   basis.y = (buoyancy, flicker, texture)    texture: 0 flame, 1 flash/round glow
//   basis.z = mode extra: muzzle axis | tracer (distance, streak length, -) | sparks (-, ground_y, -)
// Modes: 0 billboard, 1 velocity-stretched spark, 2 tracer, 3 fixed-axis muzzle flash.
shader_type particles;
render_mode disable_force, disable_velocity, keep_data;

// USERDATA1 = (life, size0, size1, mode)
// USERDATA2 = (gravity, drag, stretch, buoyancy)
// USERDATA3 = mode extra
// USERDATA4 = (age, intensity, seed, flicker)
// USERDATA5 = (start position, texture)

void start() {
	float mode = floor(CUSTOM.w);
	USERDATA1 = vec4(CUSTOM.xyz, mode);
	USERDATA2 = vec4(TRANSFORM[0].xyz, TRANSFORM[1].x);
	USERDATA3 = vec4(TRANSFORM[2].xyz, 0.0);
	USERDATA4 = vec4(0.0, COLOR.a, fract(CUSTOM.w), TRANSFORM[1].y);
	USERDATA5 = vec4(TRANSFORM[3].xyz, TRANSFORM[1].z);
	vec3 p = TRANSFORM[3].xyz;
	float s = CUSTOM.y;
	TRANSFORM = mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(p, 1.0));
	COLOR.a = 0.0;
}

void process() {
	float life = max(USERDATA1.x, 0.001);
	float age = USERDATA4.x + DELTA;
	USERDATA4.x = age;
	if (age >= life) {
		ACTIVE = false;
	}
	float f = clamp(age / life, 0.0, 1.0);
	int mode = int(USERDATA1.w + 0.5);
	int tex = int(USERDATA5.w + 0.5);
	float seed = USERDATA4.z;
	float size = mix(USERDATA1.y, USERDATA1.z, f);
	float inten = USERDATA4.y;
	vec3 p = TRANSFORM[3].xyz;
	vec3 axis = vec3(1.0, 0.0, 0.0);
	float len = size;

	if (mode == 2) {
		// Tracer: exact position along the path, streak clipped to [start, end].
		float dist = USERDATA3.x;
		float speed = length(VELOCITY);
		vec3 dir = VELOCITY / max(speed, 0.001);
		float head = min(age * speed, dist);
		float tail = max(head - USERDATA3.y, 0.0);
		p = USERDATA5.xyz + dir * ((head + tail) * 0.5);
		axis = dir;
		len = max(head - tail, 0.05);
	} else {
		VELOCITY.y += (USERDATA2.w - USERDATA2.x) * DELTA;
		VELOCITY *= exp(-USERDATA2.y * DELTA);
		p += VELOCITY * DELTA;
		if (mode == 1) {
			float gy = USERDATA3.y;
			if (p.y < gy && VELOCITY.y < 0.0) {
				p.y = gy;
				VELOCITY.y = -VELOCITY.y * 0.35;
				VELOCITY.xz *= 0.6;
			}
			float sp = length(VELOCITY);
			axis = sp > 0.001 ? VELOCITY / sp : vec3(0.0, 1.0, 0.0);
			len = max(sp * USERDATA2.z, size);
		} else if (mode == 3) {
			axis = normalize(USERDATA3.xyz + vec3(0.0, 0.00001, 0.0));
			len = size * USERDATA2.z;
			p = USERDATA5.xyz + axis * len * 0.42;
		}
	}

	// Intensity envelopes per mode.
	if (mode == 0) {
		if (tex == 1) {
			inten *= (1.0 - f) * (1.0 - f);
		} else {
			inten *= smoothstep(0.0, 0.12, f) * (1.0 - f);
		}
	} else if (mode == 1) {
		inten *= pow(1.0 - f, 0.8);
	} else if (mode == 3) {
		inten *= pow(1.0 - f, 1.4);
	}
	float fl = USERDATA4.w;
	if (fl > 0.0) {
		inten *= 1.0 - fl * (0.5 + 0.5 * sin(age * 31.0 + seed * 90.0) * sin(age * 17.0 + seed * 40.0));
	}

	if (mode == 0) {
		TRANSFORM = mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(p, 1.0));
	} else {
		// Stretched: basis.x = axis * length, basis.y = width.
		float wdt = mode == 3 ? size * 0.55 : size;
		TRANSFORM = mat4(vec4(axis * len, 0.0), vec4(0.0, wdt, 0.0, 0.0), vec4(0.0, 0.0, wdt, 0.0), vec4(p, 1.0));
	}
	COLOR.a = inten;
	CUSTOM = vec4(seed * 6.2831853 + age * (seed - 0.5) * 2.0, f, seed, float(mode * 4 + tex));
}

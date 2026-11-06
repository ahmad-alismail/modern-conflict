// Environment uber-shader: one material for every building, wall and prop.
// Vertex color RGB = sRGB tint, alpha = surface type code (EnvGeo.c()): id 0-15 + 16 * flag.
// Patterns are procedural in model space (meters), so meshes need no UVs or tangents;
// bump is derived from screen-space derivatives and faded out where it would alias.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_a : filter_linear_mipmap_anisotropic, repeat_enable;  // seamless fbm
uniform sampler2D noise_b : filter_linear_mipmap_anisotropic, repeat_enable;  // seamless cellular
uniform bool props_mode = false;   // flag bit = apply INSTANCE_CUSTOM.rgb tint
uniform float weathering = 1.0;
uniform float night_lights = 0.0;  // 0 by day, ~1 at night: lit windows and lamps
instance uniform float scorch = 0.0;

varying vec3 v_mp;
varying vec3 v_mn;
varying vec3 v_wp;
varying vec4 v_inst;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float tri_b(vec3 p, vec3 w, float s, vec2 o) {
	return texture(noise_b, p.zy * s + o).r * w.x + texture(noise_b, p.xz * s + o).r * w.y
		+ texture(noise_b, p.xy * s + o).r * w.z;
}

void vertex() {
	v_mp = VERTEX;
	v_mn = NORMAL;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_inst = props_mode ? INSTANCE_CUSTOM : vec4(1.0, 1.0, 1.0, 0.5);
}

void fragment() {
	int code = int(COLOR.a * 31.0 + 0.5);
	int id = code % 16;
	bool flag = code >= 16;
	vec3 base = to_lin(clamp(COLOR.rgb, 0.0, 1.0));
	if (props_mode && flag) {
		base *= to_lin(v_inst.rgb);
	}
	vec3 n = normalize(v_mn);
	vec3 p = v_mp;
	vec2 ofs = fract(MODEL_MATRIX[3].xz * 0.0173) * 57.0;
	bool horiz = abs(n.y) > 0.7;
	vec2 fc;
	if (horiz) {
		fc = p.xz;
	} else if (abs(n.x) > abs(n.z)) {
		fc = vec2(-p.z * sign(n.x), p.y);
	} else {
		fc = vec2(p.x * sign(n.z), p.y);
	}
	vec2 nc = fc + ofs;
	float nA = texture(noise_a, nc * 0.045).r;
	float nM = texture(noise_a, nc * 0.21).r;
	float nF = texture(noise_a, nc * 1.1).r;
	float fw = max(fwidth(fc.x), fwidth(fc.y)) + 1e-5;   // meters per pixel
	vec3 alb = base;
	float rough = 0.9;
	float metal = 0.0;
	float h = 0.0;
	float bump = 0.0;
	bool masonry = false;
	vec3 back = vec3(0.0);

	if (id == 0) {            // PLASTER (flag: old, patchy)
		masonry = true;
		alb *= 0.9 + 0.2 * nM;
		alb *= 0.94 + 0.12 * nF;
		h = nF * 0.004;
		bump = 1.0 - smoothstep(0.02, 0.08, fw);
		if (flag && !props_mode) {
			float pt = smoothstep(0.6, 0.64, nM * 0.65 + texture(noise_b, nc * 0.4).r * 0.45);
			alb = mix(alb, alb * vec3(0.8, 0.76, 0.7), pt);
			h -= pt * 0.006;
		}
		rough = 0.93;
	} else if (id == 1) {     // STONE ashlar
		masonry = true;
		float course = 0.32;
		float row = floor(fc.y / course);
		float bw = 0.5 + 0.35 * hash12(vec2(row, 7.31));
		float u = fc.x + hash12(vec2(row, 3.17)) * 3.0 + ofs.x;
		float colm = floor(u / bw);
		vec2 f = vec2(fract(u / bw) * bw, fract(fc.y / course) * course);
		float edge = min(min(f.x, bw - f.x), min(f.y, course - f.y));
		float fj = 1.0 - smoothstep(0.012, 0.035, fw);
		float fb = 1.0 - smoothstep(0.08, 0.25, fw);
		float joint = (1.0 - smoothstep(0.006, 0.02, edge)) * fj;
		float bh = hash12(vec2(colm, row) + floor(ofs * 10.0));
		alb *= mix(1.0, 0.92 + 0.15 * bh, fb);
		alb *= 0.93 + 0.14 * nF;
		alb = mix(alb, alb * 0.78, joint);
		alb *= 1.0 - 0.06 * (1.0 - fj) * fb;
		h = smoothstep(0.0, 0.02, edge) * 0.008 + nF * 0.003;
		bump = fj;
		rough = 0.9;
	} else if (id == 2) {     // CONCRETE (flag: hollow-block masonry)
		masonry = true;
		alb *= 0.84 + 0.3 * nM;
		alb *= 0.92 + 0.16 * nF;
		float fade = 1.0 - smoothstep(0.02, 0.07, fw);
		if (flag && !props_mode) {
			float row = floor(fc.y / 0.2);
			float u = fc.x + mod(row, 2.0) * 0.2;
			vec2 f = vec2(fract(u / 0.4) * 0.4, fract(fc.y / 0.2) * 0.2);
			float edge = min(min(f.x, 0.4 - f.x), min(f.y, 0.2 - f.y));
			float joint = (1.0 - smoothstep(0.005, 0.014, edge)) * fade;
			alb *= 0.9 + 0.2 * hash12(vec2(floor(u / 0.4), row));
			alb = mix(alb, alb * 0.72, joint);
			h = smoothstep(0.0, 0.015, edge) * 0.006;
		} else {
			float ly = abs(fract(fc.y / 0.6) - 0.5);
			alb *= 1.0 - 0.12 * smoothstep(0.46, 0.5, ly) * fade;
			h = nF * 0.006;
		}
		bump = fade;
		rough = 0.95;
	} else if (id == 3) {     // CORRUGATED metal (flag: ribs along the other axis)
		float axis = (flag && !props_mode) ? fc.y : fc.x;
		float P = 0.19;
		float fade = 1.0 - smoothstep(0.03, 0.1, fw);
		float s = sin(axis * 6.2832 / P);
		h = s * 0.014;
		bump = fade;
		alb *= 1.0 + 0.1 * s * fade;
		alb *= 0.86 + 0.26 * nM;
		float low = 1.0 - smoothstep(0.0, 2.2, v_wp.y);
		float rs = texture(noise_a, vec2(nc.x * 0.7, nc.y * 0.12) + 0.4).r;
		float rr = smoothstep(0.6, 0.9, nM * 0.55 + rs * 0.45 + low * 0.25);
		alb = mix(alb, vec3(0.16, 0.075, 0.035), rr * 0.75);
		metal = mix(0.45, 0.05, rr);
		rough = mix(0.5, 0.92, rr);
	} else if (id == 4) {     // SHUTTER (roll-down slats)
		float P = 0.095;
		float fade = 1.0 - smoothstep(0.015, 0.05, fw);
		float s = fract(fc.y / P);
		h = smoothstep(0.0, 0.25, s) * smoothstep(1.0, 0.75, s) * 0.01;
		bump = fade;
		alb *= 0.82 + 0.3 * nM;
		alb *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.18, s)) * fade;
		float rr = smoothstep(0.72, 0.92, texture(noise_b, nc * 0.8).r);
		alb = mix(alb, vec3(0.16, 0.07, 0.03), rr * 0.55);
		metal = 0.3;
		rough = 0.6;
	} else if (id == 5) {     // GLASS (flag: curtain wall with mullions and spandrels)
		alb = base * (0.8 + 0.4 * nM);
		rough = 0.06;
		metal = 0.6;
		if (flag && !props_mode) {
			float fade = 1.0 - smoothstep(0.05, 0.2, fw);
			float dm = abs(fract(fc.x / 1.5 + 0.5) - 0.5) * 1.5;
			float yy = fract(fc.y / 3.2) * 3.2;
			float span = 1.0 - step(0.85, yy);
			float line = max(1.0 - smoothstep(0.03, 0.05, dm), 1.0 - smoothstep(0.025, 0.045, abs(yy - 0.85)));
			alb = mix(alb, base * 0.45 + vec3(0.03, 0.032, 0.035), span);
			rough = mix(rough, 0.3, span);
			alb = mix(alb, vec3(0.05, 0.055, 0.06), line * fade);
			metal = mix(metal, 0.8, line * fade);
			rough = mix(rough, 0.35, line * fade);
		}
	} else if (id == 6) {     // VOID (interiors, rubber, soot): plain rough
		alb = base * (0.85 + 0.3 * nM);
		rough = 0.96;
	} else if (id == 7) {     // METAL (painted)
		alb *= 0.9 + 0.2 * nM;
		float rr = smoothstep(0.8, 0.96, texture(noise_b, nc * 0.9).r);
		alb = mix(alb, vec3(0.18, 0.07, 0.03), rr * 0.5);
		metal = 0.35;
		rough = mix(0.4, 0.8, rr);
	} else if (id == 8) {     // WOOD planks
		float g = texture(noise_a, vec2(nc.x * 3.0, nc.y * 0.25)).r;
		alb *= 0.72 + 0.45 * g;
		float fade = 1.0 - smoothstep(0.02, 0.05, fw);
		float pl = smoothstep(0.44, 0.5, abs(fract(fc.x / 0.14) - 0.5)) * fade;
		alb *= 1.0 - 0.3 * pl;
		h = g * 0.004 - pl * 0.004;
		bump = fade;
		rough = 0.85;
	} else if (id == 9) {     // FABRIC (striped awnings, cloth)
		float fade = 1.0 - smoothstep(0.08, 0.25, fw);
		float st = step(0.5, fract(fc.x / 0.5));
		alb = mix(alb, mix(alb, vec3(0.75, 0.73, 0.68), 0.85), st * 0.8 * fade + 0.4 * (1.0 - fade));
		alb *= 0.82 + 0.3 * nM;
		rough = 0.95;
	} else if (id == 10) {    // RUBBLE
		vec3 w = abs(n);
		w /= (w.x + w.y + w.z);
		float cb = tri_b(p, w, 1.6, ofs);
		float cb2 = tri_b(p, w, 4.1, ofs + 0.37);
		alb *= 0.58 + 0.55 * cb + 0.3 * (cb2 - 0.5);
		alb *= 0.85 + 0.3 * nM;
		h = cb * 0.05 + cb2 * 0.02;
		bump = 1.0 - smoothstep(0.05, 0.2, fw);
		rough = 1.0;
	} else if (id == 11) {    // FOLIAGE
		vec3 w = abs(n);
		w /= (w.x + w.y + w.z);
		float l = tri_b(p, w, 2.4, ofs);
		float l2 = tri_b(p, w, 0.55, ofs + 0.5);
		alb *= 0.4 + 0.8 * l * (0.65 + 0.7 * l2);
		if (props_mode) {
			alb *= mix(vec3(0.85, 1.0, 0.8), vec3(1.15, 0.95, 1.1), v_inst.a);
		}
		h = l * 0.06;
		bump = 1.0 - smoothstep(0.04, 0.15, fw);
		back = alb * 0.4;
		rough = 0.82;
	} else if (id == 12) {    // RUST / burned metal
		float t = props_mode ? v_inst.a : 0.5;
		float r1 = nM * 0.7 + texture(noise_b, nc * 0.7).r * 0.5;
		alb = mix(vec3(0.022, 0.02, 0.018), vec3(0.2, 0.07, 0.024), smoothstep(0.35, 0.8, r1 + (t - 0.5) * 0.6));
		float rem = smoothstep(0.6, 0.68, nF * 0.45 + nA * 0.6) * (1.0 - t);
		alb = mix(alb, base * 0.6, rem);
		alb = mix(alb, base * 0.5, 0.25);
		h = r1 * 0.006;
		bump = 1.0;
		metal = 0.2;
		rough = 0.95;
	} else if (id == 13) {    // ROOF membrane / screed (flag: tiled)
		alb *= 0.82 + 0.32 * nA;
		alb *= 0.9 + 0.2 * nF;
		alb = mix(alb, alb * 0.76, smoothstep(0.55, 0.8, nM) * 0.45);
		if (flag && !props_mode) {
			float fade = 1.0 - smoothstep(0.02, 0.06, fw);
			vec2 g = abs(fract(fc / 0.5) - 0.5);
			alb *= 1.0 - 0.12 * smoothstep(0.46, 0.5, max(g.x, g.y)) * fade;
		}
		rough = 0.96;
	} else if (id == 14) {    // BARK (palm rings, trunks)
		float fade = 1.0 - smoothstep(0.03, 0.1, fw);
		float s = fract(fc.y / 0.18 + nF * 0.3);
		h = smoothstep(0.0, 0.35, s) * 0.025;
		bump = fade;
		alb *= 0.7 + 0.35 * mix(0.6, s, fade) * (0.8 + 0.4 * nF);
		rough = 1.0;
	} else {                  // MESH: wire grid (flag in buildings: wooden lattice)
		float fade = 1.0 - smoothstep(0.012, 0.04, fw);
		vec2 g = abs(fract(fc / 0.1) - 0.5);
		if (flag && !props_mode) {
			float hole = 1.0 - smoothstep(0.24, 0.31, max(g.x, g.y));
			alb = mix(alb, vec3(0.012), hole * fade + 0.45 * (1.0 - fade));
		} else {
			float wire = smoothstep(0.44, 0.48, max(g.x, g.y));
			alb = mix(alb, vec3(0.1, 0.1, 0.095), wire * fade * 0.65 + 0.06 * (1.0 - fade));
			alb *= 0.88 + 0.24 * nM;
			metal = wire * fade * 0.4;
		}
		rough = 0.9;
	}

	if (masonry && !props_mode) {
		float g = 1.0 - smoothstep(0.0, 1.2 + nM * 0.9, v_wp.y);
		alb = mix(alb, alb * vec3(0.64, 0.58, 0.5), g * 0.7 * weathering);
		if (!horiz) {
			float st = texture(noise_a, vec2(nc.x * 0.45, nc.y * 0.03)).r;
			float patchy = smoothstep(0.35, 0.75, texture(noise_a, nc * 0.08 + 0.3).r);
			alb *= 1.0 - 0.17 * smoothstep(0.52, 0.8, st) * patchy * weathering;
			alb *= 0.9 + 0.2 * nA;
		} else {
			alb = mix(alb, alb * vec3(0.78, 0.74, 0.68), smoothstep(0.4, 0.8, nM) * 0.5);
		}
	}
	if (scorch > 0.0) {
		float sv = texture(noise_a, vec2(nc.x * 0.12, nc.y * 0.035) + 0.7).r;
		float sc = smoothstep(0.6, 0.85, sv * 0.65 + nA * 0.45 + texture(noise_b, nc * 0.05).r * 0.2) * scorch;
		sc *= horiz ? 0.45 : 1.0;
		alb = mix(alb, alb * 0.15 + vec3(0.008), sc * 0.85);
		rough = mix(rough, 1.0, sc);
		metal *= 1.0 - sc;
	}

	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	if (bump > 0.001) {
		vec3 N = normalize(NORMAL);
		vec3 r1 = cross(dpdy, N);
		vec3 r2 = cross(N, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dhx * r1 + dhy * r2) * bump;
		NORMAL = normalize(abs(det) * N - grad);
	}
	vec3 emit = vec3(0.0);
	if (night_lights > 0.001 && id == 5) {
		if (props_mode) {
			if (base.r > 0.6 && base.b < 0.5) {
				emit = vec3(1.0, 0.78, 0.48) * 6.0;
			}
		} else {
			float cw = flag ? 1.5 : 1.3;
			vec2 cell = floor(vec2(fc.x / cw, fc.y / 3.2)) + floor(ofs);
			float hl = hash12(cell * 1.37 + 0.5);
			bool span = flag && fract(fc.y / 3.2) * 3.2 < 0.85;
			if (hl < 0.2 && !span) {
				vec3 lc = hl < 0.13 ? vec3(1.0, 0.7, 0.4) : vec3(0.75, 0.85, 1.0);
				emit = lc * (1.2 + 2.0 * fract(hl * 37.0));
			}
		}
		emit *= night_lights;
	}
	EMISSION = emit;
	ALBEDO = clamp(alb, 0.0, 1.0);
	ROUGHNESS = rough;
	METALLIC = metal;
	BACKLIGHT = back;
}

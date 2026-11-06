extends RefCounted
## Shared shaders + materials for all unit models (built once, cached statically).
##
## One opaque "uber" fragment serves soldiers, robots and vehicles: the material
## code in UV2.x selects roughness / metalness / procedural pattern, so a whole
## soldier or vehicle part is a single surface (one draw call).
##
## Vertex stages:
##  - soldier: procedural skeleton evaluated on the GPU. Rigid parts carry a bone id
##    (UV2.y); key poses live in a uniform array, the CPU only sends blend weights,
##    gait phase and a clock per member (2 instance uniforms per frame).
##  - hound:   quadruped robot with analytic two-bone leg IK and a trot gait.
##  - vehicle: wheel roll, rotor spin and barrel recoil per vertex (UV2.y = mode,
##    CUSTOM0 = pivot + parameter), so wheels/rotors need no extra nodes.
class_name UnitShaders

# --- material codes (UV2.x) ---------------------------------------------------
const M_CLOTH := 0
const M_CAMO := 1
const M_SKIN := 2
const M_WEAPON := 3
const M_EMIT := 4
const M_TEAM := 5
const M_CHECKER := 6
const M_GLASS := 7
const M_GEAR := 8
const M_PAINT := 9
const M_RUBBER := 10
const M_TRACK := 11
const M_CANVAS := 12
const M_CHAR := 13
const M_METAL := 14
const M_VCAMO := 15
const M_HAIR := 16
const M_RUST := 17

# --- vehicle vertex animation modes (UV2.y) ------------------------------------
const A_NONE := 0
const A_ROLL := 1      # wheel: rotate about Z through pivot by -roll / radius (CUSTOM0.w = radius)
const A_SPIN_Y := 2    # rotor/prop about Y (CUSTOM0.w = rate multiplier, sign = direction)
const A_SPIN_X := 3
const A_SPIN_Z := 4
const A_RECOIL := 5    # barrel: slide along -X by recoil[slot] * stroke (CUSTOM0.w = slot + stroke/2)

static var _soldier_mat: ShaderMaterial
static var _hound_mat: ShaderMaterial
static var _vehicle_mat: ShaderMaterial
static var _disc_mat: ShaderMaterial

const COMMON := """
mat3 rx(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c)); }
mat3 ry(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c)); }
mat3 rz(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0)); }
// pitch > 0 leans forward (toward +X), yaw > 0 turns left (toward -Z), roll > 0 leans right (+Z)
mat3 body_rot(vec3 e) { return ry(e.y) * rz(-e.x) * rx(e.z); }

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(i);
	float b = hash13(i + vec3(1.0, 0.0, 0.0));
	float c = hash13(i + vec3(0.0, 1.0, 0.0));
	float d = hash13(i + vec3(1.0, 1.0, 0.0));
	float e = hash13(i + vec3(0.0, 0.0, 1.0));
	float g = hash13(i + vec3(1.0, 0.0, 1.0));
	float h = hash13(i + vec3(0.0, 1.0, 1.0));
	float k = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

// Two-bone IK. Segments hang along local -Y in rest pose and flex toward local +X.
// Returns upper/lower bases (columns = local axes in parent space) and the joint position.
void ik2(vec3 S, vec3 H, vec3 pole, float a, float b, out mat3 Ru, out mat3 Rf, out vec3 JNT) {
	vec3 d = H - S;
	float L = length(d);
	vec3 dir = L > 0.0001 ? d / L : vec3(0.0, -1.0, 0.0);
	L = clamp(L, 0.05, a + b - 0.002);
	float ca = clamp((a * a + L * L - b * b) / (2.0 * a * L), -1.0, 1.0);
	float sa = sqrt(max(0.0, 1.0 - ca * ca));
	vec3 pn = pole - dot(pole, dir) * dir;
	pn = dot(pn, pn) > 0.000001 ? normalize(pn) : normalize(cross(dir, vec3(0.0, 0.0, 1.0)) + vec3(0.0001));
	JNT = S + dir * (a * ca) + pn * (a * sa);
	vec3 Hc = S + dir * L;
	vec3 uy = normalize(S - JNT);
	vec3 ux = normalize(-pn - dot(-pn, uy) * uy);
	vec3 uz = cross(ux, uy);
	Ru = mat3(ux, uy, uz);
	vec3 fy = normalize(JNT - Hc);
	Rf = mat3(cross(fy, uz), fy, uz);
}
"""

const SHADE := """
varying vec3 v_rest;
varying flat float v_code;

vec3 debug_hue(float b) {
	return 0.5 + 0.5 * cos(6.2831 * (b * 0.137 + vec3(0.0, 0.33, 0.67)));
}

void shade(int code, vec3 col, float dirt, vec3 rp, vec2 uv, vec3 team, float roll,
		out vec3 alb, out float rough, out float metal, out vec3 emit) {
	float n1 = vnoise(rp * 9.0);
	float n2 = vnoise(rp * 2.3 + 7.0);
	alb = col;
	rough = 0.85;
	metal = 0.0;
	emit = vec3(0.0);
	if (code == 0) {
		alb *= 0.86 + 0.26 * n1;
		rough = 0.95;
	} else if (code == 1) {
		float a = smoothstep(0.5, 0.54, vnoise(rp * 7.0 + 3.1));
		float b = smoothstep(0.52, 0.56, vnoise(rp * 11.0 + 17.0));
		float c = smoothstep(0.58, 0.62, vnoise(rp * 15.0 + 41.0));
		alb = mix(col, col * vec3(0.52, 0.46, 0.36), a);
		alb = mix(alb, col * vec3(0.78, 0.80, 0.62), b * (1.0 - a));
		alb = mix(alb, col * vec3(1.18, 1.14, 1.02), c * (1.0 - a));
		alb *= 0.92 + 0.14 * n1;
		rough = 0.95;
	} else if (code == 2) {
		alb *= 0.92 + 0.12 * n1;
		rough = 0.55;
	} else if (code == 3) {
		alb *= 0.88 + 0.22 * n1;
		rough = 0.42;
		metal = 0.3;
	} else if (code == 4) {
		emit = col * 7.0;
		rough = 0.3;
	} else if (code == 5) {
		alb = team;
		emit = team * 0.35;
		rough = 0.6;
	} else if (code == 6) {
		vec3 q = floor(rp * 55.0);
		float ch = mod(q.x + q.y + q.z, 2.0);
		float ln = step(0.8, fract(rp.y * 18.0));
		alb = mix(vec3(0.74, 0.72, 0.66), col, max(ch * 0.75, ln)) * (0.88 + 0.22 * n1);
		rough = 0.97;
	} else if (code == 7) {
		rough = 0.07;
		metal = 0.6;
	} else if (code == 8) {
		alb *= 0.88 + 0.22 * n1;
		rough = 0.9;
	} else if (code == 9) {
		alb *= 0.9 + 0.12 * n2 + 0.06 * n1;
		rough = 0.6;
		metal = 0.05;
	} else if (code == 10) {
		float tr = step(0.5, fract(uv.x * 7.0));
		alb *= 0.8 + 0.3 * tr;
		rough = 0.93;
	} else if (code == 11) {
		float f = fract((uv.x + roll) / 0.16);
		float gr = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.32, 0.4, f));
		alb = mix(col * 0.45, col * 1.3, gr) * (0.85 + 0.3 * n1);
		rough = 0.55;
		metal = 0.55;
	} else if (code == 12) {
		alb *= 0.82 + 0.22 * n1 + 0.12 * n2;
		rough = 1.0;
	} else if (code == 13) {
		float r = smoothstep(0.5, 0.95, vnoise(rp * vec3(3.0, 1.2, 3.0) + 11.0) * 0.75 + n1 * 0.25);
		float ash = smoothstep(0.62, 0.9, vnoise(rp * 13.0) * 0.6 + n2 * 0.4);
		alb = mix(vec3(0.025, 0.023, 0.022), vec3(0.085, 0.045, 0.028), r);
		alb = mix(alb, vec3(0.16, 0.155, 0.15), ash * 0.5);
		alb *= 0.75 + 0.5 * n1;
		rough = 0.96;
	} else if (code == 14) {
		alb *= 0.9 + 0.15 * n1;
		rough = 0.35;
		metal = 0.85;
	} else if (code == 15) {
		float a = smoothstep(0.5, 0.56, vnoise(rp * 0.9 + 5.0));
		float b = smoothstep(0.55, 0.6, vnoise(rp * 1.4 + 23.0));
		alb = mix(col, col * vec3(0.6, 0.56, 0.46), a);
		alb = mix(alb, col * vec3(1.15, 1.1, 0.95), b * (1.0 - a));
		alb *= 0.93 + 0.1 * n1;
		rough = 0.65;
	} else if (code == 16) {
		alb *= 0.8 + 0.3 * n1;
		rough = 0.75;
	} else if (code == 17) {
		float streak = vnoise(rp * vec3(7.0, 1.3, 7.0) + 3.0);
		float r = smoothstep(0.66, 0.82, streak * 0.65 + vnoise(rp * 14.0) * 0.35);
		alb = col * (0.82 + 0.22 * n2) * (0.92 + 0.12 * streak);
		alb = mix(alb, vec3(0.16, 0.085, 0.045) * (0.8 + 0.4 * n1), r * 0.85);
		rough = mix(0.72, 0.95, r);
	}
	alb = mix(alb, vec3(0.48, 0.41, 0.31) * (0.85 + 0.3 * n2), clamp(dirt * (0.5 + 0.7 * n1), 0.0, 1.0));
}
"""

const FRAG := """
void fragment() {
	vec3 alb; float rough; float metal; vec3 emit;
	shade(int(v_code + 0.5), COLOR.rgb, 1.0 - COLOR.a, v_rest, UV, team_color.rgb, ROLL_EXPR, alb, rough, metal, emit);
	DEBUG_LINE
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
"""

const SOLDIER_HEAD := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 KP[NKP];
uniform bool debug_bones = false;
instance uniform vec4 pw = vec4(1.0, 0.0, 0.0, 0.0);   // weights: idle, move, fire, prone
instance uniform vec4 pd = vec4(0.0);                  // dead weight, gait phase, clock, recoil impulse
instance uniform vec4 cfg = vec4(0.0);                 // pose class, seed, burst shots, burst period (0 = no auto recoil)
instance uniform vec4 gl = vec4(0.3, 0.03, 0.0, 0.0);  // left-hand grip in weapon space
instance uniform vec4 team_color = vec4(0.3, 0.5, 0.9, 1.0);
varying flat float v_bone;

const vec3 PIV[13] = vec3[13](
	vec3(0.0, 0.98, 0.0), vec3(0.0, 1.08, 0.0), vec3(0.0, 1.52, 0.0),
	vec3(0.0, 1.41, -0.19), vec3(0.0, 1.13, -0.19), vec3(0.0, 1.41, 0.19), vec3(0.0, 1.13, 0.19),
	vec3(0.0, 0.93, -0.1), vec3(0.0, 0.49, -0.1), vec3(0.0, 0.93, 0.1), vec3(0.0, 0.49, 0.1),
	vec3(0.0), vec3(0.0));
const float UPPER = 0.28;
const float FORE = 0.29;
const float THIGH = 0.44;
const int NV = NVEC;
const int NR = NROW;

"""

const SOLDIER_VERTEX := """
struct Blend { int r0; int r1; int r2; int r3; int r4; vec4 w; float wd; };

vec4 kb(Blend B, int k) {
	vec4 r = vec4(0.0);
	if (B.w.x > 0.0005) { r += B.w.x * KP[B.r0 + k]; }
	if (B.w.y > 0.0005) { r += B.w.y * KP[B.r1 + k]; }
	if (B.w.z > 0.0005) { r += B.w.z * KP[B.r2 + k]; }
	if (B.w.w > 0.0005) { r += B.w.w * KP[B.r3 + k]; }
	if (B.wd > 0.0005) { r += B.wd * KP[B.r4 + k]; }
	return r;
}

// Held object (k = 6 weapon, k = 10 aux): offset relative to the pelvis unless anchored to the ground.
void held_xf(Blend B, vec3 rp, int k, float yaw_add, float rec, out mat3 R, out vec3 P) {
	vec4 a = kb(B, k);
	vec4 b = kb(B, k + 1);
	float carried = 1.0 - clamp(a.w, 0.0, 1.0);
	vec3 off = a.xyz;
	vec3 rot = b.xyz;
	rot.y += yaw_add * carried;
	off.x -= rec * 0.055 * carried;
	rot.x -= rec * 0.1 * carried;
	R = body_rot(rot);
	P = off + rp * carried;
}
void vertex() {
	int bone = int(UV2.y + 0.5);
	v_code = UV2.x;
	v_bone = UV2.y;
	v_rest = VERTEX;
	vec4 W = pw;
	vec4 D = pd;
	vec4 C = cfg;
	vec4 G = gl;
	int cls = int(C.x + 0.5);
	float seed = C.y;
	int base = cls * NR * NV;
	Blend B;
	B.r0 = base;
	B.r1 = base + NV;
	B.r2 = base + 2 * NV;
	B.r3 = base + 3 * NV;
	B.r4 = base + (4 + int(mod(seed, 2.0))) * NV;
	B.w = W;
	B.wd = D.x;
	float t = TIME + seed * 7.31;
	float ph = D.y;
	float rec = D.w;
	if (C.w > 0.0) {
		float dt = C.z > 1.5 ? 0.085 : 0.22;
		float c = mod(D.z + seed * 0.37, C.w);
		float k = floor(c / dt);
		if (k < C.z) {
			float f = fract(c / dt);
			rec = max(rec, (1.0 - f) * (1.0 - f));
		}
	}
	rec *= W.z;

	vec4 v0 = kb(B, 0);
	vec4 v1 = kb(B, 1);
	vec3 rp = v0.xyz;
	vec3 rr = v1.xyz;
	float sway = sin(0.9 * t);
	rp.z += W.x * 0.012 * sway;
	rr.z += W.x * 0.018 * sway;
	rp.y += W.y * 0.04 * (0.5 - 0.5 * cos(2.0 * ph));
	rr.y += W.y * 0.10 * sin(ph);
	rp.x -= rec * 0.012;
	mat3 Rr = body_rot(rr);
	vec3 lv = VERTEX - PIV[bone];
	mat3 R = Rr;
	vec3 P = rp;
	if (bone >= 7 && bone <= 10) {
		bool left = bone <= 8;
		vec4 th = kb(B, left ? 4 : 5);
		float knee = left ? kb(B, 2).w : kb(B, 3).w;
		float lph = left ? ph : ph + PI;
		th.x += W.y * 0.62 * sin(lph);
		knee += W.y * (0.12 + 1.15 * pow(max(0.0, cos(lph + 0.5)), 1.6));
		float sg = left ? 1.0 : -1.0;
		mat3 Rt = Rr * rz(th.x) * ry(sg * th.y) * rx(sg * th.z);
		vec3 Pt = rp + Rr * (PIV[left ? 7 : 9] - PIV[0]);
		if (bone == 7 || bone == 9) {
			R = Rt;
			P = Pt;
		} else {
			R = Rt * rz(-knee);
			P = Pt + Rt * vec3(0.0, -THIGH, 0.0);
		}
	} else if (bone == 11) {
		held_xf(B, rp, 6, W.y * 0.06 * sin(ph), rec, R, P);
	} else if (bone == 12) {
		held_xf(B, rp, 10, 0.0, 0.0, R, P);
	} else if (bone >= 1) {
		vec3 sr = kb(B, 2).xyz;
		sr.x += W.x * 0.018 * sin(1.7 * t) + W.w * 0.02 * sin(1.3 * t) - rec * 0.05;
		sr.y -= W.y * 0.15 * sin(ph);
		mat3 Rc = Rr * body_rot(sr);
		vec3 Pc = rp + Rr * (PIV[1] - PIV[0]);
		if (bone == 1) {
			R = Rc;
			P = Pc;
		} else if (bone == 2) {
			vec3 hr = kb(B, 3).xyz;
			hr.y += W.x * 0.4 * sin(0.23 * t) * sin(0.11 * t + 1.3);
			hr.x += W.y * 0.03 * sin(2.0 * ph);
			R = body_rot(hr);
			P = Pc + Rc * (PIV[2] - PIV[1]);
		} else {
			bool left = bone <= 4;
			vec3 S = Pc + Rc * (PIV[left ? 3 : 5] - PIV[1]);
			mat3 Rw;
			vec3 Pw;
			held_xf(B, rp, 6, W.y * 0.06 * sin(ph), rec, Rw, Pw);
			vec3 Hw = Pw + Rw * (left ? G.xyz : vec3(0.0));
			vec3 Hf = Pc + Rc * kb(B, left ? 8 : 9).xyz;
			float g = clamp(left ? v1.w : v0.w, 0.0, 1.0);
			vec3 H = mix(Hf, Hw, g);
			vec3 pole = ry(rr.y) * normalize(vec3(-0.35, -1.0, left ? -0.75 : 0.75));
			mat3 Ru;
			mat3 Rf;
			vec3 JNT;
			ik2(S, H, pole, UPPER, FORE, Ru, Rf, JNT);
			if (bone == 3 || bone == 5) {
				R = Ru;
				P = S;
			} else {
				R = Rf;
				P = JNT;
			}
		}
	}
	VERTEX = P + R * lv;
	NORMAL = normalize(R * NORMAL);
}
"""

const HOUND_HEAD := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform bool debug_bones = false;
instance uniform vec4 pw = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 pd = vec4(0.0);
instance uniform vec4 cfg = vec4(0.0);
instance uniform vec4 gl = vec4(0.0);
instance uniform vec4 team_color = vec4(0.3, 0.5, 0.9, 1.0);
varying flat float v_bone;

const vec3 BODY = vec3(0.0, 0.62, 0.0);
const vec3 HEADP = vec3(0.42, 0.66, 0.0);
const vec3 GUNP = vec3(0.02, 0.74, 0.0);
const vec3 HIPS[4] = vec3[4](vec3(0.31, 0.56, -0.15), vec3(0.31, 0.56, 0.15), vec3(-0.31, 0.56, -0.15), vec3(-0.31, 0.56, 0.15));
const float UPPER = 0.30;
const float LOWER = 0.32;
"""

const HOUND_VERTEX := """
void vertex() {
	int bone = int(UV2.y + 0.5);
	v_code = UV2.x;
	v_bone = UV2.y;
	v_rest = VERTEX;
	vec4 W = pw;
	vec4 D = pd;
	vec4 C = cfg;
	float wd = D.x;
	float seed = C.y;
	float t = TIME + seed * 5.17;
	float ph = D.y;
	float rec = D.w;
	if (C.w > 0.0) {
		float c = mod(D.z + seed * 0.37, C.w);
		float k = floor(c / 0.08);
		if (k < C.z) {
			float f = fract(c / 0.08);
			rec = max(rec, (1.0 - f) * (1.0 - f));
		}
	}
	rec *= W.z;
	// body pose per state: height, pitch, roll
	float h_idle = 0.60 + 0.006 * sin(1.4 * t);
	float h_move = 0.585 + 0.018 * cos(2.0 * ph);
	float by = W.x * h_idle + W.y * h_move + W.z * 0.53 + W.w * 0.33 + wd * 0.19;
	vec3 br = W.y * vec3(-0.03 + 0.025 * sin(2.0 * ph), 0.0, 0.03 * sin(ph)) + W.z * vec3(0.04 - rec * 0.03, 0.0, 0.0)
		+ W.w * vec3(0.03, 0.0, 0.0) + wd * vec3(0.12, 0.35, 1.42) + W.x * vec3(0.0, 0.0, 0.01 * sin(0.7 * t));
	vec3 bp = vec3(-W.z * 0.02 - wd * 0.05, by, wd * 0.08);
	mat3 Rb = body_rot(br);
	mat3 R = Rb;
	vec3 P = bp;
	vec3 lv = VERTEX - BODY;
	if (bone == 1) {
		float yaw = W.x * 0.45 * sin(0.37 * t) * sin(0.17 * t + 2.0) + W.z * 0.0 + wd * 0.5;
		float pitch = W.x * 0.08 * sin(0.5 * t) + W.w * -0.15 + wd * 0.5 + W.y * 0.05;
		R = Rb * ry(yaw) * rz(-pitch);
		P = bp + Rb * (HEADP - BODY);
		lv = VERTEX - HEADP;
	} else if (bone == 2) {
		R = Rb * rz(rec * 0.06);
		P = bp + Rb * (GUNP - BODY + vec3(-rec * 0.05, 0.0, 0.0));
		lv = VERTEX - GUNP;
	} else if (bone >= 3) {
		int li = (bone - 3) / 2;
		bool lower = ((bone - 3) % 2) == 1;
		vec3 hip = HIPS[li] - BODY;
		bool front = li < 2;
		float side = (li % 2 == 0) ? -1.0 : 1.0;
		float lph = ph + ((li == 0 || li == 3) ? 0.0 : PI);
		// foot targets in body space for each state
		vec3 f_stand = vec3(hip.x, 0.03 - h_idle, hip.z + side * 0.02);
		vec3 f_move = vec3(hip.x - 0.21 * cos(lph), 0.03 - h_move + 0.09 * max(0.0, sin(lph)), hip.z + side * 0.02);
		vec3 f_fire = vec3(hip.x + (front ? 0.04 : -0.04), 0.03 - 0.53, hip.z + side * 0.07);
		vec3 f_crouch = vec3(hip.x + (front ? 0.06 : -0.02), 0.03 - 0.33, hip.z + side * 0.06);
		vec3 f_dead = vec3(hip.x + (front ? 0.15 : -0.1), side > 0.0 ? -0.45 : -0.28, side > 0.0 ? hip.z + 0.04 : 0.12);
		vec3 F = W.x * f_stand + W.y * f_move + W.z * f_fire + W.w * f_crouch + wd * f_dead;
		vec3 pole = normalize(vec3(-1.0, 0.0, side * 0.15));
		mat3 Ru;
		mat3 Rf;
		vec3 JNT;
		ik2(hip, F, pole, UPPER, LOWER, Ru, Rf, JNT);
		if (!lower) {
			R = Rb * Ru;
			P = bp + Rb * hip;
			lv = VERTEX - HIPS[li];
		} else {
			R = Rb * Rf;
			P = bp + Rb * JNT;
			lv = VERTEX - (HIPS[li] - vec3(0.0, UPPER, 0.0));
		}
	}
	VERTEX = P + R * lv;
	NORMAL = normalize(R * NORMAL);
}
"""

const VEHICLE_HEAD := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform bool debug_bones = false;
instance uniform vec4 anim = vec4(0.0);      // x roll distance (m), y rotor angle (rad)
instance uniform vec4 recoil = vec4(0.0);    // per weapon slot 0..1
instance uniform vec4 team_color = vec4(0.3, 0.5, 0.9, 1.0);
varying flat float v_bone;
"""

const VEHICLE_VERTEX := """
void vertex() {
	v_code = UV2.x;
	v_bone = UV2.y;
	v_rest = VERTEX;
	int mode = int(UV2.y + 0.5);
	if (mode >= 1 && mode <= 4) {
		mat3 R;
		if (mode == 1) {
			R = rz(-anim.x / max(CUSTOM0.w, 0.05));
		} else if (mode == 2) {
			R = ry(anim.y * CUSTOM0.w);
		} else if (mode == 3) {
			R = rx(anim.y * CUSTOM0.w);
		} else {
			R = rz(anim.y * CUSTOM0.w);
		}
		VERTEX = CUSTOM0.xyz + R * (VERTEX - CUSTOM0.xyz);
		NORMAL = R * NORMAL;
	} else if (mode == 5) {
		int s = int(CUSTOM0.w);
		float stroke = fract(CUSTOM0.w) * 2.0;
		VERTEX.x -= recoil[s] * stroke;
	}
}
"""

const DISC_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform vec4 tint : source_color = vec4(0.12, 0.12, 0.13, 1.0);
uniform float strength = 0.22;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float edge = 1.0 - smoothstep(0.94, 1.0, r);
	float hub = smoothstep(0.12, 0.22, r);
	float band = 0.75 + 0.25 * smoothstep(0.8, 0.95, r);
	float streak = 0.85 + 0.15 * sin(atan(q.y, q.x) * 5.0);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.8;
	ALPHA = clamp(edge * hub * band * streak * strength, 0.0, 1.0);
}
"""


static func _make(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func _frag(roll_expr: String) -> String:
	return FRAG.replace("ROLL_EXPR", roll_expr).replace("DEBUG_LINE",
		"if (debug_bones) { alb = debug_hue(v_bone); rough = 0.8; metal = 0.0; emit = vec3(0.0); }")


static func soldier_material() -> ShaderMaterial:
	if _soldier_mat == null:
		var table := SoldierRig.pose_table()
		var head := SOLDIER_HEAD.replace("NKP", str(table.size())).replace("NVEC", str(SoldierRig.NV)).replace("NROW", str(SoldierRig.NR))
		_soldier_mat = _make(head + COMMON + SHADE + SOLDIER_VERTEX + _frag("0.0"))
		_soldier_mat.set_shader_parameter("KP", table)
	return _soldier_mat


static func hound_material() -> ShaderMaterial:
	if _hound_mat == null:
		_hound_mat = _make(HOUND_HEAD + COMMON + SHADE + HOUND_VERTEX + _frag("0.0"))
	return _hound_mat


static func vehicle_material() -> ShaderMaterial:
	if _vehicle_mat == null:
		_vehicle_mat = _make(VEHICLE_HEAD + COMMON + SHADE + VEHICLE_VERTEX + _frag("anim.x"))
	return _vehicle_mat


static func disc_material() -> ShaderMaterial:
	if _disc_mat == null:
		_disc_mat = _make(DISC_CODE)
	return _disc_mat


static func set_debug(on: bool) -> void:
	for m in [soldier_material(), hound_material(), vehicle_material()]:
		m.set_shader_parameter("debug_bones", on)

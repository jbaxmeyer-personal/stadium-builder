shader_type spatial;
render_mode cull_disabled;
// Goal netting: a mesh of cords in world space (square, hexagonal, or striped
// in two colours). The holes are cut away; the cords catch the light.

uniform vec3 net_color : source_color = vec3(1.0);
uniform bool use_uv = false;   // goal nets carry panel UVs in metres; fences use world space
uniform int pattern = 0;     // 0 square, 1 hexagon, 2 striped

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float cords(vec2 p) {
	float cell = 0.09;
	if (pattern == 1) {
		// hexagonal mesh
		vec2 r = vec2(1.0, 1.732);
		vec2 h = r * 0.5;
		vec2 a = mod(p / cell, r) - h;
		vec2 b = mod(p / cell - h, r) - h;
		vec2 g = dot(a, a) < dot(b, b) ? a : b;
		vec2 q = abs(g);
		float d = max(q.x * 0.866 + q.y * 0.5, q.y);
		return smoothstep(0.36, 0.44, d);
	}
	vec2 f = abs(fract(p / cell) - 0.5);
	return smoothstep(0.38, 0.47, max(f.x, f.y));
}

void fragment() {
	vec3 n = abs(wn);
	vec2 p = n.x > 0.5 ? wpos.zy : (n.z > 0.5 ? wpos.xy : wpos.xz);
	if (n.y > 0.3 && n.y < 0.95) { p = vec2(wpos.z, wpos.x + wpos.y); }
	// goal nets: panel-space metres, so the mesh follows a baggy net
	// instead of slicing through it
	if (use_uv) { p = UV; }
	float c = cords(p);
	vec3 col = net_color;
	if (pattern == 2) {
		col = mod(floor(p.x / 0.35), 2.0) < 1.0 ? net_color : vec3(1.0);
	}
	ALBEDO = col;
	ALPHA = c;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.8;
}

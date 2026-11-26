shader_type spatial;
// Building walls drawn by numbers: storeys, window bays with frames, sills and
// glass that reflects the sky, shopfronts on the ground floor, office curtain
// walls, a darker plinth, and a gravel flat roof. The mesh is a unit box
// (y 0..1) scaled per instance, so every face works out its own bays.
//   instance colour  = wall colour
//   INSTANCE_CUSTOM  = (style, seed, storey height, fade)
//   style: 0 house  1 flats  2 shops  3 office  4 shed

uniform float night = 0.0;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;

varying vec3 lp;          // local position, box -0.5..0.5 x 0..1
varying vec3 ln;          // local normal
varying vec3 scl;         // instance scale (metres)
varying flat vec4 cust;
varying vec3 wpos;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cust = INSTANCE_CUSTOM;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	int style = int(cust.x + 0.5);
	float seed = cust.y;
	vec3 wall = pow(COLOR.rgb, vec3(2.2));
	float g = texture(grain, wpos.xz * 0.37 + wpos.y * 0.21).r;
	// distance fade for tall buildings near the camera
	if (cust.w > 0.5) {
		float d = length(wpos - CAMERA_POSITION_WORLD);
		float t = smoothstep(35.0, 70.0, d);
		float dither = fract(dot(FRAGCOORD.xy, vec2(0.5, 0.25)) + hash(floor(FRAGCOORD.xy)) * 0.5);
		if (t < dither) { discard; }
	}
	if (ln.y > 0.5) {
		// flat roof: gravel and bitumen
		ALBEDO = vec3(0.32, 0.31, 0.3) * mix(0.8, 1.15, g);
		ROUGHNESS = 0.95;
		SPECULAR = 0.1;
	} else {
		bool xface = abs(ln.x) > 0.5;
		float along = xface ? (lp.z + 0.5) : (lp.x + 0.5);
		float len = xface ? scl.z : scl.x;
		float h = lp.y * scl.y;
		float storey = max(cust.z, 0.5);
		float floors = max(1.0, floor(scl.y / storey + 0.25));
		float fh = scl.y / floors;
		float bay = style == 3 ? 0.9 : (style == 4 ? 2.2 : 1.05);
		float bays = max(1.0, floor(len / bay + 0.5));
		vec2 cell = vec2(floor(along * bays), floor(h / fh));
		vec2 f = vec2(fract(along * bays), fract(h / fh));
		float rnd = hash(cell + seed * 17.0 + (xface ? 3.1 : 0.0));
		vec3 col = wall * mix(0.88, 1.06, g);
		float win = 0.0;      // 1 inside the glass
		float frame = 0.0;    // 1 on the window frame / sill
		float shop = 0.0;
		if (style == 3) {
			// curtain wall: tall glass with slim mullions and spandrel bands
			win = step(0.06, f.x) * step(f.x, 0.94) * step(0.22, f.y) * step(f.y, 0.97);
			frame = 1.0 - win;
			col = mix(col, wall * 0.75, 0.5);
		} else if (style == 4) {
			// shed: vertical cladding ribs, a high strip of windows, a roller door
			col *= 0.92 + 0.08 * step(0.5, fract(along * len * 3.0));
			win = step(0.75, h / scl.y) * step(h / scl.y, 0.88) * step(0.1, f.x) * step(f.x, 0.9);
			if (cell.x == 1.0 && h < 1.6) { col = vec3(0.35, 0.37, 0.4) * (0.9 + 0.1 * step(0.5, fract(h * 8.0))); }
		} else {
			float ww = style == 1 ? 0.62 : 0.5;
			float x0 = 0.5 - ww * 0.5;
			win = step(x0, f.x) * step(f.x, 1.0 - x0) * step(0.32, f.y) * step(f.y, 0.82);
			float fr = step(x0 - 0.05, f.x) * step(f.x, 1.05 - x0) * step(0.27, f.y) * step(f.y, 0.86);
			frame = fr - win;
			// balconies on flats: a slab and a rail below every other window
			if (style == 1 && cell.y > 0.0 && mod(cell.x + cell.y, 2.0) < 1.0 && f.y < 0.3 && f.x > 0.1 && f.x < 0.9) {
				col = f.y < 0.06 ? vec3(0.75) : mix(col, vec3(0.2, 0.22, 0.24), 0.6 * step(0.5, fract(along * bays * 8.0)));
			}
			// ground-floor shopfronts
			if (style == 2 && cell.y == 0.0) {
				shop = 1.0;
				win = step(0.06, f.x) * step(f.x, 0.94) * step(0.08, f.y) * step(f.y, 0.7);
				frame = 0.0;
				float band = step(0.76, f.y) * step(f.y, 0.95);
				vec3 sc = vec3(hash(vec2(cell.x, seed)), hash(vec2(seed, cell.x + 7.0)), hash(vec2(cell.x * 3.0, seed + 2.0)));
				col = mix(col, pow(mix(vec3(0.35, 0.33, 0.3), sc, 0.4), vec3(2.2)), band);
			}
			// a few doors on houses
			if (style == 0 && cell.y == 0.0 && mod(cell.x, 3.0) == 1.0 && f.x > 0.3 && f.x < 0.7 && f.y < 0.78) {
				col = pow(vec3(0.25, 0.18, 0.14) + 0.2 * vec3(rnd, rnd * 0.5, 0.0), vec3(2.2));
				win = 0.0;
				frame = 0.0;
			}
		}
		// brick: reddish walls get courses and staggered joints in pale mortar;
		// pale walls get a fine render texture instead
		if (style != 3 && style != 4 && wall.r > wall.g * 1.35) {
			float row = h / 0.055;
			float bx = along * len / 0.12 + 0.5 * mod(floor(row), 2.0);
			float mortar = max(step(0.86, fract(row)), step(0.93, fract(bx)));
			float bv = hash(vec2(floor(bx), floor(row)) + seed);
			col *= mix(0.86, 1.1, bv);
			col = mix(col, vec3(0.62, 0.6, 0.56) * 0.7, mortar * 0.55 * (1.0 - win));
		} else if (style != 3) {
			col *= mix(0.95, 1.04, texture(grain, wpos.xy * 2.3 + wpos.zy * 1.7).r);
		}
		// storey bands and a darker plinth
		col *= 1.0 - 0.18 * step(h, 0.25);
		if (style == 1 || style == 2) { col *= 1.0 - 0.12 * step(fract(h / fh), 0.04) * step(fh, h); }
		// glass: dark, with a sky reflection that brightens toward the top, curtains, the odd lit room
		vec3 sky = vec3(0.32, 0.4, 0.5);
		vec3 glass = mix(vec3(0.05, 0.06, 0.07), sky, 0.25 + 0.35 * f.y) * mix(0.7, 1.1, rnd);
		if (rnd > 0.75 && style != 3) { glass = mix(glass, vec3(0.5, 0.44, 0.35), 0.35); }
		if (shop > 0.5) { glass = mix(glass, vec3(0.55, 0.5, 0.42), 0.4); }
		vec3 frame_col = style == 3 ? vec3(0.45, 0.47, 0.5) : vec3(0.82, 0.82, 0.8);
		col = mix(col, frame_col, frame);
		col = mix(col, glass, win);
		ALBEDO = col;
		ROUGHNESS = mix(0.9, 0.12, win);
		METALLIC = win * 0.3;
		SPECULAR = mix(0.25, 0.6, win);
		// lights on at night
		float lit = step(0.62, hash(cell * 1.7 + seed)) * win;
		if (shop > 0.5) { lit = win * 0.5 * step(0.4, hash(cell + seed * 3.1)); }
		EMISSION = night * lit * vec3(1.0, 0.78, 0.45) * 0.8;
	}
}

shader_type spatial;
// The playing surface: a natural, well-kept green with fine grass detail,
// mowing patterns that change shade with the light, and worn goalmouths
// and centre circle. Mapped from world space: origin..origin+size (x = length).

uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform int pattern = 0;          // 0 stripes 1 wide 2 checks 3 diagonal 4 diamonds 5 circles 6 plain
uniform vec2 size = vec2(30.0, 18.0);
uniform vec2 origin = vec2(0.0, 0.0);
uniform float snow = 0.0;
uniform vec3 green_a : source_color = vec3(0.17, 0.36, 0.12);
uniform vec3 green_b : source_color = vec3(0.22, 0.43, 0.15);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - origin) / size;
	vec2 m = (uv - 0.5) * size;       // metres from the centre spot
	// which way each strip was mown (+1 / -1) and along which direction
	float dir = 0.0;
	vec2 axis = vec2(1.0, 0.0);
	if (pattern == 0) {
		dir = mod(floor(uv.x * 12.0), 2.0) * 2.0 - 1.0;
	} else if (pattern == 1) {
		dir = mod(floor(uv.x * 6.0), 2.0) * 2.0 - 1.0;
	} else if (pattern == 2) {
		dir = mod(floor(uv.x * 12.0) + floor(uv.y * 8.0), 2.0) * 2.0 - 1.0;
	} else if (pattern == 3) {
		axis = normalize(vec2(1.0, 1.0));
		dir = mod(floor((m.x + m.y) / 2.4), 2.0) * 2.0 - 1.0;
	} else if (pattern == 4) {
		axis = normalize(vec2(1.0, 1.0));
		dir = (mod(floor((m.x + m.y) / 2.4), 2.0) * 2.0 - 1.0) * (mod(floor((m.x - m.y) / 2.4), 2.0) * 2.0 - 1.0);
	} else if (pattern == 5) {
		float r = length(m);
		axis = r > 0.01 ? m / r : vec2(1.0, 0.0);
		dir = mod(floor(r / 1.6), 2.0) * 2.0 - 1.0;
	}
	// blades laid one way look light from one side and dark from the other
	vec3 v = CAMERA_POSITION_WORLD - wpos;
	vec2 vh = normalize(v.xz + vec2(1e-4));
	float look = dot(vh, axis);
	float shade = 0.5 + dir * (0.36 + 0.14 * look);
	vec3 col = mix(green_a, green_b, clamp(shade, 0.0, 1.0));
	float band = dir * 0.5 + 0.5;
	// patchy natural variation, broad and fine
	float n1 = texture(noise, wpos.xz * 0.06).r;
	float n2 = texture(noise, wpos.xz * 0.7).r;
	col *= mix(0.9, 1.06, n1) * mix(0.94, 1.04, n2);
	// a faint speckle of individual tufts
	col *= mix(0.94, 1.05, texture(noise, wpos.xz * 4.0).r);
	// wear: goalmouths and the centre circle get scuffed and paler
	vec2 p = (uv - 0.5) * size;
	float goal = max(1.0 - length((p - vec2(-size.x * 0.5 + 1.2, 0.0)) / vec2(2.2, 2.6)),
	                 1.0 - length((p - vec2(size.x * 0.5 - 1.2, 0.0)) / vec2(2.2, 2.6)));
	float mid = 1.0 - length(p / vec2(3.2, 3.2));
	float wear = clamp(max(goal, mid * 0.5), 0.0, 1.0) * smoothstep(0.3, 0.7, n2 + n1 * 0.5);
	col = mix(col, vec3(0.36, 0.33, 0.2), wear * 0.55);
	col = mix(col, vec3(0.9, 0.92, 0.95), snow * 0.85);
	ALBEDO = col;
	NORMAL_MAP = texture(grass_n, wpos.xz * 0.5).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
	// mown grass looks lighter or darker depending on the blade direction:
	// fake it with a stripe-dependent sheen
	RIM = 0.08;
	RIM_TINT = 0.5;
}

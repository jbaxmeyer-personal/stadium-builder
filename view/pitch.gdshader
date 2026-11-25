shader_type spatial;
// The playing surface: a natural, well-kept green with fine grass detail,
// mowing patterns that change shade with the light, and worn goalmouths
// and centre circle. Mapped from world space: origin..origin+size (x = length).

uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform int pattern = 0;          // 0 stripes, 1 wide stripes, 2 checks, 3 plain
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
	float band = 0.0;
	if (pattern == 0) {
		band = mod(floor(uv.x * 12.0), 2.0);
	} else if (pattern == 1) {
		band = mod(floor(uv.x * 6.0), 2.0);
	} else if (pattern == 2) {
		band = mod(floor(uv.x * 12.0) + floor(uv.y * 8.0), 2.0);
	} else {
		band = 0.5;
	}
	vec3 col = mix(green_a, green_b, band);
	// patchy natural variation, broad and fine
	float n1 = texture(noise, wpos.xz * 0.06).r;
	float n2 = texture(noise, wpos.xz * 0.7).r;
	col *= mix(0.88, 1.08, n1) * mix(0.93, 1.05, n2);
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
	RIM = 0.15 * band;
	RIM_TINT = 0.6;
}

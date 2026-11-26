shader_type spatial;
// The playing surface: a natural, well-kept green with fine grass detail,
// mowing patterns that change shade with the light, and worn goalmouths
// and centre circle. Mapped from world space: origin..origin+size (x = length).

uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
	// real turf detail: the grass photo's light and dark at three scales,
	// laid over our colour so it keeps the club's chosen green
	float d1 = dot(texture(grass_d, wpos.xz * 0.55).rgb, vec3(0.3, 0.59, 0.11));
	float d2 = dot(texture(grass_d, wpos.zx * 1.9 + 0.37).rgb, vec3(0.3, 0.59, 0.11));
	float d3 = dot(texture(grass_d, wpos.xz * 5.3 + 0.71).rgb, vec3(0.3, 0.59, 0.11));
	float detail = (d1 * 0.35 + d2 * 0.35 + d3 * 0.3) / 0.33;
	col *= mix(0.62, 1.28, clamp(detail * 0.5, 0.0, 1.0));
	// the grain of the cut: fine streaks running the way the mower went
	vec2 ax = axis;
	vec2 g = vec2(dot(wpos.xz, ax), dot(wpos.xz, vec2(-ax.y, ax.x)));
	float grain = texture(noise, g * vec2(0.5, 14.0)).r * 0.5 + texture(noise, g * vec2(1.2, 37.0)).r * 0.5;
	col *= mix(0.78, 1.14, grain);
	// blotches: greener, yellower and bluer patches like a real pitch
	float n1 = texture(noise, wpos.xz * 0.06).r;
	float n2 = texture(noise, wpos.xz * 0.7).r;
	float n3 = texture(noise, wpos.xz * 0.23 + vec2(0.5, 0.2)).r;
	col *= mix(0.88, 1.08, n1) * mix(0.93, 1.05, n2);
	col = mix(col, col * vec3(1.12, 1.05, 0.75), smoothstep(0.55, 0.85, n3) * 0.45);
	col = mix(col, col * vec3(0.85, 1.0, 1.08), smoothstep(0.45, 0.15, n3) * 0.35);
	// real grass is less saturated than paint
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, 0.86);
	// wear: goalmouths and the centre circle get scuffed and paler
	vec2 p = (uv - 0.5) * size;
	float goal = max(1.0 - length((p - vec2(-size.x * 0.5 + 1.2, 0.0)) / vec2(2.2, 2.6)),
	                 1.0 - length((p - vec2(size.x * 0.5 - 1.2, 0.0)) / vec2(2.2, 2.6)));
	float mid = 1.0 - length(p / vec2(3.2, 3.2));
	float wear = clamp(max(goal, mid * 0.5), 0.0, 1.0) * smoothstep(0.3, 0.7, n2 + n1 * 0.5);
	col = mix(col, vec3(0.36, 0.33, 0.2), wear * 0.55);
	col = mix(col, vec3(0.9, 0.92, 0.95), snow * 0.85);
	ALBEDO = col;
	NORMAL_MAP = normalize(texture(grass_n, wpos.xz * 0.55).rgb * 0.6 + texture(grass_n, wpos.zx * 1.9 + 0.37).rgb * 0.4);
	NORMAL_MAP_DEPTH = 1.4;
	// grass is matt; blades catch a little light only in the bright stripes
	ROUGHNESS = mix(0.86, 1.0, clamp(1.0 - band * 0.5 + grain * 0.3, 0.0, 1.0));
	SPECULAR = 0.15;
}

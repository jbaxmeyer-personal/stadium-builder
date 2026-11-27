shader_type spatial;
render_mode cull_disabled;
// Standing-seam metal roofing: raised seams every 0.42 m along the roof,
// a soft metallic sheen, panel-to-panel tone variation and faint rain
// streaks. Mapped from the mesh's own coordinates, so it follows each stand.

uniform vec3 base : source_color = vec3(0.62, 0.64, 0.66);
uniform float seam = 0.42;
uniform bool radial = false;   // corner roofs: seams fan out round the curve (UV.x runs along it)
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

varying vec3 lp;
varying vec3 wn;

void vertex() {
	lp = VERTEX;
	wn = NORMAL;
}

float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void fragment() {
	float u = (radial ? UV.x : lp.x) / seam;
	float f = fract(u);
	float panel = floor(u);
	vec3 col = base * mix(0.93, 1.05, h1(panel));
	// raised seam: a bright ridge and a dark shadow line beside it
	float ridge = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.05, 0.1, f));
	float shadow = smoothstep(0.1, 0.14, f) * (1.0 - smoothstep(0.14, 0.22, f));
	// far away the seams are thinner than a pixel: fade them to their average
	// tone (no shimmer), and let the broad sheet joints carry the look
	float near = clamp(1.0 - fwidth(u) * 2.5, 0.0, 1.0);
	ridge *= near;
	shadow *= near;
	col *= 1.0 + 0.25 * ridge - 0.22 * shadow - (1.0 - near) * 0.012;
	// sheet joints every few metres: a soft line that reads from the air
	float s2 = (radial ? UV.x : lp.x) / (seam * 9.0);
	float jf = fract(s2);
	float jw = clamp(fwidth(s2) * 1.5, 0.004, 0.08);
	float joint = 1.0 - smoothstep(0.0, jw, min(jf, 1.0 - jf));
	col *= 1.0 - 0.1 * joint * (1.0 - near * 0.6);
	// streaks running down the slope, and broad weathering
	float st = texture(noise, vec2(lp.x * 0.9, lp.z * 0.05)).r;
	float wb = texture(noise, lp.xz * 0.03).r;
	col *= mix(0.9, 1.04, st) * mix(0.92, 1.03, wb);
	ALBEDO = col;
	METALLIC = 0.55;
	ROUGHNESS = mix(0.42, 0.6, st);
	NORMAL_MAP = normalize(vec3(-(ridge - shadow) * 0.6 - joint * 0.15, 0.0, 1.0)) * 0.5 + 0.5;
}

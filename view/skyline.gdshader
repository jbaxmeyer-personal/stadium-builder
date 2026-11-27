shader_type spatial;
render_mode fog_disabled;
// Far-off towers: a hazy tone by day; at night dark shapes with a scatter of
// lit windows. The window pattern comes from world position, so every face
// of every tower gets its own.

uniform vec3 tone : source_color = vec3(0.66, 0.72, 0.8);
uniform float night = 0.0;
uniform float lit = 0.22;

varying vec3 wpos;
varying vec3 wn;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = abs(wn.x) > 0.5 ? wpos.zy : wpos.xy;
	vec2 cell = floor(p / vec2(1.6, 1.4));
	vec2 f = fract(p / vec2(1.6, 1.4));
	float window = step(0.2, f.x) * step(f.x, 0.8) * step(0.25, f.y) * step(f.y, 0.75);
	float on = step(1.0 - lit, hash(cell + floor(wpos.xz / 40.0)));
	vec3 day = tone;
	vec3 dark = tone * vec3(0.06, 0.07, 0.09);
	ALBEDO = mix(day, dark, night);
	ROUGHNESS = 0.9;
	EMISSION = vec3(1.0, 0.82, 0.55) * window * on * night * 0.9;
}

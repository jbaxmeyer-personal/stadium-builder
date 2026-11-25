shader_type spatial;
// Landscape: grass (two kinds, broken up by noise), dirt, rock on steep
// slopes, snow on high peaks (and everywhere when `snow` is up). All
// textures are Poly Haven CC0, mapped in world space.

uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_a_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D variation : filter_linear, repeat_enable;   // large-scale noise
uniform float snow = 0.0;
uniform float snow_line = 70.0;
uniform vec3 grass_tint : source_color = vec3(0.74, 0.8, 0.62);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri(sampler2D t, vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy * scale).rgb * w.x + texture(t, p.xz * scale).rgb * w.y + texture(t, p.xy * scale).rgb * w.z;
}

void fragment() {
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float v = texture(variation, wpos.xz * 0.004).r;
	float v2 = texture(variation, wpos.xz * 0.031 + vec2(0.37, 0.71)).r;
	vec3 ga = texture(grass_a, wpos.xz * 0.16).rgb;
	vec3 gb = texture(grass_b, wpos.xz * 0.11).rgb;
	vec3 grass = mix(ga, gb, smoothstep(0.35, 0.65, v)) * grass_tint * mix(0.85, 1.1, v2);
	vec3 d = texture(dirt, wpos.xz * 0.14).rgb * vec3(0.95, 0.9, 0.82);
	vec3 r = tri(rock, wpos, wnorm, 0.06) * vec3(0.92, 0.9, 0.88);
	// dirt patches in grass and on banks below the waterline
	float dirt_amt = smoothstep(0.62, 0.8, v2) * 0.6 + smoothstep(-0.05, -0.6, wpos.y);
	vec3 col = mix(grass, d, clamp(dirt_amt, 0.0, 1.0));
	float rock_amt = smoothstep(0.32, 0.55, slope) + smoothstep(38.0, 60.0, wpos.y) * 0.8;
	col = mix(col, r, clamp(rock_amt, 0.0, 1.0));
	float snow_amt = max(smoothstep(snow_line, snow_line + 15.0, wpos.y + v * 12.0) * (1.0 - smoothstep(0.55, 0.8, slope)), snow);
	col = mix(col, vec3(0.92, 0.94, 0.97), clamp(snow_amt, 0.0, 1.0));
	ALBEDO = col;
	vec3 nmap = mix(texture(grass_a_n, wpos.xz * 0.16).rgb, texture(dirt_n, wpos.xz * 0.14).rgb, clamp(dirt_amt, 0.0, 1.0));
	nmap = mix(nmap, texture(rock_n, wpos.xz * 0.06).rgb, clamp(rock_amt, 0.0, 1.0));
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(0.95, 0.6, snow_amt);
	SPECULAR = 0.2;
}

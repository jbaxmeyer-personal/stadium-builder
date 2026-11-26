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
uniform vec3 grass_tint : source_color = vec3(0.66, 0.86, 0.5);
uniform vec3 lush : source_color = vec3(0.37, 0.5, 0.23);   // the green we want; textures give the detail
uniform vec3 lush_dry : source_color = vec3(0.52, 0.54, 0.3);

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
	vec3 det = mix(ga, gb, smoothstep(0.6, 0.85, v) * 0.6);
	float lum = dot(det, vec3(0.299, 0.587, 0.114)) / 0.36;
	vec3 base = mix(lush, lush_dry, smoothstep(0.4, 0.85, v) * 0.75);
	vec3 grass = mix(det * grass_tint, base * lum, 0.72) * mix(0.86, 1.08, v2);
	// meadow detail at three scales: broad patches of greener and drier grass,
	// darker clumps, and fine blade speckle with sunlit tips
	float v3 = texture(variation, wpos.xz * 0.09 + vec2(0.13, 0.57)).r;
	float clump = smoothstep(0.55, 0.8, v3);
	grass *= mix(1.0, 0.78, clump);
	grass = mix(grass, grass * vec3(1.18, 1.1, 0.72), smoothstep(0.35, 0.15, v3) * 0.5);
	float blades = texture(grass_a_n, wpos.xz * 1.7).g * 0.6 + texture(grass_a_n, wpos.zx * 3.1 + 0.3).g * 0.4;
	grass *= mix(0.78, 1.16, blades);
	grass = mix(grass, vec3(0.62, 0.6, 0.32) * lum, smoothstep(0.82, 0.95, blades) * 0.35);
	vec3 d = texture(dirt, wpos.xz * 0.14).rgb * vec3(0.95, 0.9, 0.82);
	vec3 r = tri(rock, wpos, wnorm, 0.06) * vec3(0.92, 0.9, 0.88);
	// dirt patches in grass and on banks below the waterline
	float dirt_amt = smoothstep(0.78, 0.92, v2) * 0.3 + smoothstep(-0.05, -0.6, wpos.y);
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
	// a soft sheen across the grass where the light grazes it
	float grassy = (1.0 - clamp(dirt_amt + rock_amt + snow_amt, 0.0, 1.0));
	RIM = 0.25 * grassy;
	RIM_TINT = 0.7;
	BACKLIGHT = vec3(0.12, 0.16, 0.04) * grassy;
}

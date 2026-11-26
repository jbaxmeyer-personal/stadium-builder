shader_type spatial;
render_mode depth_draw_never;
// Lake / river water: depth-tinted (shallow, sandy-green at the banks, deep
// blue-green out in the middle) from the actual scene depth, sky reflection
// via fresnel, moving ripples, and a soft foam line where it meets the shore.

uniform sampler2D ripple : hint_normal;
uniform vec3 deep : source_color = vec3(0.05, 0.19, 0.27);
uniform vec3 shallow : source_color = vec3(0.24, 0.42, 0.38);
uniform vec3 sky : source_color = vec3(0.55, 0.68, 0.8);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.05 + vec2(TIME * 0.02, TIME * 0.013);
	vec2 uv2 = wpos.xz * 0.11 - vec2(TIME * 0.017, -TIME * 0.011);
	vec3 n = normalize(texture(ripple, uv1).xyz * 2.0 - 1.0 + texture(ripple, uv2).xyz * 2.0 - 1.0);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.5;
	// how much water lies under this pixel (scene depth behind minus ours)
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	world.xyz /= world.w;
	float thick = clamp((VERTEX.z - world.z) * 0.9, 0.0, 1.0);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 1.0, thick));
	// see the bed through the shallows
	vec3 bed = texture(screen_tex, SCREEN_UV + n.xy * 0.006).rgb;
	col = mix(bed * vec3(0.7, 0.85, 0.85), col, smoothstep(0.0, 0.45, thick));
	// sky reflection at grazing angles
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky, fres * 0.6);
	// foam where the water is very shallow
	float foam = (1.0 - smoothstep(0.0, 0.12, thick)) * (0.6 + 0.4 * sin(TIME * 1.3 + wpos.x * 2.0 + wpos.z * 1.5));
	col = mix(col, vec3(0.85, 0.88, 0.86), foam * 0.5);
	ALBEDO = col;
	ROUGHNESS = 0.05;
	METALLIC = 0.1;
	SPECULAR = 0.8;
}

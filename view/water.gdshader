shader_type spatial;
// Lake / river water: deep blue-green, glossy, with moving ripples and
// lighter shallows near the shore (vertex colour alpha = depth 0..1).

uniform sampler2D ripple : hint_normal;
uniform vec3 deep : source_color = vec3(0.07, 0.22, 0.3);
uniform vec3 shallow : source_color = vec3(0.25, 0.45, 0.45);

varying vec3 wpos;
varying float depth;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = COLOR.a;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.05 + vec2(TIME * 0.02, TIME * 0.013);
	vec2 uv2 = wpos.xz * 0.08 - vec2(TIME * 0.017, -TIME * 0.011);
	vec3 n = normalize(texture(ripple, uv1).xyz * 2.0 - 1.0 + texture(ripple, uv2).xyz * 2.0 - 1.0);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	ALBEDO = mix(shallow, deep, smoothstep(0.0, 1.0, depth));
	ROUGHNESS = 0.06;
	METALLIC = 0.25;
	SPECULAR = 0.7;
}

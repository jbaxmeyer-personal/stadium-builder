shader_type spatial;
// Crowd figures. Instance colour = shirt. INSTANCE_CUSTOM.x = phase,
// .y = how lively this stand type is, .z = skin tone. `bounce` comes from atmosphere.
// The head (upper part of the mesh) is skin-coloured, the rest wears the shirt.

uniform float bounce = 0.0;

varying vec3 shirt;
varying float height;
varying float skin_pick;
varying float card;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float lively = INSTANCE_CUSTOM.y;
	height = VERTEX.y;
	skin_pick = INSTANCE_CUSTOM.z;
	card = INSTANCE_CUSTOM.w;
	VERTEX.y += max(0.0, sin(TIME * 7.0 + phase)) * bounce * lively;
	shirt = COLOR.rgb;
}

void fragment() {
	vec3 skin = mix(mix(vec3(0.96, 0.80, 0.69), vec3(0.78, 0.57, 0.42), smoothstep(0.0, 0.5, skin_pick)),
		vec3(0.42, 0.28, 0.2), smoothstep(0.5, 1.0, skin_pick));
	ALBEDO = (height > 0.155 && card < 0.5) ? skin : shirt;
	ROUGHNESS = 0.85;
}

shader_type spatial;
// Crowd figures. Instance colour = shirt. INSTANCE_CUSTOM.x = phase,
// .y = how lively this stand type is. `bounce` comes from atmosphere.

uniform float bounce = 0.0;

varying vec3 shirt;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float lively = INSTANCE_CUSTOM.y;
	VERTEX.y += max(0.0, sin(TIME * 7.0 + phase)) * bounce * lively;
	shirt = COLOR.rgb;
}

void fragment() {
	ALBEDO = shirt;
	ROUGHNESS = 0.85;
}

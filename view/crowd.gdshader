shader_type spatial;
// Crowd fans. The mesh tags each body part in UV2.x:
//   0 torso (shirt)  1 head (skin)  2 hair  3 arm (sleeve)  4 hand (skin)  5 scarf  6 legs (trousers)
// Instance colour = shirt. INSTANCE_CUSTOM: x = phase, y = how lively the stand is,
// z = person (skin tone, hair, trousers), w = 0 plain / 0.5 wears a scarf / 1 tifo card holder.
// Arms swing up in celebration more often the louder the crowd (`cheer`).

uniform float bounce = 0.0;
uniform float cheer = 0.0;
uniform float scarves = 0.0;       // before kick-off: scarf wearers hold them up
uniform float surge = 0.0;         // a home goal: everyone up, arms in the air
uniform float hip = 0.25;          // hip height of this mesh (seated / standing)
uniform vec3 scarf_color : source_color = vec3(1.0);

varying vec3 shirt;
varying float part;
varying float who;
varying float kind;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float lively = INSTANCE_CUSTOM.y;
	part = UV2.x;
	who = INSTANCE_CUSTOM.z;
	kind = INSTANCE_CUSTOM.w;
	shirt = COLOR.rgb;
	int p = int(part + 0.5);
	if ((p == 3 || p == 4) && kind < 0.75) {
		// arms up: rotate about the shoulder, sideways and up
		float wave = smoothstep(0.2, 0.8, sin(TIME * 2.2 + phase * 1.7));
		float up = max(wave * cheer * lively, surge * (0.6 + 0.4 * lively));
		if (kind > 0.25) up = max(up, scarves);
		float side = sign(VERTEX.x);
		vec2 pivot = vec2(side * 0.08, hip + 0.16);
		vec2 v = VERTEX.xy - pivot;
		float a = side * up * 2.7;
		VERTEX.xy = pivot + vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
	}
	VERTEX.y += max(0.0, sin(TIME * 7.0 + phase)) * (bounce + surge * 0.18) * max(lively, surge * 0.7);
}

vec3 skin_tone(float t) {
	return mix(mix(vec3(0.96, 0.80, 0.69), vec3(0.80, 0.58, 0.43), smoothstep(0.0, 0.5, t)),
		vec3(0.40, 0.27, 0.19), smoothstep(0.55, 1.0, t));
}

vec3 hair_tone(float t) {
	float h = fract(t * 7.31);
	if (h < 0.35) return vec3(0.08, 0.06, 0.05);
	if (h < 0.65) return vec3(0.30, 0.18, 0.10);
	if (h < 0.85) return vec3(0.75, 0.6, 0.35);
	if (h < 0.93) return vec3(0.6, 0.25, 0.1);
	return vec3(0.75, 0.75, 0.75);
}

void fragment() {
	int p = int(part + 0.5);
	vec3 c = shirt;
	if (kind > 0.75) {
		c = shirt;  // tifo: everything is the card
	} else if (p == 1 || p == 4) {
		c = skin_tone(who);
	} else if (p == 2) {
		c = hair_tone(who);
	} else if (p == 5) {
		c = kind > 0.25 ? scarf_color : shirt;
	} else if (p == 6) {
		c = fract(who * 3.7) < 0.6 ? vec3(0.12, 0.15, 0.25) : vec3(0.08, 0.08, 0.09);
	}
	ALBEDO = c;
	ROUGHNESS = p == 2 ? 0.6 : 0.85;
}

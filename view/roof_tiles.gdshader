shader_type spatial;
// Pitched roofs: courses of tiles or slates (rows by height, staggered joints),
// weathered a little, in the instance colour. Gable ends get a plain render.

varying vec3 lp;
varying vec3 ln;
varying vec3 scl;
varying vec3 wpos;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	if (abs(ln.z) > 0.9) {
		// gable end
		ALBEDO = vec3(0.7, 0.66, 0.6) * 0.8;
		ROUGHNESS = 0.9;
	} else {
		float rows = lp.y * scl.y / 0.12;
		float along = (lp.z + 0.5) * scl.z / 0.16 + 0.5 * mod(floor(rows), 2.0);
		vec2 tile = vec2(floor(along), floor(rows));
		float r = hash(tile);
		vec3 col = base * mix(0.82, 1.12, r);
		col *= 1.0 - 0.35 * smoothstep(0.75, 1.0, fract(rows));    // shadow under each course
		col *= 1.0 - 0.2 * step(0.92, fract(along));
		col = mix(col, col * vec3(0.9, 0.95, 0.85), smoothstep(0.6, 0.9, hash(floor(wpos.xz * 0.7))));
		ALBEDO = col;
		ROUGHNESS = 0.82;
		SPECULAR = 0.25;
	}
}

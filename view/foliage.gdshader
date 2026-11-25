shader_type spatial;
render_mode cull_disabled;
// Tree canopies: leafy light-and-dark detail from a noise texture (mapped in
// the tree's own space so it doesn't swim), ragged edges where the canopy
// turns away from the camera, and light glowing through the leaves.
// Vertex colour (greens + fake AO) times the instance tint gives the colour.

uniform sampler2D leaf_noise : filter_linear_mipmap, repeat_enable;
uniform float snow = 0.0;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	// a gentle sway
	float t = TIME * 0.8 + MODEL_MATRIX[3].x * 0.3 + MODEL_MATRIX[3].z * 0.2;
	VERTEX.xz += vec2(sin(t), cos(t * 0.7)) * 0.006 * max(VERTEX.y - 0.3, 0.0);
}

float tri(vec3 p, vec3 n) {
	vec3 w = abs(n) + vec3(0.001);
	w /= (w.x + w.y + w.z);
	return texture(leaf_noise, p.zy).r * w.x + texture(leaf_noise, p.xz).r * w.y + texture(leaf_noise, p.xy).r * w.z;
}

void fragment() {
	float fine = tri(opos * 2.6, onrm);
	float coarse = tri(opos * 0.7, onrm);
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));   // vertex colours are sRGB
	// clumps of leaves: lit tufts and dark gaps
	col *= mix(0.62, 1.22, smoothstep(0.25, 0.75, fine)) * mix(0.85, 1.1, coarse);
	// snow settles on top
	col = mix(col, vec3(0.9, 0.92, 0.95), snow * smoothstep(0.3, 0.8, NORMAL.y) * 0.8);
	ALBEDO = col;
	// ragged silhouette: cut holes where the surface turns edge-on
	float edge = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	ALPHA = 1.0 - step(0.55 + fine * 0.5, edge) * 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.92;
	SPECULAR = 0.18;
	BACKLIGHT = col * 0.45;
	// leafy bumps: tilt the normal by the noise (no tangents needed)
	float f2 = tri(opos * 2.6 + vec3(0.31, 0.17, 0.53), onrm);
	vec3 bent = NORMAL + (vec3(fine, f2, coarse) - 0.5) * 0.9;
	NORMAL = dot(bent, bent) > 1e-4 ? normalize(bent) : NORMAL;
}

shader_type spatial;
render_mode cull_disabled;
// Waving flag. The quad's left edge (UV.x = 0) is the pole; the cloth ripples
// more toward the free edge. INSTANCE_CUSTOM.x = phase.

varying vec3 tint;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float free_edge = UV.x;
	VERTEX.z += sin(TIME * 7.0 + phase + UV.x * 5.0) * 0.09 * free_edge;
	VERTEX.y += sin(TIME * 5.0 + phase + UV.x * 4.0) * 0.03 * free_edge;
	tint = COLOR.rgb;
}

void fragment() {
	// two-colour flag: stripe across the middle in the instance's second colour
	ALBEDO = tint;
	ROUGHNESS = 0.9;
}

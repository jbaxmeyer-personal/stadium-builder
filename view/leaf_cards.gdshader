shader_type spatial;
render_mode cull_disabled;
// Leaf cards: a painted leaf-cluster texture with cut-out edges. Normals come
// from the crown (outward), so a whole tree lights like one soft volume; light
// shows through the leaves from behind. Vertex colour (shade + variety) times
// the instance tint gives the colour. A gentle sway in the wind.

uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic;
uniform float snow = 0.0;

void vertex() {
	float t = TIME * 0.9 + MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.23;
	float h = max(VERTEX.y - 0.3, 0.0);
	VERTEX.xz += vec2(sin(t + VERTEX.y * 3.0), cos(t * 0.8 + VERTEX.x * 4.0)) * 0.008 * h;
}

void fragment() {
	vec4 t = texture(leaves, UV);
	if (t.a < 0.5) { discard; }
	vec3 col = t.rgb * COLOR.rgb * 1.9;
	col = mix(col, vec3(0.9, 0.92, 0.95), snow * smoothstep(0.2, 0.7, NORMAL.y));
	ALBEDO = col;
	// keep the crown's outward normal on both faces
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = col * 0.55;
	AO = clamp(COLOR.g * 1.6, 0.4, 1.0);
	AO_LIGHT_AFFECT = 0.3;
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// A soft pool of lamplight on the ground: radial falloff, added on top.
uniform vec3 tint : source_color = vec3(1.0, 0.7, 0.35);
uniform float strength = 0.55;
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	ALBEDO = tint * a * strength;
}

shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec4 glow_color : source_color = vec4(0.12, 0.65, 0.86, 1.0);
uniform float glow_strength : hint_range(0.0, 2.0) = 0.72;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.6);
	float haze = pow(1.0 - facing, 7.0) * 0.35;
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * glow_strength * (rim + haze);
	ALPHA = clamp((rim * 0.48 + haze) * glow_strength, 0.0, 0.72);
}

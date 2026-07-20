shader_type canvas_item;
// Whole-screen NASA-hardware grade: faint film grain, warm tint, gentle
// vignette. Kept very subtle deliberately — it sits over HUD text, so
// anything stronger would hurt legibility.

uniform float grain_amount : hint_range(0.0, 0.2) = 0.018;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.32;
uniform vec3 warm_tint : source_color = vec3(1.02, 0.99, 0.93);
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(SCREEN_TEXTURE, uv).rgb;
	col *= warm_tint;

	vec2 centered = uv - 0.5;
	float vig = 1.0 - vignette_strength * dot(centered, centered) * 2.0;
	col *= clamp(vig, 0.0, 1.0);

	// per-pixel coordinates (not uv scaled by an assumed resolution) so
	// grain cells stay ~1 physical pixel at any window size
	float n = hash12(FRAGCOORD.xy + TIME * 60.0);
	col += (n - 0.5) * grain_amount;

	COLOR = vec4(col, 1.0);
}

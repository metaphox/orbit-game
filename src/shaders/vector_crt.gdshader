shader_type canvas_item;
// Vector-CRT mission-computer look for a screen-within-the-world (the
// minimap and the ship's status hologram): scanlines, phosphor glow,
// slight barrel curve, faint flicker. Meant to sit as the last child in
// its SubViewport so SCREEN_TEXTURE captures that viewport's own render.

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.35;
uniform float scanline_count : hint_range(50.0, 800.0) = 300.0;
uniform float glow_amount : hint_range(0.0, 1.0) = 0.25;
uniform float curve_amount : hint_range(0.0, 0.3) = 0.06;
uniform float flicker_amount : hint_range(0.0, 0.2) = 0.03;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

vec2 barrel(vec2 uv, float amount) {
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	return uv + c * r2 * amount;
}

void fragment() {
	vec2 uv = barrel(SCREEN_UV, curve_amount);
	bool in_bounds = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	vec2 sample_uv = clamp(uv, vec2(0.0), vec2(1.0));

	vec4 source = texture(SCREEN_TEXTURE, sample_uv);
	vec3 col = source.rgb;

	float scan = sin(sample_uv.y * scanline_count * 3.14159265) * 0.5 + 0.5;
	col *= mix(1.0, scan, scanline_strength);

	vec4 blurred = texture(SCREEN_TEXTURE, sample_uv, 2.0);
	col += blurred.rgb * glow_amount * 0.4;

	float flick = 1.0 - flicker_amount * 0.5 + flicker_amount * sin(TIME * 47.0) * 0.5;
	col *= flick;

	vec2 vc = sample_uv - 0.5;
	float vig = 1.0 - dot(vc, vc) * 0.6;
	col *= vig;

	col *= in_bounds ? 1.0 : 0.0;
	// Instrument viewports are transparent outside their drawn vectors.
	// Retaining that alpha prevents a billboarded gauge from becoming an
	// enormous black card that hides the ship behind it; the blurred sample
	// contributes just enough alpha for the phosphor halo to survive.
	float alpha = max(source.a, blurred.a * glow_amount * 0.55);
	alpha *= in_bounds ? 1.0 : 0.0;
	COLOR = vec4(col, alpha);
}

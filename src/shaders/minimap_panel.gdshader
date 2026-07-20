shader_type canvas_item;
// Soft backing panel for the minimap: fades from the node's own color/alpha
// at the center to fully transparent at the edge, so it reads as a glowing
// console readout rather than a hard-edged box. UV spans the rect's actual
// (non-square) bounds, so the falloff comes out elliptical for free,
// matching the panel's own aspect ratio.

void fragment() {
	vec2 c = UV - 0.5;
	float fade = 1.0 - smoothstep(0.18, 0.5, length(c));
	COLOR.a *= fade;
}

shader_type spatial;
render_mode unshaded;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 panel_uv = local_position.xz;
	float line_x = smoothstep(0.43, 0.49, abs(fract(panel_uv.x * 1.8 + 0.5) - 0.5));
	float line_y = smoothstep(0.43, 0.49, abs(fract(panel_uv.y * 3.2 + 0.5) - 0.5));
	float grid = max(line_x, line_y);
	vec3 cell = mix(vec3(0.025, 0.075, 0.105), vec3(0.05, 0.23, 0.28),
		fract(floor(panel_uv.x * 1.8) * 0.37 + floor(panel_uv.y * 3.2) * 0.61));
	vec3 color = mix(cell, vec3(0.52, 0.66, 0.58), grid);
	ALBEDO = color;
	EMISSION = color * 0.42;
	ROUGHNESS = 0.38;
	METALLIC = 0.48;
}

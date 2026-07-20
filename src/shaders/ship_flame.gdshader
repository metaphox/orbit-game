shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float radius = length(local_position.xz);
	float core = 1.0 - smoothstep(0.02, 0.42, radius);
	float pulse = 0.78 + 0.22 * sin(local_position.y * 19.0 - TIME * 34.0);
	vec3 amber = vec3(1.0, 0.25, 0.015);
	vec3 white_hot = vec3(1.0, 0.88, 0.48);
	vec3 color = mix(amber, white_hot, core * core);
	ALBEDO = color;
	EMISSION = color * (1.5 + core * 2.8) * pulse;
	ALPHA = clamp((0.28 + core * 0.74) * pulse, 0.0, 1.0);
}

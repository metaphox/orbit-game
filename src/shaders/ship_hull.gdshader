shader_type spatial;
render_mode unshaded;

uniform vec4 hull_color : source_color = vec4(0.88, 0.86, 0.79, 1.0);
uniform vec4 seam_color : source_color = vec4(0.14, 0.16, 0.15, 1.0);

varying vec3 local_position;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float axial = smoothstep(0.91, 0.985, abs(sin(local_position.y * 5.15)));
	float angle = atan(local_position.z, local_position.x);
	float radial = smoothstep(0.94, 0.995, abs(sin(angle * 6.0)));
	float seam = max(axial * 0.72, radial * 0.42);
	float speckle = hash21(floor((local_position.xy + local_position.z) * 18.0)) - 0.5;
	vec3 ceramic = hull_color.rgb * (0.98 + speckle * 0.035);
	ALBEDO = mix(ceramic, seam_color.rgb, seam);
	EMISSION = ceramic * 0.16 * (1.0 - seam);
	ROUGHNESS = mix(0.62, 0.84, seam);
	METALLIC = 0.12;
}

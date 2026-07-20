shader_type sky;
// Procedural starfield: no texture assets, three layered voxel-hashed star
// bands for size variety plus a faint gradient tint. Cheap enough for a
// sky pass — no noise textures, just a hash function.

// star_density controls the fraction of grid cells that light up, kept in
// the low tenths of a percent per layer: a naive high threshold at a grid
// resolution near screen-pixel density reads as static, not stars, once
// bloom picks it up (measured the hard way — see git history).
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.8;
uniform vec3 tint_low : source_color = vec3(0.02, 0.015, 0.05);
uniform vec3 tint_high : source_color = vec3(0.005, 0.01, 0.03);

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 dir = EYEDIR;
	float g = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(tint_low, tint_high, g);

	for (int i = 0; i < 3; i++) {
		// coarse grid cells (each spans several screen pixels at typical
		// FOV) so stars render as discrete points, not per-pixel aliasing
		float scale = 55.0 + float(i) * 50.0;
		vec3 cell = floor(dir * scale);
		float h = hash13(cell + float(i) * 91.7);
		float thresh = 0.9978 - star_density * 0.0015;
		if (h > thresh) {
			float b = (h - thresh) / (1.0 - thresh);
			col += vec3(b) * star_brightness * (0.6 + 0.4 * hash13(cell * 1.7));
		}
	}
	COLOR = col;
}

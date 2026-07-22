shader_type sky;
// Procedural starfield: no texture assets. Stars are placed on a coarse hash
// grid, but each is drawn as a SMALL, slightly irregular point within its cell
// (not a filled cell), tinted along the real stellar blackbody sequence -
// red -> white -> blue, skewed by warm_bias. See the starfield study / the
// star-color research for why the palette is that band and nothing else.

uniform float star_density : hint_range(0.0, 3.0) = 1.7;
uniform float star_size : hint_range(0.2, 3.0) = 1.15;
uniform float star_brightness : hint_range(0.0, 3.0) = 0.85;
uniform float color_saturation : hint_range(0.0, 3.0) = 1.4;
// -1 warm(red) .. +1 cool(blue). Kept near neutral: red dwarfs are ~3/4 of all
// stars but far too dim to see, so a believable *visible* sky is dominated by
// white/blue-white with only a minority of warm stars.
uniform float warm_bias : hint_range(-1.0, 1.0) = 0.0;
uniform vec3 tint_low : source_color = vec3(0.02, 0.015, 0.05);
uniform vec3 tint_high : source_color = vec3(0.005, 0.01, 0.03);

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Star color along the blackbody locus. u = 0 warmest (M, orange-red) .. 1
// hottest (O/B, blue). Saturation lifts the (naturally very subtle) tint.
vec3 star_color(float u, float sat) {
	vec3 warm  = vec3(1.0, 0.70, 0.42);
	vec3 white = vec3(1.0, 0.97, 0.93);
	vec3 cool  = vec3(0.62, 0.71, 1.0);
	vec3 c = u < 0.5 ? mix(warm, white, u * 2.0) : mix(white, cool, (u - 0.5) * 2.0);
	return clamp(vec3(1.0) + (c - vec3(1.0)) * sat, 0.0, 1.0);
}

void sky() {
	vec3 dir = EYEDIR;
	float grad = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(tint_low, tint_high, grad);

	// warm_bias -> exponent skewing the per-star color parameter toward warm.
	float bias_exp = pow(2.2, -warm_bias * 2.0);

	for (int i = 0; i < 3; i++) {
		float scale = 80.0 + float(i) * 34.0;  // finer grid than a filled cell -> small stars
		vec3 p = dir * scale;
		vec3 cell = floor(p);
		vec3 f = fract(p) - 0.5;
		vec3 r = hash33(cell + float(i) * 41.7);

		if (r.x > 1.0 - 0.018 * star_density) {
			vec3 off = (hash33(cell * 1.9 + float(i) * 7.3) - 0.5) * 0.24;
			vec3 stretch = 0.75 + 0.9 * hash33(cell * 3.1 + 5.0);  // per-star anisotropy = irregular speck
			float d = length((f - off) * stretch);
			float radius = 0.0021 * star_size * scale;  // ~constant on-screen size across layers
			float s = smoothstep(radius, radius * 0.2, d);
			if (s > 0.0) {
				float mag = 0.42 + 0.58 * pow(r.y, 2.2);   // power law: many faint, few bright
				float u = pow(r.z, bias_exp);
				col += star_color(u, color_saturation) * s * mag * star_brightness;
			}
		}
	}
	COLOR = col;
}

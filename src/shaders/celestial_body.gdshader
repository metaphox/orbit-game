shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Shared, texture-free surface treatment for the deliberately miniature
// solar system.  The palette is quantized and dithered so planets read like
// hand-painted mission-simulator models instead of photographic globes.
uniform int body_kind = 0; // 0 generic, 1 Earth, 2 Moon, 3 Sun, 4 Mars
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float seed = 0.0;
uniform sampler2D earth_map : source_color, filter_nearest_mipmap, repeat_enable;

varying vec3 object_direction;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(cell + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(cell + vec3(1.0, 1.0, 1.0));
	float x00 = mix(n000, n100, f.x);
	float x10 = mix(n010, n110, f.x);
	float x01 = mix(n001, n101, f.x);
	float x11 = mix(n011, n111, f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.03 + vec3(7.1, 3.7, 5.9);
		amplitude *= 0.48;
	}
	return total;
}

float crater(vec3 p, vec3 center, float radius) {
	float distance_to_center = acos(clamp(dot(p, normalize(center)), -1.0, 1.0));
	float rim = smoothstep(radius * 1.28, radius * 1.04, distance_to_center)
		* smoothstep(radius * 0.78, radius * 0.96, distance_to_center);
	float bowl = 1.0 - smoothstep(0.0, radius * 0.76, distance_to_center);
	return rim - bowl * 0.65;
}

float surface_dither(vec3 p) {
	// Stable stippling in object space: unlike screen-space noise it does not
	// shimmer when the chase camera or orbit camera moves.
	return hash31(floor((p + vec3(1.0)) * 96.0)) - 0.5;
}

float periodic_grid_line(float coordinate, float divisions, float thickness) {
	float cell = fract(coordinate * divisions);
	float distance_to_line = min(cell, 1.0 - cell);
	float antialias = max(fwidth(coordinate * divisions), 0.001);
	return 1.0 - smoothstep(thickness, thickness + antialias * 1.5, distance_to_line);
}

void vertex() {
	object_direction = normalize(VERTEX);
}

void fragment() {
	vec3 p = normalize(object_direction);
	float dither = surface_dither(p);
	vec3 color = base_color.rgb;
	float roughness = 0.88;
	vec3 emission = vec3(0.0);

	if (body_kind == 1) {
		// Unlike generated view-space noise, this fixed equirectangular map is
		// bound to the mesh UVs.  Camera motion therefore reveals a genuinely
		// different longitude instead of turning a front-facing texture card.
		vec3 mapped = texture(earth_map, vec2(UV.x, 1.0 - UV.y)).rgb;
		float coast_detail = fbm(p * 8.0 + vec3(2.0, seed, 9.0));
		float land = smoothstep(0.015, 0.11, mapped.r - mapped.b);
		color = mapped * mix(0.84, 1.12, coast_detail);

		float polar = smoothstep(0.69 + dither * 0.04, 0.83, abs(p.y)
			+ (fbm(p * 6.0 + vec3(4.0)) - 0.5) * 0.16);
		float cloud_noise = fbm(p * vec3(7.5, 12.0, 7.5) + vec3(seed, 11.0, 3.0));
		float cloud_bands = cloud_noise + sin(p.y * 26.0 + coast_detail * 7.0) * 0.065;
		float cloud = smoothstep(0.72 + dither * 0.03, 0.82, cloud_bands) * 0.58;
		color = mix(color, vec3(0.76, 0.81, 0.75), max(polar, cloud));

		// Navigation-grid paint shares the exact UV frame used by earth_map.
		// Twelve longitude cells and six latitude cells make 30-degree blocks;
		// equator and prime meridian are brighter registration references.
		float longitude_grid = periodic_grid_line(UV.x, 12.0, 0.022);
		float latitude_grid = periodic_grid_line(UV.y, 6.0, 0.022);
		float grid = max(longitude_grid, latitude_grid);
		float equator_width = max(fwidth(UV.y) * 1.5, 0.0015);
		float prime_width = max(fwidth(UV.x) * 1.5, 0.0015);
		float equator = 1.0 - smoothstep(equator_width, equator_width * 2.0,
			abs(UV.y - 0.5));
		float prime_meridian = 1.0 - smoothstep(prime_width, prime_width * 2.0,
			abs(UV.x - 0.5));
		float reference_line = max(equator, prime_meridian);
		vec3 grid_color = mix(vec3(0.08, 0.55, 0.52), vec3(0.95, 0.56, 0.12),
			reference_line);
		color = mix(color, grid_color, grid * 0.28 + reference_line * 0.34);
		roughness = mix(0.48, 0.9, land);
		emission = mapped * 0.025 + grid_color * (grid * 0.035 + reference_line * 0.07);
	} else if (body_kind == 2) {
		float grain = fbm(p * 8.5 + vec3(seed, 4.0, 9.0));
		float maria = smoothstep(0.47 + dither * 0.035, 0.58, fbm(p * 2.35
			+ vec3(9.0, seed, 1.0)));
		float crater_field = 0.0;
		crater_field += crater(p, vec3(0.72, 0.31, 0.61), 0.18);
		crater_field += crater(p, vec3(-0.42, 0.66, 0.63), 0.12);
		crater_field += crater(p, vec3(0.18, -0.79, 0.58), 0.10);
		crater_field += crater(p, vec3(-0.78, -0.12, -0.61), 0.15);
		crater_field += crater(p, vec3(0.50, 0.73, -0.47), 0.075);
		vec3 dust = mix(vec3(0.34, 0.33, 0.30), vec3(0.67, 0.64, 0.57), grain);
		color = mix(dust, vec3(0.24, 0.25, 0.25), maria * 0.72);
		color *= 1.0 + crater_field * 0.32;
		color = floor((color + dither * 0.025) * 7.0) / 7.0;
		roughness = 1.0;
		emission = color * 0.34;
	} else if (body_kind == 3) {
		float cells = fbm(p * 6.0 + vec3(seed, TIME * 0.015, 4.0));
		color = mix(vec3(0.95, 0.28, 0.035), vec3(1.0, 0.78, 0.24), cells);
		emission = color * 2.2;
		roughness = 0.7;
	} else if (body_kind == 4) {
		float terrain = fbm(p * 5.0 + vec3(seed, 2.0, 7.0));
		float dark = smoothstep(0.52 + dither * 0.04, 0.68, fbm(p * 2.0 + vec3(4.0)));
		color = mix(vec3(0.48, 0.17, 0.085), vec3(0.78, 0.39, 0.18), terrain);
		color = mix(color, vec3(0.22, 0.11, 0.085), dark * 0.55);
		float ice = smoothstep(0.82, 0.93, abs(p.y));
		color = mix(color, vec3(0.72, 0.68, 0.57), ice);
	} else {
		float facets = floor((fbm(p * 4.0 + vec3(seed)) + dither * 0.04) * 6.0) / 6.0;
		color = base_color.rgb * mix(0.58, 1.18, facets);
	}

	vec3 final_color = max(color, vec3(0.0));
	ALBEDO = final_color;
	ROUGHNESS = roughness;
	METALLIC = 0.02;
	EMISSION = emission;
}

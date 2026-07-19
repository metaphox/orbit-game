extends GutTest
## Shared helpers and reference constants for orbital math tests.
## Real Earth/Moon values: doubles handle them fine, and real-world numbers
## make errors recognizable (a LEO period should be ~5560 s, etc.).

const MU_EARTH := 3.986004418e14
const MU_MOON := 4.9048695e12
const R_LEO := 6.771e6  # ~400 km altitude


func assert_close(got: float, expected: float, rel_tol := 1e-9, msg := "") -> void:
	var scale := maxf(1.0, absf(expected))
	assert_lt(
		absf(got - expected), rel_tol * scale,
		"%s: got %s, expected %s" % [msg, got, expected])


func assert_dvec_close(got: DVec3, expected: DVec3, rel_tol := 1e-9, msg := "") -> void:
	var scale := maxf(1.0, expected.length())
	assert_lt(
		got.distance_to(expected), rel_tol * scale,
		"%s: got (%s, %s, %s), expected (%s, %s, %s)"
		% [msg, got.x, got.y, got.z, expected.x, expected.y, expected.z])


func circular_speed(mu: float, r: float) -> float:
	return sqrt(mu / r)

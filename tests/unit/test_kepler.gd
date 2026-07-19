extends "res://tests/unit/base_orbit_test.gd"


func test_elliptic_solver_satisfies_keplers_equation() -> void:
	for e in [0.0, 0.1, 0.5, 0.8, 0.9, 0.99, 0.999]:
		for i in 25:
			var m: float = -2.0 * TAU + i * (4.0 * TAU / 24.0)
			var ecc := Kepler.solve_elliptic(m, e)
			assert_close(ecc - e * sin(ecc), m, 1e-11, "e=%s M=%s" % [e, m])


func test_elliptic_solver_stays_on_input_branch() -> void:
	var e := 0.3
	assert_close(Kepler.solve_elliptic(3.0 * TAU, e), 3.0 * TAU, 1e-11)
	assert_close(Kepler.solve_elliptic(0.0, e), 0.0, 1e-11)


func test_hyperbolic_solver_satisfies_keplers_equation() -> void:
	for e in [1.05, 1.2, 1.5, 3.0, 10.0]:
		for n_val in [-50.0, -5.0, -0.3, -0.001, 0.0, 0.001, 0.3, 5.0, 50.0]:
			var h := Kepler.solve_hyperbolic(n_val, e)
			var residual: float = e * Kepler.sinh_f(h) - h - n_val
			assert_close(residual, 0.0, 1e-10, "e=%s N=%s" % [e, n_val])


func test_eccentric_true_round_trip() -> void:
	for e in [0.0, 0.4, 0.95]:
		for i in 16:
			var ecc: float = -PI + (i + 0.5) * (TAU / 16.0)
			var nu := Kepler.true_from_eccentric(ecc, e)
			assert_close(Kepler.eccentric_from_true(nu, e), ecc, 1e-11, "e=%s E=%s" % [e, ecc])


func test_hyperbolic_true_round_trip() -> void:
	for e in [1.1, 2.0, 5.0]:
		for h in [-4.0, -1.0, -0.01, 0.01, 1.0, 4.0]:
			var nu := Kepler.true_from_hyperbolic(h, e)
			assert_close(Kepler.hyperbolic_from_true(nu, e), h, 1e-9, "e=%s H=%s" % [e, h])


func test_hyperbolic_helpers() -> void:
	assert_close(Kepler.sinh_f(1.0), 1.1752011936438014)
	assert_close(Kepler.cosh_f(1.0), 1.5430806348152437)
	assert_close(Kepler.tanh_f(0.5), 0.46211715726000974)
	assert_close(Kepler.asinh_f(Kepler.sinh_f(2.3)), 2.3)
	assert_close(Kepler.atanh_f(Kepler.tanh_f(0.7)), 0.7)

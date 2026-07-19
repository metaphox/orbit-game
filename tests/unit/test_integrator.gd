extends "res://tests/unit/base_orbit_test.gd"


func test_unpowered_rk4_matches_closed_form() -> void:
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	var r0 := DVec3.new(R_LEO, 0.0, 0.0)
	var v0 := DVec3.new(0.0, v_circ * 1.05, 500.0)
	var el := OrbitElements.from_state(r0, v0, MU_EARTH, 0.0)

	var s := Integrator.BurnState.new(r0, v0, 1000.0)
	var dt := 0.5
	var quarter_period := el.period() * 0.25
	var steps := int(quarter_period / dt)
	var no_thrust := DVec3.new(1.0, 0.0, 0.0)
	for _i in steps:
		s = Integrator.rk4_step(s, MU_EARTH, no_thrust, 0.0, 0.0, dt)
	var expected := el.state_at_time(steps * dt)
	assert_dvec_close(s.r, expected.r, 1e-7, "position vs rails")
	assert_dvec_close(s.v, expected.v, 1e-7, "velocity vs rails")
	assert_close(s.mass, 1000.0, 1e-12, "mass untouched without flow")


func test_prograde_burn_raises_apoapsis_and_depletes_mass() -> void:
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	var r0 := DVec3.new(R_LEO, 0.0, 0.0)
	var v0 := DVec3.new(0.0, v_circ, 0.0)
	var before := OrbitElements.from_state(r0, v0, MU_EARTH, 0.0)

	var mass0 := 10000.0
	var thrust := 50000.0
	var isp := 320.0
	var flow := Integrator.mass_flow(thrust, isp)
	var s := Integrator.BurnState.new(r0, v0, mass0)
	var dt := 0.1
	var burn_time := 60.0
	var steps := int(burn_time / dt)
	for _i in steps:
		s = Integrator.rk4_step(s, MU_EARTH, s.v.normalized(), thrust, flow, dt)

	assert_close(s.mass, mass0 - flow * burn_time, 1e-9, "propellant depletion")
	var after := OrbitElements.from_state(s.r, s.v, MU_EARTH, burn_time)
	assert_gt(after.radius_apoapsis(), before.radius_apoapsis() + 1.0e5,
		"apoapsis raised by prograde burn")
	assert_close(after.radius_periapsis(), before.radius_periapsis(), 0.02,
		"periapsis roughly unchanged mid-LEO burn")

	# achieved delta-v tracks the rocket equation (prograde burn, small
	# gravity-loss correction expected -> compare loosely)
	var ideal_dv := Integrator.delta_v(mass0, s.mass, isp)
	var gained := s.v.length() - v0.length()
	assert_gt(ideal_dv, gained, "ideal dv bounds achieved speed gain")
	assert_gt(gained, ideal_dv * 0.8, "speed gain in the right ballpark")


func test_delta_v_helper() -> void:
	# 10 t wet / 5 t dry at Isp 300 -> 300 * 9.80665 * ln 2 = 2039.3 m/s
	assert_close(Integrator.delta_v(10000.0, 5000.0, 300.0), 2039.25, 1e-4)

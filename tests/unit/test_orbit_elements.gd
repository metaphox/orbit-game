extends "res://tests/unit/base_orbit_test.gd"


# state -> elements -> state must reproduce the input across orbit shapes,
# including the degenerate cases (circular, equatorial) and hyperbolic.
func test_round_trip_across_orbit_shapes() -> void:
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	var cases := {
		"circular equatorial": StateRV.new(
			DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, v_circ, 0.0)),
		"circular inclined": StateRV.new(
			DVec3.new(R_LEO, 0.0, 0.0),
			DVec3.new(0.0, v_circ * cos(0.9), v_circ * sin(0.9))),
		"elliptic generic": StateRV.new(
			DVec3.new(R_LEO, 1.0e6, -2.0e5),
			DVec3.new(-500.0, v_circ * 1.06, 900.0)),
		"retrograde": StateRV.new(
			DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, -v_circ * 1.02, 100.0)),
		"hyperbolic": StateRV.new(
			DVec3.new(R_LEO, 0.0, 0.0),
			DVec3.new(300.0, v_circ * 1.5, 400.0)),
		"polar": StateRV.new(
			DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, 0.0, v_circ * 1.1)),
	}
	for label: String in cases:
		var state: StateRV = cases[label]
		var el := OrbitElements.from_state(state.r, state.v, MU_EARTH, 100.0)
		var back := el.state_at_time(100.0)
		assert_dvec_close(back.r, state.r, 1e-8, "%s: position" % label)
		assert_dvec_close(back.v, state.v, 1e-8, "%s: velocity" % label)


func test_derived_quantities_for_known_leo() -> void:
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	var el := OrbitElements.from_state(
		DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, v_circ, 0.0), MU_EARTH, 0.0)
	assert_close(el.a, R_LEO, 1e-10, "semi-major axis")
	assert_close(el.e, 0.0, 1e-9, "eccentricity")
	# Kepler's third law: T = 2 pi sqrt(a^3 / mu) ~ 5544 s for 400 km LEO
	assert_close(el.period(), TAU * sqrt(pow(R_LEO, 3.0) / MU_EARTH), 1e-10, "period")


func test_propagation_returns_after_one_period() -> void:
	var state := StateRV.new(
		DVec3.new(R_LEO, 2.0e6, 1.0e6),
		DVec3.new(-800.0, 7000.0, 1200.0))
	var el := OrbitElements.from_state(state.r, state.v, MU_EARTH, 0.0)
	var back := el.state_at_time(el.period())
	assert_dvec_close(back.r, state.r, 1e-8, "position after full period")
	assert_dvec_close(back.v, state.v, 1e-8, "velocity after full period")


func test_propagation_conserves_energy_and_momentum() -> void:
	var state := StateRV.new(
		DVec3.new(R_LEO, -1.5e6, 3.0e6),
		DVec3.new(1000.0, 6800.0, -500.0))
	var el := OrbitElements.from_state(state.r, state.v, MU_EARTH, 0.0)
	var h0 := state.r.cross(state.v)
	var energy0 := state.v.length_squared() * 0.5 - MU_EARTH / state.r.length()
	for t in [13.7, 500.0, 4321.0, 90000.0, 1.0e6]:
		var s := el.state_at_time(t)
		var energy := s.v.length_squared() * 0.5 - MU_EARTH / s.r.length()
		assert_close(energy, energy0, 1e-9, "energy at t=%s" % t)
		assert_dvec_close(s.r.cross(s.v), h0, 1e-9, "ang. momentum at t=%s" % t)


func test_hyperbolic_propagation_moves_outbound() -> void:
	var v_esc := sqrt(2.0 * MU_EARTH / R_LEO)
	var el := OrbitElements.from_state(
		DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, v_esc * 1.2, 0.0), MU_EARTH, 0.0)
	assert_false(el.is_elliptic(), "should be hyperbolic")
	assert_lt(el.a, 0.0)
	var r_prev := R_LEO
	for t in [1000.0, 5000.0, 20000.0]:
		var r_now := el.state_at_time(t).r.length()
		assert_gt(r_now, r_prev, "radius grows at t=%s" % t)
		r_prev = r_now


func test_apsis_radii_and_radius_lookup() -> void:
	# 200 km x 35786 km style transfer ellipse
	var rp := 6.578e6
	var ra := 4.2164e7
	var a := (rp + ra) * 0.5
	var vp := sqrt(MU_EARTH * (2.0 / rp - 1.0 / a))
	var el := OrbitElements.from_state(
		DVec3.new(rp, 0.0, 0.0), DVec3.new(0.0, vp, 0.0), MU_EARTH, 0.0)
	assert_close(el.radius_periapsis(), rp, 1e-9)
	assert_close(el.radius_apoapsis(), ra, 1e-9)
	var nu_mid := el.true_anomaly_at_radius((rp + ra) * 0.5)
	assert_close(el.radius_at_true_anomaly(nu_mid), (rp + ra) * 0.5, 1e-9)
	assert_true(is_nan(el.true_anomaly_at_radius(ra * 2.0)), "unreachable radius is NAN")


func test_time_at_true_anomaly_finds_next_passage() -> void:
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	var el := OrbitElements.from_state(
		DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, v_circ * 1.1, 0.0), MU_EARTH, 0.0)
	var per := el.period()
	# starts at periapsis (nu = 0): next periapsis passage is one period out
	var t_next := el.time_at_true_anomaly(0.0, 1.0)
	assert_close(t_next, per, 1e-9, "next periapsis")
	var t_later := el.time_at_true_anomaly(0.0, per * 3.5)
	assert_close(t_later, per * 4.0, 1e-9, "periapsis after 3.5 periods")


func test_sample_positions_lie_on_conic() -> void:
	var el := OrbitElements.from_state(
		DVec3.new(R_LEO, 0.0, 2.0e6), DVec3.new(200.0, 7100.0, 300.0), MU_EARTH, 0.0)
	var pts := el.sample_positions(64)
	assert_eq(pts.size(), 64)
	var p := el.semi_latus_rectum()
	var h_dir := DVec3.new(R_LEO, 0.0, 2.0e6).cross(
		DVec3.new(200.0, 7100.0, 300.0)).normalized()
	for pt: DVec3 in pts:
		# every sample obeys the conic equation and stays in the orbit plane
		assert_close(pt.dot(h_dir), 0.0, 1e-6, "in plane")
		var r_len := pt.length()
		assert_true(
			r_len >= el.radius_periapsis() * 0.999999
			and r_len <= el.radius_apoapsis() * 1.000001,
			"radius within apsis bounds")
	assert_close(pts[0].length(), el.radius_periapsis(), 1e-9, "first sample at periapsis")


func test_hyperbolic_samples_clip_at_r_max() -> void:
	var v_esc := sqrt(2.0 * MU_EARTH / R_LEO)
	var el := OrbitElements.from_state(
		DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, v_esc * 1.3, 0.0), MU_EARTH, 0.0)
	var soi := 9.24e8
	var pts := el.sample_positions(33, soi)
	for pt: DVec3 in pts:
		assert_lt(pt.length(), soi * 1.000001, "sample inside r_max")
	assert_close(pts[0].length(), soi, 1e-6, "arc starts at r_max")
	assert_close(pts[32].length(), soi, 1e-6, "arc ends at r_max")


func test_xz_plane_crossings_empty_for_equatorial_orbit() -> void:
	# starting orbit convention: r=(R,0,0), v=(0,0,-v) -> h=(0,+,0), lies
	# entirely in the xz-plane already, no distinct crossing points
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	var el := OrbitElements.from_state(
		DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, 0.0, -v_circ), MU_EARTH, 0.0)
	assert_eq(el.xz_plane_crossings(), [], "equatorial orbit has no plane crossings")


func test_xz_plane_crossings_are_on_the_plane_and_correctly_labeled() -> void:
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	for tilt in [0.3, 1.1, 2.4, -0.8]:
		var v := DVec3.new(0.0, v_circ * sin(tilt), -v_circ * cos(tilt))
		var el := OrbitElements.from_state(DVec3.new(R_LEO, 0.0, 0.0), v, MU_EARTH, 0.0)
		var crossings: Array = el.xz_plane_crossings()
		assert_eq(crossings.size(), 2, "tilt=%s: two crossings" % tilt)
		var ascending_nu: float = crossings[0]
		var descending_nu: float = crossings[1]

		var r_asc := el.state_at_true_anomaly(ascending_nu).r
		var r_desc := el.state_at_true_anomaly(descending_nu).r
		assert_close(r_asc.y, 0.0, 1e-6, "tilt=%s: ascending point on the plane" % tilt)
		assert_close(r_desc.y, 0.0, 1e-6, "tilt=%s: descending point on the plane" % tilt)

		# confirm labeling by sampling just before/after each crossing
		var h := 0.01
		var y_before_asc := el.state_at_true_anomaly(ascending_nu - h).r.y
		var y_after_asc := el.state_at_true_anomaly(ascending_nu + h).r.y
		assert_lt(y_before_asc, 0.0, "tilt=%s: below the plane before ascending" % tilt)
		assert_gt(y_after_asc, 0.0, "tilt=%s: above the plane after ascending" % tilt)

		var y_before_desc := el.state_at_true_anomaly(descending_nu - h).r.y
		var y_after_desc := el.state_at_true_anomaly(descending_nu + h).r.y
		assert_gt(y_before_desc, 0.0, "tilt=%s: above the plane before descending" % tilt)
		assert_lt(y_after_desc, 0.0, "tilt=%s: below the plane after descending" % tilt)


func test_xz_plane_crossings_match_brute_force_scan() -> void:
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	var el := OrbitElements.from_state(
		DVec3.new(R_LEO, 1.0e6, -3.0e5),
		DVec3.new(-400.0, v_circ * 0.35, v_circ * 0.9), MU_EARTH, 0.0)
	var crossings: Array = el.xz_plane_crossings()
	assert_eq(crossings.size(), 2)
	for nu: float in crossings:
		# scan a small bracket around the analytic answer for a sign change,
		# confirming it's a genuine zero-crossing and not off by a stray pi
		var y_minus := el.state_at_true_anomaly(nu - 0.02).r.y
		var y_plus := el.state_at_true_anomaly(nu + 0.02).r.y
		assert_true(sign(y_minus) != sign(y_plus), "nu=%s brackets a real sign change" % nu)

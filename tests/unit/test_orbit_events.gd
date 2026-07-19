extends "res://tests/unit/base_orbit_test.gd"

const D_MOON := 3.844e8
const SOI_MOON := 6.6e7
const R_EARTH := 6.371e6


func _transfer_ellipse(ra: float) -> OrbitElements:
	var a := (R_LEO + ra) * 0.5
	var vp := sqrt(MU_EARTH * (2.0 / R_LEO - 1.0 / a))
	return OrbitElements.from_state(
		DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, vp, 0.0), MU_EARTH, 0.0)


## Step until |r| crosses target, in the given direction. Ground truth for
## the analytic crossing times.
func _brute_force_radius_crossing(
		el: OrbitElements, target: float, outbound: bool, dt: float,
		t_max: float) -> float:
	var t := 0.0
	var prev := el.state_at_time(0.0).r.length()
	while t < t_max:
		t += dt
		var now := el.state_at_time(t).r.length()
		if outbound and prev < target and now >= target:
			return t
		if not outbound and prev > target and now <= target:
			return t
		prev = now
	return NAN


func test_radius_crossing_matches_brute_force() -> void:
	var el := _transfer_ellipse(1.0e8)
	var target := 5.0e7
	var dt := 1.0
	var t_out := OrbitEvents.radius_crossing_time(el, target, 0.0, true)
	var t_in := OrbitEvents.radius_crossing_time(el, target, 0.0, false)
	assert_close(t_out, _brute_force_radius_crossing(el, target, true, dt, 1e6), 1e-4,
		"outbound vs brute force")
	assert_close(t_in, _brute_force_radius_crossing(el, target, false, dt, 1e6), 1e-4,
		"inbound vs brute force")
	assert_close(el.state_at_time(t_out).r.length(), target, 1e-9, "outbound radius exact")
	assert_close(el.state_at_time(t_in).r.length(), target, 1e-9, "inbound radius exact")
	assert_gt(el.state_at_time(t_out).r.dot(el.state_at_time(t_out).v), 0.0, "outbound = ascending")
	assert_lt(el.state_at_time(t_in).r.dot(el.state_at_time(t_in).v), 0.0, "inbound = descending")


func test_unreachable_radius_is_nan() -> void:
	var el := _transfer_ellipse(1.0e8)
	assert_true(is_nan(OrbitEvents.radius_crossing_time(el, 2.0e8, 0.0, true)))
	assert_true(is_nan(OrbitEvents.impact_time(el, 1.0e6, 0.0)), "periapsis above target")


func test_impact_time_on_deorbit_ellipse() -> void:
	# apoapsis at LEO, periapsis buried at 0.9 earth radii -> must impact
	var ra := R_LEO
	var rp := R_EARTH * 0.9
	var a := (rp + ra) * 0.5
	var va := sqrt(MU_EARTH * (2.0 / ra - 1.0 / a))
	var el := OrbitElements.from_state(
		DVec3.new(ra, 0.0, 0.0), DVec3.new(0.0, -va, 0.0), MU_EARTH, 0.0)
	var t_hit := OrbitEvents.impact_time(el, R_EARTH, 0.0)
	assert_false(is_nan(t_hit), "impact exists")
	assert_close(el.state_at_time(t_hit).r.length(), R_EARTH, 1e-9, "at surface")
	assert_lt(el.state_at_time(t_hit).r.dot(el.state_at_time(t_hit).v), 0.0, "descending")


func test_soi_exit_on_escape_trajectory() -> void:
	var v_esc := sqrt(2.0 * MU_EARTH / R_LEO)
	var el := OrbitElements.from_state(
		DVec3.new(R_LEO, 0.0, 0.0), DVec3.new(0.0, v_esc * 1.1, 0.0), MU_EARTH, 0.0)
	var soi_earth := 9.24e8
	var t_exit := OrbitEvents.soi_exit_time(el, soi_earth, 0.0)
	assert_false(is_nan(t_exit))
	assert_close(el.state_at_time(t_exit).r.length(), soi_earth, 1e-9, "at SOI radius")
	# once past, the event is behind us: hyperbolic pass never repeats
	assert_true(is_nan(OrbitEvents.soi_exit_time(el, soi_earth, t_exit + 1.0)))


func test_apsis_times() -> void:
	var el := _transfer_ellipse(1.0e8)
	var per := el.period()
	assert_close(OrbitEvents.apoapsis_time(el, 0.0), per * 0.5, 1e-9, "first apoapsis")
	assert_close(OrbitEvents.periapsis_time(el, 1.0), per, 1e-9, "next periapsis")
	assert_close(OrbitEvents.apoapsis_time(el, per), per * 1.5, 1e-9, "second apoapsis")


func test_child_soi_entry_at_phased_encounter() -> void:
	var ship := _transfer_ellipse(D_MOON + 1.0e7)
	var t_apo: float = ship.period() * 0.5
	# place the Moon so it sits at the ship's apoapsis direction (-X) at
	# arrival time
	var n_moon := sqrt(MU_EARTH / pow(D_MOON, 3.0))
	var theta0 := PI - n_moon * t_apo
	var v_moon := circular_speed(MU_EARTH, D_MOON)
	var moon := OrbitElements.from_state(
		DVec3.new(D_MOON * cos(theta0), D_MOON * sin(theta0), 0.0),
		DVec3.new(-v_moon * sin(theta0), v_moon * cos(theta0), 0.0),
		MU_EARTH, 0.0)
	var t_entry := OrbitEvents.child_soi_entry_time(
		ship, moon, SOI_MOON, 0.0, t_apo + 2.0e5, 3600.0)
	assert_false(is_nan(t_entry), "encounter found")
	var d := ship.state_at_time(t_entry).r.distance_to(moon.state_at_time(t_entry).r)
	assert_close(d, SOI_MOON, 1e-6, "distance equals SOI at entry")
	var d_later := ship.state_at_time(t_entry + 60.0).r.distance_to(
		moon.state_at_time(t_entry + 60.0).r)
	assert_lt(d_later, d, "moving deeper into SOI after entry")


func test_no_encounter_when_moon_out_of_phase() -> void:
	var ship := _transfer_ellipse(D_MOON + 1.0e7)
	var t_apo: float = ship.period() * 0.5
	var v_moon := circular_speed(MU_EARTH, D_MOON)
	# moon parked 90 degrees away from the arrival direction
	var moon := OrbitElements.from_state(
		DVec3.new(0.0, D_MOON, 0.0), DVec3.new(-v_moon, 0.0, 0.0), MU_EARTH, 0.0)
	var n_moon := sqrt(MU_EARTH / pow(D_MOON, 3.0))
	var quarter_moon_period: float = 0.25 * TAU / n_moon
	var t_entry := OrbitEvents.child_soi_entry_time(
		ship, moon, SOI_MOON, 0.0, minf(t_apo, quarter_moon_period), 3600.0)
	assert_true(is_nan(t_entry), "no SOI entry when badly phased")

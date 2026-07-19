extends "res://tests/unit/base_orbit_test.gd"
## M1 capstone: a full trans-lunar-injection pipeline using only the core
## library. LEO -> prograde impulse -> coast on rails -> Moon SOI entry ->
## frame handoff -> sane hyperbolic flyby elements around the Moon.

const D_MOON := 3.844e8
const SOI_MOON := 6.6e7
const R_MOON := 1.7374e6


func test_tli_to_moon_soi_handoff() -> void:
	# --- parking orbit
	var v_circ := circular_speed(MU_EARTH, R_LEO)
	var r0 := DVec3.new(R_LEO, 0.0, 0.0)
	var park := OrbitElements.from_state(
		r0, DVec3.new(0.0, v_circ, 0.0), MU_EARTH, 0.0)
	assert_close(park.e, 0.0, 1e-9, "parking orbit circular")

	# --- prograde impulse at t=0 onto a transfer ellipse reaching the Moon
	var ra := D_MOON + 1.0e7
	var a := (R_LEO + ra) * 0.5
	var vp := sqrt(MU_EARTH * (2.0 / R_LEO - 1.0 / a))
	var tli_dv := vp - v_circ
	assert_between(tli_dv, 3000.0, 3300.0, "real-scale TLI costs ~3.1 km/s")
	var transfer := OrbitElements.from_state(
		r0, DVec3.new(0.0, vp, 0.0), MU_EARTH, 0.0)
	var t_apo: float = transfer.period() * 0.5

	# --- Moon phased to arrive at the ship's apoapsis direction, with a
	# small lead so the ship flies past instead of hitting dead center
	var n_moon := sqrt(MU_EARTH / pow(D_MOON, 3.0))
	var theta0 := PI - n_moon * t_apo + 0.03
	var v_moon := circular_speed(MU_EARTH, D_MOON)
	var moon := OrbitElements.from_state(
		DVec3.new(D_MOON * cos(theta0), D_MOON * sin(theta0), 0.0),
		DVec3.new(-v_moon * sin(theta0), v_moon * cos(theta0), 0.0),
		MU_EARTH, 0.0)

	# --- coast: find SOI entry
	var t_entry := OrbitEvents.child_soi_entry_time(
		transfer, moon, SOI_MOON, 0.0, t_apo + 2.0e5, 3600.0)
	assert_false(is_nan(t_entry), "SOI entry found")
	assert_between(t_entry, t_apo * 0.7, t_apo * 1.1, "arrival near apoapsis time")

	# --- handoff into the Moon frame
	var ship_parent := transfer.state_at_time(t_entry)
	var rel := Frames.to_child_frame(ship_parent, moon, t_entry)
	assert_close(rel.r.length(), SOI_MOON, 1e-6, "handoff at SOI radius")
	assert_lt(rel.r.dot(rel.v), 0.0, "inbound at entry")

	var flyby := OrbitElements.from_state(rel.r, rel.v, MU_MOON, t_entry)
	assert_gt(flyby.e, 1.0, "arrival speed makes the lunar orbit hyperbolic")
	assert_gt(flyby.radius_periapsis(), R_MOON, "flyby clears the surface")
	assert_lt(flyby.radius_periapsis(), SOI_MOON, "periapsis inside the SOI")

	# --- round trip back to the parent frame stays exact
	var back := Frames.to_parent_frame(rel, moon, t_entry)
	assert_dvec_close(back.r, ship_parent.r, 1e-12, "handoff reversible")

	# --- and the closest-approach time is on the flyby's clock
	var t_peri := OrbitEvents.periapsis_time(flyby, t_entry)
	assert_false(is_nan(t_peri), "periapsis ahead")
	assert_gt(t_peri, t_entry, "periapsis after entry")
	var d_peri: float = Frames.to_child_frame(
		transfer.state_at_time(t_peri), moon, t_peri).r.length()
	# two-body flyby vs earth-frame coast diverge slowly; same ballpark
	assert_between(d_peri, 0.0, SOI_MOON * 0.5, "close approach well inside SOI")

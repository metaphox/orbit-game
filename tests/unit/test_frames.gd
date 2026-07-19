extends "res://tests/unit/base_orbit_test.gd"

const D_MOON := 3.844e8


func _moon_elements() -> OrbitElements:
	var v_circ := circular_speed(MU_EARTH, D_MOON)
	return OrbitElements.from_state(
		DVec3.new(D_MOON, 0.0, 0.0), DVec3.new(0.0, v_circ, 0.0), MU_EARTH, 0.0)


func test_child_parent_round_trip() -> void:
	var moon := _moon_elements()
	var ship := StateRV.new(
		DVec3.new(3.0e8, 1.2e8, 5.0e6), DVec3.new(300.0, 800.0, -40.0))
	var t := 123456.0
	var rel := Frames.to_child_frame(ship, moon, t)
	var back := Frames.to_parent_frame(rel, moon, t)
	assert_dvec_close(back.r, ship.r, 1e-12, "position round trip")
	assert_dvec_close(back.v, ship.v, 1e-12, "velocity round trip")


func test_child_frame_is_relative_state() -> void:
	var moon := _moon_elements()
	var t := 98765.0
	var moon_state := moon.state_at_time(t)
	var offset := DVec3.new(2.0e7, -1.0e7, 3.0e6)
	var rel_vel := DVec3.new(-150.0, 90.0, 10.0)
	var ship := StateRV.new(
		moon_state.r.add(offset), moon_state.v.add(rel_vel))
	var rel := Frames.to_child_frame(ship, moon, t)
	assert_dvec_close(rel.r, offset, 1e-12, "relative position")
	assert_dvec_close(rel.v, rel_vel, 1e-12, "relative velocity")

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


# --- Body-graph frames (depth-independent) ---------------------------------

const MU_SUN := 1.327e20


## Sun (root) -> Earth (child of Sun) -> Moon (child of Earth).
func _hierarchy() -> Dictionary:
	var sun := BodyDef.new()
	sun.name = "SUN"
	sun.mu = MU_SUN
	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = MU_EARTH
	earth.parent = sun
	earth.orbit_radius = 4.0e7
	earth.orbit_phase_deg = 0.0
	var moon := BodyDef.new()
	moon.name = "MOON"
	moon.mu = MU_MOON
	moon.parent = earth
	moon.orbit_radius = 3.844e6
	moon.orbit_phase_deg = 37.0  # off-axis so root vs parent frames differ visibly
	return {"sun": sun, "earth": earth, "moon": moon}


func test_root_position_recurses_to_the_origin() -> void:
	var h := _hierarchy()
	var t := 8000.0
	assert_dvec_close(Frames.root_position(h.sun, t), DVec3.new(), 1e-9, "root sits at the origin")
	# The moon's root position is its planet's plus its own parent-relative offset.
	var expected: DVec3 = h.earth.position_at(t).add(h.moon.orbit.state_at_time(t).r)
	assert_dvec_close(Frames.root_position(h.moon, t), expected, 1e-6, "moon root = earth + moon-about-earth")


func test_position_relative_to_is_exact_at_depth() -> void:
	var h := _hierarchy()
	var t := 12345.0
	# Moon measured from Earth (its direct parent) is exactly its orbit vector.
	assert_dvec_close(
		Frames.position_relative_to(h.moon, h.earth, t),
		h.moon.orbit.state_at_time(t).r, 1e-6, "moon-from-earth == moon's parent-relative orbit")
	# Measured from the root, it equals the full root-frame position.
	assert_dvec_close(
		Frames.position_relative_to(h.moon, h.sun, t),
		Frames.root_position(h.moon, t), 1e-6, "from-root == root position")
	# Passing null origin also means the root.
	assert_dvec_close(
		Frames.position_relative_to(h.moon, null, t),
		Frames.root_position(h.moon, t), 1e-6, "null origin == root")


func test_point_relative_to_offsets_a_root_point() -> void:
	var h := _hierarchy()
	var t := 500.0
	var p := DVec3.new(5.0e7, 1.0e6, -2.0e7)  # some root-frame point
	assert_dvec_close(
		Frames.point_relative_to(p, h.earth, t),
		p.sub(h.earth.position_at(t)), 1e-6, "point minus origin's root position")


func test_root_of_walks_to_the_top() -> void:
	var h := _hierarchy()
	assert_eq(Frames.root_of(h.moon), h.sun, "moon's root is the sun")
	assert_eq(Frames.root_of(h.earth), h.sun, "earth's root is the sun")
	assert_eq(Frames.root_of(h.sun), h.sun, "the root's root is itself")

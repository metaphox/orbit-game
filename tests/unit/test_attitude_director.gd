extends "res://tests/unit/base_orbit_test.gd"
## The GUIDANCE attitude director projects world velocity into the ship's local
## frame to place the prograde marker. Pin that math (no rendering): off-prograde
## magnitude matches ShipSim.off_prograde_angle(), and the on-ring direction points
## the expected way.


func _ship(attitude: Basis, v: Vector3) -> ShipSim:
	var s := ShipSim.new()
	s.attitude = attitude
	s.v = DVec3.new(v.x, v.y, v.z)
	return s


func test_off_prograde_magnitude_matches_the_sim() -> void:
	var director := AttitudeDirector.new()
	add_child_autofree(director)
	# nose along -Z, velocity 30° off in the x-z plane
	var att := Basis.IDENTITY
	var v := Vector3(sin(deg_to_rad(30.0)), 0.0, -cos(deg_to_rad(30.0))) * 500.0
	var ship := _ship(att, v)
	director.set_attitude(ship)
	assert_true(director.velocity_valid, "a moving ship has a valid prograde")
	assert_almost_eq(director.off_prograde, ship.off_prograde_angle(), 1e-5,
		"director's off-prograde equals the sim's")
	assert_almost_eq(director.off_prograde, deg_to_rad(30.0), 1e-5, "and it's the 30° we set")


func test_marker_direction_follows_velocity_in_the_ship_frame() -> void:
	var director := AttitudeDirector.new()
	add_child_autofree(director)
	# velocity to the ship's right (+X local) -> marker points right (+x screen)
	director.set_attitude(_ship(Basis.IDENTITY, Vector3(500.0, 0.0, 0.0)))
	assert_almost_eq(director.prograde_dir.x, 1.0, 1e-5, "velocity to starboard -> marker right")
	assert_almost_eq(director.prograde_dir.y, 0.0, 1e-5, "no vertical component")

	# velocity along ship-up (+Y local) -> marker points up (screen -y)
	director.set_attitude(_ship(Basis.IDENTITY, Vector3(0.0, 500.0, 0.0)))
	assert_almost_eq(director.prograde_dir.y, -1.0, 1e-5, "velocity up -> marker up (screen -y)")


func test_prograde_alignment_parks_marker_at_center() -> void:
	var director := AttitudeDirector.new()
	add_child_autofree(director)
	# velocity straight along the nose (-Z): off-prograde ~0, marker at center
	director.set_attitude(_ship(Basis.IDENTITY, Vector3(0.0, 0.0, -500.0)))
	assert_almost_eq(director.off_prograde, 0.0, 1e-5, "nose on prograde reads zero angle")


func test_zero_velocity_hides_the_marker() -> void:
	var director := AttitudeDirector.new()
	add_child_autofree(director)
	director.set_attitude(_ship(Basis.IDENTITY, Vector3.ZERO))
	assert_false(director.velocity_valid, "no velocity -> no prograde marker")

extends "res://tests/unit/base_orbit_test.gd"
## Rotational inertia: angular momentum persists until countered, the kill-rotation
## brake nulls a tumble, SAS holds settle without ringing, and a fuel-laden ship
## turns more sluggishly than a drained one (mass is felt).

const DT := 1.0 / 60.0


func _ship() -> ShipSim:
	var ship := ShipSim.new()
	ship.setup(Campaign.level_at(3))  # translunar: has propellant + SAS
	return ship


func test_momentum_persists_after_the_command_stops() -> void:
	var ship := _ship()
	for i in 30:
		ship.integrate_rotation(Vector3(1.0, 0.0, 0.0), DT)  # pitch
	assert_gt(ship.angular_velocity.x, 0.05, "spin builds up while commanded")
	var spin := ship.angular_velocity.x
	for i in 60:
		ship.integrate_rotation(Vector3.ZERO, DT)  # release the stick
	assert_almost_eq(ship.angular_velocity.x, spin, 1e-6,
		"a zero command does NOT damp: the ship keeps spinning (real momentum)")


func test_angular_velocity_is_capped() -> void:
	var ship := _ship()
	for i in 600:
		ship.integrate_rotation(Vector3(0.0, 0.0, 1.0), DT)  # roll hard, forever
	assert_almost_eq(ship.angular_velocity.z, ShipSim.MAX_ANGULAR_VEL.z, 1e-6,
		"roll rate saturates at the ceiling")


func test_kill_rotation_brakes_a_tumble_to_rest() -> void:
	var ship := _ship()
	for i in 30:
		ship.integrate_rotation(Vector3(0.7, -0.5, 0.8), DT)  # spin up on all axes
	assert_gt(ship.angular_velocity.length(), 0.05, "the ship is tumbling")
	ship.sas_mode = ShipSim.SasMode.STABILITY
	for i in 300:
		ship.integrate_rotation(ship.sas_command(), DT)
	assert_lt(ship.angular_velocity.length(), 0.02, "kill-rotation nulls the tumble")


func test_sas_hold_settles_on_target_without_ringing() -> void:
	# NORMAL points at the orbit normal, which is fixed during a coast (zero
	# feed-forward), so this isolated hold should slew there and come to rest.
	var ship := _ship()
	ship.sas_mode = ShipSim.SasMode.NORMAL
	var target := ship.sas_target_dir()
	for i in 900:
		ship.integrate_rotation(ship.sas_command(), DT)
	assert_gt(ship.forward_dir().dot(target), 0.999, "nose arrives at the orbit normal")
	assert_lt(ship.angular_velocity.length(), 0.02, "and it settles there, not ringing")


func test_fuel_laden_ship_turns_more_sluggishly() -> void:
	var ship := _ship()
	var laden := ship.max_angular_accel()
	ship.prop_mass = 0.0  # burn the tank dry
	var drained := ship.max_angular_accel()
	assert_lt(laden.x, drained.x, "a full tank means less angular authority than an empty one")

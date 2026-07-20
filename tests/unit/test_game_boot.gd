extends "res://tests/unit/base_orbit_test.gd"
## Headless integration checks: the main scene boots, the sim loop runs,
## and the burn -> coast cycle behaves through the real game orchestrator.


func _boot() -> Node:
	var scene: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(scene)
	return scene


func test_scene_boots_and_ship_coasts_on_rails() -> void:
	var game := _boot()
	simulate(game, 30, 1.0 / 60.0)
	var ship: ShipSim = game.ship
	assert_not_null(ship, "ship exists")
	assert_eq(ship.flight_state, ShipSim.FlightState.COASTING, "starts coasting")
	assert_close(ship.r.length(), game.level.start_radius, 1e-9, "on start orbit")
	assert_gt(game.sim_time, 0.4, "sim clock advances")


func test_burn_changes_orbit_and_depletes_propellant() -> void:
	var game := _boot()
	var ship: ShipSim = game.ship
	var prop0: float = ship.prop_mass
	var ap0: float = ship.elements.radius_apoapsis()

	ship.throttle = 1.0  # prograde: nose starts aligned with velocity
	simulate(game, 180, 1.0 / 60.0)  # 3 s of burn
	assert_eq(ship.flight_state, ShipSim.FlightState.BURNING, "burning while throttled")
	assert_lt(ship.prop_mass, prop0, "propellant consumed")
	assert_gt(ship.dv_used(), 1.0, "delta-v accounted")

	ship.throttle = 0.0
	simulate(game, 5, 1.0 / 60.0)
	assert_eq(ship.flight_state, ShipSim.FlightState.COASTING, "refit after cutoff")
	assert_gt(ship.elements.radius_apoapsis(), ap0 + 1000.0, "apoapsis raised")
	assert_close(
		ship.elements.radius_periapsis(), game.level.start_radius, 0.01,
		"periapsis near start radius after short prograde burn")


func test_win_on_matched_orbit() -> void:
	var game := _boot()
	var ship: ShipSim = game.ship
	# teleport the ship onto the target orbit and let the check fire
	var target: float = game.level.objective.target_radius
	ship.elements = OrbitElements.from_state(
		DVec3.new(target, 0.0, 0.0),
		DVec3.new(0.0, 0.0, -sqrt(game.level.body.mu / target)),
		game.level.body.mu, game.sim_time)
	simulate(game, 5, 1.0 / 60.0)
	assert_eq(game.phase, game.Phase.WON, "objective triggers win")


func test_fail_on_impact() -> void:
	var game := _boot()
	var ship: ShipSim = game.ship
	# drop the ship onto a plunging trajectory
	ship.elements = OrbitElements.from_state(
		DVec3.new(game.level.start_radius, 0.0, 0.0),
		DVec3.new(-800.0, 0.0, -100.0),
		game.level.body.mu, game.sim_time)
	simulate(game, 600, 1.0 / 60.0)
	assert_eq(game.phase, game.Phase.FAILED, "impact triggers fail")


func test_fail_on_degenerate_orbit() -> void:
	var game := _boot()
	var ship: ShipSim = game.ship
	# purely radial trajectory: r parallel to v, zero angular momentum -
	# unrecoverable, but must fail cleanly with a diagnostic rather than
	# corrupting state with NaN.
	ship.elements = OrbitElements.from_state(
		DVec3.new(game.level.start_radius, 0.0, 0.0), DVec3.new(500.0, 0.0, 0.0),
		game.level.body.mu, game.sim_time)
	assert_false(ship.elements.is_valid, "sanity: this state is actually degenerate")
	simulate(game, 5, 1.0 / 60.0)
	assert_eq(game.phase, game.Phase.FAILED, "degenerate orbit triggers a diagnosed fail")
	assert_true(
		game.hud.center_label.text.contains("ORBIT TRAJECTORY DEGENERATE"),
		"fail reason is shown, not a silent/frozen HUD")

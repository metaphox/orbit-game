extends "res://tests/unit/base_orbit_test.gd"
## M3 checks: live SOI handoffs in ShipSim, the TransferCapture objective,
## and event-clamped rails warp through the real game loop.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


## Transfer ellipse from the level-2 parking radius aimed to meet the moon
## at apoapsis, given the level's starting moon phase.
func _phased_transfer(level: LevelDef, t0: float) -> OrbitElements:
	var earth := level.body
	var moon: BodyDef = level.moons[0]
	var d: float = moon.orbit.a
	var r0: float = level.start_radius
	var a := (r0 + d) * 0.5
	var transfer_time := PI * sqrt(pow(a, 3.0) / earth.mu)
	var n_moon := moon.orbit.mean_motion()
	# moon angle now + travel during transfer = burn angle + PI
	var theta_now := 2.0 + n_moon * t0  # level 2 starts the moon at 2.0 rad
	var phi := theta_now + n_moon * transfer_time - PI
	var vp := sqrt(earth.mu * (2.0 / r0 - 1.0 / a))
	return OrbitElements.from_state(
		DVec3.new(r0 * cos(phi), 0.0, -r0 * sin(phi)),
		DVec3.new(-vp * sin(phi), 0.0, -vp * cos(phi)),
		earth.mu, t0)


func test_soi_entry_handoff_in_ship_sim() -> void:
	var level := Level02.make()
	var ship := ShipSim.new()
	ship.setup(level)
	var moon: BodyDef = level.moons[0]
	ship.elements = OrbitElements.from_state(
		DVec3.new(level.start_radius, 0.0, 0.0),
		DVec3.new(0.0, 0.0, -sqrt(level.body.mu / level.start_radius)),
		level.body.mu, 0.0)
	ship.elements = _phased_transfer(level, 0.0)

	var t := 0.0
	var note := ""
	while t < 1.0e5 and note == "":
		t += 30.0
		ship.advance_to(t)
		note = ship.apply_soi_transitions(t)
	assert_eq(note, "ENTERING MOON SOI", "handoff fires")
	assert_eq(ship.body, moon, "parent is now the moon")
	# 30 s polling steps overshoot the boundary by at most v_rel * 30
	assert_between(ship.r.length(), moon.soi_radius * 0.97, moon.soi_radius * 1.001,
		"handoff happened near the boundary")
	assert_true(is_finite(ship.elements.a), "lunar elements are sane")


func test_soi_exit_handoff_back_to_earth() -> void:
	var level := Level02.make()
	var ship := ShipSim.new()
	ship.setup(level)
	var moon: BodyDef = level.moons[0]
	ship.body = moon
	# hyperbolic outbound, just inside the SOI (radial + tangential mix;
	# purely radial would be a degenerate zero-angular-momentum orbit)
	var start_r := moon.soi_radius * 0.9
	var v_esc := sqrt(2.0 * moon.mu / start_r)
	ship.elements = OrbitElements.from_state(
		DVec3.new(start_r, 0.0, 0.0), DVec3.new(v_esc * 1.2, 0.0, -v_esc * 0.5),
		moon.mu, 0.0)

	var t := 0.0
	var note := ""
	while t < 5.0e4 and note == "":
		t += 20.0
		ship.advance_to(t)
		note = ship.apply_soi_transitions(t)
	assert_eq(note, "LEAVING MOON SOI", "exit handoff fires")
	assert_eq(ship.body, level.body, "parent is earth again")
	assert_gt(ship.r.length(), moon.orbit.a * 0.7, "state re-expressed at lunar distance")


func test_transfer_capture_objective() -> void:
	var level := Level02.make()
	var objective: TransferCaptureObjective = level.objective
	var ship := ShipSim.new()
	ship.setup(level)
	assert_false(objective.is_met(ship), "not met in LEO")

	var moon: BodyDef = level.moons[0]
	ship.body = moon
	var r_orbit := 30000.0
	ship.elements = OrbitElements.from_state(
		DVec3.new(r_orbit, 0.0, 0.0),
		DVec3.new(0.0, 0.0, -sqrt(moon.mu / r_orbit)), moon.mu, 0.0)
	ship.advance_to(ship.last_time + 1.0)
	assert_true(objective.is_met(ship), "met in a low circular lunar orbit")

	var v_esc := sqrt(2.0 * moon.mu / r_orbit)
	ship.elements = OrbitElements.from_state(
		DVec3.new(r_orbit, 0.0, 0.0), DVec3.new(0.0, 0.0, -v_esc * 1.1),
		moon.mu, ship.last_time)
	ship.advance_to(ship.last_time + 1.0)
	assert_false(objective.is_met(ship), "not met on a hyperbolic flyby")


func test_rails_warp_clamps_to_soi_boundary() -> void:
	GameRootScript.level_index = 1
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	var ship: ShipSim = game.ship
	ship.elements = _phased_transfer(game.level, game.sim_time)
	ship.revision += 1  # elements swapped under the sim: invalidate caches

	game.warp_index = game.WARP_STEPS.size() - 1  # 2500x, ~41 s per tick
	var moon: BodyDef = game.level.moons[0]
	var frames := 0
	while ship.body != moon and frames < 3000:
		simulate(game, 1, 1.0 / 60.0)
		frames += 1
		if game.warp_index == 0 and ship.body != moon:
			game.warp_index = game.WARP_STEPS.size() - 1  # re-warp after drops
	assert_eq(ship.body, moon, "reached the moon under max warp")
	# the event clamp must land the handoff ON the boundary, not 41 s deep:
	# at ~120 m/s relative speed one 1/60 s tick penetrates ~2 m plus the
	# 1 ms landing nudge, so within a few meters of the SOI radius
	assert_between(ship.r.length(), moon.soi_radius - 200.0, moon.soi_radius + 1.0,
		"handoff at the boundary, not skipped past it")
	assert_eq(game.phase, game.Phase.FLYING, "still flying after handoff")

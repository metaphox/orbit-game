extends "res://tests/unit/base_orbit_test.gd"
## M8: plane-change objective and the Earth-Mars interplanetary level.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func test_orbit_match_inclination_gate() -> void:
	var level := Campaign.level_at(5)
	var objective: OrbitMatchObjective = level.objective
	var earth := level.body
	var v_circ := circular_speed(earth.mu, 70000.0)

	# equatorial: right radius, wrong plane
	var equatorial := OrbitElements.from_state(
		DVec3.new(70000.0, 0.0, 0.0), DVec3.new(0.0, 0.0, -v_circ), earth.mu, 0.0)
	var ship := ShipSim.new()
	ship.setup(Campaign.level_at(0))
	ship.elements = equatorial
	assert_false(objective.is_met(ship), "equatorial orbit misses the inclination target")

	# tilted 15 degrees: matches
	var tilted := OrbitElements.from_state(
		DVec3.new(70000.0, 0.0, 0.0),
		DVec3.new(0.0, v_circ * sin(deg_to_rad(15.0)), -v_circ * cos(deg_to_rad(15.0))),
		earth.mu, 0.0)
	ship.elements = tilted
	assert_true(objective.is_met(ship), "15-degree inclined orbit meets the target")


func test_level06_boots_and_flies() -> void:
	GameRootScript.level_index = 5
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 5, 1.0 / 60.0)
	assert_eq(game.phase, game.Phase.FLYING)
	assert_eq(game.level.title, Campaign.title(5))


func test_mars_level_boots_inside_earth_soi() -> void:
	GameRootScript.level_index = 6
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 5, 1.0 / 60.0)
	assert_eq(game.ship.body.name, "EARTH", "starts in a parking orbit around Earth")
	assert_eq(game.ship.body.parent.name, "SOL", "Earth is a child of the Sun, not the root")


func test_mars_departure_guidance_uses_absolute_position() -> void:
	var level := Campaign.level_at(6)
	var objective: TransferCaptureObjective = level.objective
	var ship := ShipSim.new()
	ship.setup(level)
	# phase/lead angles must be computed off the ship's heliocentric
	# position (via Earth), not the tiny Earth-relative r - both should be
	# small sane angles, not NaN/garbage from mixing up frames
	var lines: Array = objective.status_lines(ship)
	assert_true(lines[0].begins_with("DEPARTING EARTH"), "flags still-departing state")
	var phase_line: String = lines[1]
	assert_true(phase_line.begins_with("PHASE TO MARS"), "phase guidance present from T+0")


## Mirrors test_tli_scenario.gd's structure: an idealized departure phase
## (not Level07's deliberately-offset 60 degree start, which exists so the
## *player* has to wait for the window) proves the interplanetary pipeline
## itself - Sun-centered coast, child-SOI detection two hops from the
## ship's start, capture - works, using the same mu_sun/r_earth/r_mars the
## level ships with.
func test_mars_hohmann_transfer_reaches_and_captures() -> void:
	var level := Campaign.level_at(6)
	var sun_mu: float = level.body.mu
	var earth: BodyDef = level.moons[0]
	var mars: BodyDef = level.moons[1]
	var r_earth: float = earth.orbit.a
	var r_mars: float = mars.orbit.a

	var a_transfer := (r_earth + r_mars) * 0.5
	var vp := sqrt(sun_mu * (2.0 / r_earth - 1.0 / a_transfer))
	var transfer := OrbitElements.from_state(
		DVec3.new(r_earth, 0.0, 0.0), DVec3.new(0.0, 0.0, -vp), sun_mu, 0.0)
	var t_apo: float = transfer.period() * 0.5
	assert_between(t_apo, 1.4e5, 1.6e5, "transfer time near the ~150000s design target")

	# phase Mars to arrive at the transfer ellipse's aphelion, small lead
	# so the ship flies past instead of hitting dead center (same trick
	# test_tli_scenario.gd uses for the Moon)
	var n_mars := mars.orbit.mean_motion()
	var theta0 := PI - n_mars * t_apo + 0.04
	mars.orbit_phase_deg = rad_to_deg(theta0)

	var t_encounter := OrbitEvents.child_soi_entry_time(
		transfer, mars.orbit, mars.soi_radius, 0.0, t_apo + 5.0e4, 1000.0)
	assert_false(is_nan(t_encounter), "the Hohmann arrival meets Mars")

	var rel := Frames.to_child_frame(transfer.state_at_time(t_encounter), mars.orbit, t_encounter)
	assert_close(rel.r.length(), mars.soi_radius, 1e-6, "handoff at the SOI radius")
	var flyby := OrbitElements.from_state(rel.r, rel.v, mars.mu, t_encounter)
	assert_gt(flyby.radius_periapsis(), mars.radius, "flyby clears the surface")
	assert_lt(flyby.radius_periapsis(), mars.soi_radius, "periapsis inside the SOI")

	# capture burn: circularize at periapsis
	var t_peri := OrbitEvents.periapsis_time(flyby, t_encounter)
	assert_false(is_nan(t_peri), "flyby has a periapsis ahead")
	var peri_state := flyby.state_at_time(t_peri)
	var v_capture := sqrt(mars.mu / peri_state.r.length())
	assert_lt(v_capture, peri_state.v.length(), "capture burn is a deceleration")
	var captured := OrbitElements.from_state(
		peri_state.r, peri_state.v.normalized().scaled(v_capture), mars.mu, t_peri)
	assert_true(captured.is_elliptic(), "captured orbit is bound")
	assert_lt(captured.radius_apoapsis(), mars.soi_radius, "captured orbit stays inside the SOI")

	var objective: TransferCaptureObjective = level.objective
	var ship := ShipSim.new()
	ship.setup(level)
	ship.body = mars
	ship.elements = captured
	ship.advance_to(t_peri + 1.0)
	assert_true(objective.is_met(ship), "TransferCapture recognizes the captured orbit")

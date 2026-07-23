extends "res://tests/unit/base_orbit_test.gd"
## M5: closest approach, rendezvous, airless landing, entry corridor.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func test_closest_approach_matches_brute_force() -> void:
	var level := Campaign.level_at(1)
	var ship := ShipSim.new()
	ship.setup(level)
	var objective: RendezvousObjective = level.objective
	var el := ship.elements
	var span: float = el.period()
	var ca := OrbitEvents.closest_approach(
		el, objective.station_orbit, 0.0, span, span / 240.0)
	var best_d := INF
	var t := 0.0
	while t < span:
		var d := el.state_at_time(t).r.distance_to(
			objective.station_orbit.state_at_time(t).r)
		best_d = minf(best_d, d)
		t += 2.0
	assert_close(ca.distance, best_d, 0.01, "refined min matches brute force")


func test_closest_approach_cache_survives_warp_sized_time_jumps() -> void:
	# PF-3: at high warp a render frame advances far more than the old 2 s cache
	# window, but the conic is unchanged, so the cached solve must be reused.
	var level := Campaign.level_at(1)
	var ship := ShipSim.new()
	ship.setup(level)
	var objective: RendezvousObjective = level.objective

	var ca1 := objective.closest_approach(ship)
	var t_ca: float = ca1["time"]
	assert_gt(t_ca, ship.last_time + 2.0, "the predicted approach is well beyond the old window")

	# A big time jump that stays before the predicted approach: same revision,
	# so the exact cached dictionary must come back (reference identity).
	ship.last_time = lerpf(0.0, t_ca, 0.5)
	var ca2 := objective.closest_approach(ship)
	assert_true(is_same(ca1, ca2), "unchanged conic reuses the cached approach across a big jump")

	# Once we pass the predicted approach time, the next window is solved fresh.
	ship.last_time = t_ca + 1.0
	var ca3 := objective.closest_approach(ship)
	assert_false(is_same(ca1, ca3), "passing the approach time forces a fresh solve")


func test_closest_approach_recomputes_after_a_refit() -> void:
	var level := Campaign.level_at(1)
	var ship := ShipSim.new()
	ship.setup(level)
	var objective: RendezvousObjective = level.objective
	var ca1 := objective.closest_approach(ship)
	ship.revision += 1  # a burn/refit: guidance must refresh immediately
	var ca2 := objective.closest_approach(ship)
	assert_false(is_same(ca1, ca2), "a refit (revision bump) invalidates the cache")


func test_rendezvous_met_only_in_proximity() -> void:
	var level := Campaign.level_at(1)
	var objective: RendezvousObjective = level.objective
	var ship := ShipSim.new()
	ship.setup(level)
	assert_false(objective.is_met(ship), "not met 20 km below the station")

	# park the ship right next to the station, co-moving
	var st := objective.station_orbit.state_at_time(500.0)
	ship.elements = OrbitElements.from_state(
		st.r.add(DVec3.new(0.0, 0.0, 500.0)), st.v, level.body.mu, 500.0)
	ship.advance_to(500.0)
	assert_true(objective.is_met(ship), "met alongside the station")


func test_landing_contact_win_and_crash() -> void:
	var level := Campaign.level_at(4)
	var objective: AirlessLandingObjective = level.objective
	var ship := ShipSim.new()
	ship.setup(level)
	var moon: BodyDef = level.moons[0]
	assert_eq(ship.body, moon, "level starts in lunar orbit")

	ship.r = DVec3.new(moon.radius, 0.0, 0.0)
	ship.v = DVec3.new(-4.0, 0.0, 2.0)  # gentle: |vs|=4, hs=2
	assert_eq(objective.contact_result(ship), Objective.ContactResult.WIN, "soft touchdown")

	ship.v = DVec3.new(-20.0, 0.0, 2.0)
	assert_eq(objective.contact_result(ship), Objective.ContactResult.CRASH, "too fast vertically")

	ship.v = DVec3.new(-4.0, 0.0, 9.0)
	assert_eq(objective.contact_result(ship), Objective.ContactResult.CRASH, "too fast sideways")


func test_entry_corridor_met_on_dipping_orbit() -> void:
	var level := Campaign.level_at(5)
	var objective: EntryCorridorObjective = level.objective
	var earth := level.body
	var ship := ShipSim.new()
	ship.setup(Campaign.level_at(0))  # earth-centered ship shell
	# ellipse from 300 km apoapsis down to the corridor periapsis
	var ra := 3.0e5
	var rp := objective.target_periapsis
	var a := (ra + rp) * 0.5
	var va := sqrt(earth.mu * (2.0 / ra - 1.0 / a))
	ship.elements = OrbitElements.from_state(
		DVec3.new(ra, 0.0, 0.0), DVec3.new(0.0, 0.0, -va), earth.mu, 0.0)
	ship.advance_to(1.0)
	assert_true(objective.is_met(ship), "corridor periapsis wins")

	var high := OrbitElements.from_state(
		DVec3.new(ra, 0.0, 0.0), DVec3.new(0.0, 0.0, -va * 1.05), earth.mu, 1.0)
	ship.elements = high
	ship.advance_to(2.0)
	assert_false(objective.is_met(ship), "periapsis above corridor does not win")


func test_new_levels_boot() -> void:
	for index in [1, 4, 5]:
		GameRootScript.level_index = index
		var game: Node = load("res://src/main.tscn").instantiate()
		add_child_autofree(game)
		simulate(game, 5, 1.0 / 60.0)
		assert_eq(game.phase, game.Phase.FLYING, "%s boots and flies" % Campaign.title(index))
	GameRootScript.level_index = 4
	var landing_game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(landing_game)
	simulate(landing_game, 5, 1.0 / 60.0)
	assert_eq(landing_game.ship.body.name, "MOON", "landing level starts at the moon")

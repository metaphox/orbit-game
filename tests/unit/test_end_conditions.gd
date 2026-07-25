extends "res://tests/unit/base_orbit_test.gd"
## Mission-envelope escape is a ROOT-frame predicate at any SOI depth
## (DESIGN §5): a ship deep inside a child SOI must still fail when its
## root-frame position leaves the level envelope. Regression for CR-3, where
## the check only ran while the ship was in the root body's own SOI.

const GameRootScript := preload("res://src/game_root.gd")
const MU_SUN := 1.327e20


func after_each() -> void:
	GameRootScript.level_index = 0
	GameRootScript.hardcore = false


func _boot() -> Node:
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	return game


## Sun (root) -> Earth -> Moon; returns the moon, already parented. The moon's
## root-frame distance is ~ 4.0e7 + 3.844e6 ~ 4.38e7 m.
func _nested_moon() -> BodyDef:
	var sun := BodyDef.new()
	sun.name = "SUN"
	sun.mu = MU_SUN
	sun.radius = 6.96e5

	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = MU_EARTH
	earth.radius = 63710.0
	earth.soi_radius = 9.24e6
	earth.parent = sun
	earth.orbit_radius = 4.0e7
	earth.orbit_phase_deg = 0.0

	var moon := BodyDef.new()
	moon.name = "MOON"
	moon.mu = MU_MOON
	moon.radius = 17374.0
	moon.soi_radius = 6.6e5
	moon.parent = earth
	moon.orbit_radius = 3.844e6
	moon.orbit_phase_deg = 0.0
	return moon


## Park the ship in a low circular orbit inside the moon's SOI (above the
## surface, well inside the SOI) so only the envelope predicate is in play.
func _place_in_moon_soi(game: Node, moon: BodyDef) -> void:
	game.ship.body = moon
	var r := 20000.0
	game.ship.r = DVec3.new(r, 0.0, 0.0)
	game.ship.v = DVec3.new(0.0, 0.0, -sqrt(moon.mu / r))
	game.ship.elements = OrbitElements.from_state(
		game.ship.r, game.ship.v, moon.mu, game.sim_time)


func test_envelope_fails_from_inside_a_child_soi() -> void:
	var game := _boot()
	var moon := _nested_moon()
	_place_in_moon_soi(game, moon)
	game.level.fail_radius = 1.0e7  # moon (~4.38e7) is well beyond this
	assert_gt(game.ship.absolute_position(game.sim_time).length(), game.level.fail_radius,
		"moon's root-frame position is outside the envelope")

	game._check_end_conditions()
	assert_eq(game.phase, game.Phase.FAILED, "envelope fires from a child SOI")
	assert_eq(game._fail_reason, "MISSION ENVELOPE EXCEEDED")


func test_landed_win_settles_and_stays_put() -> void:
	# CR-5: a successful airless landing must reach a terminal landed state -
	# throttle + body-relative velocity zeroed, position frozen - not keep
	# advancing on rails where a stuck throttle could lift the craft back off.
	GameRootScript.level_index = 4  # airless landing on the Moon
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	var moon: BodyDef = game.ship.body

	# Soft touchdown at full throttle, then drive the win through the real check.
	game.ship.r = DVec3.new(moon.radius, 0.0, 0.0)
	game.ship.v = DVec3.new(-4.0, 0.0, 2.0)  # |vs|=4, hs=2 -> WIN
	game.ship.throttle = 1.0
	game._check_end_conditions()

	assert_eq(game.phase, game.Phase.WON, "soft touchdown wins")
	assert_true(game.ship.landed, "the craft is marked landed")
	assert_eq(game.ship.throttle, 0.0, "throttle is cut on landing")
	assert_eq(game.ship.v.length(), 0.0, "body-relative velocity is zeroed")

	var pinned: DVec3 = game.ship.r.copy()
	simulate(game, 180, 1.0 / 60.0)  # three seconds in the post-win scene
	assert_almost_eq(game.ship.r.distance_to(pinned), 0.0, 1e-6,
		"a landed craft stays pinned to the surface instead of lifting off or sinking")
	assert_eq(game.ship.v.length(), 0.0, "and never regains velocity")


func test_orbital_win_keeps_coasting() -> void:
	# The CR-5 landed state must NOT apply to an orbital win: that keeps coasting
	# its new conic (DESIGN §14.3), so the ship's position advances over time.
	GameRootScript.level_index = 0
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	game._win()  # orbital-style win (no landing)
	assert_false(game.ship.landed, "an orbital win is not landed")
	var before: DVec3 = game.ship.r.copy()
	simulate(game, 60, 1.0 / 60.0)
	assert_gt(game.ship.r.distance_to(before), 0.0, "an orbital win keeps coasting")


func test_envelope_does_not_fire_within_the_boundary() -> void:
	var game := _boot()
	var moon := _nested_moon()
	_place_in_moon_soi(game, moon)
	game.level.fail_radius = 1.0e8  # generous: moon is well inside
	assert_lt(game.ship.absolute_position(game.sim_time).length(), game.level.fail_radius,
		"moon's root-frame position is inside the envelope")

	game._check_end_conditions()
	assert_ne(game.phase, game.Phase.FAILED, "no envelope fail when within the boundary")

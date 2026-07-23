extends "res://tests/unit/base_orbit_test.gd"
## Attitude vs time warp (DESIGN.md §4.4): rotation is a 1x activity. Under warp a
## SAS hold snaps to its target and stays locked as the orbit sweeps, a free spin
## freezes (and resumes at 1x), and nudging the stick drops warp back to 1x.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0
	Input.action_release("pitch_up")  # tests below press it; never leak the state


func _boot() -> Node:
	GameRootScript.level_index = 3  # translunar: SAS enabled, starts in a circular LEO
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	return game


func test_sas_hold_stays_locked_on_target_under_warp() -> void:
	var game := _boot()
	var ship: ShipSim = game.ship
	game._toggle_sas(ShipSim.SasMode.PROGRADE)
	game.warp_index = 5  # 100x: the orbit sweeps far faster than any real-time slew
	simulate(game, 120, 1.0 / 60.0)  # ~200 s of orbit — velocity direction moves a lot
	assert_gt(ship.forward_dir().dot(ship.v.normalized()), 0.999,
		"SAS snaps and holds prograde even as the orbit sweeps under warp")
	assert_lt(ship.angular_velocity.length(), 1e-6, "no residual spin from a snapped hold")


func test_free_spin_freezes_under_warp() -> void:
	var game := _boot()
	var ship: ShipSim = game.ship
	ship.sas_mode = ShipSim.SasMode.OFF
	ship.angular_velocity = Vector3(0.0, 1.0, 0.0)  # left tumbling before engaging warp
	game.warp_index = 5
	var frozen := ship.attitude
	simulate(game, 60, 1.0 / 60.0)
	assert_true(ship.attitude.is_equal_approx(frozen),
		"a free spin does not advance the attitude under warp")
	assert_true(ship.angular_velocity.is_equal_approx(Vector3(0.0, 1.0, 0.0)),
		"the spin is preserved, so it resumes when warp drops to 1x")


func test_manual_input_drops_warp() -> void:
	var game := _boot()
	game.warp_index = 5
	Input.action_press("pitch_up")  # released in after_each
	game._apply_flight_input(1.0 / 60.0)
	assert_eq(game.warp_index, 0, "nudging the attitude stick drops warp to 1x")

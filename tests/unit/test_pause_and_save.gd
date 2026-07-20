extends "res://tests/unit/base_orbit_test.gd"
## Pause menu (ESC/SPACE), the new 1-4 warp shortcuts, and ShipSim state
## serialization for mid-mission saves.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func _boot() -> Node:
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	return game


func _key(keycode: Key, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	return event


func test_escape_opens_and_closes_pause_menu() -> void:
	var game := _boot()
	game._unhandled_input(_key(KEY_ESCAPE))
	assert_eq(game.phase, game.Phase.PAUSED, "escape pauses")
	assert_not_null(game._pause_menu, "escape opens the pause menu")

	game._unhandled_input(_key(KEY_ESCAPE))
	assert_eq(game.phase, game.Phase.FLYING, "escape again resumes")
	assert_null(game._pause_menu, "and closes the menu")


func test_pause_freezes_simulation() -> void:
	var game := _boot()
	game._unhandled_input(_key(KEY_ESCAPE))
	var frozen_time: float = game.sim_time
	simulate(game, 30, 1.0 / 60.0)
	assert_eq(game.sim_time, frozen_time, "sim_time does not advance while paused")


func test_space_toggles_pause_without_menu() -> void:
	var game := _boot()
	game._unhandled_input(_key(KEY_SPACE))
	assert_eq(game.phase, game.Phase.PAUSED, "space pauses")
	assert_null(game._pause_menu, "but does not open the full menu")

	game._unhandled_input(_key(KEY_SPACE))
	assert_eq(game.phase, game.Phase.FLYING, "space again resumes")


func test_space_closes_an_open_pause_menu() -> void:
	var game := _boot()
	game._unhandled_input(_key(KEY_ESCAPE))
	assert_not_null(game._pause_menu)
	game._unhandled_input(_key(KEY_SPACE))
	assert_eq(game.phase, game.Phase.FLYING, "space also dismisses the full menu")
	assert_null(game._pause_menu)


func test_escape_promotes_quick_pause_to_full_menu() -> void:
	var game := _boot()
	game._unhandled_input(_key(KEY_SPACE))
	assert_eq(game.phase, game.Phase.PAUSED)
	assert_null(game._pause_menu)
	game._unhandled_input(_key(KEY_ESCAPE))
	assert_not_null(game._pause_menu, "escape opens the menu even from a quick-pause")


func test_escape_after_win_still_exits_directly() -> void:
	var game := _boot()
	game.phase = game.Phase.WON
	var exited := [false]
	game.exit_requested.connect(func(): exited[0] = true)
	game._unhandled_input(_key(KEY_ESCAPE))
	assert_true(exited[0], "no pause concept once the mission has ended")
	assert_null(game._pause_menu)


func test_pause_menu_buttons_emit_expected_signals() -> void:
	var game := _boot()
	game._open_pause_menu()
	var restart := [false]
	var quit := [false]
	game.restart_requested.connect(func(): restart[0] = true)
	game.exit_requested.connect(func(): quit[0] = true)

	game._pause_menu._activate(2)  # RESTART MISSION
	assert_true(restart[0])

	game._pause_menu._activate(3)  # QUIT TO MISSION SELECT
	assert_true(quit[0])


func test_warp_number_keys_set_exact_multipliers() -> void:
	var game := _boot()
	var expected := [1, 5, 10, 25, 50, 100, 200, 500, 1000]
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	for i in keys.size():
		game._unhandled_input(_key(keys[i]))
		assert_eq(game.WARP_STEPS[game.warp_index], expected[i], "key %d -> %dx" % [i + 1, expected[i]])


func test_warp_keys_ignored_while_thrusting() -> void:
	var game := _boot()
	game.ship.throttle = 1.0
	game._unhandled_input(_key(KEY_9))
	assert_eq(game.warp_index, 0, "can't warp while actively burning")


func test_minus_equal_step_warp_one_level_at_a_time() -> void:
	var game := _boot()
	game._unhandled_input(_key(KEY_EQUAL))
	assert_eq(game.warp_index, 1, "= steps up one level")
	game._unhandled_input(_key(KEY_EQUAL))
	assert_eq(game.warp_index, 2)
	game._unhandled_input(_key(KEY_MINUS))
	assert_eq(game.warp_index, 1, "- steps down one level")

	game.warp_index = 0
	game._unhandled_input(_key(KEY_MINUS))
	assert_eq(game.warp_index, 0, "- floors at index 0, does not wrap")

	game.warp_index = game.WARP_STEPS.size() - 1
	game._unhandled_input(_key(KEY_EQUAL))
	assert_eq(game.warp_index, game.WARP_STEPS.size() - 1, "= caps at the last step")


func test_zero_key_is_a_pause_alias_for_space() -> void:
	var game := _boot()
	game._unhandled_input(_key(KEY_0))
	assert_eq(game.phase, game.Phase.PAUSED, "0 pauses like space does")
	assert_null(game._pause_menu, "quick pause, no menu")
	game._unhandled_input(_key(KEY_0))
	assert_eq(game.phase, game.Phase.FLYING, "0 again resumes")


func test_r_resets_the_view_during_flight() -> void:
	var game := _boot()
	game.flight_view._cam_yaw = 1.2
	game.flight_view._cam_pitch = -0.4
	game.flight_view._side_azimuth = 2.0
	game.flight_view._side_elevation = -1.0
	game.flight_view._side_distance = 8.0e5

	game._unhandled_input(_key(KEY_R))
	assert_eq(game.flight_view._cam_yaw, game.flight_view.DEFAULT_CAM_YAW)
	assert_eq(game.flight_view._cam_pitch, game.flight_view.DEFAULT_CAM_PITCH)
	assert_eq(game.flight_view._side_azimuth, game.flight_view.DEFAULT_SIDE_AZIMUTH)
	assert_eq(game.flight_view._side_elevation, game.flight_view.DEFAULT_SIDE_ELEVATION)
	assert_eq(game.flight_view._side_distance, game.flight_view.DEFAULT_SIDE_DISTANCE)
	assert_eq(game.phase, game.Phase.FLYING, "R does not restart the mission while flying")


func test_r_restarts_on_win_or_fail_instead_of_resetting_view() -> void:
	var game := _boot()
	game.phase = game.Phase.WON
	var restarted := [false]
	game.restart_requested.connect(func(): restarted[0] = true)
	game._unhandled_input(_key(KEY_R))
	assert_true(restarted[0], "R matches the on-screen [R] RESTART prompt once the mission ends")


func test_ship_state_round_trips_through_serialize() -> void:
	var ship := ShipSim.new()
	ship.setup(Level02.make())
	ship.create_node(300.0)
	ship.node.prograde = 42.0
	ship.refresh_node_plan()
	ship.attitude = Basis(Vector3(0, 1, 0), 0.7)
	ship.prop_mass = 111.0
	ship.sas_mode = ShipSim.SasMode.RETROGRADE
	var original_r := ship.r
	var original_v := ship.v

	var data := ship.serialize()

	var restored := ShipSim.new()
	restored.setup(Level02.make())
	restored.apply_serialized(data, 500.0)

	assert_eq(restored.body.name, ship.body.name)
	assert_dvec_close(restored.r, original_r, 1e-9)
	assert_dvec_close(restored.v, original_v, 1e-9)
	assert_close(restored.prop_mass, 111.0, 1e-9)
	assert_eq(restored.sas_mode, ShipSim.SasMode.RETROGRADE)
	assert_eq(restored.flight_state, ShipSim.FlightState.COASTING)
	assert_eq(restored.throttle, 0.0, "resuming never auto-resumes thrust")
	assert_eq(restored.last_time, 500.0)
	assert_not_null(restored.node)
	assert_close(restored.node.prograde, 42.0, 1e-9)
	assert_dvec_close(restored.node.remaining, ship.node.remaining, 1e-6)

	var restored_forward := restored.attitude * Vector3(0, 0, -1)
	var original_forward := ship.attitude * Vector3(0, 0, -1)
	assert_true(restored_forward.is_equal_approx(original_forward), "attitude preserved")


func test_ship_state_without_node_round_trips_null() -> void:
	var ship := ShipSim.new()
	ship.setup(Level01.make())
	var data := ship.serialize()
	assert_null(data["node"])

	var restored := ShipSim.new()
	restored.setup(Level01.make())
	restored.node = ManeuverNode.new()  # should be cleared by apply_serialized
	restored.apply_serialized(data, 10.0)
	assert_null(restored.node)

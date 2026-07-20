extends "res://tests/unit/base_orbit_test.gd"
## Toolbar buttons route through Hud.toolbar_key -> game_root's own
## _unhandled_input as a synthetic key event - these tests check that
## round trip actually reaches the game state, not just that the signal
## fires.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func _boot() -> Node:
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	return game


func test_one_shot_button_taps_press_and_release() -> void:
	GameRootScript.level_index = 1  # level 2 has the avionics
	var game := _boot()
	game.hud.toolbar_key.emit(KEY_F, true)
	game.hud.toolbar_key.emit(KEY_F, false)
	assert_eq(game.ship.sas_mode, ShipSim.SasMode.PROGRADE, "F button locks prograde")

	game.hud.toolbar_key.emit(KEY_F, true)
	game.hud.toolbar_key.emit(KEY_F, false)
	assert_eq(game.ship.sas_mode, ShipSim.SasMode.OFF, "second tap releases it")


func test_toolbar_button_triggers_same_as_direct_click() -> void:
	GameRootScript.level_index = 1
	var game := _boot()
	var f_button := _find_button(game.hud, "F")
	assert_not_null(f_button, "F button exists in the toolbar")
	f_button.pressed.emit()
	assert_eq(game.ship.sas_mode, ShipSim.SasMode.PROGRADE, "clicking the real button works")


func test_warp_step_buttons() -> void:
	var game := _boot()
	game.hud.toolbar_key.emit(KEY_EQUAL, true)
	game.hud.toolbar_key.emit(KEY_EQUAL, false)
	assert_eq(game.warp_index, 1, "+ button steps warp up")
	game.hud.toolbar_key.emit(KEY_MINUS, true)
	game.hud.toolbar_key.emit(KEY_MINUS, false)
	assert_eq(game.warp_index, 0, "- button steps warp down")


func test_throttle_buttons_are_press_and_hold_not_a_tap() -> void:
	var game := _boot()
	assert_eq(game.ship.throttle, 0.0)
	game.hud.toolbar_key.emit(KEY_SHIFT, true)  # button_down: hold starts
	simulate(game, 30, 1.0 / 60.0)  # ~0.5s held
	game.hud.toolbar_key.emit(KEY_SHIFT, false)  # button_up: hold ends
	assert_gt(game.ship.throttle, 0.0, "throttle rose while held")
	var throttle_after_release: float = game.ship.throttle
	simulate(game, 30, 1.0 / 60.0)
	assert_close(game.ship.throttle, throttle_after_release, 1e-6,
		"stays put once released, doesn't keep climbing")


func test_node_cluster_buttons_create_and_delete_a_node() -> void:
	GameRootScript.level_index = 1
	var game := _boot()
	assert_null(game.ship.node)
	game.hud.toolbar_key.emit(KEY_ENTER, true)
	game.hud.toolbar_key.emit(KEY_ENTER, false)
	assert_not_null(game.ship.node, "ENTER button creates a node")

	game.hud.toolbar_key.emit(KEY_BACKSPACE, true)
	game.hud.toolbar_key.emit(KEY_BACKSPACE, false)
	assert_null(game.ship.node, "BKSP button deletes it")


func test_node_adjust_buttons_change_the_plan() -> void:
	GameRootScript.level_index = 1
	var game := _boot()
	game._node_create()
	var before: float = game.ship.node.prograde
	game.hud.toolbar_key.emit(KEY_UP, true)
	game.hud.toolbar_key.emit(KEY_UP, false)
	assert_gt(game.ship.node.prograde, before, "up-arrow button adds prograde dv")


func _find_button(node: Node, label: String) -> Button:
	if node is Button and node.text == label:
		return node
	for child in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null

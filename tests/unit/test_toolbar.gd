extends "res://tests/unit/base_orbit_test.gd"
## Toolbar buttons emit a semantic ACTION via Hud.toolbar_command; game_root
## replays that action's current binding into its own input path. These tests
## check the round trip actually reaches game state, and that it survives a
## rebind (CR-5) — the button dispatches the action, not a frozen keycode.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func _boot() -> Node:
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	return game


func test_one_shot_button_taps_press_and_release() -> void:
	GameRootScript.level_index = 3  # translunar: SAS + nodes enabled
	var game := _boot()
	game.hud.toolbar_command.emit("sas_prograde", true)
	game.hud.toolbar_command.emit("sas_prograde", false)
	assert_eq(game.ship.sas_mode, ShipSim.SasMode.PROGRADE, "prograde button locks prograde")

	game.hud.toolbar_command.emit("sas_prograde", true)
	game.hud.toolbar_command.emit("sas_prograde", false)
	assert_eq(game.ship.sas_mode, ShipSim.SasMode.OFF, "second tap releases it")


func test_toolbar_button_triggers_same_as_direct_click() -> void:
	GameRootScript.level_index = 3
	var game := _boot()
	var button := _find_button_for_action(game.hud, "sas_prograde")
	assert_not_null(button, "prograde SAS button exists in the toolbar")
	button.pressed.emit()
	assert_eq(game.ship.sas_mode, ShipSim.SasMode.PROGRADE, "clicking the real button works")


func test_toolbar_button_survives_a_rebind() -> void:
	# The core CR-5 fix: rebinding the action must not break its toolbar button.
	GameRootScript.level_index = 3
	var game := _boot()
	InputBindings.rebind("sas_prograde", KEY_K)  # was F
	var button := _find_button_for_action(game.hud, "sas_prograde")
	assert_not_null(button, "prograde button still present after a rebind")
	button.pressed.emit()
	assert_eq(game.ship.sas_mode, ShipSim.SasMode.PROGRADE,
		"the button dispatches the action via its NEW key, not the stale F")
	InputBindings.rebind("sas_prograde", KEY_F)  # restore default for other tests


func test_warp_step_buttons() -> void:
	var game := _boot()
	game.hud.toolbar_command.emit("warp_increase", true)
	game.hud.toolbar_command.emit("warp_increase", false)
	assert_eq(game.warp_index, 1, "warp+ button steps warp up")
	game.hud.toolbar_command.emit("warp_decrease", true)
	game.hud.toolbar_command.emit("warp_decrease", false)
	assert_eq(game.warp_index, 0, "warp- button steps warp down")


func test_throttle_buttons_are_press_and_hold_not_a_tap() -> void:
	var game := _boot()
	assert_eq(game.ship.throttle, 0.0)
	game.hud.toolbar_command.emit("throttle_increase", true)  # button_down: hold starts
	simulate(game, 30, 1.0 / 60.0)  # ~0.5s held
	game.hud.toolbar_command.emit("throttle_increase", false)  # button_up: hold ends
	assert_gt(game.ship.throttle, 0.0, "throttle rose while held")
	var throttle_after_release: float = game.ship.throttle
	simulate(game, 30, 1.0 / 60.0)
	assert_close(game.ship.throttle, throttle_after_release, 1e-6,
		"stays put once released, doesn't keep climbing")


func test_node_cluster_buttons_create_and_delete_a_node() -> void:
	GameRootScript.level_index = 3
	var game := _boot()
	assert_null(game.ship.node)
	game.hud.toolbar_command.emit("node_create", true)
	game.hud.toolbar_command.emit("node_create", false)
	assert_not_null(game.ship.node, "node_create button creates a node")

	game.hud.toolbar_command.emit("node_delete", true)
	game.hud.toolbar_command.emit("node_delete", false)
	assert_null(game.ship.node, "node_delete button deletes it")


func test_node_adjust_buttons_change_the_plan() -> void:
	GameRootScript.level_index = 3
	var game := _boot()
	game._node_create()
	var before: float = game.ship.node.prograde
	game.hud.toolbar_command.emit("node_prograde_increase", true)
	game.hud.toolbar_command.emit("node_prograde_increase", false)
	assert_gt(game.ship.node.prograde, before, "prograde+ button adds prograde dv")


func test_sas_buttons_absent_when_the_level_grants_no_sas() -> void:
	# Capability gating: level 0 has no SAS, so no SAS button is built.
	var game := _boot()
	assert_null(_find_button_for_action(game.hud, "sas_prograde"),
		"no SAS toolbar button on a level without SAS")


func _find_button_for_action(node: Node, action: String) -> Button:
	if node is Button and (node as Button).tooltip_text == action:
		return node
	for child in node.get_children():
		var found := _find_button_for_action(child, action)
		if found != null:
			return found
	return null

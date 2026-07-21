extends "res://tests/unit/base_orbit_test.gd"
## The HUD help strip is generated from the live InputMap bindings
## (hud.gd's _key_label) rather than hardcoded, so it can't drift out of
## sync with project.godot's [input] section. Confirm it actually reflects
## real bindings, not just that it renders something.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func test_help_text_reflects_live_input_bindings() -> void:
	GameRootScript.level_index = 3  # translunar: SAS + nodes both enabled
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)

	var text: String = game.hud.help_label.text
	# pitch/yaw/roll: matches the actual keys bound to those actions
	assert_true(text.contains("W/S PITCH"), "pitch keys shown match pitch_down=W/pitch_up=S")
	assert_true(text.contains("A/D YAW"), "yaw keys shown match yaw_left=A/yaw_right=D")
	assert_true(text.contains("Q/E ROLL"), "roll keys shown match roll_left=Q/roll_right=E")
	assert_true(text.contains("SAS:"), "SAS line present when the level has sas_enabled")
	assert_true(text.contains("NODE:"), "node line present when the level has nodes_enabled")

	# rebind pitch_up from S to J at the InputMap level and rebuild the HUD:
	# the displayed text must follow the binding, proving it's generated,
	# not a hardcoded string that happens to match the default layout.
	InputMap.action_erase_events("pitch_up")
	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_J
	InputMap.action_add_event("pitch_up", rebound)

	var hud2 := Hud.new()
	add_child_autofree(hud2)
	hud2.build(game.level)
	assert_true(
		hud2.help_label.text.contains("W/J PITCH"),
		"help text follows a rebound action instead of staying hardcoded")

	# restore the real binding so later tests in this run aren't affected
	InputMap.action_erase_events("pitch_up")
	var restored := InputEventKey.new()
	restored.physical_keycode = KEY_S
	InputMap.action_add_event("pitch_up", restored)

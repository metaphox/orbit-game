extends "res://tests/unit/base_orbit_test.gd"
## InputBindings (TD-4): registers the rewind/autopilot actions and applies
## persistent key rebinds. InputMap and Settings are global, so restore both in
## after_each or other suites inherit the mutated state.

func before_each() -> void:
	Settings.reset_to_defaults()
	InputBindings.install()


func after_each() -> void:
	# Restore default keys so e.g. test_rewind still sees H/←/→/Enter/Esc.
	for action: String in InputBindings.EXTRA_DEFAULTS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
			for keycode: int in InputBindings.EXTRA_DEFAULTS[action]:
				var e := InputEventKey.new()
				e.physical_keycode = keycode
				InputMap.action_add_event(action, e)
	Settings.reset_to_defaults()


func _has_physical_key(action: String, keycode: int) -> bool:
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == keycode:
			return true
	return false


func test_install_registers_extra_actions_with_defaults() -> void:
	assert_true(InputMap.has_action("rewind_open"), "rewind_open registered")
	assert_true(InputMap.has_action("autopilot_toggle"), "autopilot_toggle registered")
	assert_true(_has_physical_key("rewind_open", KEY_H), "rewind_open defaults to H")
	assert_true(_has_physical_key("rewind_prev", KEY_A), "rewind_prev includes A")


func test_rebind_updates_inputmap_and_persists() -> void:
	InputBindings.rebind("rewind_open", KEY_R)
	assert_true(_has_physical_key("rewind_open", KEY_R), "InputMap remapped to R")
	assert_false(_has_physical_key("rewind_open", KEY_H), "old H removed")
	assert_eq(Settings.get_value("key_bindings"), {"rewind_open": [KEY_R]}, "saved to settings")


func test_apply_overrides_reapplies_saved_binds() -> void:
	Settings.set_value("key_bindings", {"rewind_open": [KEY_G]})
	InputBindings.apply_overrides()
	assert_true(_has_physical_key("rewind_open", KEY_G), "saved override applied to InputMap")

extends "res://tests/unit/base_orbit_test.gd"
## The fail/win banners derive their key hints from the live InputMap via
## InputBindings.primary_key_label, so the advertised recovery key actually
## works and follows rebinds. Regression for CR-2: the fail banner used to
## hardcode "[Z] REWIND" while rewind is bound to H (and is rebindable).

const LEVEL_PATH := "res://src/levels/data/level_01_01.tres"


func before_each() -> void:
	InputBindings.install()  # ensure the rewind_* actions exist


func _hud() -> Hud:
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.build(load(LEVEL_PATH))
	return hud


func test_fail_banner_shows_the_live_rewind_key_not_z() -> void:
	var hud := _hud()
	hud.show_fail("TEST FAIL", 2)
	var prompt: String = hud._banner_prompt.text
	var rewind_key := InputBindings.primary_key_label("rewind_open")
	assert_true(prompt.contains("[%s] REWIND" % rewind_key),
		"banner advertises the real rewind key (%s), not a hardcoded letter" % rewind_key)
	assert_false(prompt.contains("[Z]"), "the stale [Z] hint is gone")


func test_fail_banner_follows_a_rebound_rewind_key() -> void:
	InputMap.action_erase_events("rewind_open")
	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_G
	InputMap.action_add_event("rewind_open", rebound)

	var hud := _hud()
	hud.show_fail("TEST FAIL", 1)
	assert_true(hud._banner_prompt.text.contains("[G] REWIND"),
		"banner reflects the rebound rewind key")

	# restore the default so later tests in this run aren't affected
	InputMap.action_erase_events("rewind_open")
	var restored := InputEventKey.new()
	restored.physical_keycode = KEY_H
	InputMap.action_add_event("rewind_open", restored)


func test_fail_banner_offers_restart_at_zero_charges() -> void:
	var hud := _hud()
	hud.show_fail("TEST FAIL", 0)
	var prompt: String = hud._banner_prompt.text
	assert_true(prompt.contains("RESTART"), "restart is the 0-charge fallback")
	assert_false(prompt.contains("REWIND"), "no rewind offered at zero charges")

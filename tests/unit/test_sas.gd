extends "res://tests/unit/base_orbit_test.gd"
## SAS hold modes and their capability gating.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func _boot() -> Node:
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	return game


func test_sas_target_directions() -> void:
	var level := Campaign.level_at(3)
	var ship := ShipSim.new()
	ship.setup(level)
	# start state: r = +X, v = -Z, h = +Y
	ship.sas_mode = ShipSim.SasMode.PROGRADE
	assert_dvec_close(ship.sas_target_dir(), DVec3.new(0, 0, -1), 1e-9, "prograde")
	ship.sas_mode = ShipSim.SasMode.RETROGRADE
	assert_dvec_close(ship.sas_target_dir(), DVec3.new(0, 0, 1), 1e-9, "retrograde")
	ship.sas_mode = ShipSim.SasMode.NORMAL
	assert_dvec_close(ship.sas_target_dir(), DVec3.new(0, 1, 0), 1e-9, "normal")
	ship.sas_mode = ShipSim.SasMode.ANTI_NORMAL
	assert_dvec_close(ship.sas_target_dir(), DVec3.new(0, -1, 0), 1e-9, "anti-normal")
	ship.sas_mode = ShipSim.SasMode.RADIAL_OUT
	assert_dvec_close(ship.sas_target_dir(), DVec3.new(1, 0, 0), 1e-9, "radial out")
	ship.sas_mode = ShipSim.SasMode.RADIAL_IN
	assert_dvec_close(ship.sas_target_dir(), DVec3.new(-1, 0, 0), 1e-9, "radial in")


func test_sas_gated_by_level_capability() -> void:
	var game := _boot()  # level 1: no SAS installed
	game._toggle_sas(ShipSim.SasMode.PROGRADE)
	assert_eq(game.ship.sas_mode, ShipSim.SasMode.OFF, "level 1 refuses SAS")


func test_sas_converges_on_retrograde_hold() -> void:
	GameRootScript.level_index = 3  # translunar: SAS + nodes enabled
	var game := _boot()
	var ship: ShipSim = game.ship
	game._toggle_sas(ShipSim.SasMode.RETROGRADE)
	assert_eq(ship.sas_mode, ShipSim.SasMode.RETROGRADE, "hold engaged")
	# Nose starts prograde: ~5.3 s to swing 180 deg, then it settles onto (and
	# tracks) the orbit-swept retrograde; give it the full acquire + settle.
	simulate(game, 600, 1.0 / 60.0)
	var aligned := ship.forward_dir().dot(ship.v.normalized())
	assert_lt(aligned, -0.999, "nose settled on retrograde")
	# toggling the same mode disengages
	game._toggle_sas(ShipSim.SasMode.RETROGRADE)
	assert_eq(ship.sas_mode, ShipSim.SasMode.OFF, "toggle off")


func test_sas_hold_goes_quiet_once_settled() -> void:
	# A settled hold must track the (orbit-swept) prograde on momentum and only
	# trim occasionally - not fire the RCS every frame (which would chatter and,
	# once rotation costs propellant, waste it).
	GameRootScript.level_index = 3
	var game := _boot()
	var ship: ShipSim = game.ship
	game._toggle_sas(ShipSim.SasMode.PROGRADE)
	simulate(game, 300, 1.0 / 60.0)  # acquire + spin up to match prograde's sweep
	var fired := 0
	for i in 300:
		simulate(game, 1, 1.0 / 60.0)
		if ship.rcs_command.length() > 1e-6:
			fired += 1
	assert_lt(fired, 90, "settled hold fires only occasional trims, not every frame")
	assert_gt(ship.forward_dir().dot(ship.v.normalized()), 0.999, "and stays locked on prograde")


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func test_f_and_b_lock_prograde_and_retrograde_with_toggle_release() -> void:
	GameRootScript.level_index = 3  # translunar: SAS + nodes enabled
	var game := _boot()
	var ship: ShipSim = game.ship

	game._unhandled_input(_key(KEY_F))
	assert_eq(ship.sas_mode, ShipSim.SasMode.PROGRADE, "F locks prograde")
	game._unhandled_input(_key(KEY_F))
	assert_eq(ship.sas_mode, ShipSim.SasMode.OFF, "F again releases it")

	game._unhandled_input(_key(KEY_B))
	assert_eq(ship.sas_mode, ShipSim.SasMode.RETROGRADE, "B locks retrograde")
	game._unhandled_input(_key(KEY_B))
	assert_eq(ship.sas_mode, ShipSim.SasMode.OFF, "B again releases it")


func test_g_still_reaches_anti_normal_after_the_remap() -> void:
	GameRootScript.level_index = 3
	var game := _boot()
	var ship: ShipSim = game.ship
	game._unhandled_input(_key(KEY_G))
	assert_eq(ship.sas_mode, ShipSim.SasMode.ANTI_NORMAL, "G moved here, freed by B->retrograde")

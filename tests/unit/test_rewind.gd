extends "res://tests/unit/base_orbit_test.gd"
## Rewind buffer + the game_root scrubber loop (DESIGN.md §14): anchor
## recording, commit/charge, cancel, failure recovery, post-win coast, the
## CLEAN ribbon, and hardcore.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0
	GameRootScript.hardcore = false


func _boot() -> Node:
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	return game


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


# --- RewindBuffer (pure) ---------------------------------------------------

func test_burns_coalesce_within_the_window() -> void:
	var rb := RewindBuffer.new()
	rb.setup(3)
	rb.record_launch({})
	assert_eq(rb.anchors.size(), 1, "launch anchor only")

	assert_true(rb.note_burn_start(10.0, 0, {}), "first burn anchors")
	rb.note_burn_end(11.0)
	assert_false(rb.note_burn_start(11.3, 0, {}), "0.3s later coalesces")
	assert_eq(rb.anchors.size(), 2)
	rb.note_burn_end(12.0)
	assert_true(rb.note_burn_start(13.0, 0, {}), "1s later is a fresh anchor")
	assert_eq(rb.anchors.size(), 3)


func test_commit_spends_a_charge_and_truncates_the_future() -> void:
	var rb := RewindBuffer.new()
	rb.setup(2)
	rb.record_launch({})
	rb.note_burn_start(10.0, 0, {}); rb.note_burn_end(11.0)
	rb.note_burn_start(20.0, 0, {}); rb.note_burn_end(21.0)
	rb.note_burn_start(30.0, 0, {})
	rb.add_landmark(5.0, "EARLY")
	rb.add_landmark(25.0, "LATE")
	assert_eq(rb.anchors.size(), 4, "launch + 3 burns")

	rb.commit(1, true)  # resume at the first burn (t=10)
	assert_eq(rb.charges, 1, "one charge spent")
	assert_eq(rb.rewinds_used, 1)
	assert_eq(rb.anchors.size(), 2, "everything after the resume point dropped")
	assert_eq(rb.landmarks.size(), 1, "only the landmark before the cut survives")
	assert_eq(rb.landmarks[0]["label"], "EARLY")


func test_free_commit_keeps_the_charge() -> void:
	var rb := RewindBuffer.new()
	rb.setup(2)
	rb.record_launch({})
	rb.commit(0, false)
	assert_eq(rb.charges, 2, "a free resume (no time discarded) costs nothing")
	assert_eq(rb.rewinds_used, 0)


# --- Profile CLEAN tracking ------------------------------------------------

func test_record_win_tracks_clean_and_is_sticky() -> void:
	var clean := Profile.new()
	clean.record_win(0, "GOLD ★★★", 60.0, 0)
	assert_true(clean.is_clean(0), "zero rewinds -> CLEAN")

	var dirty := Profile.new()
	dirty.record_win(0, "GOLD ★★★", 60.0, 2)
	assert_false(dirty.is_clean(0), "rewinds used -> not CLEAN")

	var sticky := Profile.new()
	sticky.record_win(0, "SILVER ★★", 80.0, 0)   # clean run
	sticky.record_win(0, "GOLD ★★★", 60.0, 3)    # better dv, but rewound
	assert_true(sticky.is_clean(0), "CLEAN survives a later rewind-assisted best run")
	assert_eq(sticky.medals[0]["medal"], "GOLD ★★★", "still keeps the best-dv medal")


# --- game_root integration -------------------------------------------------

func test_a_burn_records_an_anchor() -> void:
	var game := _boot()
	assert_eq(game.rewind.anchors.size(), 1, "just the launch anchor at start")
	game.ship.throttle = 1.0
	simulate(game, 4, 1.0 / 60.0)
	game.ship.throttle = 0.0
	simulate(game, 2, 1.0 / 60.0)
	assert_eq(game.rewind.anchors.size(), 2, "the burn added one anchor")
	assert_eq(game.rewind.anchors[1]["label"], "BURN")


func test_rewind_resume_spends_a_charge_and_restores_state() -> void:
	var game := _boot()
	var budget: int = game.level.rewind_budget
	assert_true(budget >= 1, "level 0 grants at least one rewind")
	var full_prop: float = game.ship.prop_mass

	game.ship.throttle = 1.0
	simulate(game, 6, 1.0 / 60.0)
	game.ship.throttle = 0.0
	simulate(game, 20, 1.0 / 60.0)
	assert_lt(game.ship.prop_mass, full_prop, "burn consumed propellant")

	game._enter_rewind()
	assert_eq(game.phase, game.Phase.REWINDING)
	game._handle_rewind_keys(_key(KEY_LEFT))   # step to the launch anchor
	game._handle_rewind_keys(_key(KEY_ENTER))  # RESUME HERE

	assert_eq(game.phase, game.Phase.FLYING, "resume returns to flight")
	assert_eq(game.rewind.charges, budget - 1, "one charge spent")
	assert_eq(game.rewind.rewinds_used, 1)
	assert_almost_eq(game.sim_time, 0.0, 0.001, "back at the launch anchor")
	assert_almost_eq(game.ship.prop_mass, full_prop, 1e-6, "propellant restored")


func test_rewind_cancel_costs_nothing_and_returns_to_now() -> void:
	var game := _boot()
	var budget: int = game.level.rewind_budget
	game.ship.throttle = 1.0
	simulate(game, 4, 1.0 / 60.0)
	game.ship.throttle = 0.0
	simulate(game, 20, 1.0 / 60.0)
	var now: float = game.sim_time

	game._enter_rewind()
	game._handle_rewind_keys(_key(KEY_LEFT))    # look at the launch anchor
	game._handle_rewind_keys(_key(KEY_ESCAPE))  # CANCEL

	assert_eq(game.phase, game.Phase.FLYING)
	assert_eq(game.rewind.charges, budget, "cancelling is free")
	assert_almost_eq(game.sim_time, now, 0.001, "returned to the present")


func test_rewind_cancel_during_a_burn_preserves_the_burn() -> void:
	# CR-1: opening then cancelling the scrubber mid-burn must return to "now"
	# unchanged and free - throttle and flight state included (DESIGN §14.1-2).
	var game := _boot()
	var budget: int = game.level.rewind_budget
	game.ship.throttle = 1.0
	simulate(game, 6, 1.0 / 60.0)  # still burning: throttle stays on
	assert_eq(game.ship.flight_state, ShipSim.FlightState.BURNING, "mid-burn")

	var now: float = game.sim_time
	var prop: float = game.ship.prop_mass
	var r0 := DVec3.new(game.ship.r.x, game.ship.r.y, game.ship.r.z)
	var v0 := DVec3.new(game.ship.v.x, game.ship.v.y, game.ship.v.z)
	var anchors_before: int = game.rewind.anchors.size()

	game._enter_rewind()
	game._handle_rewind_keys(_key(KEY_LEFT))    # look at the launch anchor
	game._handle_rewind_keys(_key(KEY_ESCAPE))  # CANCEL

	assert_eq(game.phase, game.Phase.FLYING)
	assert_eq(game.rewind.charges, budget, "cancelling is free")
	assert_almost_eq(game.sim_time, now, 0.001, "returned to the present")
	assert_almost_eq(game.ship.prop_mass, prop, 1e-6, "propellant unchanged")
	assert_almost_eq(game.ship.throttle, 1.0, 1e-9, "throttle restored, burn not cut")
	assert_eq(game.ship.flight_state, ShipSim.FlightState.BURNING, "still burning")
	assert_dvec_close(game.ship.r, r0, 1e-9, "position restored")
	assert_dvec_close(game.ship.v, v0, 1e-9, "velocity restored")

	# The resumed burn must not be re-recorded as a fresh anchor.
	simulate(game, 2, 1.0 / 60.0)
	assert_eq(game.rewind.anchors.size(), anchors_before, "no spurious burn anchor")


func test_resume_is_blocked_at_zero_charges() -> void:
	var game := _boot()
	game.rewind.charges = 0
	game.ship.throttle = 1.0
	simulate(game, 4, 1.0 / 60.0)
	game.ship.throttle = 0.0
	simulate(game, 10, 1.0 / 60.0)

	game._enter_rewind()
	game._handle_rewind_keys(_key(KEY_LEFT))   # to launch (an actual rewind)
	game._handle_rewind_keys(_key(KEY_ENTER))  # RESUME - should be refused
	assert_eq(game.phase, game.Phase.REWINDING, "cannot commit a rewind with no charges")

	game._handle_rewind_keys(_key(KEY_ESCAPE))  # but you can still cancel out
	assert_eq(game.phase, game.Phase.FLYING)


func test_rewind_recovers_from_a_failure() -> void:
	var game := _boot()
	game.ship.throttle = 1.0
	simulate(game, 4, 1.0 / 60.0)
	game.ship.throttle = 0.0
	simulate(game, 6, 1.0 / 60.0)

	game._fail("TEST CRASH")
	assert_eq(game.phase, game.Phase.FAILED)

	game._enter_rewind()
	assert_eq(game.phase, game.Phase.REWINDING, "rewind opens from a failure")
	game._handle_rewind_keys(_key(KEY_ENTER))  # resume at the latest anchor
	assert_eq(game.phase, game.Phase.FLYING, "a failure can be flown out of")
	assert_eq(game.rewind.charges, game.level.rewind_budget - 1)


func test_win_keeps_the_ship_coasting() -> void:
	var game := _boot()
	var target: float = game.level.objective.target_radius
	game.ship.elements = OrbitElements.from_state(
		DVec3.new(target, 0.0, 0.0),
		DVec3.new(0.0, 0.0, -sqrt(game.level.body.mu / target)),
		game.level.body.mu, game.sim_time)
	simulate(game, 5, 1.0 / 60.0)
	assert_eq(game.phase, game.Phase.WON)
	var t: float = game.sim_time
	simulate(game, 20, 1.0 / 60.0)
	assert_gt(game.sim_time, t, "the sim keeps advancing after the win")


func test_hardcore_zeroes_budget_and_strips_guidance() -> void:
	GameRootScript.hardcore = true
	var game := _boot()
	assert_eq(game.rewind.charges, 0, "no rewinds in hardcore")
	assert_false(game.flight_view.guidance_enabled, "predictive aids stripped")


func test_save_payload_carries_rewind_state() -> void:
	var game := _boot()
	game.rewind.charges = 2
	game.rewind.rewinds_used = 1
	var captured := [{}]
	game.save_requested.connect(func(p: Dictionary) -> void: captured[0] = p)
	game._save_progress()
	assert_eq(captured[0]["rewind_charges"], 2)
	assert_eq(captured[0]["rewinds_used"], 1)

extends "res://tests/unit/base_orbit_test.gd"
## Maneuver nodes: plan math, burn accounting, completion, capability gate.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func _lunar_ship() -> ShipSim:
	var ship := ShipSim.new()
	ship.setup(Campaign.level_at(3))
	return ship


func test_prograde_node_raises_predicted_apoapsis() -> void:
	var ship := _lunar_ship()
	ship.create_node(300.0)
	ship.node.prograde = 30.0
	ship.refresh_node_plan()
	var pred := ship.predicted_elements()
	assert_gt(pred.radius_apoapsis(), 71000.0, "apoapsis raised on the far side")
	assert_close(pred.radius_periapsis(), 70000.0, 0.01, "periapsis stays at the node")
	assert_close(ship.node.remaining.length(), 30.0, 1e-9, "remaining = planned")


func test_normal_node_tilts_orbit_plane() -> void:
	var ship := _lunar_ship()
	ship.create_node(200.0)
	ship.node.normal = 50.0
	ship.refresh_node_plan()
	var pred := ship.predicted_elements()
	var state := pred.state_at_time(200.0)
	var h_dir := state.r.cross(state.v).normalized()
	# 50 m/s normal vs ~1047 m/s orbital -> ~2.7 degrees of tilt
	assert_between(h_dir.dot(DVec3.new(0, 1, 0)), 0.99, 0.9995, "plane tilted")


func test_burn_depletes_remaining_and_completes_node() -> void:
	var ship := _lunar_ship()
	ship.create_node(60.0)
	ship.node.prograde = 20.0
	ship.refresh_node_plan()
	var dir := ship.node.remaining.normalized().to_vector3()
	ship.attitude = Basis.looking_at(dir, Vector3.UP)
	ship.throttle = 1.0
	var t := 0.0
	while ship.node != null and t < 30.0:
		t += 0.1
		ship.advance_to(t)
	assert_null(ship.node, "node auto-completes when burned")
	assert_true(ship.node_completed, "completion flag raised")
	assert_between(ship.dv_used(), 19.0, 21.5, "burned roughly the planned dv")


func test_predicted_ghost_does_not_double_count_delivered_dv() -> void:
	# CR-7: mid-burn the ghost must apply the REMAINING plan, not the full authored
	# dv on top of the already-delivered part. The predicted final orbit is the
	# same throughout the burn (delivered + remaining = the full plan).
	var ship := _lunar_ship()
	ship.create_node(300.0)
	ship.node.prograde = 30.0
	ship.refresh_node_plan()
	var pred_before := ship.predicted_elements().radius_apoapsis()

	var dir := ship.node.remaining.normalized().to_vector3()
	ship.attitude = Basis.looking_at(dir, Vector3.UP)
	ship.throttle = 1.0
	var t := 0.0
	while ship.node != null and ship.node.remaining.length() > 15.0 and t < 20.0:
		t += 0.1
		ship.advance_to(t)
	assert_not_null(ship.node, "still mid-burn (~half the node delivered)")
	var pred_mid := ship.predicted_elements().radius_apoapsis()
	assert_almost_eq(pred_mid, pred_before, pred_before * 0.05,
		"predicted apoapsis stays stable mid-burn (the old bug ballooned it)")


func test_off_axis_burn_still_completes_the_node() -> void:
	# CR-7: burning off the node direction can't shrink the perpendicular part of
	# remaining, so the old |remaining|<0.5 test left the node stuck forever. The
	# projection crossing completes it once the owed dv along the nose is spent.
	var ship := _lunar_ship()
	ship.create_node(60.0)
	ship.node.prograde = 20.0
	ship.refresh_node_plan()
	var dir := ship.node.remaining.normalized().to_vector3()
	var axis := Vector3(0, 1, 0).cross(dir).normalized()
	ship.attitude = Basis.looking_at(dir.rotated(axis, deg_to_rad(40.0)), Vector3.UP)
	ship.throttle = 1.0
	var t := 0.0
	while ship.node != null and t < 40.0:
		t += 0.1
		ship.advance_to(t)
	assert_null(ship.node, "an off-axis burn still completes instead of getting stuck")


func test_single_tick_over_delivering_completes_the_node() -> void:
	# CR-7: one high-accel tick can deliver far more than the remaining dv; that
	# must complete the node, not overshoot into a growing opposite vector.
	var ship := _lunar_ship()
	ship.create_node(100.0)
	ship.node.prograde = 2.0  # tiny node vs a multi-second full-throttle tick
	ship.refresh_node_plan()
	var dir := ship.node.remaining.normalized().to_vector3()
	ship.attitude = Basis.looking_at(dir, Vector3.UP)
	ship.throttle = 1.0
	ship.advance_to(5.0)  # a single burn call delivering >> 2 m/s
	assert_null(ship.node, "over-delivering in one tick completes the node")
	assert_true(ship.node_completed, "completion flag raised")


func test_warp_stops_at_scheduled_node_time() -> void:
	GameRootScript.level_index = 3
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	game._node_create()
	var t_node: float = game.ship.node.t_node  # 120s ahead of sim_time

	# single-step at max warp (~42 s/tick) until an event auto-drops warp,
	# then check it landed at the node, not blown past it
	var frames := 0
	var stopped_near_node := false
	while frames < 500:
		game.warp_index = game.WARP_STEPS.size() - 1
		simulate(game, 1, 1.0 / 60.0)
		frames += 1
		if game.warp_index == 0:
			stopped_near_node = absf(game.sim_time - t_node) < 5.0
			break
	assert_true(stopped_near_node,
		"warp dropped to 1x within 5s of the node time (got sim_time=%s, t_node=%s)"
		% [game.sim_time, t_node])


func test_normalize_coast_settles_a_cut_burn_but_not_an_active_one() -> void:
	# CR-1 unit: a throttle cut leaves flight_state BURNING until an advance;
	# normalize_coast() settles it to COASTING immediately, but only once the ship
	# is genuinely not thrusting.
	var ship := _lunar_ship()
	ship.throttle = 1.0
	ship.advance_to(2.0)
	assert_eq(ship.flight_state, ShipSim.FlightState.BURNING, "burning after a throttle-on advance")
	ship.normalize_coast()
	assert_eq(ship.flight_state, ShipSim.FlightState.BURNING, "an actively-thrusting ship stays BURNING")
	ship.throttle = 0.0
	ship.normalize_coast()
	assert_eq(ship.flight_state, ShipSim.FlightState.COASTING, "a cut burn settles to COASTING")


func test_throttle_cut_then_warp_still_clamps_to_the_next_event() -> void:
	# CR-1 integration: cut throttle (state stays BURNING) then warp in the same
	# input gap — the rails-warp event clamp must still engage, not skip the event.
	GameRootScript.level_index = 3
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)

	# Leave the ship in the exact CR-1 state: burned one tick, throttle cut, but
	# flight_state still BURNING (no advance has refitted it yet).
	game.ship.throttle = 1.0
	simulate(game, 1, 1.0 / 60.0)
	game.ship.throttle = 0.0
	assert_eq(game.ship.flight_state, ShipSim.FlightState.BURNING,
		"precondition: throttle cut but state still BURNING")

	# An event ~10 s ahead — inside a single max-warp tick (1000x -> ~16.7 s).
	game._node_create()
	var t_node: float = game.sim_time + 10.0
	game.ship.node.t_node = t_node
	game.ship.refresh_node_plan()

	game.warp_index = game.WARP_STEPS.size() - 1
	simulate(game, 1, 1.0 / 60.0)
	assert_lt(game.sim_time, t_node + 3.0,
		"warp clamped near the event (%.1f) instead of skipping past it (sim_time=%.1f)"
		% [t_node, game.sim_time])
	assert_eq(game.warp_index, 0, "and dropped out of warp at the event")


func test_node_capability_gate_and_game_flow() -> void:
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	game._node_create()  # level 1: computer not installed
	assert_null(game.ship.node, "level 1 refuses nodes")

	GameRootScript.level_index = 3
	var game2: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game2)
	simulate(game2, 2, 1.0 / 60.0)
	game2._node_create()
	assert_not_null(game2.ship.node, "level 2 grants nodes")
	game2._node_adjust(GameRootScript.NodeField.PROGRADE, 25.0)
	game2._node_adjust(GameRootScript.NodeField.T_NODE, 60.0)
	assert_close(game2.ship.node.remaining.length(), 25.0, 1e-6, "plan updated")
	simulate(game2, 10, 1.0 / 60.0)  # views rebuild ghost lines without errors
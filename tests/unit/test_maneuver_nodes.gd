extends "res://tests/unit/base_orbit_test.gd"
## Maneuver nodes: plan math, burn accounting, completion, capability gate.

const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0


func _lunar_ship() -> ShipSim:
	var ship := ShipSim.new()
	ship.setup(Level02.make())
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


func test_node_capability_gate_and_game_flow() -> void:
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 2, 1.0 / 60.0)
	game._node_create()  # level 1: computer not installed
	assert_null(game.ship.node, "level 1 refuses nodes")

	GameRootScript.level_index = 1
	var game2: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game2)
	simulate(game2, 2, 1.0 / 60.0)
	game2._node_create()
	assert_not_null(game2.ship.node, "level 2 grants nodes")
	game2._node_adjust("prograde", 25.0)
	game2._node_adjust("t_node", 60.0)
	assert_close(game2.ship.node.remaining.length(), 25.0, 1e-6, "plan updated")
	simulate(game2, 10, 1.0 / 60.0)  # views rebuild ghost lines without errors
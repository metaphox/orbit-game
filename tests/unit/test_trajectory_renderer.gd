extends "res://tests/unit/base_orbit_test.gd"
## Build + visibility behaviour for the TrajectoryRenderer, extracted from
## FlightView (TD-2/TD-3): the right target-ring shape per objective and the
## hardcore rule that hides the prediction line while the target ring stays.


func _renderer_for(level_path: String) -> TrajectoryRenderer:
	var level: LevelDef = load(level_path)
	var renderer := TrajectoryRenderer.new()
	add_child_autofree(renderer)
	renderer.build(level, RenderTheme.default())
	return renderer


func test_orbit_match_level_builds_a_dashed_target_ring() -> void:
	var renderer := _renderer_for("res://src/levels/data/level_01_01.tres")
	assert_not_null(renderer._traj_instance, "prediction line instance is built")
	assert_not_null(renderer._target_instance, "target ring instance is built")
	assert_not_null(renderer._target_instance.material_override,
		"the dashed ring carries a single line material override")


func test_entry_corridor_level_builds_a_banded_gate() -> void:
	var renderer := _renderer_for("res://src/levels/data/level_02_03.tres")
	assert_gt(renderer._target_instance.mesh.get_surface_count(), 1,
		"the corridor gate is a multi-surface band (fill + edge rings), not a single ring")
	assert_null(renderer._target_instance.material_override,
		"the band carries per-surface materials, not one override")


func test_guidance_disabled_hides_prediction_line_but_keeps_target() -> void:
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	var renderer := TrajectoryRenderer.new()
	add_child_autofree(renderer)
	renderer.build(level, RenderTheme.default())

	var ship := ShipSim.new()
	ship.setup(level)
	var t := ship.last_time
	var ship_abs := ship.absolute_position(t)

	renderer.sync(ship, ship_abs, t, false)
	assert_false(renderer._traj_instance.visible, "hardcore hides the forward prediction line")
	assert_true(renderer._target_instance.visible, "the target ring stays visible in hardcore")

	renderer.sync(ship, ship_abs, t, true)
	assert_true(renderer._traj_instance.visible, "guidance restores the prediction line")


# --- PF-1: no wasted sampling on hidden or unchanged geometry ---------------

func test_hardcore_hidden_line_is_never_sampled() -> void:
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	var renderer := TrajectoryRenderer.new()
	add_child_autofree(renderer)
	renderer.build(level, RenderTheme.default())
	var ship := ShipSim.new()
	ship.setup(level)

	renderer.sync(ship, ship.absolute_position(ship.last_time), ship.last_time, false)
	# A never-sampled line has zero mesh surfaces: the hidden path early-outs
	# before _rebuild_line, so hardcore pays no sampling / mesh-upload cost.
	assert_eq(renderer._traj_mesh.get_surface_count(), 0,
		"hardcore never builds the hidden prediction line")


func test_unchanged_geometry_is_not_rebuilt() -> void:
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	var renderer := TrajectoryRenderer.new()
	add_child_autofree(renderer)
	renderer.build(level, RenderTheme.default())
	var ship := ShipSim.new()
	ship.setup(level)
	var t := ship.last_time

	renderer.sync(ship, ship.absolute_position(t), t, true)
	assert_gt(renderer._traj_mesh.get_surface_count(), 0, "the first visible frame builds the line")

	# Wipe the mesh: a needless rebuild on an unchanged frame would refill it.
	renderer._traj_mesh.clear_surfaces()
	renderer.sync(ship, ship.absolute_position(t), t, true)  # same revision + time (frozen)
	assert_eq(renderer._traj_mesh.get_surface_count(), 0,
		"a frozen / unchanged frame reuses the cached line instead of rebuilding")


func test_advancing_the_coast_rebuilds_the_line() -> void:
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	var renderer := TrajectoryRenderer.new()
	add_child_autofree(renderer)
	renderer.build(level, RenderTheme.default())
	var ship := ShipSim.new()
	ship.setup(level)

	renderer.sync(ship, ship.absolute_position(ship.last_time), ship.last_time, true)
	renderer._traj_mesh.clear_surfaces()
	ship.advance_to(ship.last_time + 30.0)  # the ship walked along its orbit
	renderer.sync(ship, ship.absolute_position(ship.last_time), ship.last_time, true)
	assert_gt(renderer._traj_mesh.get_surface_count(), 0,
		"a new coast frame rebuilds so the line stays glued to the ship")

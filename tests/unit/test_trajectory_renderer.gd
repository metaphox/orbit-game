extends "res://tests/unit/base_orbit_test.gd"
## Build + visibility behaviour for the TrajectoryRenderer, extracted from
## FlightView (TD-2/TD-3): the right target-ring shape per objective and the
## hardcore rule that hides the prediction line while the target ring stays.


func _renderer_for(level: LevelDef) -> TrajectoryRenderer:
	var renderer := TrajectoryRenderer.new()
	add_child_autofree(renderer)
	renderer.build(level, RenderTheme.default())
	return renderer


func test_orbit_match_level_builds_a_dashed_target_ring() -> void:
	var renderer := _renderer_for(Campaign.level_at(0))
	assert_not_null(renderer._traj_instance, "prediction line instance is built")
	assert_not_null(renderer._target_instance, "target ring instance is built")
	assert_not_null(renderer._target_instance.material_override,
		"the dashed ring carries a single line material override")


func test_entry_corridor_level_builds_a_banded_gate() -> void:
	var renderer := _renderer_for(Campaign.level_at(5))
	assert_gt(renderer._target_instance.mesh.get_surface_count(), 1,
		"the corridor gate is a multi-surface band (fill + edge rings), not a single ring")
	assert_null(renderer._target_instance.material_override,
		"the band carries per-surface materials, not one override")


func test_guidance_disabled_hides_prediction_line_but_keeps_target() -> void:
	var level: LevelDef = Campaign.level_at(0)
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
	var level: LevelDef = Campaign.level_at(0)
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
	var level: LevelDef = Campaign.level_at(0)
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


# --- Floating-origin precision: the line is built in ship-relative space -----

func test_line_is_built_ship_relative_not_body_centred() -> void:
	# The whole float32 fix: vertices are (conic point - ship.r) folded in double,
	# so the vertex sitting on the ship is ~origin (small) - NOT the ship's
	# body-centred position (~7e4), which the old cast-then-GPU-subtract path
	# emitted. A large min-magnitude vertex means the regression is back and the
	# near-camera line will quantize/jitter at the float32 ULP of that magnitude.
	var level: LevelDef = Campaign.level_at(0)
	var renderer := TrajectoryRenderer.new()
	add_child_autofree(renderer)
	renderer.build(level, RenderTheme.default())
	var ship := ShipSim.new()
	ship.setup(level)
	var t := ship.last_time
	renderer.sync(ship, ship.absolute_position(t), t, true)

	var verts: PackedVector3Array = renderer._traj_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var nearest := INF
	for vertex: Vector3 in verts:
		nearest = minf(nearest, vertex.length())
	assert_lt(nearest, 1.0,
		"the on-ship vertex sits ~at the render origin (ship-relative), not at r~7e4")
	# The instance itself stays at the origin - the offset lives in the vertices.
	assert_eq(renderer._traj_instance.position, Vector3.ZERO,
		"the line instance is not re-centred by a large float32 node translation")


func test_advancing_the_coast_rebuilds_the_line() -> void:
	var level: LevelDef = Campaign.level_at(0)
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

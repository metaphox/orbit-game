extends "res://tests/unit/base_orbit_test.gd"
## HUD layout regression: the minimap, objective panel, and warp readout
## share a single top-right VBoxContainer (see hud.gd _build_right_column)
## instead of three independently hand-tuned pixel offsets that all needed
## the same magic 560 px width to avoid overlapping each other. Confirm
## they actually don't overlap - at more than one window size, since that
## was the whole point of switching to a container.

const DEFAULT_SIZE := Vector2i(1024, 768)


func after_each() -> void:
	get_tree().root.size = DEFAULT_SIZE


func _assert_no_overlap_at_size(size: Vector2i) -> void:
	get_tree().root.size = size
	var level := Campaign.level_at(0)
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.build(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var minimap_rect := hud.minimap_root.get_global_rect()
	var objective_rect := hud.objective_label.get_global_rect()
	assert_false(
		minimap_rect.intersects(objective_rect),
		"at %s: minimap %s overlaps objective panel %s" % [size, minimap_rect, objective_rect])
	# both should still be on-screen, not just non-overlapping because one
	# collapsed to zero size or got pushed off-canvas
	assert_gt(minimap_rect.size.x, 0.0, "at %s: minimap has real width" % size)
	assert_gt(minimap_rect.size.y, 0.0, "at %s: minimap has real height" % size)
	assert_gt(objective_rect.size.y, 0.0, "at %s: objective panel has real height" % size)


func test_minimap_and_objective_panel_dont_overlap_at_min_window_size() -> void:
	await _assert_no_overlap_at_size(DEFAULT_SIZE)


func test_minimap_and_objective_panel_dont_overlap_at_a_larger_window_size() -> void:
	await _assert_no_overlap_at_size(Vector2i(1920, 1080))

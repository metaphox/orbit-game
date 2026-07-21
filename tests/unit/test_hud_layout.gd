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
	Settings.debug_mode = false


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


## Regression for the minimap dominating a small window: it must stay
## within its clamped pixel bounds and well under a third of the window's
## width, instead of the old fixed 560px block (54% of the 1024 base).
func test_minimap_stays_within_a_bounded_fraction_of_a_small_window() -> void:
	get_tree().root.size = DEFAULT_SIZE
	var level := Campaign.level_at(0)
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.build(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var minimap_rect := hud.minimap_root.get_global_rect()
	assert_gt(minimap_rect.size.x, 219.0, "minimap width respects its lower clamp")
	assert_lt(minimap_rect.size.x, 341.0, "minimap width respects its upper clamp")
	assert_lt(minimap_rect.size.x, DEFAULT_SIZE.x * 0.3,
		"minimap should not cover close to a third of a small window's width")


func test_fps_label_only_appears_in_debug_mode() -> void:
	var level := Campaign.level_at(0)
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.build(level)
	assert_null(hud._fps_label, "no FPS readout for regular play")

	Settings.debug_mode = true
	var debug_hud := Hud.new()
	add_child_autofree(debug_hud)
	debug_hud.build(level)
	assert_not_null(debug_hud._fps_label, "debug mode adds the FPS readout")
	debug_hud._process(0.016)
	assert_true(debug_hud._fps_label.text.begins_with("FPS "), "shows a live FPS reading")

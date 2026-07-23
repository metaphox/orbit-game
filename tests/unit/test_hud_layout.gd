extends "res://tests/unit/base_orbit_test.gd"
## Responsive scene-layout regression: the minimap and objective share one
## scene-owned rail, while the guidance rail and flight strip remain on-screen.

const DEFAULT_SIZE := Vector2i(1920, 1080)


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
	var telemetry_rect := (hud._top_bar.get_node("%LeftTelemetry") as Control).get_global_rect()
	var met_rect := (hud._top_bar.get_node("%MetBlock") as Control).get_global_rect()
	var top_bar_rect := hud._top_bar.get_global_rect()
	var title_rect := (hud._top_bar.get_node("TitleChip") as Control).get_global_rect()
	assert_false(
		minimap_rect.intersects(objective_rect),
		"at %s: minimap %s overlaps objective panel %s" % [size, minimap_rect, objective_rect])
	# both should still be on-screen, not just non-overlapping because one
	# collapsed to zero size or got pushed off-canvas
	assert_gt(minimap_rect.size.x, 0.0, "at %s: minimap has real width" % size)
	assert_gt(minimap_rect.size.y, 0.0, "at %s: minimap has real height" % size)
	assert_gt(objective_rect.size.y, 0.0, "at %s: objective panel has real height" % size)
	assert_gte(telemetry_rect.position.x, 0.0, "at %s: MET block stays on-screen" % size)
	assert_lte(met_rect.end.y, top_bar_rect.end.y,
		"at %s: MET block stays inside the top bar" % size)
	assert_false(met_rect.intersects(minimap_rect),
		"at %s: MET block does not clip into the minimap" % size)
	assert_false(telemetry_rect.intersects(title_rect),
		"at %s: telemetry %s overlaps mission title %s" % [size, telemetry_rect, title_rect])


func test_minimap_and_objective_panel_dont_overlap_at_min_window_size() -> void:
	await _assert_no_overlap_at_size(Vector2i(1280, 720))


func test_minimap_and_objective_panel_dont_overlap_at_default_window_size() -> void:
	await _assert_no_overlap_at_size(DEFAULT_SIZE)


func test_minimap_and_objective_panel_dont_overlap_at_a_larger_window_size() -> void:
	await _assert_no_overlap_at_size(Vector2i(2560, 1440))


## Regression for the minimap dominating a small window: it must stay
## within its clamped pixel bounds and well under a third of the window's
## width, instead of the old fixed 560px block (54% of the 1024 base).
func test_minimap_stays_within_a_bounded_fraction_of_a_small_window() -> void:
	var small_size := Vector2i(1280, 720)
	get_tree().root.size = small_size
	var level := Campaign.level_at(0)
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.build(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var minimap_rect := hud.minimap_root.get_global_rect()
	assert_gt(minimap_rect.size.x, 219.0, "minimap width respects its lower clamp")
	assert_lt(minimap_rect.size.x, 341.0, "minimap width respects its upper clamp")
	assert_lt(minimap_rect.size.x, small_size.x * 0.3,
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


func test_full_capability_toolbar_stays_on_screen_at_minimum_size() -> void:
	var minimum_size := Vector2i(1280, 720)
	get_tree().root.size = minimum_size
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.build(Campaign.level_at(3))
	await get_tree().process_frame
	await get_tree().process_frame
	var toolbar_rect := hud._flight_strip.toolbar.get_global_rect()
	assert_gte(toolbar_rect.position.y, 0.0, "wrapped toolbar does not escape above the viewport")
	assert_lte(toolbar_rect.end.y, float(minimum_size.y),
		"SAS, node, and F1 controls all remain inside the minimum-height viewport")

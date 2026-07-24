extends "res://tests/unit/base_orbit_test.gd"
## Scene-first UI contract: every layout/component scene loads independently and
## exposes the unique nodes its typed script owns.


func test_shared_theme_is_cached_and_defines_core_variations() -> void:
	var theme := UiTheme.shared()
	assert_same(theme, UiTheme.shared(), "all UI roots share one generated Theme")
	assert_eq(theme.get_type_variation_base(UiTheme.DISPLAY_TITLE), &"Label")
	assert_eq(theme.get_type_variation_base(UiTheme.INSTRUMENT_PANEL), &"PanelContainer")
	assert_eq(theme.get_type_variation_base(UiTheme.HUD_BAR_BACKGROUND), &"Panel")
	assert_eq(theme.get_type_variation_base(UiTheme.HUD_DIVIDER), &"VSeparator")
	assert_eq(theme.get_type_variation_base(UiTheme.HUD_RULE), &"HSeparator")
	assert_eq(theme.get_type_variation_base(UiTheme.INTENT_INDICATOR), &"Panel")
	assert_eq(theme.get_type_variation_base(UiTheme.MAP_BACKDROP), &"Panel")
	assert_eq(theme.get_type_variation_base(UiTheme.PAUSE_SCRIM), &"Panel")
	assert_eq(theme.get_type_variation_base(UiTheme.TOOLBAR_BUTTON), &"Button")
	assert_eq(theme.get_type_variation_base(UiTheme.PRIMARY_BUTTON), &"Button")
	assert_eq(theme.get_type_variation_base(UiTheme.DANGER_BUTTON), &"Button")
	assert_eq(theme.get_type_variation_base(UiTheme.CARD), &"Button")
	assert_eq(theme.get_type_variation_base(UiTheme.CARD_SELECTED), &"Button")
	assert_eq(theme.get_type_variation_base(UiTheme.LAUNCH_BUTTON), &"Button")
	assert_eq(theme.get_type_variation_base(UiTheme.ACT_HEADER), &"Label")
	assert_eq(theme.get_type_variation_base(UiTheme.BREADCRUMB), &"Label")
	assert_eq(theme.get_type_variation_base(UiTheme.CODE_CHIP), &"PanelContainer")
	assert_eq(theme.get_type_variation_base(UiTheme.HINT_BAR), &"PanelContainer")
	assert_true(theme.has_stylebox("disabled", UiTheme.LAUNCH_BUTTON),
		"buttons carry a disabled stylebox (locked LAUNCH reads dim)")
	assert_eq(theme.get_color(&"HAIRLINE", &"Palette"), Palette.HAIRLINE)
	assert_eq(theme.get_color(&"BODY_EARTH", &"Palette"), Palette.BODY_TINTS["EARTH"])
	var editor_preview_scripts: Array[String] = [
		"res://src/ui/generated_ui_theme.gd",
		"res://src/ui/top_telemetry_bar.gd",
		"res://src/ui/propellant_flight_strip.gd",
		"res://src/ui/flight_toolbar.gd",
		"res://src/ui/bar_meter.gd",
		"res://src/ui/attitude_director.gd",
		"res://src/ui/hazard_stripe.gd",
		"res://src/ui/rewind_timeline.gd",
		"res://src/ui/difficulty_pips.gd",
		"res://src/ui/backdrop.gd",
	]
	for path: String in editor_preview_scripts:
		var preview_script: Script = load(path)
		assert_true(preview_script.is_tool(), "%s renders its editor preview" % path)


func test_hud_component_scenes_expose_required_unique_nodes() -> void:
	var cases: Array[Array] = [
		["res://src/ui/top_telemetry_bar.tscn", "%MetValue"],
		["res://src/ui/minimap_objective_rail.tscn", "%MinimapRoot"],
		["res://src/ui/guidance_warp_rail.tscn", "%GuidanceDirector"],
		["res://src/ui/flight_toolbar.tscn", "%Groups"],
		["res://src/ui/propellant_flight_strip.tscn", "%PropellantPercent"],
		["res://src/ui/hud_overlays.tscn", "%MissionPanel"],
	]
	for entry: Array in cases:
		var packed: PackedScene = load(entry[0])
		assert_not_null(packed, "%s loads" % entry[0])
		var component := packed.instantiate() as Control
		add_child_autofree(component)
		assert_not_null(component.get_node(entry[1]), "%s owns %s" % entry)
		assert_same(component.theme, UiTheme.shared(), "%s previews the shared Theme" % entry[0])


func test_complete_hud_layout_instantiates_all_components() -> void:
	var layout: HudLayout = preload("res://src/ui/hud_layout.tscn").instantiate()
	add_child_autofree(layout)
	assert_not_null(layout.get_node("%TopTelemetryBar"))
	assert_not_null(layout.get_node("%MinimapObjectiveRail"))
	assert_not_null(layout.get_node("%GuidanceWarpRail"))
	assert_not_null(layout.get_node("%PropellantFlightStrip"))
	assert_not_null(layout.get_node("%HudOverlays"))
	assert_same(layout.theme, UiTheme.shared())


func test_menu_layout_scenes_expose_typed_dynamic_slots() -> void:
	# The two-pane redesign owns the menu chrome now (MenuShell + code-built
	# components); NewProfileLayout is the last remaining scene-authored form.
	var profile_layout: NewProfileLayout = preload("res://src/ui/new_profile_layout.tscn").instantiate()
	add_child_autofree(profile_layout)
	assert_same(profile_layout.theme, UiTheme.shared())
	assert_not_null(profile_layout.line_edit)
	assert_not_null(profile_layout.hardcore_check)


func test_menu_shell_and_cards_build_headless() -> void:
	var shell := MenuShell.new()
	add_child_autofree(shell)
	shell.configure("MAIN MENU ▶ MISSIONS")
	assert_same(shell.theme, UiTheme.shared(), "the shell carries the shared theme for its children")
	assert_not_null(shell.left_column)
	assert_not_null(shell.right_pane)

extends "res://tests/unit/base_orbit_test.gd"
## Build + visibility contract for ManeuverVisuals, extracted from FlightView
## (TD-2). The heavier encounter-scan caching + node-ghost behaviour is exercised
## end-to-end in test_moon_transfer; this pins the cheap invariants directly.


func _built_on(level_path: String) -> ManeuverVisuals:
	var level: LevelDef = load(level_path)
	var mv := ManeuverVisuals.new()
	add_child_autofree(mv)
	mv.build(level)
	return mv


func test_build_creates_orbit_marks_and_node_visuals_all_hidden() -> void:
	var mv := _built_on("res://src/levels/data/level_01_01.tres")
	for mark in [mv._ap_marker, mv._pe_marker, mv._an_marker, mv._dn_marker,
			mv._impact_marker, mv._encounter_marker, mv._closest_approach_marker]:
		assert_not_null(mark, "each orbit mark is built up front")
		assert_false(mark.visible, "marks start hidden until a refresh places them")
	assert_not_null(mv._node_instance, "the node ghost line instance is built")
	assert_not_null(mv._preview_instance, "the moon-encounter preview instance is built")
	assert_false(mv._node_marker.visible, "the node marker starts hidden with no node")


func test_refresh_shows_periapsis_and_apoapsis_for_an_elliptic_orbit() -> void:
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	var mv := ManeuverVisuals.new()
	add_child_autofree(mv)
	mv.build(level)
	var ship := ShipSim.new()
	ship.setup(level)

	mv.sync(ship, 1.0, 3.0e5, true)  # traj_timer starts at 0 -> refresh fires immediately
	assert_true(mv._pe_marker.visible, "a bound orbit always shows its periapsis")
	assert_true(mv._ap_marker.visible, "a bound orbit shows its apoapsis")


func test_guidance_disabled_hides_the_node_ghost_and_preview() -> void:
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	var mv := ManeuverVisuals.new()
	add_child_autofree(mv)
	mv.build(level)
	var ship := ShipSim.new()
	ship.setup(level)

	mv.sync(ship, 1.0, 3.0e5, false)
	assert_false(mv._node_instance.visible, "hardcore hides the maneuver-node ghost")
	assert_false(mv._preview_instance.visible, "hardcore hides the encounter preview")
	assert_false(mv._node_marker.visible, "hardcore hides the node marker")

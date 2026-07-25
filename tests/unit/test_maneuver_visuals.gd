extends "res://tests/unit/base_orbit_test.gd"
## Build + visibility contract for ManeuverVisuals, extracted from FlightView
## (TD-2). The heavier encounter-scan caching + node-ghost behaviour is exercised
## end-to-end in test_moon_transfer; this pins the cheap invariants directly.


func _built_on(level: LevelDef) -> ManeuverVisuals:
	var mv := ManeuverVisuals.new()
	add_child_autofree(mv)
	mv.build(level)
	return mv


## A ship on a clearly-elliptic orbit (level starts are circular, where apsides
## are undefined and hidden): a short prograde burn raises apoapsis, then coast.
func _elliptic_ship(level: LevelDef) -> ShipSim:
	var ship := ShipSim.new()
	ship.setup(level)
	ship.throttle = 1.0
	ship.advance_to(3.0)
	ship.throttle = 0.0
	ship.advance_to(4.0)  # settle back into a coast with the new (elliptic) elements
	return ship


func test_build_creates_orbit_marks_and_node_visuals_all_hidden() -> void:
	var mv := _built_on(Campaign.level_at(0))
	for mark in [mv._ap_marker, mv._pe_marker, mv._circular_marker, mv._an_marker,
			mv._dn_marker, mv._impact_marker, mv._encounter_marker, mv._closest_approach_marker]:
		assert_not_null(mark, "each orbit mark is built up front")
		assert_false(mark.visible, "marks start hidden until a refresh places them")
	assert_not_null(mv._node_instance, "the node ghost line instance is built")
	assert_not_null(mv._preview_instance, "the moon-encounter preview instance is built")
	assert_false(mv._node_marker.visible, "the node marker starts hidden with no node")


func test_refresh_shows_periapsis_and_apoapsis_for_an_elliptic_orbit() -> void:
	var level: LevelDef = Campaign.level_at(0)
	var mv := _built_on(level)
	var ship := _elliptic_ship(level)
	assert_gt(ship.current_elements().e, ManeuverVisuals.CIRCULAR_E, "the orbit is elliptic")

	mv.sync(ship, 1.0, 3.0e5, true)  # traj_timer starts at 0 -> refresh fires immediately
	assert_true(mv._pe_marker.visible, "a bound elliptic orbit shows its periapsis")
	assert_true(mv._ap_marker.visible, "a bound elliptic orbit shows its apoapsis")
	assert_false(mv._circular_marker.visible, "the CIRCULAR callout is only for a circle")


func test_near_circular_orbit_shows_a_single_circular_callout() -> void:
	var level: LevelDef = Campaign.level_at(0)  # circular start, e ~ 0
	var mv := _built_on(level)
	var ship := ShipSim.new()
	ship.setup(level)
	assert_lt(ship.current_elements().e, ManeuverVisuals.CIRCULAR_E, "the start is circular")

	mv.sync(ship, 1.0, 3.0e5, true)
	assert_false(mv._pe_marker.visible, "a circle has no periapsis to mark")
	assert_false(mv._ap_marker.visible, "a circle has no apoapsis to mark")
	assert_true(mv._circular_marker.visible, "a circle shows one CIRCULAR callout instead")
	var pos := mv._circular_marker.position
	assert_almost_eq(pos.length(), ManeuverVisuals.CIRCULAR_MARK_LEAD, 100.0,
		"the callout leads the ship by ~10 km (chord ≈ arc)")
	var on_orbit := ship.r.add(DVec3.new(pos.x, pos.y, pos.z)).length()
	assert_almost_eq(on_orbit, ship.r.length(), 5.0, "the callout sits on the circular orbit")

	var texts := {}
	for d: Dictionary in mv.orbit_label_data():
		texts[d["text"]] = true
	assert_true(texts.has(tr("CIRCULAR")), "the circular callout is labelled")
	assert_false(texts.has(tr("APOAPSIS")), "no apoapsis callout on a circular orbit")
	assert_false(texts.has(tr("PERIAPSIS")), "no periapsis callout on a circular orbit")


func test_orbit_label_data_reports_visible_marks_with_colour_and_text() -> void:
	var level: LevelDef = Campaign.level_at(0)
	var mv := _built_on(level)
	assert_eq(mv.orbit_label_data().size(), 0, "no marks placed yet -> nothing to label")

	var ship := _elliptic_ship(level)  # circular starts hide their (undefined) apsides
	mv.sync(ship, 1.0, 3.0e5, true)  # places the marks

	var data := mv.orbit_label_data()
	var texts := {}
	for d: Dictionary in data:
		texts[d["text"]] = d["color"]
		assert_true(d["pos"] is Vector3, "each label carries a render-space point")
	assert_true(texts.has(tr("PERIAPSIS")), "periapsis is labelled on a bound orbit")
	assert_true(texts.has(tr("APOAPSIS")), "apoapsis is labelled on a bound orbit")
	assert_eq(texts[tr("APOAPSIS")], RenderTheme.default().mark_ap,
		"the label colour is the mark's theme colour, not a hard-coded one")


func test_guidance_disabled_hides_the_node_ghost_and_preview() -> void:
	var level: LevelDef = Campaign.level_at(0)
	var mv := ManeuverVisuals.new()
	add_child_autofree(mv)
	mv.build(level)
	var ship := ShipSim.new()
	ship.setup(level)

	mv.sync(ship, 1.0, 3.0e5, false)
	assert_false(mv._node_instance.visible, "hardcore hides the maneuver-node ghost")
	assert_false(mv._preview_instance.visible, "hardcore hides the encounter preview")
	assert_false(mv._node_marker.visible, "hardcore hides the node marker")

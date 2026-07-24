extends GutTest
## TDD contract for the JSON level pipeline: the body catalog (identity + scale
## sanity) and the level loader (unit conversion, station_mu auto-fill, the
## critical objective.target === moons[i] identity, and readable validation
## errors instead of crashes).

const INF_R := INF


func test_catalog_build_links_parents_to_shared_instances() -> void:
	var g := BodyCatalog.build("SOL", [{"name": "EARTH"}, {"name": "MARS", "phase_deg": 43.76}])
	assert_eq(g.root.name, "SOL", "root is the named system body")
	assert_eq(g.root.soi_radius, INF_R, "the root's SOI is INF (it's the level's universe centre)")
	assert_null(g.root.parent, "the root has no parent")
	var mars: BodyDef = g.by_name["MARS"]
	assert_same(mars.parent, g.root, "a moon's parent is the SAME in-graph root instance")
	assert_almost_eq(mars.orbit_phase_deg, 43.76, 0.001, "per-level phase is applied")
	assert_true(g.moons.has(g.by_name["EARTH"]) and g.moons.has(mars), "both bodies are moons")


func test_catalog_scale_matches_legacy_values() -> void:
	# The 4 shipped bodies must be byte-identical to the old .tres so migration is
	# behaviour-neutral.
	var g := BodyCatalog.build("SOL", [{"name": "EARTH"}, {"name": "MARS"}])
	assert_eq(g.root.mu, 54800000000000.0, "SOL mu")
	assert_eq(g.root.radius, 400000.0, "SOL radius")
	var earth: BodyDef = g.by_name["EARTH"]
	assert_eq(earth.mu, 76760000000.0, "EARTH mu")
	assert_eq(earth.radius, 63710.0, "EARTH radius")
	assert_eq(earth.soi_radius, 9240000.0, "EARTH soi (as a moon of SOL)")
	assert_eq(earth.orbit_radius, 40000000.0, "EARTH heliocentric orbit")
	var mars: BodyDef = g.by_name["MARS"]
	assert_eq(mars.mu, 8210000000.0, "MARS mu")
	assert_eq(mars.radius, 33900.0, "MARS radius")


func test_catalog_root_override_drops_moon_role() -> void:
	# EARTH is a moon of SOL in the catalog, but as a level's root it must become
	# soi=INF / parentless.
	var g := BodyCatalog.build("EARTH", [{"name": "MOON"}])
	assert_eq(g.root.soi_radius, INF_R, "EARTH-as-root gets INF SOI despite its catalog soi")
	assert_null(g.root.parent, "EARTH-as-root has no parent despite cataloguing SOL")
	assert_same(g.by_name["MOON"].parent, g.root, "MOON orbits the root EARTH instance")


func test_loader_orbit_match_units() -> void:
	var r := LevelLoader.from_dict({
		"title": "T", "system": "EARTH",
		"objective": {"type": "orbit_match", "radius_km": 80, "tolerance_km": 1.5}},
		"demo")
	assert_eq(r.error, "", "valid spec has no error")
	var lvl: LevelDef = r.level
	assert_eq(lvl.id, "demo")
	var obj := lvl.objective as OrbitMatchObjective
	assert_not_null(obj, "orbit_match builds an OrbitMatchObjective")
	assert_eq(obj.target_radius, 80000.0, "radius_km -> metres")
	assert_eq(obj.tolerance, 1500.0, "tolerance_km -> metres")


func test_loader_inclination_deg_to_rad() -> void:
	var r := LevelLoader.from_dict({
		"title": "T", "system": "EARTH",
		"objective": {"type": "orbit_match", "radius_km": 70, "tolerance_km": 1.5,
			"inclination_deg": 15, "inclination_tolerance_deg": 1}},
		"demo")
	var obj := r.level.objective as OrbitMatchObjective
	assert_almost_eq(obj.target_inclination, deg_to_rad(15.0), 1e-9, "inclination_deg -> rad")
	assert_almost_eq(obj.inclination_tolerance, deg_to_rad(1.0), 1e-9, "inclination_tolerance_deg -> rad")


func test_loader_rendezvous_autofills_station_mu() -> void:
	var r := LevelLoader.from_dict({
		"title": "T", "system": "EARTH",
		"objective": {"type": "rendezvous", "station_radius_km": 90, "station_phase_deg": 40.1}},
		"demo")
	var obj := r.level.objective as RendezvousObjective
	assert_eq(obj.station_orbit_radius, 90000.0, "station_radius_km -> metres")
	assert_eq(obj.station_mu, r.level.body.mu, "station_mu auto-fills from the root body's mu")


func test_loader_transfer_target_is_shared_moon_instance() -> void:
	# The whole feature hinges on this: ship.body != target is object identity, so
	# objective.target must BE the moons entry, not a look-alike copy.
	var r := LevelLoader.from_dict({
		"title": "T", "system": "SOL", "bodies": [{"name": "EARTH"}, {"name": "MARS", "phase_deg": 43.76}],
		"start": {"body": "EARTH", "radius_km": 70},
		"objective": {"type": "transfer_capture", "target": "MARS"}},
		"demo")
	assert_eq(r.error, "")
	var obj := r.level.objective as TransferCaptureObjective
	var mars: BodyDef = null
	for m: BodyDef in r.level.moons:
		if m.name == "MARS":
			mars = m
	assert_same(obj.target, mars, "objective.target IS the same instance placed in moons")


const EARTH_MU := 76760000000.0


func _start_orbit(lvl: LevelDef) -> OrbitElements:
	var st := lvl.start_state(EARTH_MU)
	return OrbitElements.from_state(st.r, st.v, EARTH_MU, 0.0)


func test_start_state_circular_matches_legacy() -> void:
	var lvl := LevelDef.new()
	lvl.start_radius = 70000.0
	var el := _start_orbit(lvl)
	assert_almost_eq(el.e, 0.0, 1e-6, "no shape => circular")
	assert_almost_eq(el.radius_periapsis(), 70000.0, 1.0)
	assert_almost_eq(el.radius_apoapsis(), 70000.0, 1.0)


func test_start_state_ellipse_from_apsides() -> void:
	var lvl := LevelDef.new()
	lvl.start_radius = 70000.0
	lvl.start_apoapsis = 200000.0
	var el := _start_orbit(lvl)
	assert_almost_eq(el.radius_periapsis(), 70000.0, 2.0, "periapsis held")
	assert_almost_eq(el.radius_apoapsis(), 200000.0, 2.0, "apoapsis reached")


func test_start_state_open_orbit() -> void:
	var lvl := LevelDef.new()
	lvl.start_radius = 70000.0
	lvl.start_eccentricity = 1.3
	var el := _start_orbit(lvl)
	assert_gt(el.e, 1.0, "eccentricity >= 1 is an open trajectory")
	assert_lt(el.a, 0.0, "hyperbolic semi-major axis is negative")


func test_start_state_inclination() -> void:
	var lvl := LevelDef.new()
	lvl.start_radius = 70000.0
	lvl.start_inclination = deg_to_rad(15.0)
	var el := _start_orbit(lvl)
	# The game measures inclination as the tilt from the XZ plane (acos plane_normal.y),
	# same as OrbitMatchObjective._tilt — so start_inclination agrees with inclination_deg.
	var tilt := acos(clampf(el.plane_normal.y, -1.0, 1.0))
	assert_almost_eq(rad_to_deg(tilt), 15.0, 0.01, "starting plane is tilted 15° from equatorial")


func test_start_state_begins_at_apoapsis() -> void:
	var lvl := LevelDef.new()
	lvl.start_radius = 70000.0
	lvl.start_apoapsis = 200000.0
	lvl.start_at_apoapsis = true
	var st := lvl.start_state(EARTH_MU)
	assert_almost_eq(st.r.length(), 200000.0, 2.0, "ship starts at the apoapsis radius")


func test_loader_maps_start_shape_and_rejects_bad_geometry() -> void:
	var base := {"title": "T", "system": "EARTH",
		"objective": {"type": "orbit_match", "radius_km": 90, "tolerance_km": 1}}
	var ell := base.duplicate()
	ell["start"] = {"periapsis_km": 70, "apoapsis_km": 200, "inclination_deg": 10, "at": "apoapsis"}
	var r := LevelLoader.from_dict(ell, "x")
	assert_eq(r.error, "")
	assert_eq(r.level.start_radius, 70000.0, "periapsis_km -> start_radius")
	assert_eq(r.level.start_apoapsis, 200000.0)
	assert_almost_eq(r.level.start_inclination, deg_to_rad(10.0), 1e-9)
	assert_true(r.level.start_at_apoapsis)

	var bad := base.duplicate()
	bad["start"] = {"periapsis_km": 200, "apoapsis_km": 70}
	assert_ne(LevelLoader.from_dict(bad, "x").error, "", "apoapsis below periapsis is rejected")

	var open_apo := base.duplicate()
	open_apo["start"] = {"periapsis_km": 70, "eccentricity": 1.4, "at": "apoapsis"}
	assert_ne(LevelLoader.from_dict(open_apo, "x").error, "", "apoapsis start on an open orbit is rejected")


func test_loader_marks_decorative_bodies() -> void:
	var r := LevelLoader.from_dict({
		"title": "Jupiter", "system": "SOL",
		"bodies": [{"name": "MARS"}, {"name": "EARTH", "decorative": true}],
		"start": {"body": "MARS", "radius_km": 50},
		"objective": {"type": "orbit_match", "radius_km": 60, "tolerance_km": 1}}, "x")
	assert_eq(r.error, "")
	var by := {}
	for m: BodyDef in r.level.moons:
		by[m.name] = m
	assert_false(by["MARS"].decorative, "MARS is real")
	assert_true(by["EARTH"].decorative, "EARTH is scenery")


func test_loader_rejects_duplicate_and_decorative_target() -> void:
	var dup := LevelLoader.from_dict({"system": "SOL",
		"bodies": [{"name": "EARTH"}, {"name": "EARTH"}],
		"objective": {"type": "orbit_match", "radius_km": 60, "tolerance_km": 1}}, "x")
	assert_true(dup.error.contains("EARTH"), "a duplicate body name is rejected")

	var deco_target := LevelLoader.from_dict({"system": "SOL",
		"bodies": [{"name": "EARTH", "decorative": true}],
		"objective": {"type": "transfer_capture", "target": "EARTH"}}, "x")
	assert_ne(deco_target.error, "", "a decorative body can't be the objective target")


func test_decorative_moon_never_captures() -> void:
	for deco: bool in [false, true]:
		var r := LevelLoader.from_dict({"system": "EARTH",
			"bodies": [{"name": "MOON", "decorative": deco}],
			"start": {"radius_km": 70},
			"objective": {"type": "orbit_match", "radius_km": 80, "tolerance_km": 1}}, "d")
		assert_eq(r.error, "", "deco=%s is a valid spec" % deco)
		var ship := ShipSim.new()
		ship.setup(r.level)
		ship.r = (r.level.moons[0] as BodyDef).orbit.state_at_time(0.0).r  # at the moon's centre
		ship.apply_soi_transitions(0.0)
		if deco:
			assert_eq(ship.body.name, "EARTH", "a decorative moon must NOT capture the ship")
		else:
			assert_eq(ship.body.name, "MOON", "a real moon captures the ship (control)")


func test_loader_rejects_bad_specs_with_readable_errors() -> void:
	var unknown_body := LevelLoader.from_dict({"system": "PLANET_X",
		"objective": {"type": "orbit_match", "radius_km": 80, "tolerance_km": 1}}, "x")
	assert_true(unknown_body.error.contains("PLANET_X"), "unknown system body is named in the error")
	assert_null(unknown_body.level, "rejected spec returns no level")

	var unknown_obj := LevelLoader.from_dict({"system": "EARTH",
		"objective": {"type": "land_on_sun"}}, "x")
	assert_ne(unknown_obj.error, "", "unknown objective type errors")

	var missing := LevelLoader.from_dict({"system": "EARTH",
		"objective": {"type": "orbit_match"}}, "x")
	assert_ne(missing.error, "", "orbit_match without radius_km errors")

	var bad_target := LevelLoader.from_dict({"system": "EARTH",
		"objective": {"type": "transfer_capture", "target": "MOO"}}, "x")
	assert_true(bad_target.error.contains("MOO"), "unknown objective target is named")

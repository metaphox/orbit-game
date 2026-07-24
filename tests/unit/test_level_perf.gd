extends GutTest
## Complexity limits + a coarse performance guard for levels. A hostile or
## careless level (every body + a swarm of stations) must not be able to grind
## the sim: the loader caps body counts, and a synthetic heavy level proves
## decorative (scenery) bodies stay cheap because the SOI scan skips them.


func test_loader_caps_total_body_count() -> void:
	var bodies: Array = []
	for i in LevelLoader.MAX_BODIES + 5:
		bodies.append({"name": "EARTH"})  # count is checked first, before catalog/uniqueness
	var r := LevelLoader.from_dict({"system": "SOL", "bodies": bodies,
		"objective": {"type": "orbit_match", "radius_km": 60, "tolerance_km": 1}}, "x")
	assert_true(r.error.to_lower().contains("many"), "an over-sized level is rejected: %s" % r.error)
	assert_null(r.level)


func test_loader_caps_active_body_count() -> void:
	var bodies: Array = []
	for i in LevelLoader.MAX_ACTIVE_MOONS + 3:
		bodies.append({"name": "EARTH"})  # all real (non-decorative)
	var r := LevelLoader.from_dict({"system": "SOL", "bodies": bodies,
		"objective": {"type": "orbit_match", "radius_km": 60, "tolerance_km": 1}}, "x")
	assert_true(r.error.to_lower().contains("active"), "too many active bodies is rejected: %s" % r.error)


## Build a synthetic level with `active` real moons + `decorative` scenery moons,
## bypassing the catalog (so this tests the sim, not the loader's cap).
func _heavy_level(active: int, decorative: int) -> LevelDef:
	var root := BodyDef.new()
	root.name = "ROOT"
	root.mu = 76760000000.0
	root.radius = 63710.0
	var moons: Array[BodyDef] = []
	for i in active + decorative:
		var m := BodyDef.new()
		m.name = "B%d" % i
		m.mu = 944000000.0
		m.radius = 17374.0
		m.soi_radius = 660000.0
		m.parent = root
		m.orbit_radius = 3.0e6 + i * 1.0e5  # distinct, all far from the ship
		m.orbit_phase_deg = i * 7.0
		m.decorative = i >= active  # first `active` are real, the rest scenery
		moons.append(m)
	var lvl := LevelDef.new()
	lvl.body = root
	lvl.moons = moons
	lvl.start_radius = 200000.0
	lvl.dry_mass = 1000.0
	lvl.prop_mass = 250.0
	lvl.thrust = 6000.0
	lvl.isp = 82.0
	lvl.objective = OrbitMatchObjective.new()
	return lvl


func test_decorative_swarm_stays_within_budget() -> void:
	# A handful of real moons plus a large scenery swarm. The per-step SOI scan
	# must skip the decorative ones, so this stays fast. Budget is deliberately
	# loose (real run is tens of ms) — it catches O(n^2) regressions, not jitter.
	var ship := ShipSim.new()
	ship.setup(_heavy_level(8, 300))
	var t0 := Time.get_ticks_msec()
	var t := 0.0
	for i in 2000:
		t += 0.5
		ship.advance_to(t)
		ship.apply_soi_transitions(t)
	var elapsed := Time.get_ticks_msec() - t0
	assert_lt(elapsed, 4000,
		"2000 steps with 8 active + 300 decorative bodies took %d ms (scenery must stay cheap)" % elapsed)

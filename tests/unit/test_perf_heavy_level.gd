extends "res://tests/unit/base_orbit_test.gd"
## PF benchmark harness: a worst-case community system at the loader caps
## (MAX_ACTIVE_MOONS = 12 active children, MAX_BODIES = 48 total) exercised
## through the real physics event scan and the real rendering sync, timed with a
## generous frame budget. Proves decorative bodies stay cheap, confirms the PF-1
## shared scan removes the duplicate, and catches O(n^2) regressions. Numbers are
## printed via gut.p() so the budget can be re-derived on new hardware.

const DRAW_LIMIT := 6.0e6  # translunar level's draw_limit
const R_PARK := 1.7e6      # parking-orbit radius around Earth-like parent

# Scaled catalog values (assets/bodies/catalog.json).
const MU_PARENT := 7.676e10
const R_PARENT := 63710.0
const MOON_MU := 9.44e8
const MOON_SOI := 6.6e5
const MOON_R := 17374.0


func _parent() -> BodyDef:
	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = MU_PARENT
	earth.radius = R_PARENT
	return earth


## `count` Moon-like active children of `parent`, spread across orbit radii so a
## transfer ellipse grazes some and misses others — the mix that makes the scan
## do full work rather than early-out.
func _active_moons(parent: BodyDef, count: int) -> Array[BodyDef]:
	var moons: Array[BodyDef] = []
	for i in count:
		var m := BodyDef.new()
		m.name = "MOON_%d" % i
		m.mu = MOON_MU
		m.radius = MOON_R
		m.soi_radius = MOON_SOI
		m.parent = parent
		m.orbit_radius = 2.4e6 + float(i) * 2.6e5  # 2.4e6 .. ~5.3e6
		m.orbit_phase_deg = float(i) * 37.0
		moons.append(m)
	return moons


## A transfer ellipse from the parking radius out toward the active-moon belt.
func _transfer(parent: BodyDef) -> OrbitElements:
	var ra := 4.0e6
	var a := (R_PARK + ra) * 0.5
	var vp := sqrt(parent.mu * (2.0 / R_PARK - 1.0 / a))
	return OrbitElements.from_state(
		DVec3.new(R_PARK, 0.0, 0.0), DVec3.new(0.0, 0.0, -vp), parent.mu, 0.0)


func _ship(parent: BodyDef) -> ShipSim:
	var ship := ShipSim.new()
	ship.body = parent
	ship.elements = _transfer(parent)
	var st := ship.elements.state_at_time(0.0)
	ship.r = st.r
	ship.v = st.v
	ship.last_time = 0.0
	return ship


## A tight parking orbit — the common case: radially confined, so broad-phase
## rejects every distant moon in O(1) without a fine scan.
func _parked_ship(parent: BodyDef) -> ShipSim:
	var ship := ShipSim.new()
	ship.body = parent
	var r := 1.5e6
	ship.elements = OrbitElements.from_state(
		DVec3.new(r, 0.0, 0.0), DVec3.new(0.0, 0.0, -sqrt(parent.mu / r)), parent.mu, 0.0)
	var st := ship.elements.state_at_time(0.0)
	ship.r = st.r
	ship.v = st.v
	ship.last_time = 0.0
	return ship


# --- Scenario A: worst-case physics SOI scan at MAX_ACTIVE_MOONS -------------

func test_bench_worstcase_soi_scan() -> void:
	var earth := _parent()
	var moons := _active_moons(earth, 12)
	var ship := _ship(earth)

	# One child's scan, to anchor the per-call cost quoted in the loader (~165 ms).
	var t0 := Time.get_ticks_usec()
	var span := ship.event_scan_span(DRAW_LIMIT)
	OrbitEvents.child_soi_entry_time(
		ship.elements, moons[0].orbit, moons[0].soi_radius, 0.0, span, maxf(span / 400.0, 1.0))
	var one_ms := (Time.get_ticks_usec() - t0) / 1000.0

	# A full 12-child scan. One pass keeps this heavy benchmark off the suite's
	# critical path; the ceiling below is loose enough to tolerate the variance.
	var full_start := Time.get_ticks_usec()
	ship.next_child_soi_entry(moons, 0.0, DRAW_LIMIT)
	var full_ms := (Time.get_ticks_usec() - full_start) / 1000.0

	gut.p("[PF] PATHOLOGICAL (ellipse spans the belt) single child scan: %.2f ms | full 12-child scan: %.2f ms" % [
		one_ms, full_ms])
	# Pathological: one orbit radially spanning many reachable moons. Broad-phase
	# can't reject an in-reach moon, so this is the true ceiling and the argument
	# for MAX_ACTIVE_MOONS. Loose bound just catches a gross (~2x) regression.
	assert_lt(full_ms, 6000.0, "the pathological worst case stays within a gross-regression ceiling")


# --- Scenario A': the COMMON case — a confined orbit rejects distant moons ----

func test_bench_common_case_confined_orbit() -> void:
	var earth := _parent()
	var moons := _active_moons(earth, 12)  # spread 2.4e6 .. 5.3e6
	var ship := _parked_ship(earth)        # tight parking orbit at 1.5e6

	const PASSES := 10
	var start := Time.get_ticks_usec()
	for p in PASSES:
		ship.revision += 1
		ship.next_child_soi_entry(moons, 0.0, DRAW_LIMIT)
	var ms := (Time.get_ticks_usec() - start) / 1000.0 / float(PASSES)

	gut.p("[PF] COMMON case (parking orbit, 12 distant moons) full scan: %.3f ms" % ms)
	assert_lt(ms, 50.0, "broad-phase makes the confined-orbit common case cheap (all moons rejected)")


# --- Scenario B: PF-1 sharing — the second (visual) caller is ~free ----------

func test_bench_shared_scan_second_caller_is_cached() -> void:
	var earth := _parent()
	var moons := _active_moons(earth, 12)
	var ship := _ship(earth)

	ship.next_child_soi_entry(moons, 0.0, DRAW_LIMIT)  # physics side pays the scan
	var t0 := Time.get_ticks_usec()
	for _i in 100:  # visual side, same revision -> pure cache hits
		ship.next_child_soi_entry(moons, 0.0, DRAW_LIMIT)
	var cached_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 100.0

	gut.p("[PF] cached (shared) scan call: %.4f ms" % cached_ms)
	assert_lt(cached_ms, 1.0, "the shared scan turns the second consumer into a cache hit")


# --- Scenario C: rendering sync at MAX_BODIES (PF-2 relevance) ----------------

func _heavy_level(total_bodies: int) -> LevelDef:
	var earth := _parent()
	var moons: Array[BodyDef] = []
	# A handful of active moons, the rest decorative scenery, plus one nested
	# chain so position_at recursion depth is exercised.
	var active := _active_moons(earth, 12)
	moons.append_array(active)
	var prev := active[0]
	for i in total_bodies - 1 - active.size():
		var d := BodyDef.new()
		d.name = "DECO_%d" % i
		d.mu = MOON_MU
		d.radius = MOON_R
		d.soi_radius = MOON_SOI
		d.decorative = true
		# Every 4th body rides the previous one (a nested chain); the rest orbit Earth.
		d.parent = prev if i % 4 == 0 else earth
		d.orbit_radius = 1.0e6 + float(i) * 2.0e5
		d.orbit_phase_deg = float(i) * 11.0
		moons.append(d)
		prev = d
	var level := LevelDef.new()
	level.title = "HEAVY"
	level.body = earth
	level.moons = moons
	level.start_body = earth
	level.start_radius = R_PARK
	level.dry_mass = 1000.0
	level.prop_mass = 500.0
	level.thrust = 5000.0
	level.isp = 80.0
	level.map_extent = DRAW_LIMIT
	level.draw_limit = DRAW_LIMIT
	level.objective = TransferCaptureObjective.new()
	return level


func test_bench_rendering_sync_at_max_bodies() -> void:
	var level := _heavy_level(48)
	assert_eq(level.moons.size(), 47, "48 bodies total (1 root + 47)")

	var br := BodyRenderer.new()
	add_child_autofree(br)
	var build_start := Time.get_ticks_usec()
	br.build(level, RenderTheme.default())
	var build_ms := (Time.get_ticks_usec() - build_start) / 1000.0

	var mv := MapView.new()
	add_child_autofree(mv)
	mv.build(level)
	var ship := _ship(level.body)
	mv.minimap_ortho_size = DRAW_LIMIT

	const FRAMES := 120
	var ship_abs := ship.absolute_position(0.0)
	var br_start := Time.get_ticks_usec()
	for f in FRAMES:
		var t := float(f) * 10.0
		br.sync(t, ship_abs, true)
	var br_ms := (Time.get_ticks_usec() - br_start) / 1000.0 / float(FRAMES)

	var mv_start := Time.get_ticks_usec()
	for f in FRAMES:
		var t := float(f) * 10.0
		mv.sync(ship, t, 1.0 / 60.0)
	var mv_ms := (Time.get_ticks_usec() - mv_start) / 1000.0 / float(FRAMES)

	gut.p("[PF] 48-body build: %.2f ms | body_renderer.sync: %.3f ms/frame | map_view.sync: %.3f ms/frame" % [
		build_ms, br_ms, mv_ms])
	assert_lt(br_ms + mv_ms, 8.0, "48-body render sync stays well within a 60 FPS frame")


# --- Decorative bodies must stay cheap for the physics scan ------------------

func test_decorative_bodies_do_not_enter_the_soi_scan() -> void:
	var level := _heavy_level(48)
	var ship := _ship(level.body)
	# Only the 12 active moons are scanned; the 35 decorative bodies are skipped.
	var active_only := _active_moons(level.body, 12)
	var ship2 := _ship(level.body)
	var full := ship.next_child_soi_entry(level.moons, 0.0, DRAW_LIMIT)
	var active := ship2.next_child_soi_entry(active_only, 0.0, DRAW_LIMIT)
	assert_eq(str(full), str(active),
		"decorative bodies don't change the scan result (they're skipped)")

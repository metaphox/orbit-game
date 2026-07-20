extends "res://tests/unit/base_orbit_test.gd"
## SOI hierarchy depth: apply_soi_transitions must support more than one
## level of nesting - a ship inside a non-root body's SOI can still enter
## that body's own child (e.g. a moon of Earth while Earth is itself a
## child of the Sun), not just "root vs. its direct children."

const MU_SUN := 1.327e20
const D_EARTH := 4.0e7  # Sun-Earth distance
const SOI_EARTH := 9.24e6
const R_EARTH := 63710.0
const D_MOON := 3.844e6  # Earth-Moon distance
const SOI_MOON := 6.6e5
const R_MOON := 17374.0


## Sun (root) -> Earth (child of Sun) -> Moon (child of Earth), three tiers.
func _make_hierarchy() -> Dictionary:
	var sun := BodyDef.new()
	sun.name = "SUN"
	sun.mu = MU_SUN
	sun.radius = 6.96e5

	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = MU_EARTH
	earth.radius = R_EARTH
	earth.soi_radius = SOI_EARTH
	earth.parent = sun
	earth.orbit_radius = D_EARTH
	earth.orbit_phase_deg = 0.0

	var moon := BodyDef.new()
	moon.name = "MOON"
	moon.mu = MU_MOON
	moon.radius = R_MOON
	moon.soi_radius = SOI_MOON
	moon.parent = earth
	moon.orbit_radius = D_MOON
	moon.orbit_phase_deg = 0.0

	var level := LevelDef.new()
	level.title = "TEST HIERARCHY"
	level.body = sun
	level.moons = [earth, moon]
	level.start_body = moon
	level.start_radius = 20000.0
	level.dry_mass = 1000.0
	level.prop_mass = 500.0
	level.thrust = 5000.0
	level.isp = 80.0

	return {"sun": sun, "earth": earth, "moon": moon, "level": level}


func test_sequential_exits_climb_the_full_tree() -> void:
	var h := _make_hierarchy()
	var ship := ShipSim.new()
	ship.setup(h.level)
	assert_eq(ship.body, h.moon, "starts at the moon")

	# escape the moon: hyperbolic outbound, radial+tangential mix (purely
	# radial would be a degenerate zero-angular-momentum orbit)
	var start_r: float = h.moon.soi_radius * 0.9
	var v_esc := sqrt(2.0 * h.moon.mu / start_r)
	ship.elements = OrbitElements.from_state(
		DVec3.new(start_r, 0.0, 0.0), DVec3.new(v_esc * 1.2, 0.0, -v_esc * 0.5),
		h.moon.mu, 0.0)

	var t := 0.0
	var note := ""
	while t < 5.0e4 and note == "":
		t += 20.0
		ship.advance_to(t)
		note = ship.apply_soi_transitions(t)
	assert_eq(note, "LEAVING MOON SOI", "first exit: moon to earth")
	assert_eq(ship.body, h.earth, "now in earth's frame")

	# escape earth the same way - a second, independent climb up the tree
	var start_r2: float = h.earth.soi_radius * 0.9
	var v_esc2 := sqrt(2.0 * h.earth.mu / start_r2)
	ship.elements = OrbitElements.from_state(
		DVec3.new(start_r2, 0.0, 0.0), DVec3.new(v_esc2 * 1.2, 0.0, -v_esc2 * 0.5),
		h.earth.mu, t)

	var note2 := ""
	while t < 1.0e7 and note2 == "":
		t += 2000.0
		ship.advance_to(t)
		note2 = ship.apply_soi_transitions(t)
	assert_eq(note2, "LEAVING EARTH SOI", "second exit: earth to sun")
	assert_eq(ship.body, h.sun, "now in the sun's (root) frame")


## The actual bug: on the old code, a ship already inside a non-root body's
## SOI could only ever check for exit, never for entry into a child of that
## body - so a moon of Earth was unreachable while coasting inside Earth's
## own SOI, even though BodyDef.position_at() has always supported the
## nesting fine.
func test_ship_inside_earth_soi_can_enter_moon_soi() -> void:
	var h := _make_hierarchy()
	var ship := ShipSim.new()
	ship.setup(h.level)
	ship.body = h.earth
	# fast hyperbolic trajectory from well inside Earth's SOI (9.24e6),
	# outward past the moon's orbital radius (3.844e6)
	var r0 := 1.0e6
	var v_esc := sqrt(2.0 * h.earth.mu / r0)
	var el := OrbitElements.from_state(
		DVec3.new(r0, 0.0, 0.0), DVec3.new(v_esc * 1.5, 0.0, v_esc * 0.05), h.earth.mu, 0.0)

	# phase the moon so it's where the ship is when the ship's radius is
	# closest to the moon's orbital radius - the moon moves meaningfully
	# during the encounter (its own orbital speed is ~10 km/s), so a fixed
	# phase would miss it; same phasing trick as test_moon_transfer.gd's
	# _phased_transfer.
	var best_t := 0.0
	var best_diff := INF
	var scan_t := 0.0
	while scan_t < 3000.0:
		scan_t += 1.0
		var diff := absf(el.state_at_time(scan_t).r.length() - h.moon.orbit_radius)
		if diff < best_diff:
			best_diff = diff
			best_t = scan_t
	var ship_pos_at_best := el.state_at_time(best_t).r
	var theta := atan2(-ship_pos_at_best.z, ship_pos_at_best.x)
	var n_moon := sqrt(h.earth.mu / pow(h.moon.orbit_radius, 3.0))
	h.moon.orbit_phase_deg = rad_to_deg(theta - n_moon * best_t)

	ship.elements = el
	var t := 0.0
	var note := ""
	while t < 3000.0 and note == "":
		t += 5.0
		ship.advance_to(t)
		note = ship.apply_soi_transitions(t)
	assert_eq(note, "ENTERING MOON SOI",
		"a ship inside Earth's (non-root) SOI can still enter a child of Earth")
	assert_eq(ship.body, h.moon, "parent is now the moon")

extends "res://tests/unit/base_orbit_test.gd"
## PF-1: the child-SOI encounter scan (~150 ms) must be computed ONCE per orbit
## revision and shared by the physics event clamp and the visual encounter
## marker, and it must select the EARLIEST encounter — not the first body in
## level-list order, which is what the old visual scan returned (so it could
## disagree with the physics min and mark the wrong moon).

const DRAW_LIMIT := 1.0e9


## Earth with two moons co-located near the centre, differing ONLY in SOI size,
## and a ship falling in from apoapsis. The bigger SOI is crossed first, so the
## earliest encounter is the SECOND moon in the list.
func _scenario() -> Dictionary:
	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = MU_EARTH
	earth.radius = 63710.0
	var moon_a := BodyDef.new()  # smaller SOI -> entered LATER, but first in list
	moon_a.name = "MOON_A"
	moon_a.parent = earth
	moon_a.orbit_radius = 1.0e6
	moon_a.soi_radius = 1.0e7
	var moon_b := BodyDef.new()  # bigger SOI -> entered EARLIER, second in list
	moon_b.name = "MOON_B"
	moon_b.parent = earth
	moon_b.orbit_radius = 1.0e6
	moon_b.soi_radius = 2.0e7

	var ship := ShipSim.new()
	ship.body = earth
	var ra := 5.0e7
	var a := (ra + 6.0e6) * 0.5
	var v_apo := sqrt(earth.mu * (2.0 / ra - 1.0 / a))
	ship.r = DVec3.new(ra, 0.0, 0.0)
	ship.v = DVec3.new(0.0, 0.0, -v_apo)
	ship.elements = OrbitElements.from_state(ship.r, ship.v, earth.mu, 0.0)
	ship.last_time = 0.0
	return {"earth": earth, "moon_a": moon_a, "moon_b": moon_b, "ship": ship}


func test_shared_scan_returns_the_earliest_moon_not_the_first_in_list() -> void:
	var s := _scenario()
	var ship: ShipSim = s.ship
	var span := ship.event_scan_span(DRAW_LIMIT)
	var t_a := OrbitEvents.child_soi_entry_time(
		ship.elements, s.moon_a.orbit, s.moon_a.soi_radius, 0.0, span, maxf(span / 400.0, 1.0))
	var t_b := OrbitEvents.child_soi_entry_time(
		ship.elements, s.moon_b.orbit, s.moon_b.soi_radius, 0.0, span, maxf(span / 400.0, 1.0))
	assert_true(is_finite(t_a) and is_finite(t_b), "precondition: both moons are encountered")
	assert_lt(t_b, t_a, "precondition: the bigger-SOI moon (2nd in list) is entered first")

	# moon_a is FIRST in the list; the earliest encounter is moon_b's.
	var got := ship.next_child_soi_entry([s.moon_a, s.moon_b], 0.0, DRAW_LIMIT)
	assert_almost_eq(got, t_b, 1.0, "the shared scan returns the earliest encounter, not the first listed")


func test_scan_is_cached_on_revision_and_window() -> void:
	var s := _scenario()
	var ship: ShipSim = s.ship
	var first := ship.next_child_soi_entry([s.moon_a, s.moon_b], 0.0, DRAW_LIMIT)
	assert_true(is_finite(first), "an encounter is found")

	# Mutating a moon within the same revision+window must NOT trigger a rescan.
	s.moon_b.soi_radius = 4.0e7
	var cached := ship.next_child_soi_entry([s.moon_a, s.moon_b], 1.0, DRAW_LIMIT)
	assert_eq(cached, first, "result is cached on revision+window (the SOI change is not re-scanned)")

	# A refit (revision bump) forces a fresh scan that now sees the bigger SOI.
	ship.revision += 1
	var rescanned := ship.next_child_soi_entry([s.moon_a, s.moon_b], 0.0, DRAW_LIMIT)
	assert_lt(rescanned, first, "a revision bump rescans and picks up the enlarged SOI (earlier entry)")


func test_decorative_and_foreign_children_are_ignored() -> void:
	var s := _scenario()
	var ship: ShipSim = s.ship
	s.moon_b.decorative = true  # scenery: never an encounter
	var got := ship.next_child_soi_entry([s.moon_a, s.moon_b], 0.0, DRAW_LIMIT)
	var span := ship.event_scan_span(DRAW_LIMIT)
	var t_a := OrbitEvents.child_soi_entry_time(
		ship.elements, s.moon_a.orbit, s.moon_a.soi_radius, 0.0, span, maxf(span / 400.0, 1.0))
	assert_almost_eq(got, t_a, 1.0, "a decorative moon is skipped, leaving moon_a as the encounter")

	# A body whose parent isn't the ship's current body is not an encounter here.
	var stray := BodyDef.new()
	stray.name = "STRAY"
	stray.parent = BodyDef.new()  # some other parent
	stray.orbit_radius = 1.0e6
	stray.soi_radius = 9.0e7
	ship.revision += 1
	var with_stray := ship.next_child_soi_entry([s.moon_a, stray], 0.0, DRAW_LIMIT)
	assert_almost_eq(with_stray, t_a, 1.0, "a body orbiting a different parent is ignored")

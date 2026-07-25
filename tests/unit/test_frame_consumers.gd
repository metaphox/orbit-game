extends "res://tests/unit/base_orbit_test.gd"
## CR-4: higher-level consumers (objective guidance, minimap tracks) must name
## their frames so they stay correct for bodies nested two or more levels deep,
## not just direct children of the root. Fixture: Sun -> Earth -> Moon.

const MU_SUN := 1.327e20
const D_EARTH := 4.0e7
const D_MOON := 3.844e6


func _bodies() -> Dictionary:
	var sun := BodyDef.new()
	sun.name = "SUN"
	sun.mu = MU_SUN
	sun.radius = 6.96e5
	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = MU_EARTH
	earth.radius = 63710.0
	earth.soi_radius = 9.24e6
	earth.parent = sun
	earth.orbit_radius = D_EARTH
	earth.orbit_phase_deg = 0.0
	var moon := BodyDef.new()
	moon.name = "MOON"
	moon.mu = MU_MOON
	moon.radius = 17374.0
	moon.soi_radius = 6.6e5
	moon.parent = earth
	moon.orbit_radius = D_MOON
	moon.orbit_phase_deg = 0.0
	return {"sun": sun, "earth": earth, "moon": moon}


func _level(b: Dictionary, objective: Objective) -> LevelDef:
	var level := LevelDef.new()
	level.title = "TEST"
	level.body = b.sun
	level.moons = [b.earth, b.moon]  # flat list of every non-root body
	level.start_body = b.earth
	level.start_radius = 2.0e6
	level.dry_mass = 1000.0
	level.prop_mass = 500.0
	level.thrust = 5000.0
	level.isp = 80.0
	level.map_extent = 1.0e8
	level.draw_limit = 1.0e8
	level.objective = objective
	return level


# --- Objective guidance: phase angle is measured about the shared center ----

func test_transfer_phase_angle_is_parent_centric_for_a_deep_target() -> void:
	var b := _bodies()
	var obj := TransferCaptureObjective.new()
	obj.target = b.moon  # two levels deep: Moon orbits Earth orbits Sun
	var ship := ShipSim.new()
	ship.setup(_level(b, obj))
	ship.body = b.earth
	ship.last_time = 0.0

	# Put the ship 90° (about +Y) from the Moon as seen FROM EARTH. The correct
	# phase angle is that Earth-centric 90°, not the tiny heliocentric angle you
	# get by comparing both bodies' Sun-frame positions (both sit near Earth).
	var moon_rel: DVec3 = b.moon.orbit.state_at_time(0.0).r  # Moon about Earth
	ship.r = DVec3.new(moon_rel.z, moon_rel.y, -moon_rel.x)  # rotate 90° about +Y

	# aim = the next hop from Earth toward the Moon (the Moon itself).
	assert_almost_eq(absf(obj._phase_angle(ship, b.moon)), PI / 2.0, 0.03,
		"phase angle is Earth-centric (90°), not the ~0° heliocentric comparison")


# --- CR-8: transfer guidance is route-aware (aim at the next hop, not the target) --

func test_transfer_next_hop_walks_the_route() -> void:
	var b := _bodies()
	var obj := TransferCaptureObjective.new()
	obj.target = b.moon
	assert_same(obj._next_hop(b.sun), b.earth, "from the root, the next hop is the planet, not the moon")
	assert_same(obj._next_hop(b.earth), b.moon, "inside the planet's SOI, the next hop is the moon")
	var up := TransferCaptureObjective.new()
	up.target = b.earth
	assert_null(up._next_hop(b.moon), "from a body below the target there's no descent hop (climb out)")


func test_transfer_status_and_closeness_are_frame_correct_per_leg() -> void:
	var b := _bodies()
	var obj := TransferCaptureObjective.new()
	obj.target = b.moon
	var ship := ShipSim.new()
	ship.setup(_level(b, obj))
	ship.last_time = 0.0

	# From the root, guidance names the PLANET (the next hop), not the final moon.
	ship.body = b.sun
	assert_true(str(obj.status_lines(ship)).contains("EARTH"), "from the root, aims at the planet")

	# Inside the planet's SOI, it aims at the MOON and yields a real per-leg
	# closeness, not the flat 0.2 climb-out fallback (the old code returned 0.2
	# for any non-root body).
	ship.body = b.earth
	ship.r = DVec3.new(3.0e6, 0.0, 0.0)
	ship.v = DVec3.new(0.0, 0.0, -sqrt(b.earth.mu / 3.0e6))
	ship.elements = OrbitElements.from_state(ship.r, ship.v, b.earth.mu, 0.0)
	assert_true(str(obj.status_lines(ship)).contains("MOON"), "inside the planet's SOI, aims at the moon")
	assert_ne(obj.trajectory_closeness(ship), 0.2, "per-leg closeness, not the climb-out fallback")

	# From a body off the descent route it says DEPART and returns the 0.2 fallback.
	var up := TransferCaptureObjective.new()
	up.target = b.earth
	ship.body = b.moon
	assert_true(str(up.status_lines(ship)).contains("DEPARTING"), "off the route -> climb out")
	assert_eq(up.trajectory_closeness(ship), 0.2, "off-route closeness is the climb-out fallback")


# --- Minimap: a moon's orbit track rides the body it orbits -----------------

func test_moon_orbit_track_rides_its_parent_not_the_root() -> void:
	var b := _bodies()
	var level := _level(b, TransferCaptureObjective.new())
	var mv := MapView.new()
	add_child_autofree(mv)
	mv.build(level)
	var ship := ShipSim.new()
	ship.setup(level)
	mv.minimap_ortho_size = 1.0e9

	mv.sync(ship, 0.0, 1.0 / 60.0)

	# moons[0] = Earth (orbits the root): its track stays centered at the origin.
	assert_almost_eq(mv._moon_tracks[0].position.length(), 0.0, 1e-6,
		"a root-orbiting body's track is centered at the scene origin")
	# moons[1] = Moon (orbits Earth): its track must be offset onto Earth.
	var earth_scene: Vector3 = b.earth.position_at(0.0).scaled(MapView.MAP_SCALE).to_vector3()
	assert_gt(mv._moon_tracks[1].position.length(), 0.0, "the moon's track is offset off the origin")
	assert_almost_eq(mv._moon_tracks[1].position.distance_to(earth_scene), 0.0, 1e-4,
		"the moon's orbit track is centered on Earth, not the Sun")


# --- CR-9: minimap AUTO frames a transfer/landing target on every leg --------

func test_auto_extent_frames_a_transfer_target_at_each_leg() -> void:
	var b := _bodies()
	var obj := TransferCaptureObjective.new()
	obj.target = b.moon
	var level := _level(b, obj)
	var mv := MapView.new()
	add_child_autofree(mv)
	mv.build(level)
	var ship := ShipSim.new()
	ship.setup(level)  # a parking orbit around Earth

	# Inside Earth's SOI, AUTO must zoom out enough to show the Moon — transfer
	# targets used to return 0 reach, leaving the target off-screen (CR-9).
	var reach_earth := mv.auto_extent(ship, 0.0) / (3.0 * MapView.MAP_SCALE)
	assert_gt(reach_earth, D_MOON, "from Earth, AUTO frames the Moon, not just the parking orbit")

	# From the root, it frames the next hop on the route (the planet), so the
	# interplanetary transfer setup is on-screen.
	ship.body = b.sun
	var reach_root := mv.auto_extent(ship, 0.0) / (3.0 * MapView.MAP_SCALE)
	assert_gt(reach_root, D_EARTH, "from the root, AUTO frames the planet (the next hop)")


# --- PF-3: the minimap conic is rebuilt only when the coasting orbit changes ---

func test_minimap_conic_rebuilds_only_on_revision_while_coasting() -> void:
	var b := _bodies()
	var mv := MapView.new()
	add_child_autofree(mv)
	mv.build(_level(b, TransferCaptureObjective.new()))
	var ship := ShipSim.new()
	ship.setup(_level(b, TransferCaptureObjective.new()))
	mv.minimap_ortho_size = 1.0e9

	# delta > REFRESH_INTERVAL, so the throttle fires on every sync. First sync
	# builds the 256-point conic.
	mv.sync(ship, 0.0, 1.0)
	assert_gt(mv.orbit_mesh.get_surface_count(), 0, "the coasting conic is built")

	# Poison: clear the mesh. A stationary coasting revision must NOT rebuild it,
	# even though the refresh timer keeps firing (PF-3: the old code rebuilt every
	# REFRESH_INTERVAL regardless).
	mv.orbit_mesh.clear_surfaces()
	mv.sync(ship, 1.0, 1.0)
	assert_eq(mv.orbit_mesh.get_surface_count(), 0,
		"a stationary coasting orbit skips the minimap conic rebuild")

	# A refit (revision bump) rebuilds it.
	ship.revision += 1
	mv.sync(ship, 2.0, 1.0)
	assert_gt(mv.orbit_mesh.get_surface_count(), 0, "a refit rebuilds the minimap conic")

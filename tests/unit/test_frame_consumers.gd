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

	assert_almost_eq(absf(obj._phase_angle(ship)), PI / 2.0, 0.03,
		"phase angle is Earth-centric (90°), not the ~0° heliocentric comparison")


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

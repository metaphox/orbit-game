class_name Level03
extends RefCounted
## Act 1, Level 2: phasing and rendezvous with a station 20 km above.


static func make() -> LevelDef:
	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = 7.676e10
	earth.radius = 63710.0
	earth.color = Color(0.16, 0.3, 0.48)

	var station_r := 90000.0
	var v_station := sqrt(earth.mu / station_r)
	var phase := 0.7  # rad ahead of the ship at start
	var objective := RendezvousObjective.new()
	objective.station_orbit = OrbitElements.from_state(
		DVec3.new(station_r * cos(phase), 0.0, -station_r * sin(phase)),
		DVec3.new(-v_station * sin(phase), 0.0, -v_station * cos(phase)),
		earth.mu, 0.0)

	var level := LevelDef.new()
	level.title = "ORBIT SCHOOL 2: RENDEZVOUS"
	level.body = earth
	level.start_radius = 70000.0
	level.dry_mass = 1000.0
	level.prop_mass = 250.0
	level.thrust = 6000.0
	level.isp = 82.0
	level.objective = objective
	level.dv_par = 90.0
	level.sas_enabled = true
	return level

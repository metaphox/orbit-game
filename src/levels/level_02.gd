class_name Level02
extends RefCounted
## Act 2, Level 1: trans-lunar injection and capture.
##
## Same 1/100 world as Level01. Moon: distance 3844 km, SOI 660 km (real
## mass ratio 0.0123 preserved). Transfer takes ~8.6 h sim = seconds at
## high warp; TLI costs ~420 m/s, capture ~110, par 600 vs a 736 budget.
## The moon starts out of phase — waiting for the burn window IS the level.


static func make() -> LevelDef:
	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = 7.676e10
	earth.radius = 63710.0
	earth.color = Color(0.16, 0.3, 0.48)

	var moon := BodyDef.new()
	moon.name = "MOON"
	moon.mu = 9.44e8  # earth mu * 0.0123
	moon.radius = 17374.0
	moon.soi_radius = 6.6e5
	moon.parent = earth
	moon.color = Color(0.62, 0.6, 0.58)
	var d := 3.844e6
	var v_moon := sqrt(earth.mu / d)
	var theta := 2.0  # starting phase, rad ahead of the ship's +X start
	moon.orbit = OrbitElements.from_state(
		DVec3.new(d * cos(theta), 0.0, -d * sin(theta)),
		DVec3.new(-v_moon * sin(theta), 0.0, -v_moon * cos(theta)),
		earth.mu, 0.0)

	var objective := TransferCaptureObjective.new()
	objective.target = moon

	var level := LevelDef.new()
	level.title = "LUNAR PROGRAM 1: TRANSLUNAR INJECTION"
	level.body = earth
	level.moons = [moon]
	level.start_radius = 70000.0
	level.dry_mass = 1000.0
	level.prop_mass = 1500.0
	level.thrust = 12000.0
	level.isp = 82.0
	level.objective = objective
	level.dv_par = 600.0
	level.map_extent = 9200.0
	level.draw_limit = 6.0e6
	level.fail_radius = 8.0e6
	level.sas_enabled = true
	level.nodes_enabled = true
	return level

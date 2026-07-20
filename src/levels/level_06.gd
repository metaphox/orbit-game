class_name Level06
extends RefCounted
## Act 1, Level 3: plane change. Same 70 km circular orbit as Level01, but
## tilted 15 degrees off it — a pure normal/anti-normal burn at a node
## crossing, the level SAS's normal holds were built for.
##
## Ideal impulsive plane-change cost at 1047 m/s orbital speed:
## 2 * v * sin(7.5°) ≈ 273 m/s. Par is set a little above that since a
## continuous-thrust burn (not instantaneous) can't hold the exact normal
## direction the whole time.


static func make() -> LevelDef:
	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = 7.676e10
	earth.radius = 63710.0
	earth.color = Color(0.16, 0.3, 0.48)

	var objective := OrbitMatchObjective.new()
	objective.target_radius = 70000.0
	objective.tolerance = 1500.0
	objective.target_inclination = deg_to_rad(15.0)
	objective.inclination_tolerance = deg_to_rad(1.0)

	var level := LevelDef.new()
	level.title = "ORBIT SCHOOL 3: PLANE CHANGE"
	level.body = earth
	level.start_radius = 70000.0
	level.dry_mass = 1000.0
	level.prop_mass = 750.0
	level.thrust = 6000.0
	level.isp = 82.0
	level.objective = objective
	level.dv_par = 300.0
	level.sas_enabled = true
	return level

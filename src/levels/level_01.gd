class_name Level01
extends RefCounted
## Act 1, Level 1: raise a circular orbit from R 70 km to R 80 km.
##
## World scale is ~1/100 real (Earth radius 63.71 km): low orbit takes
## ~7 minutes and the full Hohmann transfer here costs ~68 m/s against a
## 179 m/s budget. All constants are tuning values (DESIGN.md section 12).


static func make() -> LevelDef:
	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = 7.676e10
	earth.radius = 63710.0

	var objective := OrbitMatchObjective.new()
	objective.target_radius = 80000.0
	objective.tolerance = 1500.0

	var level := LevelDef.new()
	level.title = "ORBIT SCHOOL 1: RAISE ORBIT"
	level.body = earth
	level.start_radius = 70000.0
	level.dry_mass = 1000.0
	level.prop_mass = 250.0
	level.thrust = 6000.0
	level.isp = 82.0
	level.objective = objective
	level.dv_par = 75.0
	return level

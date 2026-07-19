class_name Level04
extends RefCounted
## Act 2, Level 2: powered descent from low lunar orbit to the surface.


static func make() -> LevelDef:
	var level := Level02.make()
	var moon: BodyDef = level.moons[0]

	var objective := AirlessLandingObjective.new()
	objective.target = moon
	objective.max_vertical = 8.0
	objective.max_horizontal = 5.0

	level.title = "LUNAR PROGRAM 2: MARE SERENITATIS"
	level.start_body = moon
	level.start_radius = 25000.0
	level.prop_mass = 650.0
	level.thrust = 12000.0
	level.objective = objective
	level.dv_par = 280.0
	level.sas_enabled = true
	level.nodes_enabled = true
	return level

class_name Level05
extends RefCounted
## Act 2, Level 3: escape the Moon and hit the Earth entry corridor.


static func make() -> LevelDef:
	var level := Level02.make()
	var moon: BodyDef = level.moons[0]

	var objective := EntryCorridorObjective.new()
	objective.target_periapsis = 66000.0
	objective.tolerance = 800.0

	level.title = "LUNAR PROGRAM 3: COME HOME"
	level.start_body = moon
	level.start_radius = 25000.0
	level.prop_mass = 450.0
	level.thrust = 12000.0
	level.objective = objective
	level.dv_par = 130.0
	level.sas_enabled = true
	level.nodes_enabled = true
	return level

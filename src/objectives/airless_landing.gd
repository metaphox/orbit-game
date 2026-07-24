class_name AirlessLandingObjective
extends Objective
## Powered descent onto an airless body: surface contact wins if vertical
## and horizontal speeds are under the limits, otherwise it's a crash.

@export var target: BodyDef
@export var max_vertical := 8.0
@export var max_horizontal := 5.0


func contact_result(ship: ShipSim) -> ContactResult:
	if ship.body != target:
		return ContactResult.NONE
	var up := ship.r.normalized()
	var vertical := ship.v.dot(up)
	var horizontal := ship.v.sub(up.scaled(vertical)).length()
	if absf(vertical) <= max_vertical and horizontal <= max_horizontal:
		return ContactResult.WIN
	return ContactResult.CRASH


func describe() -> String:
	return tr("LAND ON THE %s (V<%.0f  H<%.0f m/s)") % [
		tr(target.name), max_vertical, max_horizontal]


func status_lines(ship: ShipSim) -> Array[String]:
	if ship.body != target:
		return [tr("TRANSIT TO THE %s") % tr(target.name)]
	var up := ship.r.normalized()
	var vertical := ship.v.dot(up)
	var horizontal := ship.v.sub(up.scaled(vertical)).length()
	return ["RADAR %7.0f m   VS %+6.1f   HS %5.1f" % [
		ship.altitude(), vertical, horizontal]]


func trajectory_closeness(ship: ShipSim) -> float:
	return 0.85 if ship.body == target else 0.35

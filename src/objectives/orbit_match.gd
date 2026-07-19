class_name OrbitMatchObjective
extends RefCounted
## Win when the coasting orbit's apoapsis and periapsis radii are both
## inside the tolerance band around target_radius.

var target_radius := 0.0
var tolerance := 0.0


func is_met(ship: ShipSim) -> bool:
	if ship.flight_state != ShipSim.FlightState.COASTING:
		return false
	var el := ship.elements
	if not el.is_elliptic():
		return false
	return (absf(el.radius_apoapsis() - target_radius) <= tolerance
		and absf(el.radius_periapsis() - target_radius) <= tolerance)


func describe() -> String:
	return "CIRCULARIZE AT R %.1f KM ± %.1f" % [
		target_radius / 1000.0, tolerance / 1000.0]

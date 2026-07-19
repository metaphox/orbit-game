class_name OrbitMatchObjective
extends Objective
## Win when the coasting orbit's apoapsis and periapsis radii are both
## inside the tolerance band around target_radius.

var target_radius := 0.0
var tolerance := 0.0
var closeness_falloff := 20000.0  # m of Ap/Pe error at which the line is fully amber


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


func status_lines(ship: ShipSim) -> Array:
	var el := ship.current_elements()
	if not el.is_elliptic():
		return ["AP  ESCAPE   PE Δ%+8.2f" % ((el.radius_periapsis() - target_radius) / 1000.0)]
	return ["AP Δ%+8.2f   PE Δ%+8.2f" % [
		(el.radius_apoapsis() - target_radius) / 1000.0,
		(el.radius_periapsis() - target_radius) / 1000.0]]


func trajectory_closeness(ship: ShipSim) -> float:
	var el := ship.current_elements()
	if not el.is_elliptic():
		return 0.0
	var err := maxf(
		absf(el.radius_apoapsis() - target_radius),
		absf(el.radius_periapsis() - target_radius))
	return 1.0 - clampf((err - tolerance) / closeness_falloff, 0.0, 1.0)

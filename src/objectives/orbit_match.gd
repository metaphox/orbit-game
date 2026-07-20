class_name OrbitMatchObjective
extends Objective
## Win when the coasting orbit's apoapsis and periapsis radii are both
## inside the tolerance band around target_radius.

@export var target_radius := 0.0
@export var tolerance := 0.0
@export var closeness_falloff := 20000.0  # m of Ap/Pe error at which the line is fully amber

## Optional: require a specific orbital plane too (radians). Disabled by
## default (tolerance = PI, i.e. any inclination passes) so existing pure
## altitude levels are unaffected.
@export var target_inclination := 0.0
@export var inclination_tolerance := PI


func is_met(ship: ShipSim) -> bool:
	if ship.flight_state != ShipSim.FlightState.COASTING:
		return false
	var el := ship.elements
	if not el.is_elliptic():
		return false
	return (absf(el.radius_apoapsis() - target_radius) <= tolerance
		and absf(el.radius_periapsis() - target_radius) <= tolerance
		and absf(_tilt(el) - target_inclination) <= inclination_tolerance)


func describe() -> String:
	var base := "CIRCULARIZE AT R %.1f KM ± %.1f" % [
		target_radius / 1000.0, tolerance / 1000.0]
	if inclination_tolerance < PI:
		base += "\nINCLINATION %.1f° ± %.1f°" % [
			rad_to_deg(target_inclination), rad_to_deg(inclination_tolerance)]
	return base


func status_lines(ship: ShipSim) -> Array:
	var el := ship.current_elements()
	var lines: Array
	if not el.is_elliptic():
		lines = ["AP  ESCAPE   PE Δ%+8.2f" % ((el.radius_periapsis() - target_radius) / 1000.0)]
	else:
		lines = ["AP Δ%+8.2f   PE Δ%+8.2f" % [
			(el.radius_apoapsis() - target_radius) / 1000.0,
			(el.radius_periapsis() - target_radius) / 1000.0]]
	if inclination_tolerance < PI:
		lines.append("INC %6.2f°  Δ%+6.2f°" % [
			rad_to_deg(_tilt(el)), rad_to_deg(_tilt(el) - target_inclination)])
	return lines


func trajectory_closeness(ship: ShipSim) -> float:
	var el := ship.current_elements()
	if not el.is_elliptic():
		return 0.0
	var err := maxf(
		absf(el.radius_apoapsis() - target_radius),
		absf(el.radius_periapsis() - target_radius))
	var closeness := 1.0 - clampf((err - tolerance) / closeness_falloff, 0.0, 1.0)
	if inclination_tolerance < PI:
		var inc_err := absf(_tilt(el) - target_inclination)
		var inc_closeness := 1.0 - clampf(
			(inc_err - inclination_tolerance) / deg_to_rad(3.0), 0.0, 1.0)
		closeness = minf(closeness, inc_closeness)
	return closeness


## Orbit tilt against the game's actual "up" (+Y), not classical inc
## (which OrbitElements measures against +Z internally — see its doc).
func _tilt(el: OrbitElements) -> float:
	return acos(clampf(el.plane_normal.y, -1.0, 1.0))

class_name TransferCaptureObjective
extends Objective
## Win when the ship holds a bound orbit around the target body: inside its
## SOI, elliptic, apoapsis under the SOI edge, periapsis above the surface.

var target: BodyDef
var approach_falloff := 6.0e5  # m of apoapsis error at which the line is fully amber


func is_met(ship: ShipSim) -> bool:
	if ship.body != target or ship.flight_state != ShipSim.FlightState.COASTING:
		return false
	var el := ship.elements
	return (el.is_elliptic()
		and el.radius_apoapsis() <= target.soi_radius * 0.98
		and el.radius_periapsis() > target.radius)


func describe() -> String:
	return "ACHIEVE ORBIT AROUND THE %s" % target.name


func status_lines(ship: ShipSim) -> Array:
	if ship.body == target:
		var el := ship.current_elements()
		if el.is_elliptic() and el.radius_apoapsis() <= target.soi_radius * 0.98:
			if el.radius_periapsis() <= target.radius:
				return ["CAPTURED — PE BELOW SURFACE, RAISE IT"]
			return ["CAPTURED — HOLDING ORBIT"]
		return ["IN %s SOI — BURN RETROGRADE NEAR PE" % target.name]
	var el := ship.current_elements()
	var lines: Array = []
	var d: float = target.orbit.a
	if el.is_elliptic():
		lines.append("AP Δ%+8.0f km vs %s DIST" % [
			(el.radius_apoapsis() - d) / 1000.0, target.name])
	else:
		lines.append("ESCAPE TRAJECTORY — TOO FAST")
	lines.append("PHASE TO %s %+4.0f°  (BURN AT %+4.0f°)" % [
		target.name, rad_to_deg(_phase_angle(ship)), rad_to_deg(_tli_lead_angle(ship))])
	return lines


func trajectory_closeness(ship: ShipSim) -> float:
	if ship.body == target:
		var el := ship.current_elements()
		if el.is_elliptic() and el.radius_apoapsis() <= target.soi_radius:
			return 1.0
		return 0.55
	var el := ship.current_elements()
	if not el.is_elliptic():
		return 0.25
	var err := absf(el.radius_apoapsis() - target.orbit.a)
	return clampf(1.0 - err / approach_falloff, 0.0, 1.0) * 0.85


## Signed angle from the ship to the target around the orbit normal (+Y);
## positive = target is ahead.
func _phase_angle(ship: ShipSim) -> float:
	var ship_dir := ship.r.normalized()
	var target_dir := target.orbit.state_at_time(ship.last_time).r.normalized()
	var c := clampf(ship_dir.dot(target_dir), -1.0, 1.0)
	var ang := acos(c)
	return ang if ship_dir.cross(target_dir).y > 0.0 else -ang


## Phase angle at which a Hohmann-style burn from the current radius
## arrives when the target does: PI minus how far the target moves during
## the transfer.
func _tli_lead_angle(ship: ShipSim) -> float:
	var a_transfer := (ship.r.length() + target.orbit.a) * 0.5
	var transfer_time := PI * sqrt(pow(a_transfer, 3.0) / ship.body.mu)
	return PI - target.orbit.mean_motion() * transfer_time

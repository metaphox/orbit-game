class_name TransferCaptureObjective
extends Objective
## Win when the ship holds a bound orbit around the target body: inside its
## SOI, elliptic, apoapsis under the SOI edge, periapsis above the surface.

@export var target: BodyDef
@export var approach_falloff := 6.0e5  # m of apoapsis error at which the line is fully amber


func is_met(ship: ShipSim) -> bool:
	if ship.body != target or ship.flight_state != ShipSim.FlightState.COASTING:
		return false
	var el := ship.elements
	return (el.is_elliptic()
		and el.radius_apoapsis() <= target.soi_radius * 0.98
		and el.radius_periapsis() > target.radius)


func describe() -> String:
	return tr("ACHIEVE ORBIT AROUND THE %s") % tr(target.name)


func status_lines(ship: ShipSim) -> Array[String]:
	if ship.body == target:
		var el := ship.current_elements()
		if el.is_elliptic() and el.radius_apoapsis() <= target.soi_radius * 0.98:
			if el.radius_periapsis() <= target.radius:
				return [tr("CAPTURED — PE BELOW SURFACE, RAISE IT")]
			return [tr("CAPTURED — HOLDING ORBIT")]
		return [tr("IN %s SOI — BURN RETROGRADE NEAR PE") % tr(target.name)]
	# Guide toward the NEXT body on the route, not the final target: from Sol you
	# aim at the planet, and only inside the planet's SOI at the moon (CR-8). The
	# next hop's orbit is expressed in the ship's current frame, so the apoapsis
	# comparison is meaningful; comparing against the moon's planet-centric orbit
	# from a heliocentric ship was not.
	var next_body := _next_hop(ship.body)
	var lines: Array[String] = []
	if next_body != null:  # descending toward the target: apoapsis vs the next hop
		var el := ship.current_elements()
		if el.is_elliptic():
			lines.append("AP Δ%+8.0f km vs %s DIST" % [
				(el.radius_apoapsis() - next_body.orbit.a) / 1000.0, next_body.name])
		else:
			lines.append(tr("ESCAPE TRAJECTORY — TOO FAST"))
	else:  # a sibling branch: climb out of this SOI first
		lines.append(tr("DEPARTING %s") % tr(ship.body.name))
	# Phase toward the leg's aim body (the next hop, or the one after climbing out
	# by a level, e.g. Earth→Mars phases about the Sun while still departing Earth).
	var aim := _aim_body(ship.body)
	if aim != null:
		lines.append(tr("PHASE TO %s %+4.0f°  (BURN AT %+4.0f°)") % [
			tr(aim.name), rad_to_deg(_phase_angle(ship, aim)),
			rad_to_deg(_tli_lead_angle(ship, aim))])
	return lines


func trajectory_closeness(ship: ShipSim) -> float:
	if ship.body == target:
		var captured_el := ship.current_elements()
		if captured_el.is_elliptic() and captured_el.radius_apoapsis() <= target.soi_radius:
			return 1.0
		return 0.55
	var next_body := _next_hop(ship.body)
	if next_body == null:
		return 0.2  # sibling branch: must climb out first, not meaningfully "close"
	var el := ship.current_elements()
	if not el.is_elliptic():
		return 0.25
	# Compare apoapsis to the next hop's distance, both in the ship's frame — so
	# closeness reads correctly on every leg, not just from the root.
	var err := absf(el.radius_apoapsis() - next_body.orbit.a)
	return clampf(1.0 - err / approach_falloff, 0.0, 1.0) * 0.85


## The next body to aim for on the route from `from_body` to the target: the
## child of `from_body` that is (or contains) the target. null when `from_body`
## isn't an ancestor of the target — a sibling branch the ship must climb out of
## first. `next.orbit` is in `from_body`'s frame, matching the ship's elements.
func _next_hop(from_body: BodyDef) -> BodyDef:
	var node := target
	while node != null and node.parent != from_body:
		node = node.parent
	return node


## The body to phase toward for the current transfer leg. Descending, that's the
## next hop; when climbing out one level (e.g. Earth departing toward Mars), it's
## the next hop from the parent — so the phase/lead angle is shown throughout the
## departure, about the shared centre. null only for a rare multi-climb route.
func _aim_body(from_body: BodyDef) -> BodyDef:
	var here := _next_hop(from_body)
	if here != null:
		return here
	return _next_hop(from_body.parent) if from_body.parent != null else null


## Signed angle from the ship to the target around the orbit normal (+Y);
## positive = target is ahead. Measured from the body the transfer actually
## orbits — the target's parent, the shared center both bodies circle — so
## the angle is meaningful at any nesting depth. For an Earth→Mars transfer
## the shared center is the Sun (the root); for an Earth→Moon transfer it is
## Earth. Reducing everything to the root instead would be wrong for a moon,
## whose heliocentric position is dominated by its planet's, not its own.
func _phase_angle(ship: ShipSim, aim: BodyDef) -> float:
	var t := ship.last_time
	var center := aim.parent
	var ship_dir := Frames.point_relative_to(ship.absolute_position(t), center, t).normalized()
	var target_dir := Frames.position_relative_to(aim, center, t).normalized()
	var c := clampf(ship_dir.dot(target_dir), -1.0, 1.0)
	var ang := acos(c)
	return ang if ship_dir.cross(target_dir).y > 0.0 else -ang


## Phase angle at which a Hohmann-style burn from the current radius
## arrives when the target does: PI minus how far the target moves during
## the transfer. Radius, semi-major axis and mean motion are all taken about
## the shared center (target's parent), so the transfer geometry is consistent
## whatever frame the ship currently sits in.
func _tli_lead_angle(ship: ShipSim, aim: BodyDef) -> float:
	var t := ship.last_time
	var r0 := Frames.point_relative_to(ship.absolute_position(t), aim.parent, t).length()
	var a_transfer := (r0 + aim.orbit.a) * 0.5
	var transfer_time := PI * sqrt(pow(a_transfer, 3.0) / aim.orbit.mu)
	return PI - aim.orbit.mean_motion() * transfer_time

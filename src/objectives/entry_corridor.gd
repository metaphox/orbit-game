class_name EntryCorridorObjective
extends Objective
## Win when the coasting orbit around the root body dips its periapsis into
## the entry corridor. No atmosphere is simulated — the capsule takes it
## from there (DESIGN.md section 5).

@export var target_periapsis := 0.0
@export var tolerance := 0.0
@export var closeness_falloff := 5.0e5


func is_met(ship: ShipSim) -> bool:
	if ship.body.parent != null or ship.flight_state != ShipSim.FlightState.COASTING:
		return false
	return absf(ship.elements.radius_periapsis() - target_periapsis) <= tolerance


func describe() -> String:
	return "ENTRY CORRIDOR: PE %.1f ± %.1f KM" % [
		target_periapsis / 1000.0, tolerance / 1000.0]


func status_lines(ship: ShipSim) -> Array[String]:
	if ship.body.parent != null:
		return ["ESCAPE THE %s FIRST" % ship.body.name]
	return ["PE Δ%+9.2f km vs CORRIDOR" % [
		(ship.current_elements().radius_periapsis() - target_periapsis) / 1000.0]]


func trajectory_closeness(ship: ShipSim) -> float:
	if ship.body.parent != null:
		return 0.3
	var err := absf(ship.current_elements().radius_periapsis() - target_periapsis)
	return 1.0 - clampf((err - tolerance) / closeness_falloff, 0.0, 1.0)

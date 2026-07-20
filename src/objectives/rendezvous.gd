class_name RendezvousObjective
extends Objective
## Win when coasting within max_distance of the station with relative
## speed under max_rel_speed. No docking minigame — proximity ends it.

var station_orbit: OrbitElements
var station_name := "STATION"
var max_distance := 2000.0
var max_rel_speed := 25.0
var closeness_falloff := 1.0e5


func is_met(ship: ShipSim) -> bool:
	if ship.body.parent != null or ship.flight_state != ShipSim.FlightState.COASTING:
		return false
	var st := station_orbit.state_at_time(ship.last_time)
	return (ship.r.distance_to(st.r) <= max_distance
		and ship.v.sub(st.v).length() <= max_rel_speed)


func describe() -> String:
	return "RENDEZVOUS WITH %s (<%.1f KM, <%.0f M/S)" % [
		station_name, max_distance / 1000.0, max_rel_speed]


func status_lines(ship: ShipSim) -> Array:
	var st := station_orbit.state_at_time(ship.last_time)
	var lines: Array = ["DIST %8.2f km   REL-V %6.1f m/s" % [
		ship.r.distance_to(st.r) / 1000.0, ship.v.sub(st.v).length()]]
	var ca := closest_approach(ship)
	lines.append("CLOSEST %8.2f km  T+%4.0f s" % [
		ca.distance / 1000.0, ca.time - ship.last_time])
	return lines


func trajectory_closeness(ship: ShipSim) -> float:
	if is_met(ship):
		return 1.0
	var ca := closest_approach(ship)
	return clampf(1.0 - ca.distance / closeness_falloff, 0.0, 1.0) * 0.9


func closest_approach(ship: ShipSim) -> Dictionary:
	var el := ship.current_elements()
	var span := el.period() if el.is_elliptic() else 2.0e4
	return OrbitEvents.closest_approach(
		el, station_orbit, ship.last_time, ship.last_time + span, span / 240.0)

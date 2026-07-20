class_name RendezvousObjective
extends Objective
## Win when coasting within max_distance of the station with relative
## speed under max_rel_speed. No docking minigame — proximity ends it.

## Circular orbit around the level's root body, in the XZ plane - literal
## @export fields rather than a stored OrbitElements so a level .tres stays
## plain Inspector-editable data; the OrbitElements is derived and cached
## lazily via the `station_orbit` property below.
@export var station_orbit_radius := 0.0
@export var station_orbit_phase_deg := 0.0
@export var station_mu := 0.0
@export var station_orbit_epoch := 0.0
@export var station_name := "STATION"
@export var max_distance := 2000.0
@export var max_rel_speed := 25.0
@export var closeness_falloff := 1.0e5

## OrbitElements for the station, rebuilt on every access - see BodyDef.orbit
## for why this isn't cached. Read-only: nothing should assign to this
## directly.
var station_orbit: OrbitElements:
	get:
		return OrbitElements.circular(
			station_mu, station_orbit_radius, station_orbit_phase_deg, station_orbit_epoch)


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


const CLOSEST_APPROACH_CACHE_WINDOW := 2.0  # sim seconds

var _ca_cache: Dictionary = {}
var _ca_revision := -1
var _ca_time := -INF


## Shared by status_lines, trajectory_closeness, and FlightView's marker so
## the ~360-Kepler-solve OrbitEvents.closest_approach() call underneath
## this doesn't run 2-3x per frame. Cached until a burn/refit bumps
## ship.revision or predicted sim time drifts past the cache window - the
## prediction window is [ship.last_time, ship.last_time + span], which
## genuinely shifts as the ship coasts, so revision alone isn't enough.
func closest_approach(ship: ShipSim) -> Dictionary:
	if ship.revision != _ca_revision or absf(ship.last_time - _ca_time) >= CLOSEST_APPROACH_CACHE_WINDOW:
		var el := ship.current_elements()
		var span := el.period() if el.is_elliptic() else 2.0e4
		_ca_cache = OrbitEvents.closest_approach(
			el, station_orbit, ship.last_time, ship.last_time + span, span / 240.0)
		_ca_revision = ship.revision
		_ca_time = ship.last_time
	return _ca_cache

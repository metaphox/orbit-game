class_name BodyDef
extends Resource
## A gravitating body. Root bodies sit at the origin; children ride Kepler
## rails around their parent. Single-level hierarchy for now (moons of the
## root body); position_at recurses, so deeper nesting only needs SOI logic
## updates in ShipSim.

@export var name := ""
@export var mu := 0.0
@export var radius := 0.0
@export var soi_radius := INF
@export var parent: BodyDef:
	set(value):
		parent = value
		_orbit_cache = null
@export var color := Color(0.5, 0.5, 0.5)

## Circular orbit around parent, in the XZ plane; unused for the root body
## (parent == null). Literal @export fields rather than a stored
## OrbitElements so a level .tres stays plain Inspector-editable data - the
## OrbitElements is derived and cached lazily via the `orbit` property below.
@export var orbit_radius := 0.0:
	set(value):
		orbit_radius = value
		_orbit_cache = null
@export var orbit_phase_deg := 0.0:
	set(value):
		orbit_phase_deg = value
		_orbit_cache = null
@export var orbit_epoch := 0.0:
	set(value):
		orbit_epoch = value
		_orbit_cache = null

var _orbit_cache: OrbitElements = null

## OrbitElements around parent, lazily built from orbit_radius/orbit_phase_deg/
## orbit_epoch and cached until one of those (or parent) changes. position_at
## calls this on every access from several per-frame call sites (flight_view,
## map_view, ship_sim's SOI checks); rebuilding it from scratch each time -
## OrbitElements.circular() does several DVec3 allocations plus a from_state()
## fit - was cheap in isolation but added up badly once a level actually has
## a moon to orbit (root-body-only levels never touch this at all, which is
## why only lunar/multi-body missions felt it). Read-only: nothing should
## assign to this directly.
var orbit: OrbitElements:
	get:
		if _orbit_cache == null:
			_orbit_cache = OrbitElements.circular(parent.mu, orbit_radius, orbit_phase_deg, orbit_epoch)
		return _orbit_cache


func position_at(t: float) -> DVec3:
	if parent == null:
		return DVec3.new()
	return parent.position_at(t).add(orbit.state_at_time(t).r)


func velocity_at(t: float) -> DVec3:
	if parent == null:
		return DVec3.new()
	return parent.velocity_at(t).add(orbit.state_at_time(t).v)

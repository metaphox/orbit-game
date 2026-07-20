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
@export var parent: BodyDef
@export var color := Color(0.5, 0.5, 0.5)

## Circular orbit around parent, in the XZ plane; unused for the root body
## (parent == null). Literal @export fields rather than a stored
## OrbitElements so a level .tres stays plain Inspector-editable data - the
## OrbitElements is derived and cached lazily via the `orbit` property below.
@export var orbit_radius := 0.0
@export var orbit_phase_deg := 0.0
@export var orbit_epoch := 0.0

## OrbitElements around parent, rebuilt from orbit_radius/orbit_phase_deg/
## orbit_epoch on every access (cheap: a handful of trig ops, dwarfed by the
## Kepler solve state_at_time() already does). Not cached, so re-phasing a
## body (e.g. a test that reflies it at a different starting angle) via
## orbit_phase_deg takes effect immediately. Read-only: nothing should
## assign to this directly.
var orbit: OrbitElements:
	get:
		return OrbitElements.circular(parent.mu, orbit_radius, orbit_phase_deg, orbit_epoch)


func position_at(t: float) -> DVec3:
	if parent == null:
		return DVec3.new()
	return parent.position_at(t).add(orbit.state_at_time(t).r)


func velocity_at(t: float) -> DVec3:
	if parent == null:
		return DVec3.new()
	return parent.velocity_at(t).add(orbit.state_at_time(t).v)

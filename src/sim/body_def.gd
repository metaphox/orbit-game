class_name BodyDef
extends RefCounted
## A gravitating body. Root bodies sit at the origin; children ride Kepler
## rails around their parent. Single-level hierarchy for now (moons of the
## root body); position_at recurses, so deeper nesting only needs SOI logic
## updates in ShipSim.

var name := ""
var mu := 0.0
var radius := 0.0
var soi_radius := INF
var parent: BodyDef
var orbit: OrbitElements  # around parent; null for the root body
var color := Color(0.5, 0.5, 0.5)


func position_at(t: float) -> DVec3:
	if parent == null:
		return DVec3.new()
	return parent.position_at(t).add(orbit.state_at_time(t).r)


func velocity_at(t: float) -> DVec3:
	if parent == null:
		return DVec3.new()
	return parent.velocity_at(t).add(orbit.state_at_time(t).v)

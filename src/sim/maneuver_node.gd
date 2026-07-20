class_name ManeuverNode
extends RefCounted
## A planned burn: a time on the current orbit plus a delta-v expressed in
## the orbital frame at that time (prograde / normal / radial-out).
## `remaining` is the world-frame dv still to be burned; it depletes as the
## player executes and defines the node-hold SAS direction.

var t_node := 0.0
var prograde := 0.0
var normal := 0.0
var radial := 0.0
var remaining := DVec3.new()


func total_dv() -> float:
	return sqrt(prograde * prograde + normal * normal + radial * radial)


## The planned dv in parent-frame world coordinates, using the orbital
## frame (prograde/normal/radial) at the node's position on `el`.
func planned_world_dv(el: OrbitElements) -> DVec3:
	var state := el.state_at_time(t_node)
	var pro_dir := state.v.normalized()
	var norm_dir := state.r.cross(state.v).normalized()
	var rad_dir := state.r.normalized()
	return pro_dir.scaled(prograde) \
		.add(norm_dir.scaled(normal)) \
		.add(rad_dir.scaled(radial))


func serialize() -> Dictionary:
	return {
		"t_node": t_node,
		"prograde": prograde,
		"normal": normal,
		"radial": radial,
		"remaining": [remaining.x, remaining.y, remaining.z],
	}

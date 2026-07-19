class_name Frames
extends RefCounted
## Re-expressing ship states between parent and child body frames.
##
## child_el is the child body's orbit around the parent (e.g. the Moon
## around Earth). Both transforms are exact at the given time; SOI handoff
## is just a frame change plus re-fitting elements in the new frame.


## Ship state in the parent frame -> state relative to the child body.
static func to_child_frame(ship: StateRV, child_el: OrbitElements, t: float) -> StateRV:
	var child := child_el.state_at_time(t)
	return StateRV.new(ship.r.sub(child.r), ship.v.sub(child.v))


## Ship state relative to the child body -> state in the parent frame.
static func to_parent_frame(ship: StateRV, child_el: OrbitElements, t: float) -> StateRV:
	var child := child_el.state_at_time(t)
	return StateRV.new(ship.r.add(child.r), ship.v.add(child.v))

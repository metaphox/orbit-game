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


# --- Body-graph frames (depth-independent) ---------------------------------
# BodyDef.position_at already recurses to the root; these name the frame a
# value lives in so call sites stop mixing root-frame `.position_at()` with
# parent-relative `.orbit.r`. `origin == null` means the root (the origin).


## Root-frame position of `body` at time t (an explicitly-named alias for
## BodyDef.position_at, so frame-sensitive reads say which frame they mean).
static func root_position(body: BodyDef, t: float) -> DVec3:
	return body.position_at(t)


## Root-frame position of `origin` (or the origin itself when null).
static func _origin_position(origin: BodyDef, t: float) -> DVec3:
	return origin.position_at(t) if origin != null else DVec3.new()


## Position of `body` measured from `origin`'s center at time t. Both are taken
## in the root frame first, so this is exact at any nesting depth - `origin`
## need not be `body`'s direct parent.
static func position_relative_to(body: BodyDef, origin: BodyDef, t: float) -> DVec3:
	return body.position_at(t).sub(_origin_position(origin, t))


## Same, for an arbitrary root-frame point (e.g. a ship's absolute_position).
static func point_relative_to(root_pos: DVec3, origin: BodyDef, t: float) -> DVec3:
	return root_pos.sub(_origin_position(origin, t))


## The root ancestor of `body` (walks parents; returns `body` if it is root).
static func root_of(body: BodyDef) -> BodyDef:
	var b := body
	while b.parent != null:
		b = b.parent
	return b

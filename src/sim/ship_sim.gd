class_name ShipSim
extends RefCounted
## The ship's physical state machine: Coasting (closed-form rails via
## OrbitElements) or Burning (RK4 with mass depletion). Pure sim — no Nodes.
##
## Sim frame == Godot frame (y-up, right-handed); the orbital plane of the
## starting orbit is the horizontal xz-plane. Ship forward is local -Z.

enum FlightState { COASTING, BURNING }
enum SasMode { OFF, PROGRADE, RETROGRADE, NORMAL, ANTI_NORMAL, RADIAL_OUT, RADIAL_IN, NODE }

const BURN_SUBSTEP := 0.05
const SAS_NAMES := ["OFF", "PROGRADE", "RETROGRADE", "NORMAL", "ANTI-NORM", "RADIAL+", "RADIAL-", "NODE"]
const NODE_COMPLETE_DV := 0.5  # m/s left at which a node counts as burned

var body: BodyDef
var elements: OrbitElements
var r := DVec3.new()
var v := DVec3.new()
var attitude := Basis.IDENTITY
var throttle := 0.0
var dry_mass := 0.0
var prop_mass := 0.0
var thrust_max := 0.0
var isp := 0.0
var flight_state := FlightState.COASTING
var last_time := 0.0
var initial_mass := 0.0
var accel_along_track := 0.0  # smoothed d|v|/dt in sim time, m/s^2
var revision := 0  # bumps whenever elements are refit (event caches key on it)
var sas_mode := SasMode.OFF
var node: ManeuverNode
var node_completed := false  # one-shot flag for the UI to poll and clear

var _level: LevelDef


func setup(level: LevelDef) -> void:
	_level = level
	body = level.start_body if level.start_body != null else level.body
	dry_mass = level.dry_mass
	prop_mass = level.prop_mass
	thrust_max = level.thrust
	isp = level.isp
	initial_mass = mass()
	r = DVec3.new(level.start_radius, 0.0, 0.0)
	v = DVec3.new(0.0, 0.0, -sqrt(body.mu / level.start_radius))
	attitude = Basis.IDENTITY  # forward (-Z) starts prograde
	elements = OrbitElements.from_state(r, v, body.mu, 0.0)
	flight_state = FlightState.COASTING
	last_time = 0.0


func advance_to(t: float) -> void:
	if t <= last_time:
		return
	var speed_before := v.length()
	if throttle > 0.0 and prop_mass > 0.0:
		var thrust := thrust_max * throttle
		var flow := Integrator.mass_flow(thrust, isp)
		var burn_end := minf(t, last_time + prop_mass / flow)
		_integrate_burn(burn_end - last_time, thrust, flow)
		if burn_end < t:  # tank ran dry mid-frame; coast the remainder
			_refit_elements(burn_end)
			_coast_to(t)
	elif flight_state == FlightState.BURNING:
		_refit_elements(last_time)
		_coast_to(t)
	else:
		_coast_to(t)
	accel_along_track = lerpf(
		accel_along_track, (v.length() - speed_before) / (t - last_time), 0.25)
	last_time = t


## Cross SOI boundaries: hand the state to the new parent frame and refit.
## Called after each advance; rails warp is clamped to precomputed event
## times upstream, so polling here only ever sees small overshoots.
## Returns a short notice for the HUD, or "" when nothing happened.
##
## Exit and entry aren't mutually exclusive once nesting is more than one
## level deep (e.g. a ship inside Earth's SOI, Earth itself a child of the
## Sun, can still enter a moon of Earth), so both are checked every call -
## not just at the root. level.moons is a flat list of every non-root body
## in the level regardless of depth; filtering by moon.parent == body finds
## the current body's actual children at any depth.
func apply_soi_transitions(t: float) -> String:
	if body.parent != null and r.length() >= body.soi_radius:
		var st := Frames.to_parent_frame(StateRV.new(r, v), body.orbit, t)
		var old := body.name
		body = body.parent
		r = st.r
		v = st.v
		_refit_elements(t)
		return "LEAVING %s SOI" % old
	for moon in _level.moons:
		if moon.parent != body:
			continue
		var moon_state := moon.orbit.state_at_time(t)
		if r.distance_to(moon_state.r) <= moon.soi_radius:
			var st := Frames.to_child_frame(StateRV.new(r, v), moon.orbit, t)
			body = moon
			r = st.r
			v = st.v
			_refit_elements(t)
			return "ENTERING %s SOI" % moon.name
	return ""


## Position in root-body coordinates (parents recurse to the origin).
func absolute_position(t: float) -> DVec3:
	return body.position_at(t).add(r)


func rotate_local(angles: Vector3) -> void:
	attitude = (attitude
		* Basis(Vector3(1, 0, 0), angles.x)
		* Basis(Vector3(0, 1, 0), angles.y)
		* Basis(Vector3(0, 0, 1), angles.z)).orthonormalized()


## Orbit elements matching the current state, valid this instant even
## mid-burn (refit on the fly for trajectory display).
func current_elements() -> OrbitElements:
	if flight_state == FlightState.COASTING:
		return elements
	return OrbitElements.from_state(r, v, body.mu, last_time)


func forward_dir() -> DVec3:
	var f := attitude * Vector3(0, 0, -1)
	return DVec3.new(f.x, f.y, f.z).normalized()


func mass() -> float:
	return dry_mass + prop_mass


func altitude() -> float:
	return r.length() - body.radius


func speed() -> float:
	return v.length()


func dv_remaining() -> float:
	return Integrator.delta_v(mass(), dry_mass, isp)


func dv_used() -> float:
	return Integrator.delta_v(initial_mass, mass(), isp)


func create_node(at_time: float) -> void:
	node = ManeuverNode.new()
	node.t_node = at_time
	refresh_node_plan()


## Recompute the node's world-frame dv after any edit (also resets the
## remaining-burn vector to the full plan).
func refresh_node_plan() -> void:
	if node != null:
		node.remaining = node.planned_world_dv(current_elements())


func predicted_elements() -> OrbitElements:
	if node == null:
		return null
	var el := current_elements()
	var state := el.state_at_time(node.t_node)
	return OrbitElements.from_state(
		state.r, state.v.add(node.planned_world_dv(el)), body.mu, node.t_node)


## Direction the active SAS mode wants the nose pointing (unit vector in
## the parent frame). Roll is left free — holds align forward only. Falls
## back to holding the current attitude (a no-op) when the mode's source
## vector is too close to zero to define a direction (e.g. PROGRADE/
## RETROGRADE after a burn that's nearly killed velocity, or NORMAL/
## ANTI_NORMAL on a near-radial trajectory) rather than snapping to
## DVec3.normalized()'s zero-vector fallback.
func sas_target_dir() -> DVec3:
	if sas_mode == SasMode.NODE:
		if node != null and node.remaining.length() > 0.05:
			return node.remaining.normalized()
		return forward_dir()
	match sas_mode:
		SasMode.PROGRADE:
			return v.normalized() if v.length() > 1e-6 else forward_dir()
		SasMode.RETROGRADE:
			return v.normalized().neg() if v.length() > 1e-6 else forward_dir()
		SasMode.NORMAL:
			var h := r.cross(v)
			return h.normalized() if h.length() > 1e-6 else forward_dir()
		SasMode.ANTI_NORMAL:
			var h := r.cross(v)
			return h.normalized().neg() if h.length() > 1e-6 else forward_dir()
		SasMode.RADIAL_OUT:
			return r.normalized() if r.length() > 1e-6 else forward_dir()
		SasMode.RADIAL_IN:
			return r.normalized().neg() if r.length() > 1e-6 else forward_dir()
	return forward_dir()


## Angle between the nose and prograde, for the HUD.
func off_prograde_angle() -> float:
	var c := forward_dir().dot(v.normalized())
	return acos(clampf(c, -1.0, 1.0))


func _integrate_burn(duration: float, thrust: float, flow: float) -> void:
	flight_state = FlightState.BURNING
	var mass_before := mass()
	var s := Integrator.BurnState.new(r, v, mass_before)
	var dir := forward_dir()
	var t_done := 0.0
	while t_done < duration - 1e-9:
		var h := minf(BURN_SUBSTEP, duration - t_done)
		s = Integrator.rk4_step(s, body.mu, dir, thrust, flow, h)
		t_done += h
	r = s.r
	v = s.v
	prop_mass = maxf(s.mass - dry_mass, 0.0)
	if node != null:
		var dv_step := Integrator.delta_v(mass_before, mass(), isp)
		node.remaining = node.remaining.sub(dir.scaled(dv_step))
		if node.remaining.length() < NODE_COMPLETE_DV:
			node = null
			node_completed = true
			if sas_mode == SasMode.NODE:
				sas_mode = SasMode.OFF


func _refit_elements(at_time: float) -> void:
	elements = OrbitElements.from_state(r, v, body.mu, at_time)
	flight_state = FlightState.COASTING
	revision += 1


func _coast_to(t: float) -> void:
	var s := elements.state_at_time(t)
	r = s.r
	v = s.v


## Plain-Dictionary snapshot (JSON-safe: floats/strings/arrays/null only)
## for a mid-mission save. Bodies aren't included - they're on rails, so
## sim_time alone reconstructs every body's position on load.
func serialize() -> Dictionary:
	return {
		"body_name": body.name,
		"r": [r.x, r.y, r.z],
		"v": [v.x, v.y, v.z],
		"attitude": _basis_to_array(attitude),
		"prop_mass": prop_mass,
		"sas_mode": sas_mode,
		"node": node.serialize() if node != null else null,
	}


## Restores state from serialize()'s output at the given sim time. Always
## lands COASTING (elements refit fresh from r,v) with throttle zeroed -
## resuming mid-burn-substep isn't meaningful across a save boundary.
func apply_serialized(data: Dictionary, at_time: float) -> void:
	body = _find_body(data.get("body_name", body.name))
	var rv: Array = data.get("r", [r.x, r.y, r.z])
	r = DVec3.new(rv[0], rv[1], rv[2])
	var vv: Array = data.get("v", [v.x, v.y, v.z])
	v = DVec3.new(vv[0], vv[1], vv[2])
	attitude = _array_to_basis(data.get("attitude", []))
	prop_mass = data.get("prop_mass", prop_mass)
	sas_mode = data.get("sas_mode", SasMode.OFF) as SasMode
	throttle = 0.0
	last_time = at_time
	_refit_elements(at_time)

	var node_data = data.get("node")
	if node_data != null:
		node = ManeuverNode.new()
		node.t_node = node_data["t_node"]
		node.prograde = node_data["prograde"]
		node.normal = node_data["normal"]
		node.radial = node_data["radial"]
		var rem: Array = node_data["remaining"]
		node.remaining = DVec3.new(rem[0], rem[1], rem[2])
	else:
		node = null


func _find_body(body_name: String) -> BodyDef:
	if _level.body.name == body_name:
		return _level.body
	for moon in _level.moons:
		if moon.name == body_name:
			return moon
	return body  # shouldn't happen; keep current rather than crash


static func _basis_to_array(b: Basis) -> Array:
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]


static func _array_to_basis(a: Array) -> Basis:
	if a.size() < 9:
		return Basis.IDENTITY
	return Basis(
		Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))

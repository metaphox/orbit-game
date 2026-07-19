class_name ShipSim
extends RefCounted
## The ship's physical state machine: Coasting (closed-form rails via
## OrbitElements) or Burning (RK4 with mass depletion). Pure sim — no Nodes.
##
## Sim frame == Godot frame (y-up, right-handed); the orbital plane of the
## starting orbit is the horizontal xz-plane. Ship forward is local -Z.

enum FlightState { COASTING, BURNING }
enum SasMode { OFF, PROGRADE, RETROGRADE, NORMAL, ANTI_NORMAL, RADIAL_OUT, RADIAL_IN }

const BURN_SUBSTEP := 0.05
const SAS_NAMES := ["OFF", "PROGRADE", "RETROGRADE", "NORMAL", "ANTI-NORM", "RADIAL+", "RADIAL-"]

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

var _level: LevelDef


func setup(level: LevelDef) -> void:
	_level = level
	body = level.body
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
func apply_soi_transitions(t: float) -> String:
	if body.parent != null:
		if r.length() >= body.soi_radius:
			var st := Frames.to_parent_frame(StateRV.new(r, v), body.orbit, t)
			var old := body.name
			body = body.parent
			r = st.r
			v = st.v
			_refit_elements(t)
			return "LEAVING %s SOI" % old
		return ""
	for moon in _level.moons:
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


## Direction the active SAS mode wants the nose pointing (unit vector in
## the parent frame). Roll is left free — holds align forward only.
func sas_target_dir() -> DVec3:
	match sas_mode:
		SasMode.PROGRADE:
			return v.normalized()
		SasMode.RETROGRADE:
			return v.normalized().neg()
		SasMode.NORMAL:
			return r.cross(v).normalized()
		SasMode.ANTI_NORMAL:
			return r.cross(v).normalized().neg()
		SasMode.RADIAL_OUT:
			return r.normalized()
		SasMode.RADIAL_IN:
			return r.normalized().neg()
	return forward_dir()


## Angle between the nose and prograde, for the HUD.
func off_prograde_angle() -> float:
	var c := forward_dir().dot(v.normalized())
	return acos(clampf(c, -1.0, 1.0))


func _integrate_burn(duration: float, thrust: float, flow: float) -> void:
	flight_state = FlightState.BURNING
	var s := Integrator.BurnState.new(r, v, mass())
	var dir := forward_dir()
	var t_done := 0.0
	while t_done < duration - 1e-9:
		var h := minf(BURN_SUBSTEP, duration - t_done)
		s = Integrator.rk4_step(s, body.mu, dir, thrust, flow, h)
		t_done += h
	r = s.r
	v = s.v
	prop_mass = maxf(s.mass - dry_mass, 0.0)


func _refit_elements(at_time: float) -> void:
	elements = OrbitElements.from_state(r, v, body.mu, at_time)
	flight_state = FlightState.COASTING
	revision += 1


func _coast_to(t: float) -> void:
	var s := elements.state_at_time(t)
	r = s.r
	v = s.v

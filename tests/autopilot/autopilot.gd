extends RefCounted
## Analytic autopilot: flies a level to its win condition through the REAL
## ShipSim (finite burns, RK4 mass depletion, SOI handoffs) rather than
## teleporting the orbit into place. Every impulsive maneuver reduces to
## "at this point on the orbit, change velocity to v_target"; burn_to_velocity
## steers the thrust down the residual each step, so the Δv it spends (read
## back via ship.dv_used()) is the realistic cost including cosine/finite-burn
## losses - which is exactly what makes it usable as an empirical Δv-par check.
##
## Not shipped with the game (lives under tests/); preload it where needed.

const BURN_SUBSTEP := 0.05  # coarse burn step; shrinks near the target to avoid overshoot
const V_CUT := 0.01         # m/s residual at which a burn is "done"
const SOI_STEP := 5.0       # rails step while watching for an SOI crossing


## Points the ship's thrust axis (local -Z) along `dir` (parent frame).
## Rotation is currently free in this game (no RCS cost yet), so snapping the
## attitude is a fair model of an idealized-but-not-instant burn.
static func point(ship: ShipSim, dir: DVec3) -> void:
	if dir.length_squared() < 1e-18:
		return
	ship.attitude = OrbitalManeuvers.look_along(dir)


## Burns until `done_fn(ship)` is true, re-pointing the thrust along
## `dir_fn(ship)` (a direction, re-evaluated from the CURRENT state each step)
## every substep. Steering off the live state - not a fixed inertial vector -
## is what keeps a multi-second finite burn efficient: the ship swings around
## its orbit mid-burn, so a target frozen at ignition would drift off-axis and
## waste Δv chasing it. Cutting on an orbital element (apoapsis, tilt, …) is
## how a real pilot flies it. Leaves the ship COASTING.
static func burn_until(ship: ShipSim, dir_fn: Callable, done_fn: Callable, max_burn := 6000.0) -> void:
	var deadline := ship.last_time + max_burn
	while ship.prop_mass > 0.0 and ship.last_time < deadline:
		if done_fn.call(ship):
			break
		point(ship, dir_fn.call(ship))
		ship.throttle = 1.0
		ship.advance_to(ship.last_time + BURN_SUBSTEP)
	ship.throttle = 0.0
	ship._refit_elements(ship.last_time)


## Burns along `dir_fn(ship)` to drive the scalar `value_fn(ship)` (an orbital
## element - periapsis, apoapsis, …) to `target` within `tol`, sizing each step
## from the measured rate of change so it converges without overshoot even
## where the element is wildly velocity-sensitive (e.g. trimming periapsis from
## a multi-million-metre apoapsis, where a fixed step blows straight past tol).
static func burn_element(ship: ShipSim, dir_fn: Callable, value_fn: Callable,
		target: float, tol: float, max_burn := 6000.0) -> void:
	var deadline := ship.last_time + max_burn
	var prev_val: float = value_fn.call(ship)
	var prev_t := ship.last_time
	var rate := 0.0
	while ship.prop_mass > 0.0 and ship.last_time < deadline:
		var val: float = value_fn.call(ship)
		if absf(val - target) <= tol:
			break
		if ship.last_time > prev_t + 1e-9:
			rate = (val - prev_val) / (ship.last_time - prev_t)
		prev_val = val
		prev_t = ship.last_time
		point(ship, dir_fn.call(ship))
		ship.throttle = 1.0
		var dt := BURN_SUBSTEP
		if absf(rate) > 1e-9:
			dt = clampf(absf((val - target) / rate), 1e-4, BURN_SUBSTEP)
		ship.advance_to(ship.last_time + dt)
	ship.throttle = 0.0
	ship._refit_elements(ship.last_time)


## Burns to match the velocity `vt_fn(ship)` returns, re-evaluated from the
## current state each step (so a moving target - matching a station, or a
## rotated plane-change target - converges cleanly), shrinking the step near
## the end so it doesn't oscillate past the target. Stops when the residual
## either drops under V_CUT or stops improving: gravity perturbs velocity by
## far more than V_CUT per integration step, so a pure fixed-threshold cut
## would never trigger and the burn would run to fuel-out - the "no longer
## decreasing" guard is what actually ends it, at the best reachable match.
static func burn_toward_velocity(ship: ShipSim, vt_fn: Callable, max_burn := 6000.0) -> void:
	var deadline := ship.last_time + max_burn
	var prev_need := INF
	while ship.prop_mass > 0.0 and ship.last_time < deadline:
		var dv: DVec3 = vt_fn.call(ship).sub(ship.v)
		var need := dv.length()
		if need < V_CUT or need > prev_need:
			break
		prev_need = need
		point(ship, dv)
		ship.throttle = 1.0
		var accel := ship.thrust_max / ship.mass()
		var dt := minf(BURN_SUBSTEP, need / maxf(accel, 1e-6))
		ship.advance_to(ship.last_time + maxf(dt, 1e-4))
	ship.throttle = 0.0
	ship._refit_elements(ship.last_time)


## Coasts on rails to absolute time t. Steps in SOI_STEP chunks and polls for
## boundary crossings so a transfer that enters/leaves a moon's SOI mid-coast
## hands off correctly (harmless overhead for single-body levels, which just
## never trigger a transition).
static func coast_to(ship: ShipSim, t: float) -> void:
	while ship.last_time < t - 1e-6:
		ship.advance_to(minf(ship.last_time + SOI_STEP, t))
		ship.apply_soi_transitions(ship.last_time)


static func coast_to_rails(ship: ShipSim, t: float) -> void:
	if t > ship.last_time:
		ship.advance_to(t)


static func coast_to_apoapsis(ship: ShipSim) -> void:
	var t := OrbitEvents.apoapsis_time(ship.elements, ship.last_time)
	coast_to_rails(ship, t)


static func coast_to_periapsis(ship: ShipSim) -> void:
	var t := OrbitEvents.periapsis_time(ship.elements, ship.last_time)
	coast_to_rails(ship, t)


## Lambert and Rodrigues rotation live in the shared OrbitalManeuvers module
## (the live flight director uses the same maths); thin aliases keep this
## file's call sites readable.
static func lambert(r1v: DVec3, r2v: DVec3, dt: float, mu: float, prograde := true) -> Array:
	return OrbitalManeuvers.lambert(r1v, r2v, dt, mu, prograde)


static func rotate_about(v: DVec3, axis: DVec3, angle: float) -> DVec3:
	return OrbitalManeuvers.rotate_about(v, axis, angle)


static func _tilt(ship: ShipSim) -> float:
	return acos(clampf(ship.current_elements().plane_normal.y, -1.0, 1.0))


static func _phase_of(p: DVec3) -> float:
	return OrbitalManeuvers.phase_of(p)


## Coasts on rails until `pred(ship)` is true or `max_t` absolute time,
## handling SOI handoffs. Returns whether the predicate was met.
static func coast_until(ship: ShipSim, pred: Callable, max_t: float) -> bool:
	while ship.last_time < max_t:
		if pred.call(ship):
			return true
		ship.advance_to(minf(ship.last_time + SOI_STEP, max_t))
		ship.apply_soi_transitions(ship.last_time)
	return pred.call(ship)


# --- maneuvers -------------------------------------------------------------


## Circularizes/raises/lowers to `target_radius`, optionally after a pure
## plane change to `target_inc` (radians, measured like OrbitMatch._tilt: the
## orbit normal's angle off +Y). Assumes a near-circular start, which is every
## OrbitMatch level's opening state. Raise = prograde Hohmann (burn to lift
## apoapsis, coast to it, burn to lift periapsis); lower is the retrograde
## mirror. The plane change steers toward the current velocity rotated about
## the current radial to the target tilt, a pure rotation that adds no energy.
static func achieve_circular(ship: ShipSim, target_radius: float, target_inc := 0.0) -> void:
	if target_inc > 1e-4:
		var plane_target := func(s: ShipSim) -> DVec3:
			var rotated := rotate_about(s.v, s.r.normalized(), target_inc - _tilt(s))
			return rotated.normalized().scaled(s.v.length())
		burn_toward_velocity(ship, plane_target)

	var r0 := ship.r.length()
	if absf(r0 - target_radius) <= 1.0:
		return
	if target_radius > r0:
		burn_until(ship, func(s): return s.v,
			func(s): return s.current_elements().radius_apoapsis() >= target_radius)
		coast_to_apoapsis(ship)
		burn_until(ship, func(s): return s.v,
			func(s): return s.current_elements().radius_periapsis() >= target_radius)
	else:
		burn_until(ship, func(s): return s.v.neg(),
			func(s): return s.current_elements().radius_periapsis() <= target_radius)
		coast_to_periapsis(ship)
		burn_until(ship, func(s): return s.v.neg(),
			func(s): return s.current_elements().radius_apoapsis() <= target_radius)


## Rendezvous with a station on a circular coplanar orbit: a phased Hohmann to
## the station's radius (timed so the ship reaches apoapsis where the station
## will be), then a closed-loop terminal approach that closes the residual
## miss - a finite burn's multi-second duration shifts arrival by far more than
## the ~2 km win box allows, so an analytic phase alone can't land it. Each
## terminal hop aims a straight-line intercept at the station's near-future
## position, then nulls the relative velocity; repeated, it converges into the
## box. Returns when inside `max_dist`/`max_rel` or after the hop budget.
static func rendezvous(ship: ShipSim, station_orbit: OrbitElements,
		max_dist: float, max_rel: float) -> void:
	var mu := ship.body.mu
	var r_park := ship.r.length()
	var r_dest := station_orbit.semi_latus_rectum()  # circular: p == a == r
	var a := (r_park + r_dest) * 0.5
	var t_transfer := PI * sqrt(pow(a, 3.0) / mu)
	var n_ship := sqrt(mu / pow(r_park, 3.0))
	var n_st := station_orbit.mean_motion()

	# Solve for the earliest burn time whose apoapsis (half a synodic step
	# opposite the burn point) coincides with the station at arrival.
	var phi0 := atan2(-station_orbit.state_at_time(0.0).r.z, station_orbit.state_at_time(0.0).r.x)
	var theta0 := atan2(-ship.r.z, ship.r.x)
	var t_burn := INF
	for k in range(-2, 8):
		var t := (theta0 + PI + TAU * k - phi0 - n_st * t_transfer) / (n_st - n_ship)
		if t >= 0.0 and t < t_burn:
			t_burn = t
	if is_inf(t_burn):
		t_burn = 0.0
	coast_to_rails(ship, ship.last_time + t_burn)

	burn_until(ship, func(s): return s.v,
		func(s): return s.current_elements().radius_apoapsis() >= r_dest)
	coast_to_apoapsis(ship)
	burn_toward_velocity(ship, func(s): return station_orbit.state_at_time(s.last_time).v)

	# Terminal approach: drift straight in at the station's velocity plus a
	# gentle closing rate, staying under the relative-speed cap the win box
	# allows (so we spend Δv on closing, not on nulling to a dead stop we
	# don't need). The closing rate tapers with range so arrival is soft.
	for _hop in 40:
		var st := station_orbit.state_at_time(ship.last_time)
		var offset := st.r.sub(ship.r)
		var miss := offset.length()
		var rel := ship.v.sub(st.v).length()
		if miss <= max_dist * 0.8 and rel <= max_rel * 0.8:
			return
		var closing := clampf(miss * 0.08, 3.0, max_rel * 0.5)
		var v_cmd := st.v.add(offset.normalized().scaled(closing))
		burn_toward_velocity(ship, func(s): return v_cmd)
		coast_to(ship, ship.last_time + 12.0)


## Hohmann-transfers from a circular parking orbit around ship.body to `target`
## (a child of ship.body on its own rails), then captures into a bound orbit
## inside the target's SOI. Phases the departure so the ship's apoapsis and the
## target coincide at arrival, coasts through the SOI handoff, then burns
## retrograde at the lunar/planetary periapsis until the orbit is elliptic and
## fits under the SOI - exactly a TransferCapture win. Requires the ship to
## orbit the target's parent directly (Earth→Moon); an interplanetary hop that
## must first escape a departure body's own SOI (Earth→Mars) is not handled.
static func transfer_and_capture(ship: ShipSim, target: BodyDef) -> bool:
	var mu := ship.body.mu
	var r_park := ship.r.length()
	var r_dest: float = target.orbit.a
	var a := (r_park + r_dest) * 0.5
	var t_transfer := PI * sqrt(pow(a, 3.0) / mu)
	var n_ship := sqrt(mu / pow(r_park, 3.0))
	var n_dest := target.orbit.mean_motion()

	var t_now := ship.last_time
	var theta := _phase_of(ship.r)
	var phi := _phase_of(target.orbit.state_at_time(t_now).r)
	var tau := INF
	for m in range(-40, 40):
		var t := (theta + PI - phi - n_dest * t_transfer + TAU * m) / (n_dest - n_ship)
		if t >= 0.0 and t < tau:
			tau = t
	if is_inf(tau):
		return false
	coast_to_rails(ship, t_now + tau)

	burn_until(ship, func(s): return s.v,
		func(s): return s.current_elements().radius_apoapsis() >= r_dest)

	var entry := OrbitEvents.child_soi_entry_time(ship.elements, target.orbit,
		target.soi_radius, ship.last_time, ship.last_time + t_transfer * 1.5, t_transfer / 400.0)
	if is_nan(entry):
		return false
	coast_to_rails(ship, entry + 1.0)
	ship.apply_soi_transitions(ship.last_time)
	if ship.body != target:
		return false

	coast_to_periapsis(ship)
	var captured := func(s: ShipSim) -> bool:
		var el := s.current_elements()
		return el.is_elliptic() and el.radius_apoapsis() <= target.soi_radius * 0.9
	burn_until(ship, func(s): return s.v.neg(), captured)
	return true


## Hyperbolic excess speed of the ship's current orbit, or 0 if still bound.
static func _v_infinity(ship: ShipSim) -> float:
	var el := ship.current_elements()
	if el.is_elliptic():
		return 0.0
	return sqrt(maxf(-ship.body.mu / el.a, 0.0))


## Interplanetary TransferCapture (Earth→Mars): the three-patched-conic case
## transfer_and_capture can't do, where the ship must first climb out of its
## departure planet's own SOI. Phases the departure for a heliocentric Hohmann
## window, escapes the departure planet with roughly the transfer's excess
## velocity, then - crucially - LAMBERT-targets the target planet's true future
## position from the real post-escape heliocentric state (sweeping arrival
## times for the cheapest intercept), which absorbs the large, imprecise
## SOI-climb rather than trusting an impulsive phase. Then coasts to the target
## SOI and captures, exactly like transfer_and_capture's final leg.
static func interplanetary_transfer(ship: ShipSim, target: BodyDef) -> bool:
	var depart := ship.body
	var sun := depart.parent
	if sun == null:
		return false
	var mu_sun := sun.mu
	var r1: float = depart.orbit.a
	var r2: float = target.orbit.a
	var a_t := (r1 + r2) * 0.5
	var t_transfer := PI * sqrt(pow(a_t, 3.0) / mu_sun)
	var n_dep := depart.orbit.mean_motion()
	var n_tgt := target.orbit.mean_motion()

	var t0 := ship.last_time
	var theta := _phase_of(depart.orbit.state_at_time(t0).r)
	var phi := _phase_of(target.orbit.state_at_time(t0).r)
	var t_d := INF
	for k in range(-40, 40):
		var t := (theta + PI - phi - n_tgt * t_transfer + TAU * k) / (n_tgt - n_dep)
		if t >= 0.0 and t < t_d:
			t_d = t
	if is_inf(t_d):
		return false
	coast_to_rails(ship, t0 + t_d)

	# Rotate within the parking orbit to where the ship's velocity already
	# points along the departure planet's heliocentric prograde, so a plain
	# prograde escape leaves roughly along the transfer direction.
	coast_until(ship, func(s: ShipSim) -> bool:
		var e_dir := depart.orbit.state_at_time(s.last_time).v.normalized()
		return s.v.normalized().dot(e_dir) > 0.999, ship.last_time + TAU / n_dep)

	var v_inf_target := sqrt(mu_sun * (2.0 / r1 - 1.0 / a_t)) - sqrt(mu_sun / r1)
	burn_until(ship, func(s): return s.v,
		func(s): return _v_infinity(s) >= v_inf_target)
	if not coast_until(ship, func(s): return s.body == sun, ship.last_time + 3.0e5):
		return false
	if ship.body != sun:
		return false

	var t_now := ship.last_time
	var best_dv := INF
	var best_v1: DVec3 = null
	var best_arr := 0.0
	for frac in range(50, 160, 5):
		var t_arr := t_now + t_transfer * frac / 100.0
		var sol := lambert(ship.r, target.orbit.state_at_time(t_arr).r, t_arr - t_now, mu_sun, true)
		if sol.is_empty():
			continue
		var dv: float = sol[0].sub(ship.v).length()
		if dv < best_dv:
			best_dv = dv
			best_v1 = sol[0]
			best_arr = t_arr
	if best_v1 == null:
		return false
	burn_toward_velocity(ship, func(s): return best_v1)

	var entry := OrbitEvents.child_soi_entry_time(ship.elements, target.orbit,
		target.soi_radius, ship.last_time, best_arr + t_transfer * 0.3, t_transfer / 400.0)
	if is_nan(entry):
		return false
	coast_to_rails(ship, entry + 1.0)
	ship.apply_soi_transitions(ship.last_time)
	if ship.body != target:
		return false

	coast_to_periapsis(ship)
	var captured := func(s: ShipSim) -> bool:
		var el := s.current_elements()
		return el.is_elliptic() and el.radius_apoapsis() <= target.soi_radius * 0.9
	burn_until(ship, func(s): return s.v.neg(), captured)
	return true


## Return-from-a-moon: escape the moon's SOI (burn prograde until the lunar
## orbit no longer stays inside it), coast back into the parent's frame, then
## trim the parent-relative periapsis to `target_pe` at apoapsis - an
## EntryCorridor win. The trim uses burn_element because periapsis at a
## near-apoapsis lunar distance moves by thousands of metres per fixed step.
static func return_to_periapsis(ship: ShipSim, target_pe: float, tol: float) -> bool:
	var moon := ship.body
	var parent := moon.parent
	if parent == null:
		return false
	burn_until(ship, func(s): return s.v, func(s: ShipSim) -> bool:
		var el := s.current_elements()
		return not el.is_elliptic() or el.radius_apoapsis() >= moon.soi_radius)
	if not coast_until(ship, func(s): return s.body == parent, ship.last_time + 4.0e5):
		return false
	coast_to_apoapsis(ship)
	burn_element(ship, func(s): return s.v.neg(),
		func(s): return s.current_elements().radius_periapsis(), target_pe, tol * 0.5)
	return true


## Powered descent to a soft landing on an airless body (AirlessLanding win):
## a suicide burn. Deorbit so the trajectory strikes the surface, then free-fall
## - cheap, since coasting spends no propellant - staying under the speed
## profile that a full-thrust retrograde brake can still null by touchdown
## (v ≤ sqrt(2·a·h), a = usable decel after gravity). Braking retrograde nulls
## horizontal and vertical together; near the ground the profile → 0 so the
## ship arrives slow. Free-falling until late keeps gravity losses small, which
## a constant-thrust hover-descent (the naive version) blows the whole tank on.
## Returns whether the surface was reached (caller checks contact_result).
static func land(ship: ShipSim, target: BodyDef) -> bool:
	if ship.body != target:
		return false
	var radius := target.radius
	burn_until(ship, func(s): return s.v.neg(),
		func(s): return s.current_elements().radius_periapsis() <= radius * 0.9)

	var steps := 0
	while ship.r.length() > radius and ship.prop_mass > 0.0 and steps < 40000:
		steps += 1
		var r := ship.r.length()
		var alt := maxf(r - radius, 0.0)
		var speed := ship.v.length()
		var a_max := ship.thrust_max / ship.mass()
		var g := target.mu / (r * r)
		var a_decel := maxf(0.8 * a_max - g, 0.5)
		if speed > sqrt(2.0 * a_decel * alt):
			point(ship, ship.v.neg())
			ship.throttle = 1.0
		else:
			ship.throttle = 0.0  # under the brake profile: free-fall, no gravity-loss
		# finer steps near the ground so the touchdown state is precise
		ship.advance_to(ship.last_time + clampf(alt / maxf(speed, 1.0) * 0.2, 0.01, 0.2))
	ship.throttle = 0.0
	ship._refit_elements(ship.last_time)
	return ship.r.length() <= radius + 1.0

class_name FlightDirector
extends RefCounted
## The live, in-game autopilot: flies a level to its objective by setting the
## ship's throttle, attitude, and time-warp ONCE PER FRAME while the normal
## game loop advances the sim and renders - so you watch the maneuvers happen
## in the real flight view. It's the frame-driven twin of the headless
## tests/autopilot solver: same orbital maths (via OrbitalManeuvers and the
## same target/cut conditions), restructured from tight loops into a queue of
## phases the game steps through, plus warp management the headless version
## didn't need (it jumped time; here we warp toward each target without
## overshooting it).
##
## game_root owns one of these and calls update(self) each physics frame in
## place of player input while it's active.

const V_CUT := 0.05  # m/s residual at which a velocity-match is "close enough"

## For a long "wait for a transfer window" coast, high warp is capped to
## WINDOW_OBSERVE_WARP once within WINDOW_OBSERVE_LEAD (sim seconds) of the
## window, so the player watches the planets slide into alignment at a
## readable pace instead of the window snapping past at 1000x. At 25x the
## default lead plays the run-up over ~1-2 real minutes; raise the lead for a
## longer look, lower it for a quicker launch.
const WINDOW_OBSERVE_LEAD := 1800.0
const WINDOW_OBSERVE_WARP := 3  # index into WARP_STEPS -> 25x

var _queue: Array = []
var _current = null   # the active Phase, or null between phases
var _status := "STANDING BY"


## One unit of the plan. Kept functional (Callables + a mutable `state` bag)
## rather than a subclass-per-kind so plan builders can compose phases with
## closures over the level's precomputed targets.
class Phase:
	extends RefCounted
	var label := ""
	var on_enter: Callable      # func(dir, game) -> void, or invalid
	var on_update: Callable     # func(dir, game) -> void
	var is_done: Callable       # func(game) -> bool
	var state := {}

	func _init(p_label: String, upd: Callable, done: Callable, enter := Callable()) -> void:
		label = p_label
		on_update = upd
		is_done = done
		on_enter = enter


func status() -> String:
	return _status


## Build the plan for the level currently loaded in `game`. Returns false if
## the objective type has no director support (caller leaves manual control).
func setup(game) -> bool:
	_queue = _build_plan(game)
	_current = null
	_status = "AUTOPILOT ENGAGED" if not _queue.is_empty() else "NO PLAN"
	return not _queue.is_empty()


## Called each physics frame while active. Sets ship.throttle / ship.attitude /
## game.warp_index for the current phase; advances the queue as phases finish.
func update(game) -> void:
	game.ship.throttle = 0.0
	if _current == null:
		if _queue.is_empty():
			game.warp_index = 0
			_status = "AUTOPILOT COMPLETE"
			return
		_current = _queue.pop_front()
		if _current.on_enter.is_valid():
			_current.on_enter.call(self, game)
		_status = _current.label
	_current.on_update.call(self, game)
	if _current.is_done.call(game):
		_current = null
		game.ship.throttle = 0.0


## Phases a follow-up phase (or several) to run next, ahead of the rest of the
## queue - used by phases whose successors can only be computed mid-flight
## (e.g. a Lambert correction after the real escape state is known).
func insert_next(phases: Array) -> void:
	for i in range(phases.size() - 1, -1, -1):
		_queue.push_front(phases[i])


# --- phase constructors ----------------------------------------------------


## Full-thrust burn steering along dir_fn(ship) until done_fn(ship). Warp is
## forced to 1x so the RK4 burn integrates finely and stays watchable.
func _burn(label: String, dir_fn: Callable, done_fn: Callable) -> Phase:
	var upd := func(_dir, game) -> void:
		game.warp_index = 0
		var d: DVec3 = dir_fn.call(game.ship)
		if d.length_squared() > 1e-18:
			game.ship.attitude = OrbitalManeuvers.look_along(d)
		game.ship.throttle = 1.0
	return Phase.new(label, upd, func(game): return done_fn.call(game.ship))


## Throttle-tapered burn that drives value_fn(ship) to `target` within `tol`.
## Tapering throttle with the remaining error keeps the last frames from
## overshooting an element (like periapsis at a huge apoapsis) that moves a
## long way per full-thrust frame.
func _burn_to_value(label: String, dir_fn: Callable, value_fn: Callable,
		target: float, tol: float) -> Phase:
	var upd := func(_dir, game) -> void:
		game.warp_index = 0
		var d: DVec3 = dir_fn.call(game.ship)
		if d.length_squared() > 1e-18:
			game.ship.attitude = OrbitalManeuvers.look_along(d)
		var err: float = absf(value_fn.call(game.ship) - target)
		game.ship.throttle = clampf(err / (tol * 20.0), 0.04, 1.0)
	var done := func(game): return absf(value_fn.call(game.ship) - target) <= tol
	return Phase.new(label, upd, done)


## Burn to match the velocity vt_fn(ship) returns, stopping when the residual
## stops shrinking (gravity perturbs v more per frame than any fine threshold).
func _burn_toward(label: String, vt_fn: Callable) -> Phase:
	var upd := func(dir, game) -> void:
		game.warp_index = 0
		var residual: DVec3 = vt_fn.call(game.ship).sub(game.ship.v)
		var need := residual.length()
		if need < V_CUT or need > dir._current.state.get("prev", INF):
			dir._current.state["settled"] = true
			return
		dir._current.state["prev"] = need
		game.ship.attitude = OrbitalManeuvers.look_along(residual)
		game.ship.throttle = 1.0
	var done := func(_game): return _current != null and _current.state.get("settled", false)
	var enter := func(_dir, _game) -> void:
		_current.state["prev"] = INF
		_current.state["settled"] = false
	return Phase.new(label, upd, done, enter)


## Coast (no thrust) to an absolute sim time computed on entry by time_fn,
## warping toward it but easing down so a frame can't overshoot the target.
## When `observe` is set, warp is also capped to WINDOW_OBSERVE_WARP within
## WINDOW_OBSERVE_LEAD of the target, giving a watchable run-up to a transfer
## window rather than a 1000x blur straight into launch.
func _coast_to_time(label: String, time_fn: Callable, observe := false) -> Phase:
	var enter := func(_dir, game) -> void:
		_current.state["t"] = time_fn.call(game)
	var upd := func(dir, game) -> void:
		var remaining: float = dir._current.state["t"] - game.sim_time
		var wi := _warp_for_remaining(game, remaining)
		if observe and remaining < WINDOW_OBSERVE_LEAD:
			wi = mini(wi, WINDOW_OBSERVE_WARP)
		game.warp_index = wi
	var done := func(game): return game.sim_time >= _current.state["t"] - 1e-6
	return Phase.new(label, upd, done, enter)


## Coast at high warp until pred(ship). SOI/impact handoffs are handled by
## game_root's own warp clamp, which drops out of warp at each boundary.
func _coast_until(label: String, pred: Callable, warp_idx := -1) -> Phase:
	var upd := func(_dir, game) -> void:
		game.warp_index = (game.WARP_STEPS.size() - 1) if warp_idx < 0 else warp_idx
	return Phase.new(label, upd, func(game): return pred.call(game.ship))


## Largest warp step whose single frame stays inside `remaining` seconds
## (with margin), so time-warp eases to 1x right as the target arrives.
func _warp_for_remaining(game, remaining: float) -> int:
	if remaining <= 0.0:
		return 0
	var max_step := remaining / (2.0 * (1.0 / 60.0))
	var wi := 0
	for i in game.WARP_STEPS.size():
		if float(game.WARP_STEPS[i]) <= max_step:
			wi = i
	return wi


# --- plan builders ---------------------------------------------------------


func _build_plan(game) -> Array:
	var obj = game.level.objective
	if obj is OrbitMatchObjective:
		return _plan_orbit_match(game, obj)
	if obj is RendezvousObjective:
		return _plan_rendezvous(game, obj)
	if obj is TransferCaptureObjective:
		if game.ship.body.parent == null:
			return _plan_transfer_capture(game, obj)
		return _plan_interplanetary(game, obj)
	if obj is EntryCorridorObjective:
		return _plan_return(game, obj)
	if obj is AirlessLandingObjective:
		return _plan_landing(game, obj)
	return []


func _plan_orbit_match(game, obj) -> Array:
	var target_r: float = obj.target_radius
	var target_inc: float = obj.target_inclination
	var r0: float = game.ship.r.length()
	var phases: Array = []
	if target_inc > 1e-4:
		var plane_target := func(s: ShipSim) -> DVec3:
			var tilt := acos(clampf(s.current_elements().plane_normal.y, -1.0, 1.0))
			var rotated := OrbitalManeuvers.rotate_about(s.v, s.r.normalized(), target_inc - tilt)
			return rotated.normalized().scaled(s.v.length())
		phases.append(_burn_toward("PLANE CHANGE", plane_target))
		# A finite plane-change burn leaves a little eccentricity; clean it back
		# to circular at apoapsis so the OrbitMatch tolerances are met.
		phases.append(_coast_to_time("COAST TO APOAPSIS",
			func(g): return OrbitEvents.apoapsis_time(g.ship.current_elements(), g.sim_time)))
		phases.append(_burn("RECIRCULARIZE", func(s): return s.v,
			func(s): return s.v.length() >= sqrt(s.body.mu / s.r.length())))
	if target_r > r0 + 1.0:
		phases.append(_burn("RAISE APOAPSIS", func(s): return s.v,
			func(s): return s.current_elements().radius_apoapsis() >= target_r))
		phases.append(_coast_to_time("COAST TO APOAPSIS",
			func(g): return OrbitEvents.apoapsis_time(g.ship.current_elements(), g.sim_time)))
		# Cut when local speed reaches local circular speed: raising periapsis
		# "until it reaches target" is asymptotically marginal - past circular,
		# the burn point becomes periapsis and Pe caps just under target while
		# apoapsis runs away. Speed vs circular speed crosses cleanly instead.
		phases.append(_burn("CIRCULARIZE", func(s): return s.v,
			func(s): return s.v.length() >= sqrt(s.body.mu / s.r.length())))
	elif target_r < r0 - 1.0:
		phases.append(_burn("LOWER PERIAPSIS", func(s): return s.v.neg(),
			func(s): return s.current_elements().radius_periapsis() <= target_r))
		phases.append(_coast_to_time("COAST TO PERIAPSIS",
			func(g): return OrbitEvents.periapsis_time(g.ship.current_elements(), g.sim_time)))
		phases.append(_burn("CIRCULARIZE", func(s): return s.v.neg(),
			func(s): return s.v.length() <= sqrt(s.body.mu / s.r.length())))
	return phases


func _plan_rendezvous(game, obj) -> Array:
	var so: OrbitElements = obj.station_orbit
	var mu: float = game.ship.body.mu
	var r_park: float = game.ship.r.length()
	var r_dest: float = so.semi_latus_rectum()
	var a := (r_park + r_dest) * 0.5
	var t_transfer := PI * sqrt(pow(a, 3.0) / mu)
	var n_ship := sqrt(mu / pow(r_park, 3.0))
	var n_st := so.mean_motion()
	var t0: float = game.sim_time
	var theta := OrbitalManeuvers.phase_of(game.ship.r)
	var phi := OrbitalManeuvers.phase_of(so.state_at_time(t0).r)
	var t_burn := INF
	for k in range(-2, 8):
		var t := (theta + PI + TAU * k - phi - n_st * t_transfer) / (n_st - n_ship)
		if t >= 0.0 and t < t_burn:
			t_burn = t
	if is_inf(t_burn):
		t_burn = 0.0
	var fire_at := t0 + t_burn
	return [
		_coast_to_time("PHASING", func(_g): return fire_at),
		_burn("HOHMANN BURN", func(s): return s.v,
			func(s): return s.current_elements().radius_apoapsis() >= r_dest),
		_coast_to_time("COAST TO APOAPSIS",
			func(g): return OrbitEvents.apoapsis_time(g.ship.current_elements(), g.sim_time)),
		_burn_toward("MATCH STATION", func(s): return so.state_at_time(s.last_time).v),
		_terminal_rendezvous("FINAL APPROACH", so, obj.max_distance, obj.max_rel_speed),
	]


## Gentle station-relative closing: drift in at the station's velocity plus a
## range-tapered closing rate, staying under the rel-speed cap (spend Δv on
## closing, not on a dead stop the win box doesn't require).
func _terminal_rendezvous(label: String, so: OrbitElements, max_dist: float, max_rel: float) -> Phase:
	var upd := func(_dir, game) -> void:
		game.warp_index = 0
		var s: ShipSim = game.ship
		var st := so.state_at_time(s.last_time)
		var offset := st.r.sub(s.r)
		var closing := clampf(offset.length() * 0.08, 3.0, max_rel * 0.5)
		var v_cmd := st.v.add(offset.normalized().scaled(closing))
		var residual := v_cmd.sub(s.v)
		if residual.length() > V_CUT:
			s.attitude = OrbitalManeuvers.look_along(residual)
			s.throttle = 1.0
	var done := func(game) -> bool:
		var s: ShipSim = game.ship
		var st := so.state_at_time(s.last_time)
		return st.r.sub(s.r).length() <= max_dist * 0.8 and s.v.sub(st.v).length() <= max_rel * 0.8
	return Phase.new(label, upd, done)


func _plan_transfer_capture(game, obj) -> Array:
	var target: BodyDef = obj.target
	var mu: float = game.ship.body.mu
	var r_park: float = game.ship.r.length()
	var r_dest: float = target.orbit.a
	var a := (r_park + r_dest) * 0.5
	var t_transfer := PI * sqrt(pow(a, 3.0) / mu)
	var n_ship := sqrt(mu / pow(r_park, 3.0))
	var n_dest := target.orbit.mean_motion()
	var t0: float = game.sim_time
	var theta := OrbitalManeuvers.phase_of(game.ship.r)
	var phi := OrbitalManeuvers.phase_of(target.orbit.state_at_time(t0).r)
	var tau := INF
	for m in range(-40, 40):
		var t := (theta + PI - phi - n_dest * t_transfer + TAU * m) / (n_dest - n_ship)
		if t >= 0.0 and t < tau:
			tau = t
	if is_inf(tau):
		tau = 0.0
	var fire_at := t0 + tau
	return [
		_coast_to_time("TLI PHASING", func(_g): return fire_at, true),
		_burn("TRANS-LUNAR INJECTION", func(s): return s.v,
			func(s): return s.current_elements().radius_apoapsis() >= r_dest),
		_coast_until("COAST TO " + target.name + " SOI", func(s): return s.body == target),
		_coast_to_time("COAST TO PERIAPSIS",
			func(g): return OrbitEvents.periapsis_time(g.ship.current_elements(), g.sim_time)),
		_burn("CAPTURE BURN", func(s): return s.v.neg(), func(s: ShipSim) -> bool:
			var el := s.current_elements()
			return el.is_elliptic() and el.radius_apoapsis() <= target.soi_radius * 0.9),
	]


func _plan_interplanetary(game, obj) -> Array:
	var target: BodyDef = obj.target
	var depart: BodyDef = game.ship.body
	var sun: BodyDef = depart.parent
	var mu_sun: float = sun.mu
	var r1: float = depart.orbit.a
	var r2: float = target.orbit.a
	var a_t := (r1 + r2) * 0.5
	var t_transfer := PI * sqrt(pow(a_t, 3.0) / mu_sun)
	var n_dep := depart.orbit.mean_motion()
	var n_tgt := target.orbit.mean_motion()
	var t0: float = game.sim_time
	var theta := OrbitalManeuvers.phase_of(depart.orbit.state_at_time(t0).r)
	var phi := OrbitalManeuvers.phase_of(target.orbit.state_at_time(t0).r)
	var t_d := INF
	for k in range(-40, 40):
		var t := (theta + PI - phi - n_tgt * t_transfer + TAU * k) / (n_tgt - n_dep)
		if t >= 0.0 and t < t_d:
			t_d = t
	if is_inf(t_d):
		t_d = 0.0
	var fire_at := t0 + t_d
	var v_inf_target := sqrt(mu_sun * (2.0 / r1 - 1.0 / a_t)) - sqrt(mu_sun / r1)

	# The heliocentric correction can only be computed once we're actually in
	# the sun's frame, so this phase's on_enter runs the Lambert sweep then and
	# queues the correction burn + coast-to-capture ahead of the rest.
	var lambert_leg := Phase.new("MARS INTERCEPT (LAMBERT)",
		func(_d, _g): pass, func(_g): return true)
	lambert_leg.on_enter = func(dir, game) -> void:
		var s: ShipSim = game.ship
		var t_now: float = s.last_time
		var best_v1 = null
		var best_dv := INF
		var best_arr := 0.0
		for frac in range(50, 160, 5):
			var t_arr := t_now + t_transfer * frac / 100.0
			var sol := OrbitalManeuvers.lambert(s.r, target.orbit.state_at_time(t_arr).r,
				t_arr - t_now, mu_sun, true)
			if sol.is_empty():
				continue
			var dv: float = sol[0].sub(s.v).length()
			if dv < best_dv:
				best_dv = dv
				best_v1 = sol[0]
				best_arr = t_arr
		if best_v1 == null:
			return
		dir.insert_next([
			dir._burn_toward("MID-COURSE CORRECTION", func(_s): return best_v1),
			dir._coast_until("COAST TO " + target.name + " SOI", func(sh): return sh.body == target),
			dir._coast_to_time("COAST TO PERIAPSIS",
				func(g): return OrbitEvents.periapsis_time(g.ship.current_elements(), g.sim_time)),
			dir._burn("CAPTURE BURN", func(sh): return sh.v.neg(), func(sh: ShipSim) -> bool:
				var el := sh.current_elements()
				return el.is_elliptic() and el.radius_apoapsis() <= target.soi_radius * 0.9),
		])

	return [
		_coast_to_time("DEPARTURE PHASING", func(_g): return fire_at, true),
		_coast_until("ALIGN TO PROGRADE", func(s: ShipSim) -> bool:
			var e_dir := depart.orbit.state_at_time(s.last_time).v.normalized()
			return s.v.normalized().dot(e_dir) > 0.999, 3),
		_burn("EARTH DEPARTURE", func(s): return s.v, func(s: ShipSim) -> bool:
			var el := s.current_elements()
			var vinf := 0.0 if el.is_elliptic() else sqrt(maxf(-s.body.mu / el.a, 0.0))
			return vinf >= v_inf_target),
		_coast_until("ESCAPE EARTH SOI", func(s): return s.body == sun),
		lambert_leg,
	]


func _plan_return(game, obj) -> Array:
	var moon: BodyDef = game.ship.body
	var parent: BodyDef = moon.parent
	var target_pe: float = obj.target_periapsis
	var tol: float = obj.tolerance
	var phases: Array = [
		_burn("TRANS-EARTH INJECTION", func(s): return s.v, func(s: ShipSim) -> bool:
			var el := s.current_elements()
			return not el.is_elliptic() or el.radius_apoapsis() >= moon.soi_radius),
		_coast_until("ESCAPE " + moon.name + " SOI", func(s): return s.body == parent),
	]
	# The escape leaves a high-energy Earth orbit whose apoapsis can breach the
	# mission's fail_radius; pull it in first so coasting to apoapsis stays
	# inside the envelope. (The headless solver skips this - it never sees the
	# fail_radius the live game enforces.)
	if game.level.fail_radius > 0.0:
		var cap: float = game.level.fail_radius * 0.85
		phases.append(_burn("LOWER RETURN APOAPSIS", func(s): return s.v.neg(),
			func(s): return s.current_elements().radius_apoapsis() <= cap))
	phases.append_array([
		_coast_to_time("COAST TO APOAPSIS",
			func(g): return OrbitEvents.apoapsis_time(g.ship.current_elements(), g.sim_time)),
		_burn_to_value("TRIM PERIAPSIS", func(s): return s.v.neg(),
			func(s): return s.current_elements().radius_periapsis(), target_pe, tol * 0.5),
	])
	return phases


func _plan_landing(game, obj) -> Array:
	var target: BodyDef = obj.target
	var radius: float = target.radius
	return [
		_burn("DEORBIT", func(s): return s.v.neg(),
			func(s): return s.current_elements().radius_periapsis() <= radius * 0.9),
		_descent("POWERED DESCENT", target),
	]


## Suicide-burn descent: free-fall (low warp) under the stop-at-surface speed
## profile, full-thrust retrograde above it. game_root's own contact check ends
## the mission at touchdown, so this just flies the profile until then.
func _descent(label: String, target: BodyDef) -> Phase:
	var radius: float = target.radius
	var upd := func(_dir, game) -> void:
		var s: ShipSim = game.ship
		var r := s.r.length()
		var alt := maxf(r - radius, 0.0)
		var speed := s.v.length()
		var a_max := s.thrust_max / s.mass()
		var g := target.mu / (r * r)
		var a_decel := maxf(0.8 * a_max - g, 0.5)
		if speed > sqrt(2.0 * a_decel * alt):
			s.attitude = OrbitalManeuvers.look_along(s.v.neg())
			s.throttle = 1.0
			game.warp_index = 0
		else:
			s.throttle = 0.0  # free-fall; keep warp low so we don't skip the surface
			game.warp_index = 1 if alt > 1500.0 else 0
	# The game flips to WON/FAILED at contact and stops calling us; a huge step
	# cap guards against a plan that never reaches the ground.
	var done := func(game): return game.ship.r.length() <= radius
	return Phase.new(label, upd, done)

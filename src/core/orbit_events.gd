class_name OrbitEvents
extends RefCounted
## Event times on a coasting trajectory. Rails time-warp jumps to
## min(next_event, target_time), so these must be exact (analytic where the
## geometry allows) rather than discovered by stepping the simulation.
##
## All functions return NAN when the event never occurs.


## Next time >= after_t when the orbit radius crosses target_radius.
## outbound = true for the ascending crossing (radial velocity > 0).
## Analytic: the crossing true anomaly comes from the conic equation, the
## time from Kepler's equation.
static func radius_crossing_time(
		el: OrbitElements, target_radius: float, after_t: float,
		outbound: bool) -> float:
	var nu := el.true_anomaly_at_radius(target_radius)
	if is_nan(nu):
		return NAN
	if not outbound:
		nu = -nu
	var t := el.time_at_true_anomaly(nu, after_t)
	if t < after_t:  # hyperbolic single pass already behind the ship
		return NAN
	return t


static func soi_exit_time(el: OrbitElements, soi_radius: float, after_t: float) -> float:
	return radius_crossing_time(el, soi_radius, after_t, true)


static func impact_time(el: OrbitElements, body_radius: float, after_t: float) -> float:
	return radius_crossing_time(el, body_radius, after_t, false)


static func periapsis_time(el: OrbitElements, after_t: float) -> float:
	var t := el.time_at_true_anomaly(0.0, after_t)
	return NAN if t < after_t else t


static func apoapsis_time(el: OrbitElements, after_t: float) -> float:
	if not el.is_elliptic():
		return NAN
	return el.time_at_true_anomaly(PI, after_t)


## First time in [t_start, t_end] when the ship enters a child body's SOI.
## No closed form exists (two independent conics), so: coarse scan for a
## sign change of distance - soi, then bisection. coarse_dt must be small
## enough not to step over a whole encounter; a fraction of the child's
## period is a safe choice.
static func child_soi_entry_time(
		ship_el: OrbitElements, child_el: OrbitElements, soi_radius: float,
		t_start: float, t_end: float, coarse_dt: float) -> float:
	var prev_t := t_start
	var prev_outside := _distance(ship_el, child_el, t_start) > soi_radius
	if not prev_outside:
		return t_start
	var t := t_start + coarse_dt
	while t < t_end + coarse_dt:
		var t_clamped := minf(t, t_end)
		if _distance(ship_el, child_el, t_clamped) <= soi_radius:
			return _bisect_entry(ship_el, child_el, soi_radius, prev_t, t_clamped)
		prev_t = t_clamped
		t += coarse_dt
	return NAN


static func _bisect_entry(
		ship_el: OrbitElements, child_el: OrbitElements, soi_radius: float,
		t_out: float, t_in: float) -> float:
	for _i in 80:
		var mid := 0.5 * (t_out + t_in)
		if _distance(ship_el, child_el, mid) > soi_radius:
			t_out = mid
		else:
			t_in = mid
	return t_in


static func _distance(ship_el: OrbitElements, child_el: OrbitElements, t: float) -> float:
	return ship_el.state_at_time(t).r.distance_to(child_el.state_at_time(t).r)

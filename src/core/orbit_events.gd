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
## No closed form exists (two independent conics), so: coarse scan, but
## checking each interval's actual minimum distance (not just its
## endpoints) so an encounter fully contained between two samples - a fast
## or grazing flyby - still shows up. coarse_dt is only a suggested step;
## it's tightened internally to a bound derived from relative speed and the
## SOI radius, so no caller-supplied step can hide an encounter.
static func child_soi_entry_time(
		ship_el: OrbitElements, child_el: OrbitElements, soi_radius: float,
		t_start: float, t_end: float, coarse_dt: float) -> float:
	if t_end <= t_start:
		return NAN
	if _distance(ship_el, child_el, t_start) <= soi_radius:
		return t_start
	var dt := _bounded_step(ship_el, child_el, t_start, t_end, soi_radius, coarse_dt)
	var prev_t := t_start
	while prev_t < t_end:
		var t_clamped := minf(prev_t + dt, t_end)
		var m := _interval_min(ship_el, child_el, prev_t, t_clamped)
		if m.distance <= soi_radius:
			return _bisect_entry(ship_el, child_el, soi_radius, prev_t, m.time)
		prev_t = t_clamped
	return NAN


## Suggested_dt tightened to a bound derived from the fastest relative speed
## sampled across [t_start, t_end] and the SOI radius, so a step can never
## span more than roughly one SOI crossing. Floored at suggested_dt / 64 so
## a near-zero relative speed (co-orbital case) can't blow up the iteration
## count; suggested_dt is never exceeded either way.
static func _bounded_step(
		ship_el: OrbitElements, child_el: OrbitElements, t_start: float, t_end: float,
		soi_radius: float, suggested_dt: float) -> float:
	const SAMPLES := 16
	var max_rel_speed := 0.0
	for i in SAMPLES + 1:
		var t := t_start + (t_end - t_start) * float(i) / float(SAMPLES)
		var rel_speed := ship_el.state_at_time(t).v.sub(child_el.state_at_time(t).v).length()
		max_rel_speed = maxf(max_rel_speed, rel_speed)
	var dt_speed := soi_radius / maxf(max_rel_speed * 1.2, 1e-9)
	return clampf(dt_speed, suggested_dt / 64.0, suggested_dt)


## Minimum relative distance in [t0, t1]: an 8-point sub-scan to locate the
## neighborhood of the minimum, then ternary refinement around it. Mirrors
## closest_approach()'s coarse-scan-then-ternary shape, scoped to one
## interval instead of the whole window.
static func _interval_min(
		ship_el: OrbitElements, child_el: OrbitElements, t0: float, t1: float) -> Dictionary:
	const SUB := 8
	var best_t := t0
	var best_d := _distance(ship_el, child_el, t0)
	for i in range(1, SUB + 1):
		var t := t0 + (t1 - t0) * float(i) / float(SUB)
		var d := _distance(ship_el, child_el, t)
		if d < best_d:
			best_d = d
			best_t = t
	var half_width := (t1 - t0) / float(SUB)
	var lo := maxf(best_t - half_width, t0)
	var hi := minf(best_t + half_width, t1)
	for _i in 40:
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
		if _distance(ship_el, child_el, m1) < _distance(ship_el, child_el, m2):
			hi = m2
		else:
			lo = m1
	var t_final := 0.5 * (lo + hi)
	var d_final := _distance(ship_el, child_el, t_final)
	if d_final < best_d:
		return {"time": t_final, "distance": d_final}
	return {"time": best_t, "distance": best_d}


## Time and distance of closest approach between two conics in [t0, t1].
## Coarse scan for the minimum, then ternary refinement around it.
static func closest_approach(
		el_a: OrbitElements, el_b: OrbitElements, t0: float, t1: float,
		coarse_dt: float) -> Dictionary:
	var best_t := t0
	var best_d := _distance(el_a, el_b, t0)
	var t := t0 + coarse_dt
	while t <= t1:
		var d := _distance(el_a, el_b, t)
		if d < best_d:
			best_d = d
			best_t = t
		t += coarse_dt
	var lo := maxf(best_t - coarse_dt, t0)
	var hi := minf(best_t + coarse_dt, t1)
	for _i in 60:
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
		if _distance(el_a, el_b, m1) < _distance(el_a, el_b, m2):
			hi = m2
		else:
			lo = m1
	best_t = 0.5 * (lo + hi)
	return {"time": best_t, "distance": _distance(el_a, el_b, best_t)}


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

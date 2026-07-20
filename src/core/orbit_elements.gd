class_name OrbitElements
extends RefCounted
## Classical Keplerian elements around a single gravitating body, plus
## conversions to and from Cartesian state vectors.
##
## Conventions:
## - a < 0 and e > 1 for hyperbolic trajectories.
## - Near-parabolic eccentricities are nudged off 1 (this is a game, not an
##   ephemeris service).
## - Degenerate angles are pinned so elements always round-trip: raan := 0
##   for near-equatorial orbits, argp := 0 for near-circular orbits.
## - m0 is the mean anomaly at [member epoch] (hyperbolic mean anomaly when
##   e > 1).

const ECC_PARABOLIC_GUARD := 1e-9
const ECC_CIRCULAR := 1e-10
const INC_EQUATORIAL := 1e-10

## Below these, from_state() treats the input as degenerate: r or v too
## small to mean anything, a non-physical mu, or r nearly parallel to v
## (near-zero angular momentum - a purely radial trajectory, reachable in
## play by killing tangential velocity). MIN_H_RATIO is h_len / (r_len *
## v_len), the sine of the angle between r and v, so it stays meaningful
## at both LEO and interplanetary scale rather than needing a fixed
## absolute h_len epsilon.
const MIN_RADIUS := 1.0
const MIN_SPEED := 1.0e-6
const MIN_H_RATIO := 1.0e-9

var mu := 0.0
var a := 0.0
var e := 0.0
var inc := 0.0
var raan := 0.0
var argp := 0.0
var m0 := 0.0
var epoch := 0.0

## False when from_state() was given a degenerate input. Elements are still
## finite and usable (nudged away from the singularity, the same technique
## the eccentricity guard below already uses) rather than NaN, so
## rendering/save code never sees NaN - but callers that can, like
## ShipSim._refit_elements, should treat this as a mission-ending fault
## rather than silently continuing on a physically-meaningless orbit.
var is_valid := true

## Orbit normal (r x v, normalized) in world/render coordinates. `inc` is
## measured against the classical +Z pole for the internal element math
## (see _perifocal_basis); this game's orbital plane is XZ with +Y "up",
## so gameplay code that wants tilt-from-the-game's-reference-plane
## (e.g. a plane-change objective) should use plane_normal.y, not inc.
var plane_normal := DVec3.new()


## A circular orbit at the given radius, starting phase_deg around from +X
## (in the XZ plane, matching the level-data convention used throughout
## src/levels and src/objectives) at the given epoch.
static func circular(mu_p: float, radius: float, phase_deg: float, t: float) -> OrbitElements:
	var v := sqrt(mu_p / radius)
	var theta := deg_to_rad(phase_deg)
	return from_state(
		DVec3.new(radius * cos(theta), 0.0, -radius * sin(theta)),
		DVec3.new(-v * sin(theta), 0.0, -v * cos(theta)), mu_p, t)


## Degenerate input (non-physical mu, r/v too small to mean anything, or r
## nearly parallel to v - near-zero angular momentum) does NOT get nudged
## through the normal math with floored inputs: even a floored angular
## momentum can combine with the input's actual energy to produce a
## vanishingly small semi-major axis, which blows up mean_motion() and
## overflows the Kepler solver several steps downstream - a floor prevents
## the immediate division by zero but not that. Instead, degenerate input
## is replaced outright with a synthesized, numerically tame circular
## orbit (same technique as circular() above) at a safe radius, flagged
## is_valid = false so callers know the shape is a placeholder, not a fit
## to the actual input.
static func from_state(r: DVec3, v: DVec3, mu_p: float, t: float) -> OrbitElements:
	var r_len := r.length()
	var v_len := v.length()
	var h_len := r.cross(v).length()
	var degenerate := (mu_p <= 0.0 or r_len < MIN_RADIUS or v_len < MIN_SPEED
		or h_len < MIN_H_RATIO * r_len * v_len)
	if not degenerate:
		return _from_state_unchecked(r, v, mu_p, t)

	var safe_mu := mu_p if mu_p > 0.0 else 1.0
	var safe_r := maxf(r_len, MIN_RADIUS)
	var el := _from_state_unchecked(
		DVec3.new(safe_r, 0.0, 0.0), DVec3.new(0.0, sqrt(safe_mu / safe_r), 0.0), safe_mu, t)
	el.is_valid = false
	return el


static func _from_state_unchecked(r: DVec3, v: DVec3, mu_p: float, t: float) -> OrbitElements:
	var el := OrbitElements.new()
	el.mu = mu_p
	el.epoch = t

	var h_vec := r.cross(v)
	var h_len := h_vec.length()
	var p := h_len * h_len / mu_p
	el.plane_normal = h_vec.scaled(1.0 / h_len)

	var e_vec := v.cross(h_vec).scaled(1.0 / mu_p).sub(r.normalized())
	var ecc := e_vec.length()
	if absf(ecc - 1.0) < ECC_PARABOLIC_GUARD:
		var energy := v.length_squared() * 0.5 - mu_p / r.length()
		ecc = 1.0 - ECC_PARABOLIC_GUARD if energy < 0.0 else 1.0 + ECC_PARABOLIC_GUARD
	el.e = ecc
	el.a = p / (1.0 - ecc * ecc)

	el.inc = acos(clampf(h_vec.z / h_len, -1.0, 1.0))
	var equatorial := el.inc < INC_EQUATORIAL or el.inc > PI - INC_EQUATORIAL
	var circular := ecc < ECC_CIRCULAR

	var node := DVec3.new(-h_vec.y, h_vec.x, 0.0)
	if equatorial:
		node = DVec3.new(1.0, 0.0, 0.0)
		el.raan = 0.0
	else:
		el.raan = atan2(node.y, node.x)
	node = node.normalized()

	var peri := node if circular else e_vec.normalized()
	el.argp = 0.0 if circular else _signed_angle(node, peri, h_vec)

	var nu := _signed_angle(peri, r.normalized(), h_vec)
	el.m0 = el.mean_from_true(nu)
	return el


func state_at_time(t: float) -> StateRV:
	return state_at_true_anomaly(true_anomaly_at_time(t))


func state_at_true_anomaly(nu: float) -> StateRV:
	var p := semi_latus_rectum()
	var r_len := p / (1.0 + e * cos(nu))
	var basis := _perifocal_basis()
	var p_hat: DVec3 = basis[0]
	var q_hat: DVec3 = basis[1]
	var cn := cos(nu)
	var sn := sin(nu)
	var r := p_hat.scaled(r_len * cn).add(q_hat.scaled(r_len * sn))
	var v_factor := sqrt(mu / p)
	var v := p_hat.scaled(-v_factor * sn).add(q_hat.scaled(v_factor * (e + cn)))
	return StateRV.new(r, v)


func true_anomaly_at_time(t: float) -> float:
	var m := mean_anomaly_at_time(t)
	if is_elliptic():
		return Kepler.true_from_eccentric(Kepler.solve_elliptic(m, e), e)
	return Kepler.true_from_hyperbolic(Kepler.solve_hyperbolic(m, e), e)


## First time >= after_t at which the orbit passes true anomaly nu.
## Hyperbolic passes are single-shot: the returned time may be < after_t,
## meaning the anomaly is already behind the ship.
func time_at_true_anomaly(nu: float, after_t: float) -> float:
	var n := mean_motion()
	var t := epoch + (mean_from_true(nu) - m0) / n
	if not is_elliptic():
		return t
	var per := TAU / n
	return t + ceilf((after_t - t) / per) * per


func mean_anomaly_at_time(t: float) -> float:
	return m0 + mean_motion() * (t - epoch)


func mean_from_true(nu: float) -> float:
	if is_elliptic():
		return Kepler.mean_from_eccentric(Kepler.eccentric_from_true(nu, e), e)
	return Kepler.mean_from_hyperbolic(Kepler.hyperbolic_from_true(nu, e), e)


func radius_at_true_anomaly(nu: float) -> float:
	return semi_latus_rectum() / (1.0 + e * cos(nu))


## Outbound-branch true anomaly (>= 0) where the radius equals r_len,
## or NAN if the orbit never reaches that radius. Inbound crossing is at
## the negated value.
func true_anomaly_at_radius(r_len: float) -> float:
	var c := (semi_latus_rectum() / r_len - 1.0) / e
	if absf(c) > 1.0:
		return NAN
	return acos(c)


## True anomalies [ascending, descending] where the orbit crosses the
## world XZ-plane (Y=0) — i.e. the ascending/descending nodes against this
## game's reference plane, not against plane_normal itself (which just
## records this orbit's own tilt). Empty if the orbit doesn't leave the
## plane at all (equatorial: plane_normal.y ~ ±1). Reachability on a
## hyperbolic arc isn't checked here — callers should confirm via
## radius_at_true_anomaly / the true-anomaly bound before using a result.
func xz_plane_crossings() -> Array[float]:
	if absf(plane_normal.y) > 1.0 - INC_EQUATORIAL:
		return []
	var basis := _perifocal_basis()
	var p_hat: DVec3 = basis[0]
	var q_hat: DVec3 = basis[1]
	var nu1 := atan2(-p_hat.y, q_hat.y)
	var nu2 := wrapf(nu1 + PI, -PI, PI)
	var dy_dnu_at_nu1 := -p_hat.y * sin(nu1) + q_hat.y * cos(nu1)
	if dy_dnu_at_nu1 > 0.0:
		return [nu1, nu2]
	return [nu2, nu1]


func is_elliptic() -> bool:
	return e < 1.0


func mean_motion() -> float:
	return sqrt(mu / absf(a * a * a))


func period() -> float:
	return TAU / mean_motion() if is_elliptic() else INF


func semi_latus_rectum() -> float:
	return a * (1.0 - e * e)


func radius_periapsis() -> float:
	return a * (1.0 - e)


func radius_apoapsis() -> float:
	return a * (1.0 + e) if is_elliptic() else INF


func specific_energy() -> float:
	return -mu / (2.0 * a)


## Positions along the orbit for drawing. Elliptic orbits that stay under
## r_max produce a closed loop; otherwise the arc is clipped at r_max
## (or just inside the asymptotes for unbounded hyperbolas).
func sample_positions(count: int, r_max := INF) -> Array[DVec3]:
	var pts: Array[DVec3] = []
	if is_elliptic() and radius_apoapsis() <= r_max:
		for i in count:
			pts.append(state_at_true_anomaly(TAU * i / count).r)
		return pts
	var nu_limit: float
	if r_max == INF:
		nu_limit = acos(-1.0 / e) - 1e-3
	else:
		nu_limit = true_anomaly_at_radius(r_max)
	for i in count:
		var nu := lerpf(-nu_limit, nu_limit, float(i) / float(count - 1))
		pts.append(state_at_true_anomaly(nu).r)
	return pts


## Unit vectors toward periapsis (P) and 90 degrees ahead in-plane (Q).
func _perifocal_basis() -> Array[DVec3]:
	var cr := cos(raan)
	var sr := sin(raan)
	var ci := cos(inc)
	var si := sin(inc)
	var cw := cos(argp)
	var sw := sin(argp)
	var p_hat := DVec3.new(
		cr * cw - sr * sw * ci,
		sr * cw + cr * sw * ci,
		sw * si)
	var q_hat := DVec3.new(
		-cr * sw - sr * cw * ci,
		-sr * sw + cr * cw * ci,
		cw * si)
	return [p_hat, q_hat]


## Angle from unit vector `from` to unit vector `to`, signed positive
## around `axis`, in (-PI, PI].
static func _signed_angle(from: DVec3, to: DVec3, axis: DVec3) -> float:
	var cross := from.cross(to)
	var s := cross.length()
	if cross.dot(axis) < 0.0:
		s = -s
	return atan2(s, clampf(from.dot(to), -1.0, 1.0))

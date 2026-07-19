class_name Kepler
extends RefCounted
## Kepler's-equation solvers and anomaly conversions, elliptic and hyperbolic.
##
## GDScript has no hyperbolic functions, so the needed ones live here too.

const TOLERANCE := 1e-13
const MAX_ITERATIONS := 64


## Solve E - e sin E = M for the eccentric anomaly E. Works for any M
## (result stays on the same 2*PI branch as the input).
static func solve_elliptic(mean_anomaly: float, e: float) -> float:
	var m := wrapf(mean_anomaly, -PI, PI)
	var branch := mean_anomaly - m
	var ecc := m + e * sin(m)
	if e >= 0.8:
		ecc = PI * signf(m)
	for _i in MAX_ITERATIONS:
		var step := (ecc - e * sin(ecc) - m) / (1.0 - e * cos(ecc))
		ecc -= step
		if absf(step) < TOLERANCE:
			return ecc + branch
	# Newton can stall near e ~ 1 with small M; g(E) = E - e sin E - M is
	# monotone on [m - e, m + e], so bisection always recovers.
	var lo := m - e
	var hi := m + e
	for _i in 128:
		ecc = 0.5 * (lo + hi)
		if ecc - e * sin(ecc) - m > 0.0:
			hi = ecc
		else:
			lo = ecc
	return ecc + branch


## Solve e sinh H - H = N for the hyperbolic anomaly H.
static func solve_hyperbolic(mean_anomaly: float, e: float) -> float:
	var h := asinh_f(mean_anomaly / e)
	for _i in MAX_ITERATIONS:
		var step := (e * sinh_f(h) - h - mean_anomaly) / (e * cosh_f(h) - 1.0)
		h -= step
		if absf(step) < TOLERANCE * maxf(1.0, absf(h)):
			return h
	# Fallback: expand a bracket around 0, then bisect the monotone residual.
	var lo := -1.0
	var hi := 1.0
	while e * sinh_f(lo) - lo - mean_anomaly > 0.0:
		lo *= 2.0
	while e * sinh_f(hi) - hi - mean_anomaly < 0.0:
		hi *= 2.0
	for _i in 200:
		h = 0.5 * (lo + hi)
		if e * sinh_f(h) - h - mean_anomaly > 0.0:
			hi = h
		else:
			lo = h
	return h


static func true_from_eccentric(ecc: float, e: float) -> float:
	return 2.0 * atan2(sqrt(1.0 + e) * sin(ecc * 0.5), sqrt(1.0 - e) * cos(ecc * 0.5))


static func eccentric_from_true(nu: float, e: float) -> float:
	return 2.0 * atan2(sqrt(1.0 - e) * sin(nu * 0.5), sqrt(1.0 + e) * cos(nu * 0.5))


static func mean_from_eccentric(ecc: float, e: float) -> float:
	return ecc - e * sin(ecc)


static func true_from_hyperbolic(h: float, e: float) -> float:
	return 2.0 * atan(sqrt((e + 1.0) / (e - 1.0)) * tanh_f(h * 0.5))


static func hyperbolic_from_true(nu: float, e: float) -> float:
	var t := sqrt((e - 1.0) / (e + 1.0)) * tan(nu * 0.5)
	return 2.0 * atanh_f(clampf(t, -1.0 + 1e-15, 1.0 - 1e-15))


static func mean_from_hyperbolic(h: float, e: float) -> float:
	return e * sinh_f(h) - h


static func sinh_f(x: float) -> float:
	return 0.5 * (exp(x) - exp(-x))


static func cosh_f(x: float) -> float:
	return 0.5 * (exp(x) + exp(-x))


static func tanh_f(x: float) -> float:
	var e2 := exp(2.0 * x)
	return (e2 - 1.0) / (e2 + 1.0)


static func asinh_f(x: float) -> float:
	return log(x + sqrt(x * x + 1.0))


static func atanh_f(x: float) -> float:
	return 0.5 * log((1.0 + x) / (1.0 - x))

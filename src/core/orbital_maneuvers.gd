class_name OrbitalManeuvers
extends RefCounted
## Pure orbital-maneuver math shared by the headless test autopilot
## (tests/autopilot) and the live in-game flight director
## (src/autopilot/flight_director). No ShipSim, no Nodes - just geometry and
## the Lambert two-point boundary solve - so both a fast solver and a
## frame-paced pilot can lean on exactly the same maths.


## A basis whose thrust axis (local -Z) points along `dir`. Identity if `dir`
## is ~zero (caller should skip applying it in that case).
static func look_along(dir: DVec3) -> Basis:
	var d := dir.normalized().to_vector3()
	if d.length_squared() < 1e-12:
		return Basis.IDENTITY
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(d, up)


## Angular position of a point in the XZ plane, matching the phase convention
## OrbitElements.circular uses (position (r cosθ, 0, -r sinθ)).
static func phase_of(p: DVec3) -> float:
	return atan2(-p.z, p.x)


## Rodrigues rotation of `v` about a unit `axis` by `angle`.
static func rotate_about(v: DVec3, axis: DVec3, angle: float) -> DVec3:
	var u := axis.normalized()
	var c := cos(angle)
	var s := sin(angle)
	return (v.scaled(c)
		.add(u.cross(v).scaled(s))
		.add(u.scaled(u.dot(v) * (1.0 - c))))


static func _stumpff_c(z: float) -> float:
	if z > 1e-6:
		return (1.0 - cos(sqrt(z))) / z
	if z < -1e-6:
		return (cosh(sqrt(-z)) - 1.0) / (-z)
	return 0.5


static func _stumpff_s(z: float) -> float:
	if z > 1e-6:
		var sz := sqrt(z)
		return (sz - sin(sz)) / (sz * sz * sz)
	if z < -1e-6:
		var sz := sqrt(-z)
		return (sinh(sz) - sz) / (sz * sz * sz)
	return 1.0 / 6.0


## Universal-variable Lambert solver (Vallado): the velocities [v1, v2] that
## carry a body from r1 to r2 in time `dt` on a `prograde` (+Y normal) conic,
## or [] if no solution converges. Lets an interplanetary intercept target the
## destination's true future position from the real post-escape state.
static func lambert(r1v: DVec3, r2v: DVec3, dt: float, mu: float, prograde := true) -> Array:
	var r1 := r1v.length()
	var r2 := r2v.length()
	var cos_dnu := clampf(r1v.dot(r2v) / (r1 * r2), -1.0, 1.0)
	var dnu := acos(cos_dnu)
	var short_way := r1v.cross(r2v).y >= 0.0
	if short_way != prograde:
		dnu = TAU - dnu
	var a_coef := sin(dnu) * sqrt(r1 * r2 / (1.0 - cos(dnu)))
	if absf(a_coef) < 1e-9:
		return []
	var z_low := -4.0 * PI * PI
	var z_high := 4.0 * PI * PI
	var z := 0.0
	var y := 0.0
	for _i in 200:
		var c := _stumpff_c(z)
		var s := _stumpff_s(z)
		y = r1 + r2 + a_coef * (z * s - 1.0) / sqrt(c)
		if a_coef > 0.0 and y < 0.0:
			z_low = z
			z = 0.5 * (z_low + z_high)
			continue
		var chi := sqrt(y / c)
		var dt_z := (chi * chi * chi * s + a_coef * sqrt(y)) / sqrt(mu)
		if absf(dt_z - dt) < maxf(1e-4 * dt, 1e-3):
			break
		if dt_z <= dt:
			z_low = z
		else:
			z_high = z
		z = 0.5 * (z_low + z_high)
	if y <= 0.0:
		return []
	var g := a_coef * sqrt(y / mu)
	var f := 1.0 - y / r1
	var gdot := 1.0 - y / r2
	return [r2v.sub(r1v.scaled(f)).scaled(1.0 / g), r2v.scaled(gdot).sub(r1v).scaled(1.0 / g)]

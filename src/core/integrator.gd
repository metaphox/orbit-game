class_name Integrator
extends RefCounted
## RK4 integration for powered flight: two-body gravity plus thrust along a
## fixed direction, with propellant mass depletion. Coasting flight never
## comes here — it stays on closed-form rails (see OrbitElements).

const G0 := 9.80665


class BurnState:
	var r: DVec3
	var v: DVec3
	var mass: float

	func _init(pr: DVec3, pv: DVec3, pmass: float) -> void:
		r = pr
		v = pv
		mass = pmass


## One RK4 step. thrust_dir must be unit length; it is held constant across
## the step (attitude changes on much longer timescales than dt).
static func rk4_step(
		s: BurnState, mu: float, thrust_dir: DVec3, thrust: float,
		flow: float, dt: float) -> BurnState:
	var half := dt * 0.5
	var m_half := s.mass - flow * half
	var m_full := s.mass - flow * dt

	var k1v := _accel(s.r, s.mass, mu, thrust_dir, thrust)
	var k1r := s.v

	var k2v := _accel(s.r.add(k1r.scaled(half)), m_half, mu, thrust_dir, thrust)
	var k2r := s.v.add(k1v.scaled(half))

	var k3v := _accel(s.r.add(k2r.scaled(half)), m_half, mu, thrust_dir, thrust)
	var k3r := s.v.add(k2v.scaled(half))

	var k4v := _accel(s.r.add(k3r.scaled(dt)), m_full, mu, thrust_dir, thrust)
	var k4r := s.v.add(k3v.scaled(dt))

	var sixth := dt / 6.0
	var r_new := s.r.add(
		k1r.add(k2r.scaled(2.0)).add(k3r.scaled(2.0)).add(k4r).scaled(sixth))
	var v_new := s.v.add(
		k1v.add(k2v.scaled(2.0)).add(k3v.scaled(2.0)).add(k4v).scaled(sixth))
	return BurnState.new(r_new, v_new, m_full)


static func mass_flow(thrust: float, isp: float) -> float:
	return thrust / (isp * G0)


## Ideal delta-v from the rocket equation.
static func delta_v(wet_mass: float, dry_mass: float, isp: float) -> float:
	return isp * G0 * log(wet_mass / dry_mass)


static func _accel(
		r: DVec3, mass: float, mu: float, thrust_dir: DVec3,
		thrust: float) -> DVec3:
	var r_len := r.length()
	var grav := r.scaled(-mu / (r_len * r_len * r_len))
	if thrust == 0.0:
		return grav
	return grav.add(thrust_dir.scaled(thrust / mass))

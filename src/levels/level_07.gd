class_name Level07
extends RefCounted
## Act 3, Level 1: Earth to Mars. The Sun is the root body; Earth and Mars
## are both its children — the same single-parent-of-many-children data
## shape already used for Earth+Moon, just with the ship's starting body
## (Earth) itself being a non-root child this time. No engine changes were
## needed for this: SOI handoff, event-clamped warp, and TransferCapture's
## phase-angle guidance already generalize (see transfer_capture.gd).
##
## Numbers are tuned for pacing, not real astronomy: Sun-Earth 4.0e7 m,
## Sun-Mars 6.0e7 m (ratio ~1.5, echoing the real Mars/Earth AU ratio),
## mu_sun chosen so the Hohmann transfer takes ~150,000 s sim time (a few
## seconds at max warp, comparable in feel to the lunar transfer). Mars
## starts 60 degrees ahead of Earth; the ideal departure lead is ~43
## degrees, so the burn window is ~6 sim-hours out — the player has to
## wait for it, same as the TLI level's moon phasing.
##
## Ideal patched-conic dv: ~438 m/s Earth departure + ~177 m/s Mars
## capture ≈ 615 m/s. Par (700) sits just above that; the 2300 kg
## propellant load budgets ~945 m/s total, generous margin for a
## hand-flown (not Lambert-solved) transfer.


static func make() -> LevelDef:
	var sun := BodyDef.new()
	sun.name = "SOL"
	sun.mu = 5.48e13
	sun.radius = 400000.0
	sun.color = Color(0.95, 0.75, 0.3)

	var mu_sun: float = sun.mu
	var r_earth := 4.0e7
	var r_mars := 6.0e7

	var earth := BodyDef.new()
	earth.name = "EARTH"
	earth.mu = 7.676e10
	earth.radius = 63710.0
	earth.soi_radius = 9.24e6
	earth.parent = sun
	earth.color = Color(0.16, 0.3, 0.48)
	var v_earth := sqrt(mu_sun / r_earth)
	earth.orbit = OrbitElements.from_state(
		DVec3.new(r_earth, 0.0, 0.0), DVec3.new(0.0, 0.0, -v_earth), mu_sun, 0.0)

	var mars := BodyDef.new()
	mars.name = "MARS"
	mars.mu = 8.21e9
	mars.radius = 33900.0
	mars.soi_radius = 3.0e6
	mars.parent = sun
	mars.color = Color(0.72, 0.36, 0.22)
	var v_mars := sqrt(mu_sun / r_mars)
	var theta_mars := deg_to_rad(60.0)  # ahead of the ~43 deg ideal lead
	mars.orbit = OrbitElements.from_state(
		DVec3.new(r_mars * cos(theta_mars), 0.0, -r_mars * sin(theta_mars)),
		DVec3.new(-v_mars * sin(theta_mars), 0.0, -v_mars * cos(theta_mars)),
		mu_sun, 0.0)

	var objective := TransferCaptureObjective.new()
	objective.target = mars
	objective.approach_falloff = 3.0e6

	var level := LevelDef.new()
	level.title = "INTERPLANETARY 1: EARTH TO MARS"
	level.body = sun
	level.moons = [earth, mars]
	level.start_body = earth
	level.start_radius = 70000.0
	level.dry_mass = 1200.0
	level.prop_mass = 2300.0
	level.thrust = 15000.0
	level.isp = 90.0
	level.objective = objective
	level.dv_par = 700.0
	level.map_extent = 145000.0
	level.draw_limit = 9.0e7
	level.fail_radius = 1.3e8
	level.sas_enabled = true
	level.nodes_enabled = true
	return level

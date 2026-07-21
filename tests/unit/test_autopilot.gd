extends "res://tests/unit/base_orbit_test.gd"
## Automated proof that each level is actually winnable, flown through the
## real ShipSim by the analytic autopilot (tests/autopilot/autopilot.gd) - no
## teleporting the orbit into place. Each test asserts the objective's own
## is_met() flips true, and reports the Δv the autopilot spent against the
## level's authored par so the pars can be sanity-checked empirically.

const Autopilot := preload("res://tests/autopilot/autopilot.gd")


func _fresh_ship(level: LevelDef) -> ShipSim:
	var ship := ShipSim.new()
	ship.setup(level)
	return ship


## Nudges the sim one rails step so is_met (which requires COASTING) sees a
## settled post-burn state, then reports the win + Δv vs par.
func _assert_solved(level: LevelDef, ship: ShipSim) -> void:
	ship.advance_to(ship.last_time + 1.0)
	var dv := ship.dv_used()
	assert_true(level.objective.is_met(ship),
		"%s: autopilot met the objective (Δv %.1f / par %.0f)" % [
			level.title, dv, level.dv_par])
	gut.p("  %s — Δv %.1f m/s (par %.0f, %.0f%% of par)" % [
		level.title, dv, level.dv_par, 100.0 * dv / level.dv_par])


func test_level_01_raise_orbit() -> void:
	var level := Campaign.level_at(0)
	var ship := _fresh_ship(level)
	var obj: OrbitMatchObjective = level.objective
	Autopilot.achieve_circular(ship, obj.target_radius, obj.target_inclination)
	_assert_solved(level, ship)


func test_level_06_plane_change() -> void:
	var level := Campaign.level_at(5)
	var ship := _fresh_ship(level)
	var obj: OrbitMatchObjective = level.objective
	Autopilot.achieve_circular(ship, obj.target_radius, obj.target_inclination)
	_assert_solved(level, ship)


func test_level_03_rendezvous() -> void:
	var level := Campaign.level_at(2)
	var ship := _fresh_ship(level)
	var obj: RendezvousObjective = level.objective
	Autopilot.rendezvous(ship, obj.station_orbit, obj.max_distance, obj.max_rel_speed)
	_assert_solved(level, ship)


func test_level_02_translunar_injection() -> void:
	var level := Campaign.level_at(1)
	var ship := _fresh_ship(level)
	var obj: TransferCaptureObjective = level.objective
	assert_true(Autopilot.transfer_and_capture(ship, obj.target),
		"autopilot flew the transfer and captured into lunar orbit")
	_assert_solved(level, ship)


func test_level_05_come_home() -> void:
	var level := Campaign.level_at(4)
	var ship := _fresh_ship(level)
	var obj: EntryCorridorObjective = level.objective
	assert_true(Autopilot.return_to_periapsis(ship, obj.target_periapsis, obj.tolerance),
		"autopilot escaped the Moon and reached Earth's frame")
	_assert_solved(level, ship)


func test_level_07_earth_to_mars() -> void:
	var level := Campaign.level_at(6)
	var ship := _fresh_ship(level)
	var obj: TransferCaptureObjective = level.objective
	assert_true(Autopilot.interplanetary_transfer(ship, obj.target),
		"autopilot escaped Earth, crossed to Mars, and captured into orbit")
	_assert_solved(level, ship)


func test_level_04_airless_landing() -> void:
	var level := Campaign.level_at(3)
	var ship := _fresh_ship(level)
	var obj: AirlessLandingObjective = level.objective
	assert_true(Autopilot.land(ship, obj.target), "autopilot flew a powered descent to the surface")
	assert_eq(obj.contact_result(ship), Objective.ContactResult.WIN,
		"soft touchdown within the V/H limits")
	var dv := ship.dv_used()
	gut.p("  %s — Δv %.1f m/s (par %.0f, %.0f%% of par)" % [
		level.title, dv, level.dv_par, 100.0 * dv / level.dv_par])

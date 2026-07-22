extends "res://tests/unit/base_orbit_test.gd"
## MapView.velocity_heading_angle() drives the minimap's PROGRADE-up rotation
## (hud.gd rotates the camera by it, so the ship glyph can show real attitude).
## Confirm it tracks the ship's velocity projected onto the map plane, and holds
## the last angle across a momentary zero velocity so the map never spins.

const ANGLE_TOLERANCE := 1e-3


func _heading_for_velocity(vx: float, vz: float) -> float:
	var ship := ShipSim.new()
	ship.setup(Campaign.level_at(3))
	ship.v = DVec3.new(vx, 0.0, vz)
	var mv: MapView = autofree(MapView.new())
	return mv.velocity_heading_angle(ship)


func test_heading_tracks_ship_velocity() -> void:
	assert_almost_eq(_heading_for_velocity(0.0, -1.0), PI, ANGLE_TOLERANCE, "prograde -Z")
	assert_almost_eq(_heading_for_velocity(1.0, 0.0), PI / 2.0, ANGLE_TOLERANCE, "prograde +X")
	assert_almost_eq(_heading_for_velocity(0.0, 1.0), 0.0, ANGLE_TOLERANCE, "prograde +Z")
	assert_almost_eq(_heading_for_velocity(-1.0, 0.0), -PI / 2.0, ANGLE_TOLERANCE, "prograde -X")


func test_heading_holds_through_zero_velocity() -> void:
	var ship := ShipSim.new()
	ship.setup(Campaign.level_at(3))
	ship.v = DVec3.new(1.0, 0.0, 0.0)
	var mv: MapView = autofree(MapView.new())
	var held := mv.velocity_heading_angle(ship)
	ship.v = DVec3.new(0.0, 0.0, 0.0)  # momentary null velocity -> keep last heading
	assert_almost_eq(mv.velocity_heading_angle(ship), held, ANGLE_TOLERANCE, "held across zero velocity")

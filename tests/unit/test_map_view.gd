extends "res://tests/unit/base_orbit_test.gd"
## MapView.ship_heading_angle() is the single source of truth for the
## minimap's heading-up rotation (both the camera in hud.gd and the ship
## marker's own basis in map_view.gd derive from it) - confirm it tracks
## the ship's actual yaw with real, empirically-verified numbers.

const ANGLE_TOLERANCE := 1e-3


func _heading_for_yaw_deg(yaw_deg: float) -> float:
	var level := Campaign.level_at(1)
	var ship := ShipSim.new()
	ship.setup(level)
	ship.attitude = Basis(Vector3.UP, deg_to_rad(yaw_deg))
	return MapView.ship_heading_angle(ship)


func test_heading_tracks_ship_yaw() -> void:
	assert_almost_eq(_heading_for_yaw_deg(0.0), PI, ANGLE_TOLERANCE, "yaw 0")
	assert_almost_eq(_heading_for_yaw_deg(90.0), -PI / 2.0, ANGLE_TOLERANCE, "yaw 90")
	assert_almost_eq(_heading_for_yaw_deg(180.0), 0.0, ANGLE_TOLERANCE, "yaw 180")
	assert_almost_eq(_heading_for_yaw_deg(-90.0), PI / 2.0, ANGLE_TOLERANCE, "yaw -90")

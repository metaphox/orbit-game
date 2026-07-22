extends "res://tests/unit/base_orbit_test.gd"
## Camera positioning + view-state math for the CameraRig, extracted from
## FlightView (TD-2). Pins the floating-origin camera poses so a future edit to
## the rig can't silently shift the framing.


func _rig_with_cameras() -> CameraRig:
	var host := Node3D.new()
	add_child_autofree(host)
	var chase := Camera3D.new()
	var side := Camera3D.new()
	host.add_child(chase)
	host.add_child(side)
	var rig := CameraRig.new()
	rig.bind(chase, side)
	return rig


func test_update_poses_both_cameras_around_the_floating_origin() -> void:
	var rig := _rig_with_cameras()
	var scene_reach := 8.0e5
	rig.update(Basis.IDENTITY, scene_reach)

	# chase: identity attitude with zero yaw/pitch leaves the authored shoulder offset
	assert_eq(rig.chase_camera.position,
		Vector3(4.2, 3.5, 11.0) * rig.chase_distance,
		"chase camera keeps its shoulder offset scaled by zoom")

	var side_basis := Basis(Vector3(0, 1, 0), rig.side_azimuth) \
		* Basis(Vector3(1, 0, 0), -rig.side_elevation)
	assert_eq(rig.side_camera.position, side_basis * Vector3(0, 0, rig.side_distance),
		"side camera orbits at side_distance on its azimuth/elevation")
	assert_almost_eq(rig.side_camera.near, maxf(50.0, rig.side_distance * 0.002), 1e-3,
		"side near tracks distance")
	assert_almost_eq(rig.side_camera.far, rig.side_distance + scene_reach * 1.25 + 1000.0, 1e-1,
		"side far reaches past the whole scene from any angle")


func test_chase_and_side_zoom_clamp_to_their_ranges() -> void:
	var rig := _rig_with_cameras()
	rig.chase_zoom(0.0001)
	assert_almost_eq(rig.chase_distance, 0.35, 1e-6, "chase zoom-in floors at ship-detail scale")
	rig.chase_zoom(1.0e6)
	assert_almost_eq(rig.chase_distance, 3.5, 1e-6, "chase zoom-out ceilings short of orbital scale")
	rig.side_zoom(0.0001)
	assert_almost_eq(rig.side_distance, 9.0e4, 1.0, "side zoom-in floors at close range")
	rig.side_zoom(1.0e6)
	assert_almost_eq(rig.side_distance, rig.side_zoom_max, 1.0, "side zoom-out ceilings at its max")


func test_drag_wraps_azimuth_and_clamps_pitch_elevation() -> void:
	var rig := CameraRig.new()
	rig.chase_drag(Vector2(1000.0, 1000.0))
	assert_lt(rig.cam_pitch, -1.29, "chase pitch clamps down at its limit")
	assert_between(rig.cam_yaw, -PI, PI, "chase yaw wraps into +/-PI")
	rig.side_drag(Vector2(0.0, 1000.0))
	assert_almost_eq(rig.side_elevation, 1.45, 1e-6, "side elevation clamps at its ceiling")


func test_configure_scales_side_zoom_ceiling_with_draw_limit() -> void:
	var rig := CameraRig.new()
	rig.configure(2.0e6)
	assert_almost_eq(rig.side_zoom_max, 2.8e6, 1.0, "big draw limits raise the zoom ceiling")
	rig.configure(1.0e5)
	assert_almost_eq(rig.side_zoom_max, 1.6e6, 1.0, "small levels keep the 1.6e6 floor")


func test_reset_restores_all_view_state_to_defaults() -> void:
	var rig := CameraRig.new()
	rig.cam_yaw = 1.0
	rig.cam_pitch = 1.0
	rig.chase_distance = 2.0
	rig.side_azimuth = 1.0
	rig.side_elevation = 1.0
	rig.side_distance = 9.0e5
	rig.reset()
	assert_eq(rig.cam_yaw, rig.DEFAULT_CAM_YAW)
	assert_eq(rig.cam_pitch, rig.DEFAULT_CAM_PITCH)
	assert_eq(rig.chase_distance, rig.DEFAULT_CHASE_DISTANCE)
	assert_eq(rig.side_azimuth, rig.DEFAULT_SIDE_AZIMUTH)
	assert_eq(rig.side_elevation, rig.DEFAULT_SIDE_ELEVATION)
	assert_eq(rig.side_distance, rig.DEFAULT_SIDE_DISTANCE)


func test_set_side_active_switches_the_current_camera() -> void:
	var rig := _rig_with_cameras()
	rig.set_side_active(true)
	assert_true(rig.side_active, "flag follows the active view")
	assert_true(rig.side_camera.is_current(), "orbit view makes the side camera current")
	rig.set_side_active(false)
	assert_false(rig.side_active)
	assert_true(rig.chase_camera.is_current(), "chase view makes the chase camera current")

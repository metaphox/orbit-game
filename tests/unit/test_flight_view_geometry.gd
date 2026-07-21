extends "res://tests/unit/base_orbit_test.gd"
## Rendering regression checks for the generated celestial-body sphere.


func test_faceted_sphere_renders_outer_surface_with_outward_normals() -> void:
	var view := FlightView.new()
	add_child_autofree(view)
	var mesh: ArrayMesh = view._make_faceted_sphere(10.0, 12, 6)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var clockwise_outside := true
	var normals_outside := true

	for i in range(0, vertices.size(), 3):
		var center := vertices[i] + vertices[i + 1] + vertices[i + 2]
		var geometric_normal := (vertices[i + 1] - vertices[i]).cross(
			vertices[i + 2] - vertices[i])
		if geometric_normal.dot(center) >= 0.0:
			clockwise_outside = false
		if normals[i].dot(center) <= 0.0:
			normals_outside = false

	assert_true(clockwise_outside,
		"Godot-clockwise faces expose the near hemisphere, not the globe interior")
	assert_true(normals_outside, "lighting normals still point out of the sphere")
	assert_eq(uvs.size(), vertices.size(), "every surface vertex has a fixed map UV")


func test_chase_zoom_clamps_to_ship_detail_range() -> void:
	var view := FlightView.new()
	add_child_autofree(view)
	view.chase_zoom(0.0001)
	assert_almost_eq(view._chase_distance, 0.35, 1e-6, "chase zoom-in floors at ship-detail scale")
	view.chase_zoom(1.0e6)
	assert_almost_eq(view._chase_distance, 3.5, 1e-6, "chase zoom-out ceilings well short of orbital scale")


func test_side_zoom_clamps_between_close_and_orbital_scale() -> void:
	var view := FlightView.new()
	add_child_autofree(view)
	view.side_zoom(0.0001)
	assert_almost_eq(view._side_distance, 9.0e4, 1.0, "side zoom-in floors at close range")
	view.side_zoom(1.0e6)
	assert_almost_eq(view._side_distance, view._side_zoom_max, 1.0, "side zoom-out ceilings at its max")


func test_station_model_keeps_physical_and_orbit_marker_scales_separate() -> void:
	var view := FlightView.new()
	add_child_autofree(view)
	view._objective = preload("res://src/levels/data/level_03.tres").objective
	view._build_node_visuals()

	assert_not_null(view._station_marker, "rendezvous level builds the close-up station")
	assert_not_null(view._station_orbit_marker, "rendezvous level builds a distant marker")
	assert_eq(view._station_marker.scale, Vector3.ONE,
		"the close-up station does not inherit the orbit camera's marker scale")
	var icon_mesh := view._station_orbit_marker.get_node("CentralHub") as VisualInstance3D
	assert_eq(icon_mesh.layers, view.SIDE_MARKER_LAYER,
		"the enlarged station copy is visible only to the orbit camera")


func test_giant_station_marker_is_larger_than_ship_in_zoomed_out_view() -> void:
	var ship_span: float = FlightView.SHIP_POSTURE_MARKER_LENGTH \
		* FlightView.SIDE_MARKER_SCALE_PER_CAMERA_DISTANCE
	var station_span: float = FlightView.STATION_MODEL_WIDTH \
		* FlightView.STATION_MARKER_SCALE_PER_CAMERA_DISTANCE
	assert_almost_eq(station_span,
		ship_span * FlightView.STATION_MARKER_SIZE_MULTIPLIER, 0.000001,
		"the giant station reads larger than the player marker at every zoom")
	assert_gt(FlightView.STATION_PHYSICAL_SCALE * FlightView.STATION_MODEL_WIDTH, 1000.0,
		"the physical station is comically wider than the real ISS")

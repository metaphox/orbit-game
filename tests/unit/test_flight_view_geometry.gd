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

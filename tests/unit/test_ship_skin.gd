extends "res://tests/unit/base_orbit_test.gd"
## The imported craft's material names are the stable contract between its OBJ
## geometry and theme-selected ShipSkin resources.

const SHIP_RIG := preload("res://src/ui/world/ship_camera_rig.tscn")
const EXPECTED_SLOTS: Array[String] = [
	"foil_gold",
	"frame_alloy",
	"hazard_amber",
	"hull_beige",
	"hull_white",
	"nozzle_scorched",
	"nozzle_steel",
	"panel_dark",
	"solar_cell",
]


func _hull() -> MeshInstance3D:
	var rig := SHIP_RIG.instantiate()
	add_child_autofree(rig)
	return rig.get_node("Ship/Hull") as MeshInstance3D


func _named_material(name: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	return material


func _sentinel_skin() -> ShipSkin:
	var skin := ShipSkin.new()
	skin.hull_white = _named_material("sentinel_hull_white")
	skin.hull_beige = _named_material("sentinel_hull_beige")
	skin.panel_dark = _named_material("sentinel_panel_dark")
	skin.hazard_amber = _named_material("sentinel_hazard_amber")
	skin.frame_alloy = _named_material("sentinel_frame_alloy")
	skin.nozzle_steel = _named_material("sentinel_nozzle_steel")
	skin.nozzle_scorched = _named_material("sentinel_nozzle_scorched")
	skin.solar_cell = _named_material("sentinel_solar_cell")
	skin.foil_gold = _named_material("sentinel_foil_gold")
	return skin


func _source_slot_names(hull: MeshInstance3D) -> Array[String]:
	var names: Array[String] = []
	var source_mesh: Mesh = hull.mesh
	for surface_index: int in source_mesh.get_surface_count():
		var source_material: Material = source_mesh.surface_get_material(surface_index)
		var source_name := source_material.resource_name
		if source_name not in names:
			names.append(source_name)
	names.sort()
	return names


func test_imported_ship_material_names_match_skin_contract() -> void:
	assert_eq(_source_slot_names(_hull()), EXPECTED_SLOTS,
		"OBJ material names stay aligned with the typed ShipSkin slots")


func test_default_skin_fills_every_imported_slot_with_pbr_materials() -> void:
	var hull := _hull()
	var skin := RenderTheme.default().ship_skin
	var unmatched := skin.apply_to(hull)
	assert_eq(unmatched, PackedStringArray(), "the default skin covers every OBJ material")

	var source_mesh: Mesh = hull.mesh
	for surface_index: int in source_mesh.get_surface_count():
		var source_material: Material = source_mesh.surface_get_material(surface_index)
		var expected := skin.material_for(StringName(source_material.resource_name))
		assert_not_null(expected, "every imported source material resolves")
		assert_true(expected is StandardMaterial3D, "default skin slots use PBR materials")
		assert_same(hull.get_surface_override_material(surface_index), expected,
			"every repeated OBJ surface receives its named override")


func test_custom_render_theme_skin_reaches_flight_view_hull() -> void:
	var theme := RenderTheme.default()
	theme.ship_skin = _sentinel_skin()
	var view := FlightView.new()
	add_child_autofree(view)
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	view.build(level, theme)

	var hull := view.get_node("ShipCameraRig/Ship/Hull") as MeshInstance3D
	var source_mesh: Mesh = hull.mesh
	for surface_index: int in source_mesh.get_surface_count():
		var source_material: Material = source_mesh.surface_get_material(surface_index)
		var expected := theme.ship_skin.material_for(StringName(source_material.resource_name))
		assert_same(hull.get_surface_override_material(surface_index), expected,
			"FlightView passes the RenderTheme skin to ShipVisuals")


func test_missing_slot_keeps_imported_material_and_reports_name() -> void:
	var hull := _hull()
	var skin := _sentinel_skin()
	skin.hull_white = null
	var unmatched := skin.apply_to(hull)

	assert_eq(unmatched, PackedStringArray(["hull_white"]))
	assert_push_error("hull_white", "asset drift is reported with the missing slot name")
	var source_mesh: Mesh = hull.mesh
	for surface_index: int in source_mesh.get_surface_count():
		var source_material: Material = source_mesh.surface_get_material(surface_index)
		if source_material.resource_name == "hull_white":
			assert_null(hull.get_surface_override_material(surface_index),
				"an unmatched surface keeps using its embedded OBJ material")

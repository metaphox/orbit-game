class_name ShipSkin
extends Resource
## Theme-selected material set for the imported player-craft mesh. The OBJ's
## material names are the stable slot contract; every matching surface receives
## the corresponding Godot material as an explicit runtime override.

const HULL_WHITE := &"hull_white"
const HULL_BEIGE := &"hull_beige"
const PANEL_DARK := &"panel_dark"
const HAZARD_AMBER := &"hazard_amber"
const FRAME_ALLOY := &"frame_alloy"
const NOZZLE_STEEL := &"nozzle_steel"
const NOZZLE_SCORCHED := &"nozzle_scorched"
const SOLAR_CELL := &"solar_cell"
const FOIL_GOLD := &"foil_gold"

@export var hull_white: Material
@export var hull_beige: Material
@export var panel_dark: Material
@export var hazard_amber: Material
@export var frame_alloy: Material
@export var nozzle_steel: Material
@export var nozzle_scorched: Material
@export var solar_cell: Material
@export var foil_gold: Material


func material_for(source_name: StringName) -> Material:
	match source_name:
		HULL_WHITE:
			return hull_white
		HULL_BEIGE:
			return hull_beige
		PANEL_DARK:
			return panel_dark
		HAZARD_AMBER:
			return hazard_amber
		FRAME_ALLOY:
			return frame_alloy
		NOZZLE_STEEL:
			return nozzle_steel
		NOZZLE_SCORCHED:
			return nozzle_scorched
		SOLAR_CELL:
			return solar_cell
		FOIL_GOLD:
			return foil_gold
	return null


## Leaves an imported material in place when a slot is absent, making asset drift
## visible without turning the affected surface blank. Callers/tests can inspect
## the returned, de-duplicated names as well as the emitted Godot errors.
func apply_to(target: MeshInstance3D) -> PackedStringArray:
	var unmatched := PackedStringArray()
	var source_mesh: Mesh = target.mesh
	if source_mesh == null:
		unmatched.append("<missing mesh>")
		push_error("Cannot apply ShipSkin to %s: the MeshInstance3D has no mesh." % target.name)
		return unmatched

	for surface_index: int in source_mesh.get_surface_count():
		var source_material: Material = source_mesh.surface_get_material(surface_index)
		var source_name := StringName()
		if source_material != null:
			source_name = StringName(source_material.resource_name)
		var replacement := material_for(source_name)
		if replacement != null:
			target.set_surface_override_material(surface_index, replacement)
			continue

		var missing_name := String(source_name)
		if missing_name.is_empty():
			missing_name = "<unnamed surface %d>" % surface_index
		if missing_name not in unmatched:
			unmatched.append(missing_name)

	for missing_name: String in unmatched:
		push_error("ShipSkin has no material for imported slot '%s'; keeping the OBJ material." % missing_name)
	return unmatched

class_name LevelDef
extends Resource
## Everything that defines a level, as an Inspector-editable Resource
## authored to a .tres file per level (see src/levels/data/).

@export var title := ""
@export var body: BodyDef  # root body of the system
@export var moons: Array[BodyDef] = []
@export var start_body: BodyDef  # where the ship starts; null = the root body
@export var start_radius := 0.0
@export var dry_mass := 0.0
@export var prop_mass := 0.0
@export var thrust := 0.0
@export var isp := 0.0
@export var objective: Objective
@export var dv_par := 0.0
@export var map_extent := 360.0  # minimap ortho height, km units
@export var draw_limit := 4.0e5  # trajectory clip radius around the root body, m
@export var fail_radius := 0.0  # mission envelope around the root body; 0 = none

# Capability flags ("the flight computer"): granted per level as in-fiction
# avionics upgrades at act boundaries (DESIGN.md section 6).
@export var sas_enabled := false
@export var nodes_enabled := false


func medal(dv_used: float) -> String:
	if dv_used <= dv_par:
		return "GOLD ★★★"
	if dv_used <= dv_par * 1.2:
		return "SILVER ★★"
	return "BRONZE ★"

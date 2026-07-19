class_name LevelDef
extends RefCounted
## Everything that defines a level. M2: plain code objects; becomes .tres
## resources in M6.

var title := ""
var body: BodyDef  # root body; the ship starts in its SOI
var moons: Array[BodyDef] = []
var start_radius := 0.0
var dry_mass := 0.0
var prop_mass := 0.0
var thrust := 0.0
var isp := 0.0
var objective: Objective
var dv_par := 0.0
var map_extent := 360.0  # minimap ortho height, km units
var draw_limit := 4.0e5  # trajectory clip radius around the root body, m
var fail_radius := 0.0  # mission envelope around the root body; 0 = none

# Capability flags ("the flight computer"): granted per level as in-fiction
# avionics upgrades at act boundaries (DESIGN.md section 6).
var sas_enabled := false
var nodes_enabled := false


func medal(dv_used: float) -> String:
	if dv_used <= dv_par:
		return "GOLD ★★★"
	if dv_used <= dv_par * 1.2:
		return "SILVER ★★"
	return "BRONZE ★"

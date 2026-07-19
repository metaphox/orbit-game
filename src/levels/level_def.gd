class_name LevelDef
extends RefCounted
## Everything that defines a level. M2: plain code objects; becomes .tres
## resources in M6.

var title := ""
var body: BodyDef
var start_radius := 0.0
var dry_mass := 0.0
var prop_mass := 0.0
var thrust := 0.0
var isp := 0.0
var objective: OrbitMatchObjective
var dv_par := 0.0


func medal(dv_used: float) -> String:
	if dv_used <= dv_par:
		return "GOLD ★★★"
	if dv_used <= dv_par * 1.2:
		return "SILVER ★★"
	return "BRONZE ★"

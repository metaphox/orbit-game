class_name Objective
extends Resource
## Base for level win conditions. Subclasses are pure predicates plus the
## bits the UI needs: a description, live status lines, and a 0..1
## "closeness" that colors the in-world trajectory (1 = on target).


enum ContactResult { NONE, WIN, CRASH }


func is_met(_ship: ShipSim) -> bool:
	return false


## Called when the ship touches a surface. NONE means contact is always a
## failure (the default); landing objectives override.
func contact_result(_ship: ShipSim) -> ContactResult:
	return ContactResult.NONE


func describe() -> String:
	return ""


func status_lines(_ship: ShipSim) -> Array:
	return []


func trajectory_closeness(_ship: ShipSim) -> float:
	return 0.0

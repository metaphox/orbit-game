class_name Objective
extends RefCounted
## Base for level win conditions. Subclasses are pure predicates plus the
## bits the UI needs: a description, live status lines, and a 0..1
## "closeness" that colors the in-world trajectory (1 = on target).


func is_met(_ship: ShipSim) -> bool:
	return false


func describe() -> String:
	return ""


func status_lines(_ship: ShipSim) -> Array:
	return []


func trajectory_closeness(_ship: ShipSim) -> float:
	return 0.0

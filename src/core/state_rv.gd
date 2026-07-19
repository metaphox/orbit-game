class_name StateRV
extends RefCounted
## Position/velocity pair in a parent body's inertial frame.

var r: DVec3
var v: DVec3


func _init(pr: DVec3 = null, pv: DVec3 = null) -> void:
	r = pr if pr != null else DVec3.new()
	v = pv if pv != null else DVec3.new()

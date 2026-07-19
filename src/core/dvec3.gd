class_name DVec3
extends RefCounted
## 64-bit float 3-vector for simulation math.
##
## Standard Godot builds store Vector3 components as 32-bit floats, which
## cannot represent interplanetary distances to sub-meter precision. The
## simulation core works exclusively in DVec3; Vector3 appears only at the
## render boundary.

var x := 0.0
var y := 0.0
var z := 0.0


func _init(px := 0.0, py := 0.0, pz := 0.0) -> void:
	x = px
	y = py
	z = pz


func add(o: DVec3) -> DVec3:
	return DVec3.new(x + o.x, y + o.y, z + o.z)


func sub(o: DVec3) -> DVec3:
	return DVec3.new(x - o.x, y - o.y, z - o.z)


func scaled(s: float) -> DVec3:
	return DVec3.new(x * s, y * s, z * s)


func neg() -> DVec3:
	return DVec3.new(-x, -y, -z)


func dot(o: DVec3) -> float:
	return x * o.x + y * o.y + z * o.z


func cross(o: DVec3) -> DVec3:
	return DVec3.new(
		y * o.z - z * o.y,
		z * o.x - x * o.z,
		x * o.y - y * o.x)


func length_squared() -> float:
	return x * x + y * y + z * z


func length() -> float:
	return sqrt(length_squared())


func normalized() -> DVec3:
	var l := length()
	return DVec3.new(x / l, y / l, z / l)


func distance_to(o: DVec3) -> float:
	return sub(o).length()


func copy() -> DVec3:
	return DVec3.new(x, y, z)


func to_vector3() -> Vector3:
	return Vector3(x, y, z)


static func from_vector3(v: Vector3) -> DVec3:
	return DVec3.new(v.x, v.y, v.z)

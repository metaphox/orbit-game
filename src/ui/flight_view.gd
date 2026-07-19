class_name FlightView
extends Node3D
## Exterior chase view. Floating origin: the ship renders at (0,0,0) and
## the world shifts around it, so float32 GPU precision never sees large
## coordinates. 1 render unit = 1 m. Placeholder art until M7.

var camera: Camera3D
var planet: MeshInstance3D
var ship_root: Node3D
var prograde_marker: Node3D
var retrograde_marker: Node3D


func build(level: LevelDef) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.008, 0.016)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.35)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.55, 0.65, 0.0)
	sun.light_energy = 1.3
	add_child(sun)

	planet = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = level.body.radius
	sphere.height = level.body.radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var planet_mat := StandardMaterial3D.new()
	planet_mat.albedo_color = Color(0.16, 0.3, 0.48)
	planet_mat.roughness = 0.9
	sphere.material = planet_mat
	planet.mesh = sphere
	add_child(planet)

	ship_root = Node3D.new()
	add_child(ship_root)
	_build_ship_mesh()

	prograde_marker = _make_marker(Color(0.3, 1.0, 0.4))
	retrograde_marker = _make_marker(Color(1.0, 0.35, 0.25))

	camera = Camera3D.new()
	camera.near = 0.5
	camera.far = 500000.0
	camera.cull_mask = 1
	add_child(camera)
	camera.position = Vector3(0, 3.5, 11.0)


func sync(ship: ShipSim) -> void:
	ship_root.basis = ship.attitude
	planet.position = ship.r.neg().to_vector3()

	var v_dir := ship.v.normalized().to_vector3()
	_place_marker(prograde_marker, v_dir)
	_place_marker(retrograde_marker, -v_dir)

	camera.position = ship.attitude * Vector3(0, 3.5, 11.0)
	camera.look_at(Vector3.ZERO, ship.attitude.y)


func _build_ship_mesh() -> void:
	var hull := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.8
	capsule.height = 3.4
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.92, 0.9, 0.86)
	hull_mat.roughness = 0.55
	capsule.material = hull_mat
	hull.mesh = capsule
	hull.rotation.x = -PI / 2  # capsule axis (+Y) -> forward (-Z)
	ship_root.add_child(hull)

	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.75
	cone.height = 1.3
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.95, 0.45, 0.1)
	cone.material = nose_mat
	nose.mesh = cone
	nose.rotation.x = -PI / 2
	nose.position = Vector3(0, 0, -2.3)
	ship_root.add_child(nose)


func _make_marker(color: Color) -> Node3D:
	var marker := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	cone.material = mat
	mesh_node.mesh = cone
	mesh_node.rotation.x = PI / 2  # cone tip (+Y) -> node forward (-Z)
	marker.add_child(mesh_node)
	add_child(marker)
	return marker


func _place_marker(marker: Node3D, dir: Vector3) -> void:
	marker.position = dir * 14.0
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	marker.look_at(marker.position + dir, up)

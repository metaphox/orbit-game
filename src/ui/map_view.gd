class_name MapView
extends Node3D
## The mission-computer map: planet, current orbit conic, ghost target
## orbit, ship marker. 1 render unit = 1 km, everything on visual layer 2
## so only the map camera sees it. Vector-CRT styling arrives in M7.

const MAP_SCALE := 0.001
const MAP_LAYER := 2
const ORBIT_SAMPLES := 160
const REFRESH_INTERVAL := 0.2
const DRAW_LIMIT_RADIUS := 4.0e5  # clip unbound trajectories at 400 km

var camera: Camera3D
var orbit_mesh: ImmediateMesh
var ship_marker: MeshInstance3D
var _refresh_left := 0.0


func build(level: LevelDef) -> void:
	var planet := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = level.body.radius * MAP_SCALE
	sphere.height = level.body.radius * MAP_SCALE * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	sphere.material = _line_material(Color(0.05, 0.22, 0.1))
	planet.mesh = sphere
	planet.layers = MAP_LAYER
	add_child(planet)

	var target: OrbitMatchObjective = level.objective
	var ring := _circle_points(target.target_radius * MAP_SCALE)
	add_child(_line_instance(ring, Color(0.2, 0.55, 0.28)))

	orbit_mesh = ImmediateMesh.new()
	var orbit_instance := MeshInstance3D.new()
	orbit_instance.mesh = orbit_mesh
	orbit_instance.material_override = _line_material(Color(0.35, 1.0, 0.45))
	orbit_instance.layers = MAP_LAYER
	add_child(orbit_instance)

	ship_marker = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 1.6
	dot.height = 3.2
	dot.material = _line_material(Color(1.0, 1.0, 1.0))
	ship_marker.mesh = dot
	ship_marker.layers = MAP_LAYER
	add_child(ship_marker)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 320.0
	camera.near = 1.0
	camera.far = 2000.0
	camera.cull_mask = MAP_LAYER
	add_child(camera)
	camera.position = Vector3(0, 320, 150)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func sync(ship: ShipSim, delta: float) -> void:
	ship_marker.position = ship.r.scaled(MAP_SCALE).to_vector3()
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_INTERVAL
	_rebuild_orbit_line(ship.current_elements())


func _rebuild_orbit_line(el: OrbitElements) -> void:
	var pts: Array = el.sample_positions(ORBIT_SAMPLES, DRAW_LIMIT_RADIUS)
	orbit_mesh.clear_surfaces()
	orbit_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: DVec3 in pts:
		orbit_mesh.surface_add_vertex(p.scaled(MAP_SCALE).to_vector3())
	var closed := el.is_elliptic() and el.radius_apoapsis() <= DRAW_LIMIT_RADIUS
	if closed:
		var first: DVec3 = pts[0]
		orbit_mesh.surface_add_vertex(first.scaled(MAP_SCALE).to_vector3())
	orbit_mesh.surface_end()


func _circle_points(radius: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 129:
		var ang := TAU * i / 128.0
		pts.append(Vector3(cos(ang) * radius, 0.0, sin(ang) * radius))
	return pts


func _line_instance(pts: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pts:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _line_material(color)
	inst.layers = MAP_LAYER
	return inst


func _line_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat

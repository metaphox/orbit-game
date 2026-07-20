class_name MapView
extends Node3D
## The schematic mission-computer map feeding the HUD minimap: bodies,
## the ship's current orbit conic, target ghosts (orbit ring or moon SOI),
## moon orbit tracks. 1 render unit = 1 km, everything on visual layer 2
## so only the minimap camera sees it. Vector-CRT styling arrives in M7.

const MAP_SCALE := 0.001
const MAP_LAYER := 2
const ORBIT_SAMPLES := 160
const REFRESH_INTERVAL := 0.2

var orbit_mesh: ImmediateMesh
var orbit_instance: MeshInstance3D
var ship_marker: MeshInstance3D

var _level: LevelDef
var _moon_markers: Array[MeshInstance3D] = []
var _soi_rings: Array[MeshInstance3D] = []
var _station_marker: MeshInstance3D
var _refresh_left := 0.0
var _ship_marker_scale := 1.0


## Planet/OrbitInstance/ShipMarker - the three nodes always present exactly
## once regardless of level - come from map_view_layout.tscn. Everything
## else here is genuinely level-variable (the ghost ring depends on which
## of five objective types the level uses; moon tracks/markers/SOI rings
## depend on level.moons.size()), so it stays runtime-built, matching
## flight_view.gd's planet meshes for the same reason.
func build(level: LevelDef) -> void:
	_level = level
	var layout := preload("res://src/ui/map_view_layout.tscn").instantiate()
	add_child(layout)

	var planet: MeshInstance3D = layout.get_node("Planet")
	var planet_mesh: SphereMesh = planet.mesh
	planet_mesh.radius = level.body.radius * MAP_SCALE
	planet_mesh.height = level.body.radius * MAP_SCALE * 2.0

	orbit_instance = layout.get_node("OrbitInstance")
	orbit_mesh = orbit_instance.mesh

	ship_marker = layout.get_node("ShipMarker")
	# ShipMarker's baked mesh is a unit-scale directional wedge (tip at -Z);
	# scaling its basis in sync() both sizes it per-level and lets the
	# heading-up rotation spin it in place without touching mesh geometry.
	_ship_marker_scale = level.map_extent / 220.0

	if level.objective is OrbitMatchObjective:
		var target := level.objective as OrbitMatchObjective
		add_child(_line_instance(
			_circle_points(target.target_radius * MAP_SCALE), Color(0.2, 0.55, 0.28)))
	elif level.objective is RendezvousObjective:
		var rdv := level.objective as RendezvousObjective
		add_child(_line_instance(
			_circle_points(rdv.station_orbit.a * MAP_SCALE), Color(0.2, 0.55, 0.28)))
		_station_marker = MeshInstance3D.new()
		var st_dot := SphereMesh.new()
		var st_radius := level.map_extent / 200.0
		st_dot.radius = st_radius
		st_dot.height = st_radius * 2.0
		st_dot.material = _line_material(Color(1.0, 0.7, 0.2))
		_station_marker.mesh = st_dot
		_station_marker.layers = MAP_LAYER
		add_child(_station_marker)
	elif level.objective is EntryCorridorObjective:
		var corridor := level.objective as EntryCorridorObjective
		add_child(_line_instance(
			_circle_points(corridor.target_periapsis * MAP_SCALE), Color(0.2, 0.55, 0.28)))

	for moon in level.moons:
		# the moon's orbit track around the root
		add_child(_line_instance(
			_circle_points(moon.orbit.a * MAP_SCALE), Color(0.16, 0.35, 0.2)))
		var marker := MeshInstance3D.new()
		var dot := SphereMesh.new()
		var dot_radius := maxf(moon.radius * MAP_SCALE, level.map_extent / 130.0)
		dot.radius = dot_radius
		dot.height = dot_radius * 2.0
		dot.material = _line_material(Color(0.55, 0.53, 0.5))
		marker.mesh = dot
		marker.layers = MAP_LAYER
		add_child(marker)
		_moon_markers.append(marker)

		var soi := _line_instance(
			_circle_points(moon.soi_radius * MAP_SCALE), Color(0.2, 0.55, 0.28))
		add_child(soi)
		_soi_rings.append(soi)


## Ship's current heading (nose direction, projected onto the orbital
## plane) as a yaw angle - single source of truth shared by the ship
## marker's own basis and the minimap camera's heading-up rotation in
## hud.gd, so the two always agree regardless of the reference convention
## chosen here.
static func ship_heading_angle(ship: ShipSim) -> float:
	var f := ship.forward_dir()
	return atan2(f.x, f.z)


func sync(ship: ShipSim, t: float, delta: float) -> void:
	ship_marker.position = ship.absolute_position(t).scaled(MAP_SCALE).to_vector3()
	ship_marker.basis = Basis(Vector3.UP, ship_heading_angle(ship)).scaled(Vector3.ONE * _ship_marker_scale)
	for i in _level.moons.size():
		var moon_pos := _level.moons[i].position_at(t).scaled(MAP_SCALE).to_vector3()
		_moon_markers[i].position = moon_pos
		_soi_rings[i].position = moon_pos
	if _station_marker != null:
		_station_marker.position = (_level.objective as RendezvousObjective) \
			.station_orbit.state_at_time(t).r.scaled(MAP_SCALE).to_vector3()
	# orbit conic is parent-centered; offset the node by the parent's spot
	orbit_instance.position = ship.body.position_at(t).scaled(MAP_SCALE).to_vector3()
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_INTERVAL
	var r_max := minf(_level.draw_limit, ship.body.soi_radius * 1.15)
	_rebuild_orbit_line(ship.current_elements(), r_max)


func _rebuild_orbit_line(el: OrbitElements, r_max: float) -> void:
	var pts: Array[DVec3] = el.sample_positions(ORBIT_SAMPLES, r_max)
	orbit_mesh.clear_surfaces()
	orbit_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: DVec3 in pts:
		orbit_mesh.surface_add_vertex(p.scaled(MAP_SCALE).to_vector3())
	if el.is_elliptic() and el.radius_apoapsis() <= r_max:
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

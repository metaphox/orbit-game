class_name FlightView
extends Node3D
## The 3D world view. Floating origin: the ship renders at (0,0,0) and the
## world shifts around it, so float32 GPU precision never sees large
## coordinates. 1 render unit = 1 m. Placeholder art until M7.
##
## Two cameras share this world: the mouse-orbitable chase camera, and the
## "orbit view" side camera centered on the planet (TAB) — zoom and rotate
## freely without touching the ship. The current trajectory glows in-world
## (color = how close to the target orbit); the target orbit is a dashed
## ring.

const TRAJ_SAMPLES := 256
const TRAJ_REFRESH := 0.25
const TRAJ_DRAW_LIMIT := 4.0e5
# Adaptive orbit-line sampling: the camera rides ON the line, so chords
# near the ship are seen edge-on and must be near-tangent-continuous.
# Steps in true anomaly start fine at the ship and grow geometrically.
const TRAJ_FINE_STEP := 0.002
const TRAJ_COARSE_STEP := 0.06
const TRAJ_STEP_GROWTH := 1.18
const MATCH_COLOR := Color(0.35, 1.0, 0.45)
const FAR_COLOR := Color(1.0, 0.55, 0.12)
const SIDE_MARKER_LAYER := 8  # ship dot only the side camera can see

var camera: Camera3D
var side_camera: Camera3D
var planet: MeshInstance3D
var ship_root: Node3D
var prograde_marker: Node3D
var retrograde_marker: Node3D
var star_dust: StarDust
var flame: MeshInstance3D
var gauge: AccelGauge

var _prop_full := 1.0
var _target_radius := 0.0
var _tolerance := 0.0

var _traj_mesh: ImmediateMesh
var _traj_instance: MeshInstance3D
var _traj_material: StandardMaterial3D
var _target_instance: MeshInstance3D
var _traj_timer := 0.0

var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _side_azimuth := 0.6
var _side_elevation := 0.5
var _side_distance := 3.0e5
var _side_marker: MeshInstance3D


func build(level: LevelDef) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.008, 0.016)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.35)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_bloom = 0.2
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

	star_dust = StarDust.new()
	add_child(star_dust)
	star_dust.build()

	_prop_full = level.prop_mass
	_build_status_hologram(level)

	var objective: OrbitMatchObjective = level.objective
	_target_radius = objective.target_radius
	_tolerance = objective.tolerance
	_build_trajectory_lines()

	prograde_marker = _make_marker(Color(0.3, 1.0, 0.4))
	retrograde_marker = _make_marker(Color(1.0, 0.35, 0.25))

	camera = Camera3D.new()
	camera.near = 0.5
	camera.far = 500000.0
	camera.cull_mask = 1
	add_child(camera)
	camera.position = Vector3(0, 3.5, 11.0)

	side_camera = Camera3D.new()
	side_camera.near = 50.0
	side_camera.far = 4.0e6
	side_camera.cull_mask = 1 | SIDE_MARKER_LAYER
	add_child(side_camera)


func sync(ship: ShipSim, delta: float) -> void:
	ship_root.basis = ship.attitude
	var planet_pos := ship.r.neg().to_vector3()
	planet.position = planet_pos

	var v_dir := ship.v.normalized().to_vector3()
	_place_marker(prograde_marker, v_dir)
	_place_marker(retrograde_marker, -v_dir)
	star_dust.update_motion(v_dir, ship.speed())

	var thrusting := ship.throttle > 0.0 and ship.prop_mass > 0.0
	flame.visible = thrusting
	if thrusting:
		flame.scale = Vector3(1.0, 1.0, ship.throttle * randf_range(0.85, 1.15))

	gauge.speed = ship.speed()
	gauge.accel = ship.accel_along_track
	gauge.prop_frac = ship.prop_mass / _prop_full
	gauge.dv_left = ship.dv_remaining()

	# trajectory + target ring ride the floating origin via node offset
	_traj_instance.position = planet_pos
	_target_instance.position = planet_pos
	_traj_timer -= delta
	if _traj_timer <= 0.0:
		_traj_timer = TRAJ_REFRESH
		var el := ship.current_elements()
		_rebuild_trajectory(el, el.true_anomaly_at_time(ship.last_time))

	# chase camera: ship-relative orbit, offset by mouse drag
	var chase_basis := ship.attitude \
		* Basis(Vector3(0, 1, 0), _cam_yaw) * Basis(Vector3(1, 0, 0), _cam_pitch)
	camera.position = chase_basis * Vector3(0, 3.5, 11.0)
	camera.look_at(Vector3.ZERO, chase_basis.y)

	# side camera: orbits the planet center, ship-independent
	var side_basis := Basis(Vector3(0, 1, 0), _side_azimuth) \
		* Basis(Vector3(1, 0, 0), -_side_elevation)
	side_camera.position = planet_pos + side_basis * Vector3(0, 0, _side_distance)
	side_camera.near = maxf(50.0, _side_distance * 0.002)
	side_camera.look_at(planet_pos, side_basis.y)
	_side_marker.scale = Vector3.ONE * maxf(_side_distance * 0.006, 1.0)


func set_side_active(active: bool) -> void:
	if active:
		side_camera.make_current()
	else:
		camera.make_current()


func chase_drag(relative: Vector2) -> void:
	_cam_yaw = wrapf(_cam_yaw - relative.x * 0.008, -PI, PI)
	_cam_pitch = clampf(_cam_pitch - relative.y * 0.008, -1.3, 1.3)


func side_drag(relative: Vector2) -> void:
	_side_azimuth = wrapf(_side_azimuth - relative.x * 0.008, -PI, PI)
	_side_elevation = clampf(_side_elevation + relative.y * 0.008, -1.45, 1.45)


func side_zoom(factor: float) -> void:
	_side_distance = clampf(_side_distance * factor, 9.0e4, 1.6e6)


func _build_trajectory_lines() -> void:
	_traj_mesh = ImmediateMesh.new()
	_traj_material = StandardMaterial3D.new()
	_traj_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_traj_material.emission_enabled = true
	_traj_material.emission_energy_multiplier = 2.5
	_traj_instance = MeshInstance3D.new()
	_traj_instance.mesh = _traj_mesh
	_traj_instance.material_override = _traj_material
	add_child(_traj_instance)

	# target orbit: dashed ring in the starting orbital plane (y = 0)
	var dash_mesh := ImmediateMesh.new()
	dash_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var dashes := 96
	for i in dashes:
		if i % 2 == 1:
			continue
		for k in 2:
			var ang := TAU * (i + k * 0.85) / dashes
			dash_mesh.surface_add_vertex(Vector3(
				cos(ang) * _target_radius, 0.0, sin(ang) * _target_radius))
	dash_mesh.surface_end()
	var dash_mat := StandardMaterial3D.new()
	dash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dash_mat.albedo_color = Color(0.5, 0.85, 0.6, 0.55)
	dash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dash_mat.emission_enabled = true
	dash_mat.emission = Color(0.5, 0.85, 0.6)
	dash_mat.emission_energy_multiplier = 1.2
	_target_instance = MeshInstance3D.new()
	_target_instance.mesh = dash_mesh
	_target_instance.material_override = dash_mat
	add_child(_target_instance)

	_side_marker = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 1.0
	dot.height = 2.0
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(1.0, 1.0, 1.0)
	dot.material = dot_mat
	_side_marker.mesh = dot
	_side_marker.layers = SIDE_MARKER_LAYER
	add_child(_side_marker)  # stays at origin = ship render position


func _rebuild_trajectory(el: OrbitElements, nu_ship: float) -> void:
	var err := 1.0e9
	if el.is_elliptic():
		err = maxf(
			absf(el.radius_apoapsis() - _target_radius),
			absf(el.radius_periapsis() - _target_radius))
	var t := clampf((err - _tolerance) / 20000.0, 0.0, 1.0)
	var color := MATCH_COLOR.lerp(FAR_COLOR, t)
	_traj_material.albedo_color = color
	_traj_material.emission = color

	var closed := el.is_elliptic() and el.radius_apoapsis() <= TRAJ_DRAW_LIMIT
	var pts: Array
	if closed:
		pts = _adaptive_loop_points(el, nu_ship)
	else:
		pts = el.sample_positions(TRAJ_SAMPLES, TRAJ_DRAW_LIMIT)
	_traj_mesh.clear_surfaces()
	_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: DVec3 in pts:
		_traj_mesh.surface_add_vertex(p.to_vector3())
	if closed:
		var first: DVec3 = pts[0]
		_traj_mesh.surface_add_vertex(first.to_vector3())
	_traj_mesh.surface_end()


## Full loop with vertex density concentrated at the ship: the first point
## sits exactly on the ship, neighbors ~0.1 degrees apart (invisible bends
## at grazing view), widening to coarse steps on the far side.
func _adaptive_loop_points(el: OrbitElements, nu_ship: float) -> Array:
	var offsets: Array[float] = []
	var step := TRAJ_FINE_STEP
	var off := 0.0
	while off < PI:
		offsets.append(off)
		off += step
		step = minf(step * TRAJ_STEP_GROWTH, TRAJ_COARSE_STEP)
	var pts := []
	for i in range(offsets.size() - 1, 0, -1):
		pts.append(el.state_at_true_anomaly(nu_ship - offsets[i]).r)
	for i in offsets.size():
		pts.append(el.state_at_true_anomaly(nu_ship + offsets[i]).r)
	return pts


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

	flame = MeshInstance3D.new()
	var plume := CylinderMesh.new()
	plume.top_radius = 0.06  # narrow tail (far end after rotation)
	plume.bottom_radius = 0.5
	plume.height = 2.4
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	plume.material = flame_mat
	flame.mesh = plume
	flame.rotation.x = PI / 2  # plume axis (+Y) -> backward (+Z)
	flame.position = Vector3(0, 0, 3.1)
	flame.visible = false
	ship_root.add_child(flame)


## The status dial lives on a SubViewport texture floated beside the hull:
## positioned in ship-local space (it travels and turns with the ship) but
## billboarded toward the camera — a virtual instrument, not a physical one.
func _build_status_hologram(level: LevelDef) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 600)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	gauge = AccelGauge.new()
	gauge.accel_max = level.thrust / level.dry_mass * 1.1
	viewport.add_child(gauge)
	gauge.size = Vector2(256, 300)
	gauge.scale = Vector2(2.0, 2.0)  # crisp 2x render into the 512-wide target

	var sprite := Sprite3D.new()
	sprite.texture = viewport.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.012  # 512 px -> ~6 m panel
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.92)
	sprite.no_depth_test = true  # hologram never hides behind the hull
	sprite.render_priority = 10
	sprite.position = Vector3(5.2, 1.2, 0.0)
	ship_root.add_child(sprite)


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

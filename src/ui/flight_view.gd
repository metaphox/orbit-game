class_name FlightView
extends Node3D
## The 3D world view. Floating origin: the ship renders at (0,0,0) and the
## world (all bodies) shifts around it, so float32 GPU precision never sees
## large coordinates. 1 render unit = 1 m. Placeholder art until M7.
##
## Two cameras share this world: the mouse-orbitable chase camera, and the
## "orbit view" side camera centered on the ship's current parent body
## (TAB) — zoom and rotate freely without touching the ship. The current
## trajectory glows in-world, colored by the objective's 0..1 closeness;
## the target (orbit or SOI) is a dashed ring.

const TRAJ_SAMPLES := 256
const TRAJ_REFRESH := 0.25
# Adaptive orbit-line sampling: the camera rides ON the line, so chords
# near the ship are seen edge-on and must be near-tangent-continuous.
# Steps in true anomaly start fine at the ship and grow geometrically.
const TRAJ_FINE_STEP := 0.002
const TRAJ_COARSE_STEP := 0.06
const TRAJ_STEP_GROWTH := 1.18
const MATCH_COLOR := Color(0.35, 1.0, 0.45)
const FAR_COLOR := Color(1.0, 0.55, 0.12)
const SIDE_MARKER_LAYER := 8  # ship dot only the side camera can see

# Orbit marks: apoapsis/periapsis/nodes/etc, orbit-view only (see
# _build_orbit_marks) - meaningless at chase-cam range where the whole
# orbit shape isn't visible anyway.
const AP_COLOR := Color(0.4, 0.75, 1.0)
const PE_COLOR := Color(1.0, 0.85, 0.3)
const AN_COLOR := Color(0.85, 0.4, 1.0)
const DN_COLOR := Color(0.55, 0.3, 0.75)
const IMPACT_COLOR := Color(1.0, 0.2, 0.15)
const ENCOUNTER_COLOR := Color(1.0, 1.0, 1.0)
const CLOSEST_APPROACH_COLOR := Color(1.0, 0.3, 0.6)

var camera: Camera3D
var side_camera: Camera3D
var ship_root: Node3D
var prograde_marker: Node3D
var retrograde_marker: Node3D
var star_dust: StarDust
var flame: MeshInstance3D
var gauge: AccelGauge

var _bodies: Array[BodyDef] = []
var _body_meshes: Array[MeshInstance3D] = []
var _prop_full := 1.0
var _objective: Objective
var _draw_limit := 4.0e5

var _traj_mesh: ImmediateMesh
var _traj_instance: MeshInstance3D
var _traj_material: StandardMaterial3D
var _target_instance: MeshInstance3D
var _ring_body: BodyDef
var _traj_timer := 0.0

var _node_mesh: ImmediateMesh
var _node_instance: MeshInstance3D
var _preview_mesh: ImmediateMesh
var _preview_instance: MeshInstance3D
var _preview_anchor: DVec3  # parent-frame moon position at predicted entry
var _preview_active := false
var _node_marker: MeshInstance3D
var _station_marker: MeshInstance3D
var _level: LevelDef

var _ap_marker: MeshInstance3D
var _pe_marker: MeshInstance3D
var _an_marker: MeshInstance3D
var _dn_marker: MeshInstance3D
var _impact_marker: MeshInstance3D
var _encounter_marker: MeshInstance3D
var _closest_approach_marker: MeshInstance3D

const DEFAULT_CAM_YAW := 0.0
const DEFAULT_CAM_PITCH := 0.0
const DEFAULT_SIDE_AZIMUTH := 0.6
const DEFAULT_SIDE_ELEVATION := 0.5
const DEFAULT_SIDE_DISTANCE := 3.0e5

var _cam_yaw := DEFAULT_CAM_YAW
var _cam_pitch := DEFAULT_CAM_PITCH
var _side_azimuth := DEFAULT_SIDE_AZIMUTH
var _side_elevation := DEFAULT_SIDE_ELEVATION
var _side_distance := DEFAULT_SIDE_DISTANCE
var _side_zoom_max := 1.6e6
var _side_marker: Node3D


func build(level: LevelDef) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://src/shaders/starfield_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
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

	_bodies = [level.body]
	for moon in level.moons:
		_bodies.append(moon)
	for body in _bodies:
		var mesh_instance := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = body.radius
		sphere.height = body.radius * 2.0
		sphere.radial_segments = 96
		sphere.rings = 48
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body.color
		mat.roughness = 0.9
		mat.rim_enabled = true
		mat.rim = 0.65
		mat.rim_tint = 0.55
		mat.emission_enabled = true
		mat.emission = body.color.lightened(0.3)
		mat.emission_energy_multiplier = 0.12  # faint grazing-angle atmosphere glow
		sphere.material = mat
		mesh_instance.mesh = sphere
		add_child(mesh_instance)
		_body_meshes.append(mesh_instance)

	ship_root = Node3D.new()
	add_child(ship_root)
	_build_ship_mesh()

	star_dust = StarDust.new()
	add_child(star_dust)
	star_dust.build()

	_prop_full = level.prop_mass
	_build_status_hologram(level)

	_objective = level.objective
	_draw_limit = level.draw_limit
	_side_zoom_max = maxf(1.6e6, level.draw_limit * 1.4)
	_level = level
	_build_trajectory_lines(level)
	_build_node_visuals()
	_build_orbit_marks()

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
	side_camera.far = 3.0e7
	side_camera.cull_mask = 1 | SIDE_MARKER_LAYER
	add_child(side_camera)


func sync(ship: ShipSim, delta: float) -> void:
	var t := ship.last_time
	var ship_abs := ship.absolute_position(t)
	ship_root.basis = ship.attitude
	for i in _bodies.size():
		_body_meshes[i].position = _bodies[i].position_at(t).sub(ship_abs).to_vector3()

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

	# trajectory + target ring ride the floating origin via node offsets
	var parent_offset := ship.r.neg().to_vector3()
	_traj_instance.position = parent_offset  # current parent
	_target_instance.position = _ring_body.position_at(t).sub(ship_abs).to_vector3()
	_node_instance.position = parent_offset
	if _preview_active:
		_preview_instance.position = _preview_anchor.sub(ship.r).to_vector3()
	if _station_marker != null:
		var st := (_objective as RendezvousObjective).station_orbit.state_at_time(t)
		_station_marker.position = st.r.sub(ship_abs).to_vector3()
		_station_marker.scale = Vector3.ONE * maxf(_side_distance * 0.002, 1.0)

	var has_node := ship.node != null
	_node_marker.visible = has_node
	if has_node:
		_node_marker.position = ship.current_elements() \
			.state_at_time(ship.node.t_node).r.sub(ship.r).to_vector3()
		_node_marker.scale = Vector3.ONE * maxf(_side_distance * 0.004, 4.0)
	_traj_timer -= delta
	if _traj_timer <= 0.0:
		_traj_timer = TRAJ_REFRESH
		_rebuild_trajectory(ship)

	# chase camera: ship-relative orbit, offset by mouse drag
	var chase_basis := ship.attitude \
		* Basis(Vector3(0, 1, 0), _cam_yaw) * Basis(Vector3(1, 0, 0), _cam_pitch)
	camera.position = chase_basis * Vector3(0, 3.5, 11.0)
	camera.look_at(Vector3.ZERO, chase_basis.y)

	# side camera: orbits and tracks the ship, which - thanks to the
	# floating origin - is always exactly at the render-space origin
	var side_basis := Basis(Vector3(0, 1, 0), _side_azimuth) \
		* Basis(Vector3(1, 0, 0), -_side_elevation)
	side_camera.position = side_basis * Vector3(0, 0, _side_distance)
	side_camera.near = maxf(50.0, _side_distance * 0.002)
	side_camera.look_at(Vector3.ZERO, side_basis.y)
	# scale grows with distance so the marker's ON-SCREEN (angular) size
	# stays constant regardless of zoom; 0.006 (the old plain-dot marker's
	# factor) reads as a barely-visible fleck now that the marker needs to
	# show a legible directional shape, not just a location.
	var marker_scale := maxf(_side_distance * 0.024, 4.0)
	_side_marker.basis = ship.attitude.scaled(Vector3.ONE * marker_scale)


func mark_traj_dirty() -> void:
	_traj_timer = 0.0


## Resets both cameras (chase-cam mouse-drag offset and the orbit-view
## rotation/zoom) back to their starting state.
func reset_view() -> void:
	_cam_yaw = DEFAULT_CAM_YAW
	_cam_pitch = DEFAULT_CAM_PITCH
	_side_azimuth = DEFAULT_SIDE_AZIMUTH
	_side_elevation = DEFAULT_SIDE_ELEVATION
	_side_distance = DEFAULT_SIDE_DISTANCE


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
	_side_distance = clampf(_side_distance * factor, 9.0e4, _side_zoom_max)


func _build_trajectory_lines(level: LevelDef) -> void:
	_traj_mesh = ImmediateMesh.new()
	_traj_material = StandardMaterial3D.new()
	_traj_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_traj_material.emission_enabled = true
	_traj_material.emission_energy_multiplier = 2.5
	_traj_instance = MeshInstance3D.new()
	_traj_instance.mesh = _traj_mesh
	_traj_instance.material_override = _traj_material
	add_child(_traj_instance)

	# target ring: whatever circle best marks the goal for this objective
	var ring_radius: float
	if _objective is TransferCaptureObjective:
		var capture := _objective as TransferCaptureObjective
		_ring_body = capture.target
		ring_radius = capture.target.soi_radius
	elif _objective is RendezvousObjective:
		var rdv := _objective as RendezvousObjective
		_ring_body = level.body
		ring_radius = rdv.station_orbit.a
	elif _objective is AirlessLandingObjective:
		var landing := _objective as AirlessLandingObjective
		_ring_body = landing.target
		ring_radius = landing.target.radius * 1.03
	elif _objective is EntryCorridorObjective:
		var corridor := _objective as EntryCorridorObjective
		_ring_body = level.body
		ring_radius = corridor.target_periapsis
	else:
		var match_obj := _objective as OrbitMatchObjective
		_ring_body = level.body
		ring_radius = match_obj.target_radius

	var dash_mesh := ImmediateMesh.new()
	dash_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var dashes := 96
	for i in dashes:
		if i % 2 == 1:
			continue
		for k in 2:
			var ang := TAU * (i + k * 0.85) / dashes
			dash_mesh.surface_add_vertex(Vector3(
				cos(ang) * ring_radius, 0.0, sin(ang) * ring_radius))
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

	_side_marker = _build_posture_marker()
	add_child(_side_marker)  # stays at origin = ship render position


func _build_node_visuals() -> void:
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.albedo_color = Color(0.45, 0.85, 1.0)
	ghost_mat.emission_enabled = true
	ghost_mat.emission = Color(0.45, 0.85, 1.0)
	ghost_mat.emission_energy_multiplier = 1.8

	_node_mesh = ImmediateMesh.new()
	_node_instance = MeshInstance3D.new()
	_node_instance.mesh = _node_mesh
	_node_instance.material_override = ghost_mat
	add_child(_node_instance)

	_preview_mesh = ImmediateMesh.new()
	_preview_instance = MeshInstance3D.new()
	_preview_instance.mesh = _preview_mesh
	_preview_instance.material_override = ghost_mat
	add_child(_preview_instance)

	_node_marker = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 1.0
	dot.height = 2.0
	var marker_mat := StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color(0.45, 0.85, 1.0)
	dot.material = marker_mat
	_node_marker.mesh = dot
	_node_marker.layers = 1 | SIDE_MARKER_LAYER
	_node_marker.visible = false
	add_child(_node_marker)

	if _objective is RendezvousObjective:
		_station_marker = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3, 3, 3)
		var station_mat := StandardMaterial3D.new()
		station_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		station_mat.albedo_color = Color(1.0, 0.7, 0.2)
		station_mat.emission_enabled = true
		station_mat.emission = Color(1.0, 0.7, 0.2)
		box.material = station_mat
		_station_marker.mesh = box
		_station_marker.layers = 1 | SIDE_MARKER_LAYER
		add_child(_station_marker)


## Apoapsis/periapsis/nodes/impact/encounter/closest-approach: small
## colored dots, orbit-view only, positioned each trajectory refresh in
## _update_orbit_marks. Built once here and toggled visible/hidden rather
## than recreated, since most of them don't apply to every level.
func _build_orbit_marks() -> void:
	_ap_marker = _make_orbit_mark(AP_COLOR)
	_pe_marker = _make_orbit_mark(PE_COLOR)
	_an_marker = _make_orbit_mark(AN_COLOR)
	_dn_marker = _make_orbit_mark(DN_COLOR)
	_impact_marker = _make_orbit_mark(IMPACT_COLOR)
	_encounter_marker = _make_orbit_mark(ENCOUNTER_COLOR)
	_closest_approach_marker = _make_orbit_mark(CLOSEST_APPROACH_COLOR)


func _make_orbit_mark(color: Color) -> MeshInstance3D:
	var mark := MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 1.0
	dot.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	dot.material = mat
	mark.mesh = dot
	mark.layers = SIDE_MARKER_LAYER
	mark.visible = false
	add_child(mark)
	return mark


## Whether a true anomaly is physically reachable on this trajectory - for
## a hyperbolic arc only |nu| < acos(-1/e) is ever actually visited.
func _nu_reachable(el: OrbitElements, nu: float) -> bool:
	if el.is_elliptic():
		return true
	return absf(wrapf(nu, -PI, PI)) < acos(-1.0 / el.e)


func _update_orbit_marks(ship: ShipSim, el: OrbitElements) -> void:
	var mark_scale := Vector3.ONE * maxf(_side_distance * 0.006, 1.0)

	_pe_marker.visible = true
	_pe_marker.position = el.state_at_true_anomaly(0.0).r.sub(ship.r).to_vector3()
	_pe_marker.scale = mark_scale

	_ap_marker.visible = el.is_elliptic()
	if _ap_marker.visible:
		_ap_marker.position = el.state_at_true_anomaly(PI).r.sub(ship.r).to_vector3()
		_ap_marker.scale = mark_scale

	var crossings: Array = el.xz_plane_crossings()
	var nodes_valid := (crossings.size() == 2
		and _nu_reachable(el, crossings[0]) and _nu_reachable(el, crossings[1]))
	_an_marker.visible = nodes_valid
	_dn_marker.visible = nodes_valid
	if nodes_valid:
		_an_marker.position = el.state_at_true_anomaly(crossings[0]).r.sub(ship.r).to_vector3()
		_dn_marker.position = el.state_at_true_anomaly(crossings[1]).r.sub(ship.r).to_vector3()
		_an_marker.scale = mark_scale
		_dn_marker.scale = mark_scale

	var t := ship.last_time
	var impact_t := OrbitEvents.impact_time(el, ship.body.radius, t)
	_impact_marker.visible = not is_nan(impact_t)
	if _impact_marker.visible:
		_impact_marker.position = el.state_at_time(impact_t).r.sub(ship.r).to_vector3()
		_impact_marker.scale = mark_scale

	_encounter_marker.visible = false
	if ship.body.parent == null:
		var span := el.period() if el.is_elliptic() else 6.0e4
		for moon in _level.moons:
			var entry := OrbitEvents.child_soi_entry_time(
				el, moon.orbit, moon.soi_radius, t, t + span, maxf(span / 400.0, 1.0))
			if not is_nan(entry):
				_encounter_marker.visible = true
				_encounter_marker.position = el.state_at_time(entry).r.sub(ship.r).to_vector3()
				_encounter_marker.scale = mark_scale
				break

	_closest_approach_marker.visible = false
	if _objective is RendezvousObjective and ship.body.parent == null:
		var ca := (_objective as RendezvousObjective).closest_approach(ship)
		_closest_approach_marker.visible = true
		_closest_approach_marker.position = el.state_at_time(ca.time).r.sub(ship.r).to_vector3()
		_closest_approach_marker.scale = mark_scale


## Predicted post-burn conic (cyan), plus a moon-centric arc when the
## prediction enters a moon's SOI — anchored at the moon's position at the
## predicted entry time, KSP-style.
func _rebuild_node_ghost(ship: ShipSim) -> void:
	_node_mesh.clear_surfaces()
	_preview_mesh.clear_surfaces()
	_preview_active = false
	if ship.node == null:
		return
	var pred := ship.predicted_elements()
	var r_max := minf(_draw_limit, ship.body.soi_radius * 1.15)
	var pts: Array = pred.sample_positions(TRAJ_SAMPLES, r_max)
	var closed := pred.is_elliptic() and pred.radius_apoapsis() <= r_max
	_node_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: DVec3 in pts:
		_node_mesh.surface_add_vertex(p.to_vector3())
	if closed:
		var first: DVec3 = pts[0]
		_node_mesh.surface_add_vertex(first.to_vector3())
	_node_mesh.surface_end()

	if ship.body.parent != null:
		return
	for moon in _level.moons:
		var span := pred.period() if pred.is_elliptic() else 6.0e4
		var entry := OrbitEvents.child_soi_entry_time(
			pred, moon.orbit, moon.soi_radius, ship.node.t_node,
			ship.node.t_node + span, maxf(span / 400.0, 1.0))
		if is_nan(entry):
			continue
		var rel := Frames.to_child_frame(pred.state_at_time(entry), moon.orbit, entry)
		var arc := OrbitElements.from_state(rel.r, rel.v, moon.mu, entry)
		var arc_pts: Array = arc.sample_positions(96, moon.soi_radius)
		_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p: DVec3 in arc_pts:
			_preview_mesh.surface_add_vertex(p.to_vector3())
		_preview_mesh.surface_end()
		_preview_anchor = moon.position_at(entry)
		_preview_active = true
		break


func _rebuild_trajectory(ship: ShipSim) -> void:
	var el := ship.current_elements()
	var color := FAR_COLOR.lerp(MATCH_COLOR, _objective.trajectory_closeness(ship))
	_traj_material.albedo_color = color
	_traj_material.emission = color

	var r_max := minf(_draw_limit, ship.body.soi_radius * 1.15)
	var closed := el.is_elliptic() and el.radius_apoapsis() <= r_max
	var pts: Array
	if closed:
		pts = _adaptive_loop_points(el, el.true_anomaly_at_time(ship.last_time))
	else:
		pts = el.sample_positions(TRAJ_SAMPLES, r_max)
	_traj_mesh.clear_surfaces()
	_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: DVec3 in pts:
		_traj_mesh.surface_add_vertex(p.to_vector3())
	if closed:
		var first: DVec3 = pts[0]
		_traj_mesh.surface_add_vertex(first.to_vector3())
	_traj_mesh.surface_end()
	_rebuild_node_ghost(ship)
	_update_orbit_marks(ship, el)


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
	hull_mat.metallic = 0.15
	hull_mat.rim_enabled = true
	hull_mat.rim = 0.35
	hull_mat.rim_tint = 0.7
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
	if Settings.effects_enabled:
		viewport.add_child(CrtOverlay.new())  # composited into the baked texture, drawn last

	var sprite := Sprite3D.new()
	sprite.texture = viewport.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.012  # 512 px -> ~6 m panel
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.92)
	sprite.no_depth_test = true  # hologram never hides behind the hull
	sprite.render_priority = 10
	sprite.position = Vector3(5.2, 1.2, 0.0)
	ship_root.add_child(sprite)


## Small directional stand-in for the ship in the orbit-view/minimap
## distance range, where the real hull would be sub-pixel: an elongated
## nose cone (pitch/yaw legible) plus an off-axis wing (roll legible too),
## unshaded so it reads clearly regardless of light angle. Its own basis
## gets set to the ship's attitude each frame, unlike a plain sphere which
## can't show orientation at all.
func _build_posture_marker() -> Node3D:
	var marker := Node3D.new()

	var hull := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.5
	capsule.height = 2.2
	var hull_mat := StandardMaterial3D.new()
	hull_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hull_mat.albedo_color = Color(0.92, 0.9, 0.86)
	capsule.material = hull_mat
	hull.mesh = capsule
	hull.rotation.x = -PI / 2  # capsule axis (+Y) -> forward (-Z)
	hull.layers = SIDE_MARKER_LAYER
	marker.add_child(hull)

	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.01
	cone.bottom_radius = 0.48
	cone.height = 0.9
	var nose_mat := StandardMaterial3D.new()
	nose_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nose_mat.albedo_color = Color(0.95, 0.45, 0.1)
	cone.material = nose_mat
	nose.mesh = cone
	nose.rotation.x = -PI / 2
	nose.position = Vector3(0, 0, -1.5)
	nose.layers = SIDE_MARKER_LAYER
	marker.add_child(nose)

	var wing := MeshInstance3D.new()
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(1.7, 0.1, 0.5)
	var wing_mat := StandardMaterial3D.new()
	wing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wing_mat.albedo_color = Color(0.5, 0.85, 1.0)
	wing_mesh.material = wing_mat
	wing.mesh = wing_mesh
	wing.position = Vector3(0, 0, 0.2)
	wing.layers = SIDE_MARKER_LAYER
	marker.add_child(wing)

	return marker


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

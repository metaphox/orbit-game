class_name TrajectoryRenderer
extends Node3D
## The current-orbit prediction line - rebuilt every frame and glued to the ship
## via the floating origin - plus the objective's target ring or entry-corridor
## band. Reads its line colours from the RenderTheme. Extracted from FlightView
## (TECH_DEBTS.md TD-2/TD-3) so the forward-path visuals live in one themeable
## place. Sits at the render origin (identity transform); its children are posed
## in ship-relative space just as they were as FlightView's own children.

const TRAJ_SAMPLES := 256
# Adaptive orbit-line sampling: the camera rides ON the line, so chords near the
# ship are seen edge-on and must be near-tangent-continuous. Steps in true
# anomaly start fine at the ship and grow geometrically. The coarse cap also
# bounds how angular the foreshortened apoapsis fold looks.
const TRAJ_FINE_STEP := 0.002
const TRAJ_COARSE_STEP := 0.03
const TRAJ_STEP_GROWTH := 1.18

var _theme: RenderTheme
var _objective: Objective
var _draw_limit := 4.0e5
var _ring_body: BodyDef
var _traj_mesh: ImmediateMesh
var _traj_instance: MeshInstance3D
var _traj_material: StandardMaterial3D
var _target_instance: MeshInstance3D


func build(level: LevelDef, theme: RenderTheme) -> void:
	_theme = theme
	_objective = level.objective
	_draw_limit = level.draw_limit

	_traj_mesh = ImmediateMesh.new()
	_traj_material = StandardMaterial3D.new()
	_traj_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_traj_material.emission_enabled = true
	_traj_material.emission_energy_multiplier = 2.5
	_traj_instance = MeshInstance3D.new()
	_traj_instance.mesh = _traj_mesh
	_traj_instance.material_override = _traj_material
	add_child(_traj_instance)

	# target ring: whatever circle best marks the goal for this objective.
	# ring_tilt inclines it off the equatorial plane so a plane-change goal
	# reads as a tilted hoop the ship must line its orbit up with, not just a
	# number - the flat radius circle alone hid the inclination target.
	var ring_radius: float
	var ring_tilt := 0.0
	var corridor_tol := 0.0  # > 0 switches to the entry-corridor band render
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
		corridor_tol = corridor.tolerance
	else:
		var match_obj := _objective as OrbitMatchObjective
		_ring_body = level.body
		ring_radius = match_obj.target_radius
		ring_tilt = match_obj.target_inclination

	_target_instance = MeshInstance3D.new()
	if corridor_tol > 0.0:
		# A hairline ring at the corridor radius read as "on the planet" (the
		# 66 km corridor sits barely above Earth's ~64 km surface). Render the
		# ±tolerance band instead - a filled amber annulus with bright edge
		# rings - so it's an unmistakable gate hovering just above the surface
		# that the ship's periapsis must drop into.
		_target_instance.mesh = _build_corridor_band(ring_radius, corridor_tol)
	else:
		var tilt_basis := Basis(Vector3(1, 0, 0), ring_tilt)
		var dash_mesh := ImmediateMesh.new()
		dash_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var dashes := 96
		for i in dashes:
			if i % 2 == 1:
				continue
			for k in 2:
				var ang := TAU * (i + k * 0.85) / dashes
				dash_mesh.surface_add_vertex(tilt_basis * Vector3(
					cos(ang) * ring_radius, 0.0, sin(ang) * ring_radius))
		dash_mesh.surface_end()
		var dash_mat := StandardMaterial3D.new()
		dash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dash_mat.albedo_color = Color(_theme.ring_color, 0.55)
		dash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dash_mat.emission_enabled = true
		dash_mat.emission = _theme.ring_color
		dash_mat.emission_energy_multiplier = 1.2
		_target_instance.mesh = dash_mesh
		_target_instance.material_override = dash_mat
	add_child(_target_instance)


## Reposition both meshes for this frame and rebuild the prediction line so it
## stays glued to the ship (first vertex exactly on the ship). `guidance_enabled`
## false (hardcore) hides the prediction line; the target ring always stays.
func sync(ship: ShipSim, ship_abs: DVec3, t: float, guidance_enabled: bool) -> void:
	_traj_instance.position = ship.r.neg().to_vector3()  # current parent
	_target_instance.position = _ring_body.position_at(t).sub(ship_abs).to_vector3()
	_rebuild_line(ship)
	_traj_instance.visible = guidance_enabled


## The entry-corridor gate: a faint filled amber annulus between the periapsis
## tolerance bounds plus a bright ring on each edge, so the shallow corridor
## reads as a distinct band above the surface instead of a hairline circle.
func _build_corridor_band(radius: float, tol: float) -> ImmediateMesh:
	var inner := radius - tol
	var outer := radius + tol
	var seg := 96
	var mesh := ImmediateMesh.new()

	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_mat.albedo_color = Color(_theme.corridor_color, 0.16)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, fill_mat)
	for i in seg + 1:
		var ang := TAU * i / seg
		mesh.surface_add_vertex(Vector3(cos(ang) * inner, 0.0, sin(ang) * inner))
		mesh.surface_add_vertex(Vector3(cos(ang) * outer, 0.0, sin(ang) * outer))
	mesh.surface_end()

	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.albedo_color = Color(_theme.corridor_color, 0.9)
	edge_mat.emission_enabled = true
	edge_mat.emission = _theme.corridor_color
	edge_mat.emission_energy_multiplier = 1.5
	for edge_radius in [inner, outer]:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, edge_mat)
		for i in seg + 1:
			var ang := TAU * i / seg
			mesh.surface_add_vertex(Vector3(cos(ang) * edge_radius, 0.0, sin(ang) * edge_radius))
		mesh.surface_end()
	return mesh


## The orbit line itself, rebuilt every frame. Cheap (analytic sampling of a
## conic) and it keeps the first vertex sitting exactly on the ship, so the
## ship never drifts off the line and the far-side fold never twitches at the
## old 4 Hz refresh rate. The pricier node ghost / orbit marks stay throttled.
func _rebuild_line(ship: ShipSim) -> void:
	var el := ship.current_elements()
	var color := _theme.traj_far_color.lerp(_theme.traj_match_color, _objective.trajectory_closeness(ship))
	_traj_material.albedo_color = color
	_traj_material.emission = color

	var r_max := minf(_draw_limit, ship.body.soi_radius * 1.15)
	var closed := el.is_elliptic() and el.radius_apoapsis() <= r_max
	var pts: Array[DVec3]
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


## Full loop with vertex density concentrated at the ship: the first point
## sits exactly on the ship, neighbors ~0.1 degrees apart (invisible bends
## at grazing view), widening to coarse steps on the far side.
func _adaptive_loop_points(el: OrbitElements, nu_ship: float) -> Array[DVec3]:
	var offsets: Array[float] = []
	var step := TRAJ_FINE_STEP
	var off := 0.0
	while off < PI:
		offsets.append(off)
		off += step
		step = minf(step * TRAJ_STEP_GROWTH, TRAJ_COARSE_STEP)
	var pts: Array[DVec3] = []
	for i in range(offsets.size() - 1, 0, -1):
		pts.append(el.state_at_true_anomaly(nu_ship - offsets[i]).r)
	for i in offsets.size():
		pts.append(el.state_at_true_anomaly(nu_ship + offsets[i]).r)
	return pts

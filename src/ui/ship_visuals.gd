class_name ShipVisuals
extends Node3D
## Everything that represents the player craft in the flight view, extracted from
## FlightView (TECH_DEBTS.md TD-2): the ship attitude, engine flame, the drifting
## star dust, the prograde/retrograde velocity markers, and the orbit-view posture
## marker (a directional stand-in for the sub-pixel hull at orbital range).
## (The old diegetic status hologram was removed once the screen HUD became the
## single source of ACC/VEL/Δv/PROP.)
##
## It also renders the rendezvous-target station, because the station's orbit
## marker is deliberately sized as a matched pair with the ship's posture marker
## (STATION_MARKER_SCALE_PER_CAMERA_DISTANCE is derived from the ship marker's),
## so both live behind one set of marker-scale constants here.

const STATION_MODEL := preload("res://src/ui/station_model.tscn")
const STATION_PHYSICAL_SCALE := 32.0  # deliberately absurd: just over 1 km across
# The distant station is intentionally larger than the ship marker too. The
# base ratio accounts for their authored dimensions; the multiplier sells the
# station's exaggerated scale without letting it cover an entire orbit view.
const SIDE_MARKER_SCALE_PER_CAMERA_DISTANCE := 0.024
const SHIP_POSTURE_MARKER_LENGTH := 3.05
const STATION_MODEL_WIDTH := 31.8
const STATION_MARKER_SIZE_MULTIPLIER := 1.8
const STATION_MARKER_SCALE_PER_CAMERA_DISTANCE := \
	SIDE_MARKER_SCALE_PER_CAMERA_DISTANCE * SHIP_POSTURE_MARKER_LENGTH \
	* STATION_MARKER_SIZE_MULTIPLIER / STATION_MODEL_WIDTH

var star_dust: StarDust
var prograde_marker: Node3D
var retrograde_marker: Node3D

var _ship_root: Node3D
var _flame: MeshInstance3D
## Rest Z of the flame node and half its cone length (ship-local), captured so
## the throttle-scaled cone can keep its wide base pinned to the nozzle.
var _flame_rest_z := 0.0
var _flame_half_len := 0.0
var _side_marker: Node3D  # posture stand-in, stays at origin = ship render position
var _station_marker: Node3D
var _station_orbit_marker: Node3D
var _objective: Objective
var _theme: RenderTheme


func build(level: LevelDef, ship_root: Node3D, flame: MeshInstance3D, theme: RenderTheme = null) -> void:
	_theme = theme if theme != null else RenderTheme.default()
	_ship_root = ship_root
	_flame = flame
	_flame_rest_z = flame.position.z
	var flame_cone := flame.mesh as CylinderMesh
	_flame_half_len = flame_cone.height * 0.5 if flame_cone != null else 0.0
	_objective = level.objective

	star_dust = StarDust.new()
	add_child(star_dust)
	star_dust.build()

	_side_marker = _build_posture_marker()
	add_child(_side_marker)

	prograde_marker = _make_marker(_theme.prograde_color)
	retrograde_marker = _make_marker(_theme.retrograde_color)

	_build_station_markers()


func sync(ship: ShipSim, ship_abs: DVec3, t: float, side_distance: float) -> void:
	_ship_root.basis = ship.attitude

	var v_dir := ship.v.normalized().to_vector3()
	_place_marker(prograde_marker, v_dir)
	_place_marker(retrograde_marker, -v_dir)
	star_dust.update_motion(v_dir, ship.speed())

	var thrusting := ship.throttle > 0.0 and ship.prop_mass > 0.0
	_flame.visible = thrusting
	if thrusting:
		# Scale the cone's LENGTH (local Y = the height axis, which maps to +Z),
		# not a cross-section axis — scaling Z would squash the cone flat. The node
		# scales about its centre, so shift Z to keep the wide base pinned to the
		# nozzle; the flame then retracts from the tail as throttle drops.
		var s := ship.throttle * randf_range(0.85, 1.15)
		_flame.scale = Vector3(1.0, s, 1.0)
		var pos := _flame.position
		pos.z = _flame_rest_z + _flame_half_len * (s - 1.0)
		_flame.position = pos

	if _station_marker != null:
		var st := (_objective as RendezvousObjective).station_orbit.state_at_time(t)
		var station_position := st.r.sub(ship_abs).to_vector3()
		var radial := st.r.normalized().to_vector3()
		var tangent := st.v.normalized().to_vector3()
		var orbit_normal := radial.cross(tangent).normalized()
		var station_basis := Basis(orbit_normal, radial, tangent)
		_station_marker.position = station_position
		_station_marker.basis = station_basis.scaled(Vector3.ONE * STATION_PHYSICAL_SCALE)
		_station_orbit_marker.position = station_position
		_station_orbit_marker.basis = station_basis.scaled(
			Vector3.ONE * maxf(
				side_distance * STATION_MARKER_SCALE_PER_CAMERA_DISTANCE, 1.0))

	# scale grows with distance so the marker's ON-SCREEN (angular) size
	# stays constant regardless of zoom; 0.006 (the old plain-dot marker's
	# factor) reads as a barely-visible fleck now that the marker needs to
	# show a legible directional shape, not just a location.
	var marker_scale := maxf(side_distance * SIDE_MARKER_SCALE_PER_CAMERA_DISTANCE, 4.0)
	_side_marker.basis = ship.attitude.scaled(Vector3.ONE * marker_scale)


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
	hull_mat.albedo_color = _theme.posture_hull_color
	capsule.material = hull_mat
	hull.mesh = capsule
	hull.rotation.x = -PI / 2  # capsule axis (+Y) -> forward (-Z)
	hull.layers = ManeuverVisuals.SIDE_MARKER_LAYER
	marker.add_child(hull)

	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.01
	cone.bottom_radius = 0.48
	cone.height = 0.9
	var nose_mat := StandardMaterial3D.new()
	nose_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nose_mat.albedo_color = _theme.posture_nose_color
	cone.material = nose_mat
	nose.mesh = cone
	nose.rotation.x = -PI / 2
	nose.position = Vector3(0, 0, -1.5)
	nose.layers = ManeuverVisuals.SIDE_MARKER_LAYER
	marker.add_child(nose)

	var wing := MeshInstance3D.new()
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(1.7, 0.1, 0.5)
	var wing_mat := StandardMaterial3D.new()
	wing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wing_mat.albedo_color = _theme.posture_wing_color
	wing_mesh.material = wing_mat
	wing.mesh = wing_mesh
	wing.position = Vector3(0, 0, 0.2)
	wing.layers = ManeuverVisuals.SIDE_MARKER_LAYER
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


## The rendezvous target: a physically scaled station for the close-approach
## camera, plus a second, enlarged copy on the orbit camera's private marker
## layer. Scaling the physical model itself made the old 3 m placeholder become
## kilometers wide just when the player arrived at it.
func _build_station_markers() -> void:
	if _objective is not RendezvousObjective:
		return
	_station_marker = STATION_MODEL.instantiate()
	add_child(_station_marker)
	_station_orbit_marker = STATION_MODEL.instantiate()
	_set_visual_layer(_station_orbit_marker, ManeuverVisuals.SIDE_MARKER_LAYER)
	add_child(_station_orbit_marker)


func _set_visual_layer(root: Node, layer: int) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = layer
	for child in root.get_children():
		_set_visual_layer(child, layer)

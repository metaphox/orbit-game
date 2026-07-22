class_name CameraRig
extends RefCounted
## Owns the flight view's two cameras and their view state (TECH_DEBTS.md TD-2).
## The mouse-orbitable chase camera frames the ship itself; the "orbit view"
## side camera orbits the ship at orbital scale. Thanks to the floating origin
## the ship is always at render-space (0,0,0), so both cameras only ever pose
## themselves relative to that point. This class holds the yaw/pitch/zoom/
## azimuth/elevation state, turns drag/zoom input into it, and positions both
## cameras each frame. The Camera3D nodes live in ship_camera_rig.tscn; FlightView
## instantiates that scene and hands the two cameras to bind().

const DEFAULT_CAM_YAW := 0.0
const DEFAULT_CAM_PITCH := 0.0
const DEFAULT_CHASE_DISTANCE := 1.0
const DEFAULT_SIDE_AZIMUTH := 0.6
const DEFAULT_SIDE_ELEVATION := 0.5
const DEFAULT_SIDE_DISTANCE := 3.0e5

var chase_camera: Camera3D
var side_camera: Camera3D
var side_active := false  # which camera is current; drives the far-body proxy

var cam_yaw := DEFAULT_CAM_YAW
var cam_pitch := DEFAULT_CAM_PITCH
var chase_distance := DEFAULT_CHASE_DISTANCE
var side_azimuth := DEFAULT_SIDE_AZIMUTH
var side_elevation := DEFAULT_SIDE_ELEVATION
var side_distance := DEFAULT_SIDE_DISTANCE
var side_zoom_max := 1.6e6


## Wire up the two cameras from the instanced rig scene and give the chase
## camera its own short-range fill light. The world sun often sits behind a
## tail-following camera, which turned the small craft into a silhouette; a
## short-range fill affects only nearby hardware (never the kilometer-scale
## bodies) and reads like the chase rig's own inspection lamp.
func bind(chase: Camera3D, side: Camera3D) -> void:
	chase_camera = chase
	side_camera = side
	var chase_fill := OmniLight3D.new()
	chase_fill.light_color = Color(0.78, 0.86, 0.92)
	chase_fill.light_energy = 2.1
	chase_fill.omni_range = 22.0
	chase_fill.shadow_enabled = false
	chase_camera.add_child(chase_fill)


## Orbit-view zoom ceiling scales with the level's draw limit so distant
## targets stay reachable.
func configure(draw_limit: float) -> void:
	side_zoom_max = maxf(1.6e6, draw_limit * 1.4)


func set_side_active(active: bool) -> void:
	side_active = active
	if active:
		side_camera.make_current()
	else:
		chase_camera.make_current()


## Reset both cameras (chase-cam mouse-drag offset and the orbit-view
## rotation/zoom) back to their starting state.
func reset() -> void:
	cam_yaw = DEFAULT_CAM_YAW
	cam_pitch = DEFAULT_CAM_PITCH
	chase_distance = DEFAULT_CHASE_DISTANCE
	side_azimuth = DEFAULT_SIDE_AZIMUTH
	side_elevation = DEFAULT_SIDE_ELEVATION
	side_distance = DEFAULT_SIDE_DISTANCE


func chase_drag(relative: Vector2) -> void:
	cam_yaw = wrapf(cam_yaw - relative.x * 0.008, -PI, PI)
	cam_pitch = clampf(cam_pitch - relative.y * 0.008, -1.3, 1.3)


func side_drag(relative: Vector2) -> void:
	side_azimuth = wrapf(side_azimuth - relative.x * 0.008, -PI, PI)
	side_elevation = clampf(side_elevation + relative.y * 0.008, -1.45, 1.45)


func side_zoom(factor: float) -> void:
	side_distance = clampf(side_distance * factor, 9.0e4, side_zoom_max)


## Ship-detail-scale zoom for the chase camera, deliberately a much tighter
## range than side_zoom's orbital-scale one - this camera only ever needs to
## frame the ship itself, not a whole orbit.
func chase_zoom(factor: float) -> void:
	chase_distance = clampf(chase_distance * factor, 0.35, 3.5)


## Position both cameras around the floating origin for this frame.
## `scene_reach` is the farthest thing (bodies or draw limit) that must stay
## inside the orbit camera's far plane from any rotation angle.
func update(ship_attitude: Basis, scene_reach: float) -> void:
	# chase camera: ship-relative orbit, offset by mouse drag
	var chase_basis := ship_attitude \
		* Basis(Vector3(0, 1, 0), cam_yaw) * Basis(Vector3(1, 0, 0), cam_pitch)
	# A slight shoulder angle keeps the radiator silhouette and antenna
	# readable; a dead-center tail camera collapses the whole craft into the
	# dark engine bell.
	chase_camera.position = chase_basis * Vector3(4.2, 3.5, 11.0) * chase_distance
	chase_camera.look_at(Vector3.ZERO, chase_basis.y)

	# side camera: orbits and tracks the ship, which - thanks to the floating
	# origin - is always exactly at the render-space origin
	var side_basis := Basis(Vector3(0, 1, 0), side_azimuth) \
		* Basis(Vector3(1, 0, 0), -side_elevation)
	side_camera.position = side_basis * Vector3(0, 0, side_distance)
	side_camera.near = maxf(50.0, side_distance * 0.002)
	# Far must reach from the (possibly very distant) camera past the farthest
	# thing on screen, from ANY orbit angle - the camera sits side_distance from
	# the ship, and a body/target orbit can be that plus its own distance away on
	# the far side. Sizing to the real scene extent keeps the Sun, target planet
	# and target orbit from clipping in/out as you rotate.
	side_camera.far = side_distance + scene_reach * 1.25 + 1000.0
	side_camera.look_at(Vector3.ZERO, side_basis.y)

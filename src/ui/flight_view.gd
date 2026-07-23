class_name FlightView
extends Node3D
## The 3D world view. Floating origin: the ship renders at (0,0,0) and the
## world (all bodies) shifts around it, so float32 GPU precision never sees
## large coordinates. 1 render unit = 1 m. Placeholder art until M7.
##
## A thin orchestrator: it owns the environment (sky/sun/glow) and the shared
## ship-camera rig, and delegates the actual rendering to focused collaborators,
## each reading its look from the RenderTheme — BodyRenderer (celestial bodies),
## TrajectoryRenderer (forward path + target ring), ManeuverVisuals (node ghost +
## orbit marks), ShipVisuals (craft, markers, hologram, star dust) and CameraRig
## (the two cameras).

var _camera_rig := CameraRig.new()
var _theme: RenderTheme
var _body_renderer: BodyRenderer
var _traj_renderer: TrajectoryRenderer
var _maneuver: ManeuverVisuals
var _ship_visuals: ShipVisuals
var star_dust: StarDust  # exposed so game_root can freeze it when the sim pauses
## Hardcore (DESIGN.md §14.4) strips the predictive aids: the forward
## trajectory line and the maneuver-node preview ghost. The target ring stays.
var guidance_enabled := true
var _draw_limit := 4.0e5
var _sun_flare: SunFlare
## Bounding radius of the ship at the render origin, for eclipsing the sun flare.
const SHIP_OCCLUDE_RADIUS := 2.5


func build(level: LevelDef, theme: RenderTheme = null) -> void:
	_theme = theme if theme != null else RenderTheme.default()

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = _theme.sky_shader
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _theme.ambient_light_color
	env.ambient_light_energy = _theme.ambient_light_energy
	env.glow_enabled = true
	env.glow_bloom = _theme.glow_bloom
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation = _theme.sun_rotation
	sun.light_energy = _theme.sun_light_energy
	add_child(sun)

	_body_renderer = BodyRenderer.new()
	add_child(_body_renderer)
	_body_renderer.build(level, _theme)

	if _body_renderer.has_sun:
		sky_mat.set_shader_parameter("sun_direction", _body_renderer.sun_dir)
		sky_mat.set_shader_parameter("sun_wash", 1.0)
		var flare_layer := CanvasLayer.new()  # over the 3D view, under the HUD
		flare_layer.layer = 0
		add_child(flare_layer)
		_sun_flare = SunFlare.new()
		flare_layer.add_child(_sun_flare)

	var rig := preload("res://src/ui/ship_camera_rig.tscn").instantiate()
	add_child(rig)

	_draw_limit = level.draw_limit
	_camera_rig.configure(level.draw_limit)

	_traj_renderer = TrajectoryRenderer.new()
	add_child(_traj_renderer)
	_traj_renderer.build(level, _theme)

	_maneuver = ManeuverVisuals.new()
	add_child(_maneuver)
	_maneuver.build(level, _theme)

	_ship_visuals = ShipVisuals.new()
	add_child(_ship_visuals)
	_ship_visuals.build(level, rig.get_node("Ship"), rig.get_node("Ship/Flame"), _theme)
	star_dust = _ship_visuals.star_dust

	_camera_rig.bind(rig.get_node("ChaseCamera"), rig.get_node("SideCamera"))


func sync(ship: ShipSim, delta: float) -> void:
	var t := ship.last_time
	var ship_abs := ship.absolute_position(t)
	_body_renderer.sync(t, ship_abs, _camera_rig.side_active)
	_traj_renderer.sync(ship, ship_abs, t, guidance_enabled)
	_maneuver.sync(ship, delta, _camera_rig.side_distance, guidance_enabled)
	_ship_visuals.sync(ship, ship_abs, t, _camera_rig.side_distance)
	# Far-plane sizing needs the farthest body, so the camera updates last -
	# after BodyRenderer.sync has refreshed max_body_dist for this frame.
	var scene_reach := maxf(_body_renderer.max_body_dist, _draw_limit)
	_camera_rig.update(ship, scene_reach, delta)

	if _sun_flare != null:
		_update_sun_flare()


## Screen-space lens flare: project the sun to screen and set an intensity, unless
## it's behind the camera, off in the orbit view, or eclipsed by the root body.
func _update_sun_flare() -> void:
	var cam := _camera_rig.chase_camera
	if not _body_renderer.sun_visible or cam == null or not cam.is_current():
		_sun_flare.set_flare(Vector2.ZERO, 0.0)
		return
	var sun_pos := _body_renderer.sun_render_pos
	var cam_pos := cam.global_position
	var to_sun := (sun_pos - cam_pos).normalized()
	# Eclipsed by the root body (Earth) or by the ship (at the render origin)?
	# The sun disc itself is depth-occluded by both, so the flare must vanish too.
	if cam.is_position_behind(sun_pos) \
			or _ray_hits_sphere(cam_pos, to_sun, _body_renderer.root_render_pos, _body_renderer.root_radius) \
			or _ray_hits_sphere(cam_pos, to_sun, Vector3.ZERO, SHIP_OCCLUDE_RADIUS):
		_sun_flare.set_flare(Vector2.ZERO, 0.0)
		return
	var screen := cam.unproject_position(sun_pos)
	var vp := get_viewport().get_visible_rect().size
	var centred := 1.0 - clampf((screen - vp * 0.5).length() / maxf(vp.length() * 0.5, 1.0), 0.0, 1.0)
	_sun_flare.set_flare(screen, 0.4 + 0.6 * centred)


static func _ray_hits_sphere(origin: Vector3, dir: Vector3, centre: Vector3, radius: float) -> bool:
	var oc := origin - centre
	var b := oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var disc := b * b - c
	return disc >= 0.0 and -b - sqrt(disc) > 0.0


func mark_traj_dirty() -> void:
	_maneuver.mark_dirty()


## Camera control delegates to the CameraRig; kept here as FlightView's public
## surface so game_root drives the view without reaching into the rig.
func reset_view() -> void:
	_camera_rig.reset()


func set_side_active(active: bool) -> void:
	_camera_rig.set_side_active(active)


func chase_drag(relative: Vector2) -> void:
	_camera_rig.chase_drag(relative)


func side_drag(relative: Vector2) -> void:
	_camera_rig.side_drag(relative)


func side_zoom(factor: float) -> void:
	_camera_rig.side_zoom(factor)


func chase_zoom(factor: float) -> void:
	_camera_rig.chase_zoom(factor)

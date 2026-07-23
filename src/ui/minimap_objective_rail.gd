class_name MinimapObjectiveRail
extends VBoxContainer

@onready var objective_label: Label = %ObjectiveLabel
@onready var minimap_root: Control = %MinimapRoot
@onready var minimap_camera: Camera3D = %MinimapCamera
@onready var minimap_viewport: SubViewport = %MinimapViewport

var map_view: MapView
var _overlay: MinimapOverlay
var _zoom_auto := true
var _manual_size := 0.0
var _minimum_size := 1.0
var _maximum_size := 1.0e9


func _ready() -> void:
	%AutoButton.pressed.connect(func() -> void: _on_zoom("auto"))
	%ZoomInButton.pressed.connect(func() -> void: _on_zoom("in"))
	%ZoomOutButton.pressed.connect(func() -> void: _on_zoom("out"))


func configure(level: LevelDef) -> void:
	minimap_camera.size = level.map_extent
	_minimum_size = level.body.radius * 1.6 * MapView.MAP_SCALE
	_maximum_size = level.draw_limit * 2.6 * MapView.MAP_SCALE
	_manual_size = level.map_extent
	_zoom_auto = true
	minimap_camera.make_current()
	if Settings.effects_enabled:
		minimap_viewport.add_child(CrtOverlay.new())

	_overlay = MinimapOverlay.new()
	_overlay.font = UiTheme.MONO
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_root.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func refresh(ship: ShipSim, time: float) -> void:
	var target_size := _manual_size
	if _zoom_auto and map_view != null:
		target_size = map_view.auto_extent(ship, time)
	target_size = clampf(target_size, _minimum_size, _maximum_size)
	minimap_camera.size = lerpf(minimap_camera.size, target_size, 0.15)

	var camera_size := minimap_camera.size
	if map_view != null:
		map_view.minimap_ortho_size = camera_size
	var focus := map_view.focus_point(ship, time) if map_view != null else Vector3.ZERO
	var heading := (map_view.velocity_heading_angle(ship) + PI) if map_view != null else 0.0
	minimap_camera.position = focus + Basis(Vector3.UP, heading) * Vector3(
		0.0, camera_size * 0.9, camera_size * 0.42)
	minimap_camera.look_at(focus, Vector3.UP)
	minimap_camera.far = camera_size * 8.0 + focus.length() + 10.0

	if _overlay != null and map_view != null:
		_overlay.cam = minimap_camera
		_overlay.points = map_view.marked_points(ship, time)
		_overlay.queue_redraw()


func update_objective(ship: ShipSim, level: LevelDef) -> void:
	var lines: Array[String] = [level.objective.describe()]
	lines.append_array(level.objective.status_lines(ship))
	lines.append("PAR %.0f m/s" % level.dv_par)
	objective_label.text = "\n".join(lines)


func set_map_visible(shown: bool) -> void:
	%MapPanel.visible = shown


func _on_zoom(mode: String) -> void:
	match mode:
		"auto":
			_zoom_auto = true
		"in":
			if _zoom_auto:
				_manual_size = minimap_camera.size
			_zoom_auto = false
			_manual_size = maxf(_manual_size / 1.35, _minimum_size)
		"out":
			if _zoom_auto:
				_manual_size = minimap_camera.size
			_zoom_auto = false
			_manual_size = minf(_manual_size * 1.35, _maximum_size)

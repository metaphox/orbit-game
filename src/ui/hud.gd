class_name Hud
extends CanvasLayer
## Text HUD, green monospace on black — placeholder that already leans
## toward the CRT look. Shaders and real styling arrive in M7.

const GREEN := Color(0.45, 1.0, 0.55)
const DIM_GREEN := Color(0.3, 0.65, 0.38)
const RED := Color(1.0, 0.4, 0.3)

var status_label: Label
var objective_label: Label
var engine_label: Label
var help_label: Label
var center_label: Label
var minimap_root: Control
var _font: SystemFont
var _flash_label: Label
var _flash_left := 0.0
var _menu_label: Label


func build(level: LevelDef) -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	status_label = _label(Control.PRESET_TOP_LEFT, GREEN)
	objective_label = _label(Control.PRESET_TOP_RIGHT, GREEN)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# leave the top-right corner itself to the minimap
	objective_label.offset_top += 545
	objective_label.offset_bottom += 545
	engine_label = _label(Control.PRESET_BOTTOM_LEFT, GREEN)
	help_label = _label(Control.PRESET_BOTTOM_RIGHT, DIM_GREEN)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help_label.text = "\n".join([
		"W/S PITCH  A/D YAW  Q/E ROLL",
		"SHIFT/CTRL THROTTLE  Z MAX  X CUT",
		",/. TIME WARP  R RESTART  L MISSIONS",
		"TAB ORBIT VIEW  DRAG ROTATE  WHEEL ZOOM"])
	center_label = _label(Control.PRESET_CENTER, GREEN, 34)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.visible = false

	var title := _label(Control.PRESET_CENTER_TOP, DIM_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = level.title

	_flash_label = _label(Control.PRESET_CENTER_TOP, GREEN, 24)
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.offset_top += 44
	_flash_label.offset_bottom += 44
	_flash_label.visible = false

	_build_minimap(level)


func refresh(ship: ShipSim, level: LevelDef, sim_time: float, warp: int) -> void:
	var el := ship.current_elements()
	var state_text := "BURNING" if ship.flight_state == ShipSim.FlightState.BURNING else "COASTING"
	var ap := el.radius_apoapsis()
	var ap_text := "  ESCAPE" if not el.is_elliptic() else "%8.2f" % (ap / 1000.0)
	status_label.text = "\n".join([
		"T+ %s   WARP %dx" % [_clock(sim_time), warp],
		"SOI %s   ALT %8.2f km   VEL %7.1f m/s" % [
			ship.body.name, ship.altitude() / 1000.0, ship.speed()],
		"R-AP %s km   R-PE %8.2f km" % [ap_text, el.radius_periapsis() / 1000.0],
		"%s   OFF-PROGRADE %3.0f°" % [state_text, rad_to_deg(ship.off_prograde_angle())]])

	var lines: Array = ["OBJECTIVE", level.objective.describe()]
	lines.append_array(level.objective.status_lines(ship))
	lines.append("PAR %.0f m/s" % level.dv_par)
	objective_label.text = "\n".join(lines)

	engine_label.text = "\n".join([
		"THR  %s %3.0f%%" % [_bar(ship.throttle), ship.throttle * 100.0],
		"PROP %s %3.0f%%   Δv %5.1f   USED %5.1f" % [
			_bar(ship.prop_mass / level.prop_mass),
			100.0 * ship.prop_mass / level.prop_mass,
			ship.dv_remaining(), ship.dv_used()]])


func show_win(level: LevelDef, dv_used: float, has_next: bool) -> void:
	center_label.add_theme_color_override("font_color", GREEN)
	var lines := [
		"■ OBJECTIVE COMPLETE ■", "",
		"ΔV USED %.1f m/s — PAR %.0f" % [dv_used, level.dv_par],
		"MEDAL: %s" % level.medal(dv_used), "",
		"[R] FLY AGAIN"]
	if has_next:
		lines.append("[N] NEXT MISSION")
	center_label.text = "\n".join(lines)
	center_label.visible = true


## Temp mission-select overlay (replaced by the M6 campaign shell).
func toggle_level_menu(titles: Array) -> void:
	if _menu_label == null:
		_menu_label = _label(Control.PRESET_CENTER, GREEN, 24)
		_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _menu_label.visible:
		_menu_label.visible = false
		return
	var lines := ["■ SELECT MISSION ■", ""]
	for i in titles.size():
		lines.append("[%d] %s" % [i + 1, titles[i]])
	lines.append("")
	lines.append("[L] CLOSE")
	_menu_label.text = "\n".join(lines)
	_menu_label.visible = true


func flash(text: String) -> void:
	_flash_label.text = "■ %s ■" % text
	_flash_label.visible = true
	_flash_left = 2.5


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash_label.visible = false


func show_fail(reason: String) -> void:
	center_label.add_theme_color_override("font_color", RED)
	center_label.text = "\n".join(["■ %s ■" % reason, "", "[R] RESTART"])
	center_label.visible = true


## Picture-in-picture orbit map: a SubViewport sharing the main world with
## its own camera on the map layer, so it always mirrors the live map.
func _build_minimap(level: LevelDef) -> void:
	minimap_root = Control.new()
	minimap_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap_root)
	# pin to the top-right corner explicitly: 560x520, 12 px margin
	minimap_root.anchor_left = 1.0
	minimap_root.anchor_right = 1.0
	minimap_root.anchor_top = 0.0
	minimap_root.anchor_bottom = 0.0
	minimap_root.offset_left = -572.0
	minimap_root.offset_right = -12.0
	minimap_root.offset_top = 12.0
	minimap_root.offset_bottom = 532.0
	minimap_root.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap_root.grow_vertical = Control.GROW_DIRECTION_END

	var back := ColorRect.new()
	back.color = Color(0.0, 0.06, 0.02, 0.45)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_root.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_root.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = level.map_extent
	cam.near = 1.0
	cam.far = level.map_extent * 6.0
	cam.cull_mask = MapView.MAP_LAYER
	viewport.add_child(cam)
	cam.position = Vector3(0, level.map_extent * 0.9, level.map_extent * 0.42)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.make_current()


func set_minimap_visible(shown: bool) -> void:
	minimap_root.visible = shown


func _label(preset: int, color: Color, size := 19) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 4)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 14)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	return label


func _bar(frac: float) -> String:
	var filled := int(round(clampf(frac, 0.0, 1.0) * 10.0))
	return "[%s%s]" % ["█".repeat(filled), "░".repeat(10 - filled)]


func _clock(t: float) -> String:
	var total := int(t)
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]

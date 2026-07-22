class_name Hud
extends CanvasLayer
## Text HUD, green monospace on black — placeholder that already leans
## toward the CRT look. Shaders and real styling arrive in M7.

## Emitted by toolbar buttons; game_root routes this straight into its own
## _unhandled_input as a synthetic InputEventKey, so a click does exactly
## what the real key does with zero duplicated logic - same code path
## real key-presses and headless tests already use.
signal toolbar_key(keycode: int, pressed: bool)

# Colours sourced from the shared Palette (TD-1); names kept as local aliases
# for the many call sites. Font is UiTheme.MONO (IBM Plex Mono).
const GREEN := Palette.LIVE
const DIM_GREEN := Palette.LIVE_DIM
const AMBER := Palette.INTENT
const BONE := Palette.INK
const CONSOLE_BLACK := Color(0.02, 0.055, 0.035, 0.94)
const RED := Palette.WARNING

# [label, physical keycode, holdable]. Holdable buttons (throttle) fire on
# button_down/button_up like a held key; everything else taps press+release
# on a single click.
const TOOLBAR_GROUPS_ROW_1 := [
	["VIEW", [["TAB", KEY_TAB, false]]],
	["THRUST", [
		["SHIFT", KEY_SHIFT, true], ["CTRL", KEY_CTRL, true],
		["Z", KEY_Z, false], ["X", KEY_X, false]]],
	["SAS LOCK", [
		["F", KEY_F, false], ["B", KEY_B, false], ["N", KEY_N, false],
		["G", KEY_G, false], ["U", KEY_U, false], ["I", KEY_I, false],
		["T", KEY_T, false]]],
	["WARP", [["+", KEY_EQUAL, false], ["-", KEY_MINUS, false]]],
]
const TOOLBAR_GROUPS_ROW_2 := [
	["MANEUVER", [
		["ENTER", KEY_ENTER, false], ["BKSP", KEY_BACKSPACE, false],
		["[", KEY_BRACKETLEFT, false], ["]", KEY_BRACKETRIGHT, false]]],
	["VECTOR", [
		["↑", KEY_UP, false], ["↓", KEY_DOWN, false],
		["←", KEY_LEFT, false], ["→", KEY_RIGHT, false],
		["O", KEY_O, false], ["P", KEY_P, false]]],
	["GUIDANCE", [["V", KEY_V, false]]],
]

var status_label: Label
var objective_label: Label
var engine_label: Label
var help_label: Label
var center_label: Label
var minimap_root: Control
var warp_label: Label
var _font: Font
var _flash_label: Label
var _flash_left := 0.0
var _paused_label: Label
var _rewind_label: Label  # top-center: persistent charge pips + the scrub panel
var _rewind_timeline: RewindTimeline
var _toolbar_buttons: Dictionary = {}
var _minimap_aspect: AspectRatioContainer
var _right_column: VBoxContainer
var _minimap_cam: Camera3D
var _minimap_overlay: MinimapOverlay
var _minimap_zoom_auto := true
var _minimap_manual_size := 0.0
var _minimap_min_size := 1.0
var _minimap_max_size := 1.0e9
## Set by game_root after both are built; the minimap needs it for auto-fit,
## the parent-centred focus, and the marked-point list.
var map_view: MapView
var _fps_label: Label


## Everything static and single-instance (status/objective/engine/help/
## center/title/flash/paused labels, the minimap) lives in hud_layout.tscn
## and just gets its node references grabbed here; the toolbar stays
## code-built since its content is data-driven from TOOLBAR_GROUPS_ROW_1/2,
## not a fixed set of nodes a scene can pre-author.
func build(level: LevelDef) -> void:
	_font = UiTheme.MONO

	var layout := preload("res://src/ui/hud_layout.tscn").instantiate()
	add_child(layout)

	status_label = layout.get_node("StatusLabel")
	engine_label = layout.get_node("EngineLabel")
	help_label = layout.get_node("HelpLabel")
	center_label = layout.get_node("CenterLabel")
	var title: Label = layout.get_node("TitleLabel")
	_flash_label = layout.get_node("FlashLabel")
	_paused_label = layout.get_node("PausedLabel")
	objective_label = layout.get_node("RightColumn/ObjectiveLabel")
	warp_label = layout.get_node("RightColumn/WarpLabel")
	_right_column = layout.get_node("RightColumn")
	_minimap_aspect = layout.get_node("RightColumn/MinimapAspect")
	minimap_root = layout.get_node("RightColumn/MinimapAspect/MinimapRoot")

	var help_lines: Array[String] = [
		"%s/%s PITCH  %s/%s YAW  %s/%s ROLL" % [
			_key_label("pitch_down"), _key_label("pitch_up"),
			_key_label("yaw_left"), _key_label("yaw_right"),
			_key_label("roll_left"), _key_label("roll_right")],
		"%s/%s THROTTLE  %s MAX  %s CUT" % [
			_key_label("throttle_increase"), _key_label("throttle_decrease"),
			_key_label("throttle_full"), _key_label("throttle_cut")],
		"1-9 WARP LEVEL  %s/%s WARP STEP" % [
			_key_label("warp_decrease"), _key_label("warp_increase")],
		"%s PAUSE  %s PAUSE MENU  %s RESET VIEW" % [
			_key_label("quick_pause"), _key_label("pause_menu"), _key_label("reset_or_restart")],
		"%s ORBIT VIEW  DRAG ROTATE  WHEEL/TRACKPAD ZOOM" % _key_label("toggle_side_camera")]
	if level.sas_enabled:
		help_lines.append("SAS: %s PRO  %s RETRO  %s NORM  %s ANTI  %s/%s RADIAL  %s OFF" % [
			_key_label("sas_prograde"), _key_label("sas_retrograde"), _key_label("sas_normal"),
			_key_label("sas_antinormal"), _key_label("sas_radial_out"), _key_label("sas_radial_in"),
			_key_label("sas_off")])
	if level.nodes_enabled:
		help_lines.append("NODE: %s ADD  %s DEL  %s/%s TIME  %s/%s PRO  %s/%s NORM  %s/%s RAD" % [
			_key_label("node_create"), _key_label("node_delete"),
			_key_label("node_time_earlier"), _key_label("node_time_later"),
			_key_label("node_prograde_increase"), _key_label("node_prograde_decrease"),
			_key_label("node_normal_increase"), _key_label("node_normal_decrease"),
			_key_label("node_radial_increase"), _key_label("node_radial_decrease")])
		help_lines.append("      SHIFT = COARSE   %s HOLD NODE" % _key_label("sas_node_hold"))
	help_label.text = "\n".join(help_lines)
	title.text = level.title

	_rewind_label = Label.new()
	_rewind_label.add_theme_font_override("font", _font)
	_rewind_label.add_theme_font_size_override("font_size", 16)
	_rewind_label.add_theme_color_override("font_color", AMBER)
	_rewind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rewind_label.visible = false
	add_child(_rewind_label)
	# Low-centre band, clear of the top-left status block, the title, the
	# top-right minimap, and the bottom toolbar.
	_rewind_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_rewind_label.offset_top = 588

	_rewind_timeline = RewindTimeline.new()
	_rewind_timeline.font = _font
	_rewind_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat camera drags
	_rewind_timeline.custom_minimum_size = Vector2(780, 80)
	_rewind_timeline.visible = false
	add_child(_rewind_timeline)
	_rewind_timeline.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 498)

	_finish_minimap(level)
	get_viewport().size_changed.connect(_update_minimap_size)
	_build_toolbar()
	if Settings.debug_mode:
		_build_fps_label()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())  # drawn last: whole-screen film grade on top


func refresh(ship: ShipSim, level: LevelDef, sim_time: float, warp: int) -> void:
	_sync_minimap_camera(ship, sim_time)

	var el := ship.current_elements()
	var state_text := "BURNING" if ship.flight_state == ShipSim.FlightState.BURNING else "COASTING"
	var ap := el.radius_apoapsis()
	var ap_text := "  ESCAPE" if not el.is_elliptic() else "%8.2f" % (ap / 1000.0)
	status_label.text = "\n".join([
		"T+ %s   WARP %dx" % [_clock(sim_time), warp],
		"SOI %s   ALT %8.2f km   VEL %7.1f m/s" % [
			ship.body.name, ship.altitude() / 1000.0, ship.speed()],
		"R-AP %s km   R-PE %8.2f km" % [ap_text, el.radius_periapsis() / 1000.0],
		"%s   OFF-PROGRADE %3.0f°   SAS %s" % [
			state_text, rad_to_deg(ship.off_prograde_angle()),
			ShipSim.SAS_NAMES[ship.sas_mode]]])

	var lines: Array[String] = ["OBJECTIVE", level.objective.describe()]
	lines.append_array(level.objective.status_lines(ship))
	lines.append("PAR %.0f m/s" % level.dv_par)
	objective_label.text = "\n".join(lines)

	var engine_lines := [
		"THR  %s %3.0f%%" % [_bar(ship.throttle), ship.throttle * 100.0],
		"PROP %s %3.0f%%   Δv %5.1f   USED %5.1f" % [
			_bar(ship.prop_mass / level.prop_mass),
			100.0 * ship.prop_mass / level.prop_mass,
			ship.dv_remaining(), ship.dv_used()]]
	if ship.node != null:
		var dv := ship.node.total_dv()
		var exhaust_v := ship.isp * Integrator.G0
		var burn_time := ship.mass() * (1.0 - exp(-dv / exhaust_v)) \
			/ (ship.thrust_max / exhaust_v)
		engine_lines.append(
			"NODE Δv %5.1f   T%+7.0fs   BURN %3.0fs   REM %5.1f" % [
				dv, sim_time - ship.node.t_node, burn_time,
				ship.node.remaining.length()])
	engine_label.text = "\n".join(engine_lines)

	warp_label.text = "TIME WARP: %dx" % warp
	_sync_toolbar_state(ship)


## The whole rewind readout: game_root composes the text (persistent charge
## pips while flying, or the full scrub panel while REWINDING) and this just
## displays it. Empty string hides it.
func set_rewind_line(text: String) -> void:
	if _rewind_label == null:
		return
	_rewind_label.text = text
	_rewind_label.visible = text != ""


func update_rewind_timeline(
		t_start: float, t_now: float, playhead: float, cursor: int,
		anchors: Array, landmarks: Array) -> void:
	_rewind_timeline.t_start = t_start
	_rewind_timeline.t_now = t_now
	_rewind_timeline.playhead = playhead
	_rewind_timeline.cursor = cursor
	_rewind_timeline.anchors = anchors
	_rewind_timeline.landmarks = landmarks
	_rewind_timeline.visible = true
	_rewind_timeline.queue_redraw()


func hide_rewind_timeline() -> void:
	if _rewind_timeline != null:
		_rewind_timeline.visible = false


func show_win(level: LevelDef, dv_used: float, has_next: bool, clean := false) -> void:
	center_label.add_theme_color_override("font_color", GREEN)
	var medal_line := "MEDAL: %s" % level.medal(dv_used)
	if clean:
		medal_line += "   ◇ CLEAN"
	var lines := [
		"■ OBJECTIVE COMPLETE ■", "",
		"ΔV USED %.1f m/s — PAR %.0f" % [dv_used, level.dv_par],
		medal_line, "",
		"[R] FLY AGAIN"]
	if has_next:
		lines.append("[N] NEXT MISSION")
	center_label.text = "\n".join(lines)
	center_label.visible = true


func flash(text: String) -> void:
	_flash_label.text = "■ %s ■" % text
	_flash_label.visible = true
	_flash_left = 2.5


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash_label.visible = false
	if _fps_label != null:
		_fps_label.text = "FPS %d" % Engine.get_frames_per_second()


## Debug-mode-only readout (Settings.debug_mode), top-left corner clear of
## StatusLabel (which starts at y=14) - not part of hud_layout.tscn since
## it's a dev aid, not a player-facing HUD element.
func _build_fps_label() -> void:
	_fps_label = Label.new()
	_fps_label.add_theme_font_override("font", _font)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", AMBER)
	add_child(_fps_label)
	_fps_label.position = Vector2(14, 0)


func show_fail(reason: String, rewinds_left := 0) -> void:
	center_label.add_theme_color_override("font_color", RED)
	var lines := ["■ %s ■" % reason, ""]
	if rewinds_left > 0:
		lines.append("[Z] REWIND — %d LEFT" % rewinds_left)
	lines.append("[R] RESTART")
	center_label.text = "\n".join(lines)
	center_label.visible = true


## The minimap's node structure (SubViewport + camera) comes from
## hud_layout.tscn already; only the level-dependent camera framing (extent
## varies per level) and the effects-conditional CRT overlay need setting
## up here, same as before this was a scene.
func _finish_minimap(level: LevelDef) -> void:
	var viewport: SubViewport = minimap_root.get_node("SubViewportContainer/SubViewport")
	_minimap_cam = viewport.get_node("Camera3D")
	_minimap_cam.size = level.map_extent
	# Zoom clamps: from roughly the body's surface out to the draw limit.
	_minimap_min_size = level.body.radius * 1.6 * MapView.MAP_SCALE
	_minimap_max_size = level.draw_limit * 2.6 * MapView.MAP_SCALE
	_minimap_manual_size = level.map_extent
	_minimap_zoom_auto = true
	_minimap_cam.make_current()
	if Settings.effects_enabled:
		viewport.add_child(CrtOverlay.new())  # last child: composites over the 3D render

	# 2D marker/label overlay, above the SubViewport render.
	_minimap_overlay = MinimapOverlay.new()
	_minimap_overlay.font = _font
	_minimap_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_root.add_child(_minimap_overlay)
	_minimap_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_minimap_zoom_controls()

	# The old flat 0.45-alpha near-black tint was nearly indistinguishable
	# from the space background behind it - brightened here so the panel
	# actually reads as a console backdrop instead of just vanishing.
	var back: ColorRect = minimap_root.get_node("Back")
	back.color = Color(0.03, 0.22, 0.12, 0.55)
	var panel_mat := ShaderMaterial.new()
	panel_mat.shader = preload("res://src/shaders/minimap_panel.gdshader")
	back.material = panel_mat

	_update_minimap_size()


## Caps the minimap to a modest, resolution-independent fraction of the
## screen instead of the fixed 560x520 the layout scene bakes in as a
## pre-first-layout default - a small starting window otherwise lets the
## minimap dominate the view.
func _update_minimap_size() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := clampf(vp.x * 0.22, 220.0, 340.0)
	_minimap_aspect.custom_minimum_size = Vector2(w, w / _minimap_aspect.ratio)
	_right_column.custom_minimum_size.x = w


## Per-frame minimap framing: centre on the current parent body, heading-up,
## at the AUTO-fit or manual zoom (eased). Also feeds the marker overlay.
func _sync_minimap_camera(ship: ShipSim, t: float) -> void:
	if _minimap_cam == null:
		return
	var target_size := _minimap_manual_size
	if _minimap_zoom_auto and map_view != null:
		target_size = map_view.auto_extent(ship, t)
	target_size = clampf(target_size, _minimap_min_size, _minimap_max_size)
	_minimap_cam.size = lerpf(_minimap_cam.size, target_size, 0.15)

	var s := _minimap_cam.size
	if map_view != null:
		map_view.minimap_ortho_size = s  # markers scale off this to stay constant on-screen
	var focus := map_view.focus_point(ship, t) if map_view != null else Vector3.ZERO
	# Prograde-up: velocity points to the top of the map (stable regardless of
	# attitude), so the ship glyph can show where the nose actually points. The
	# +PI puts the velocity vector at the top (not the bottom) of the panel.
	var heading := (map_view.velocity_heading_angle(ship) + PI) if map_view != null else 0.0
	_minimap_cam.position = focus + Basis(Vector3.UP, heading) * Vector3(0.0, s * 0.9, s * 0.42)
	_minimap_cam.look_at(focus, Vector3.UP)
	_minimap_cam.far = s * 8.0 + focus.length() + 10.0

	if _minimap_overlay != null and map_view != null:
		_minimap_overlay.cam = _minimap_cam
		_minimap_overlay.points = map_view.marked_points(ship, t)
		_minimap_overlay.queue_redraw()


func _build_minimap_zoom_controls() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	minimap_root.add_child(row)
	row.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 7)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_minimap_button("AUTO", 42, func() -> void: _on_minimap_zoom("auto"), row)
	_minimap_button("+", 24, func() -> void: _on_minimap_zoom("in"), row)
	_minimap_button("−", 24, func() -> void: _on_minimap_zoom("out"), row)


func _minimap_button(text: String, width: float, on_press: Callable, row: HBoxContainer) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 22)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", GREEN)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.add_theme_color_override("font_pressed_color", AMBER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.03, 0.88)
	sb.set_border_width_all(1)
	sb.border_color = Color(DIM_GREEN, 0.85)
	sb.set_content_margin_all(2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(on_press)
	row.add_child(b)


func _on_minimap_zoom(mode: String) -> void:
	match mode:
		"auto":
			_minimap_zoom_auto = true
		"in":
			if _minimap_zoom_auto:
				_minimap_manual_size = _minimap_cam.size
			_minimap_zoom_auto = false
			_minimap_manual_size = maxf(_minimap_manual_size / 1.35, _minimap_min_size)
		"out":
			if _minimap_zoom_auto:
				_minimap_manual_size = _minimap_cam.size
			_minimap_zoom_auto = false
			_minimap_manual_size = minf(_minimap_manual_size * 1.35, _minimap_max_size)


## Static reference strip of the non-warp keybinds (1-9 warp levels are
## covered by the warp indicator, not repeated here). A plain CanvasLayer
## overlay isn't tied to either Camera3D, so this shows in the chase view
## and the orbit view (TAB) alike with no extra wiring. Letters only for
## now; state highlighting (e.g. which SAS mode is active) can follow.
## Real clickable buttons (not a text label) for every non-warp keybind:
## the mode/hold cluster plus the maneuver-node editing cluster. Clicking
## one taps (or holds, for SHIFT/CTRL throttle) the matching physical key
## via toolbar_key - see the signal doc for why that's the whole
## integration surface.
func _build_toolbar() -> void:
	var console := PanelContainer.new()
	console.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(console)
	console.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
	console.grow_horizontal = Control.GROW_DIRECTION_BOTH
	console.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var console_style := StyleBoxFlat.new()
	console_style.bg_color = CONSOLE_BLACK
	console_style.set_border_width_all(1)
	console_style.border_color = Color(DIM_GREEN, 0.72)
	console_style.corner_radius_top_left = 5
	console_style.corner_radius_top_right = 5
	console_style.corner_radius_bottom_left = 2
	console_style.corner_radius_bottom_right = 2
	console_style.set_content_margin_all(6)
	console.add_theme_stylebox_override("panel", console_style)

	var toolbar := VBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console.add_child(toolbar)
	_build_toolbar_row(toolbar, TOOLBAR_GROUPS_ROW_1)
	_build_toolbar_row(toolbar, TOOLBAR_GROUPS_ROW_2)


func _build_toolbar_row(parent: Control, groups: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	for group: Array in groups:
		row.add_child(_make_toolbar_group(group[0], group[1]))


func _make_toolbar_group(title: String, entries: Array) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.065, 0.048, 0.82)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.18, 0.38, 0.29, 0.9)
	panel_style.corner_radius_top_left = 2
	panel_style.corner_radius_top_right = 2
	panel_style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stack)

	var heading := Label.new()
	heading.text = "▰  " + title
	heading.add_theme_font_override("font", _font)
	heading.add_theme_font_size_override("font_size", 9)
	heading.add_theme_color_override("font_color", AMBER)
	stack.add_child(heading)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(buttons)
	for entry: Array in entries:
		buttons.add_child(_make_toolbar_button(entry[0], entry[1], entry[2]))
	return panel


func _make_toolbar_button(label: String, keycode: int, holdable: bool) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 26)
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 13)
	button.focus_mode = Control.FOCUS_NONE  # never steals keyboard focus from flying
	if keycode in [KEY_F, KEY_B, KEY_N, KEY_G, KEY_U, KEY_I, KEY_T, KEY_V]:
		button.toggle_mode = true
	_style_toolbar_button(button)
	if not _toolbar_buttons.has(keycode):
		_toolbar_buttons[keycode] = []
	(_toolbar_buttons[keycode] as Array).append(button)
	if holdable:
		button.button_down.connect(func() -> void: toolbar_key.emit(keycode, true))
		button.button_up.connect(func() -> void: toolbar_key.emit(keycode, false))
	else:
		button.pressed.connect(func() -> void:
			toolbar_key.emit(keycode, true)
			toolbar_key.emit(keycode, false))
	return button


func _style_toolbar_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.018, 0.055, 0.04, 0.96)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.25, 0.48, 0.34, 0.9)
	normal.corner_radius_top_left = 2
	normal.corner_radius_top_right = 2
	normal.corner_radius_bottom_left = 1
	normal.corner_radius_bottom_right = 1
	normal.set_content_margin_all(4)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	var hover := normal.duplicate()
	hover.bg_color = Color(0.04, 0.19, 0.105, 0.98)
	hover.border_color = GREEN
	var pressed_style := normal.duplicate()
	pressed_style.bg_color = Color(0.34, 0.17, 0.025, 0.98)
	pressed_style.border_color = AMBER

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("hover_pressed", pressed_style)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_color_override("font_color", BONE)
	button.add_theme_color_override("font_hover_color", GREEN)
	button.add_theme_color_override("font_pressed_color", AMBER)
	button.add_theme_color_override("font_hover_pressed_color", AMBER)


func _sync_toolbar_state(ship: ShipSim) -> void:
	var active_modes := {
		KEY_F: ShipSim.SasMode.PROGRADE,
		KEY_B: ShipSim.SasMode.RETROGRADE,
		KEY_N: ShipSim.SasMode.NORMAL,
		KEY_G: ShipSim.SasMode.ANTI_NORMAL,
		KEY_U: ShipSim.SasMode.RADIAL_OUT,
		KEY_I: ShipSim.SasMode.RADIAL_IN,
		KEY_T: ShipSim.SasMode.OFF,
		KEY_V: ShipSim.SasMode.NODE,
	}
	for keycode: int in active_modes:
		var active: bool = ship.sas_mode == active_modes[keycode]
		for button: Button in _toolbar_buttons.get(keycode, []):
			button.set_pressed_no_signal(active)


func set_paused_indicator(shown: bool) -> void:
	_paused_label.visible = shown


func set_minimap_visible(shown: bool) -> void:
	minimap_root.visible = shown


## Human-readable key name(s) actually bound to an InputMap action,
## uppercased to match the HUD's all-caps style and joined with "/" for
## multi-key actions (e.g. quick_pause is bound to both Space and 0).
## Generated from the live bindings rather than hardcoded, so the help
## text can't drift out of sync with project.godot's [input] section -
## including once a remap UI exists on top of this (not built yet).
func _key_label(action: String) -> String:
	var parts: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			parts.append(OS.get_keycode_string((event as InputEventKey).physical_keycode).to_upper())
	return "/".join(parts)


func _bar(frac: float) -> String:
	var filled := int(round(clampf(frac, 0.0, 1.0) * 10.0))
	return "[%s%s]" % ["█".repeat(filled), "░".repeat(10 - filled)]


func _clock(t: float) -> String:
	var total := int(t)
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]

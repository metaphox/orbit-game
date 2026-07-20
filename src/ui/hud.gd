class_name Hud
extends CanvasLayer
## Text HUD, green monospace on black — placeholder that already leans
## toward the CRT look. Shaders and real styling arrive in M7.

## Emitted by toolbar buttons; game_root routes this straight into its own
## _unhandled_input as a synthetic InputEventKey, so a click does exactly
## what the real key does with zero duplicated logic - same code path
## real key-presses and headless tests already use.
signal toolbar_key(keycode: int, pressed: bool)

const GREEN := Color(0.45, 1.0, 0.55)
const DIM_GREEN := Color(0.3, 0.65, 0.38)
const AMBER := Color(1.0, 0.67, 0.2)
const BONE := Color(0.86, 0.84, 0.72)
const CONSOLE_BLACK := Color(0.008, 0.025, 0.02, 0.94)
const RED := Color(1.0, 0.4, 0.3)

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
var _font: SystemFont
var _flash_label: Label
var _flash_left := 0.0
var _paused_label: Label
var _toolbar_buttons: Dictionary = {}


## Everything static and single-instance (status/objective/engine/help/
## center/title/flash/paused labels, the minimap) lives in hud_layout.tscn
## and just gets its node references grabbed here; the toolbar stays
## code-built since its content is data-driven from TOOLBAR_GROUPS_ROW_1/2,
## not a fixed set of nodes a scene can pre-author.
func build(level: LevelDef) -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

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

	_finish_minimap(level)
	_build_toolbar()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())  # drawn last: whole-screen film grade on top


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


## The minimap's node structure (SubViewport + camera) comes from
## hud_layout.tscn already; only the level-dependent camera framing (extent
## varies per level) and the effects-conditional CRT overlay need setting
## up here, same as before this was a scene.
func _finish_minimap(level: LevelDef) -> void:
	var viewport: SubViewport = minimap_root.get_node("SubViewportContainer/SubViewport")
	var cam: Camera3D = viewport.get_node("Camera3D")
	cam.size = level.map_extent
	cam.far = level.map_extent * 6.0
	cam.position = Vector3(0, level.map_extent * 0.9, level.map_extent * 0.42)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.make_current()
	if Settings.effects_enabled:
		viewport.add_child(CrtOverlay.new())  # last child: composites over the 3D render


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
	for group in groups:
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
	for entry in entries:
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
		button.button_down.connect(func(): toolbar_key.emit(keycode, true))
		button.button_up.connect(func(): toolbar_key.emit(keycode, false))
	else:
		button.pressed.connect(func():
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

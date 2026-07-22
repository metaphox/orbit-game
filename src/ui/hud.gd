class_name Hud
extends CanvasLayer
## NASA-punk "ORBITAL OS" flight HUD (ref/hud-ref.html): a top telemetry bar,
## left/right instrument rails, a bottom fuel/throttle strip, a functional
## attitude director, and every non-flying state (win/fail/pause/flash/keys)
## styled from the shared Palette/UiTheme — one colour source (TD-1).

## Emitted by toolbar buttons; game_root routes this straight into its own
## _unhandled_input as a synthetic InputEventKey, so a click does exactly what
## the real key does with zero duplicated logic.
signal toolbar_key(keycode: int, pressed: bool)

const GREEN := Palette.LIVE
const AMBER := Palette.INTENT
const CYAN := Palette.TARGET
const RED := Palette.WARNING
const BONE := Palette.INK
const DIMC := Palette.DIM

# Display-only mirror of game_root.WARP_STEPS, used to fill the warp bar-graph.
const WARP_STEPS := [1, 5, 10, 25, 50, 100, 200, 500, 1000]

# Bottom-strip clickable chips [label, physical keycode, holdable]: the ref's
# compact SAS / WARP / NODE quick-access row. The full keybind reference lives in
# the F1 overlay (text); power controls stay keyboard, matching the mock.
const STRIP_GROUPS := [
	["SAS", [
		["F", KEY_F, false], ["B", KEY_B, false], ["N", KEY_N, false],
		["G", KEY_G, false], ["T", KEY_T, false]]],
	["WARP", [["+", KEY_EQUAL, false], ["-", KEY_MINUS, false]]],
	["NODE", [["ENTER", KEY_ENTER, false], ["BKSP", KEY_BACKSPACE, false]]],
]

# --- fields read by game_root / tests (contract; keep the names) ---
var objective_label: Label
var help_label: Label
var center_label: Control       # win/fail banner panel (game_root sets .visible=false)
var minimap_root: Control
var warp_label: Label
var _fps_label: Label
## Set by game_root after both are built; the minimap needs it for auto-fit,
## the parent-centred focus, and the marked-point list.
var map_view: MapView

# --- top bar ---
var _v_met: Label
var _v_warp: Label
var _v_soi: Label
var _v_alt: Label
var _v_vel: Label
var _v_rap: Label
var _v_rpe: Label
var _burn_dot: ColorRect
var _burn_label: Label
var _offpro_label: Label
var _sas_label: Label
var _burning := false

# --- right rail ---
var _guidance: AttitudeDirector
var _guid_head: Label
var _v_acc: Label
var _v_gvel: Label
var _v_dv: Label
var _warp_meter: BarMeter

# --- bottom strip ---
var _thr_meter: BarMeter
var _thr_pct: Label
var _prop_meter: BarMeter
var _prop_pct: Label
var _prop_extra: Label
var _node_label: Label

# --- overlays / transient ---
var _flash_panel: PanelContainer
var _flash_label: Label
var _flash_left := 0.0
var _paused_panel: Control
var _keys_panel: Control
var _banner_title: Label
var _banner_body: Label
var _banner_prompt: Label

# --- rewind ---
var _rewind_label: Label
var _rewind_timeline: RewindTimeline

# --- toolbar ---
var _toolbar_buttons: Dictionary = {}

# --- minimap ---
var _font: Font
var _minimap_aspect: AspectRatioContainer
var _minimap_cam: Camera3D
var _minimap_overlay: MinimapOverlay
var _minimap_zoom_auto := true
var _minimap_manual_size := 0.0
var _minimap_min_size := 1.0
var _minimap_max_size := 1.0e9


func build(level: LevelDef) -> void:
	_font = UiTheme.MONO
	var layout := preload("res://src/ui/hud_layout.tscn").instantiate()
	add_child(layout)
	_minimap_aspect = layout.get_node("MinimapAspect")
	minimap_root = layout.get_node("MinimapAspect/MinimapRoot")

	_build_top_bar(level)
	_build_left_rail(level)
	_build_right_rail(level)
	_build_bottom_strip(level)
	_build_rewind_widgets()
	_build_banner()
	_build_flash()
	_build_paused()
	_build_keys_overlay(level)
	_finish_minimap(level)

	if Settings.debug_mode:
		_build_fps_label()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())  # drawn last: whole-screen film grade on top


# ══════════════════════════════════════════════════ TOP BAR ══

func _build_top_bar(level: LevelDef) -> void:
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 46

	var bg := ColorRect.new()
	bg.color = Color(0.016, 0.027, 0.02, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rule := ColorRect.new()
	rule.color = Palette.HAIRLINE
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(rule)
	rule.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	rule.offset_top = -2

	# left group: MET block + telemetry cells
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(left)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)

	left.add_child(_met_block())
	_v_warp = _stat_into(left, "WARP", AMBER)
	_v_soi = _stat_into(left, "SOI", BONE)
	_v_alt = _stat_into(left, "ALT", GREEN)
	_v_vel = _stat_into(left, "VEL", GREEN)
	_v_rap = _stat_into(left, "R-AP", GREEN)
	_v_rpe = _stat_into(left, "R-PE", GREEN)

	# right group: status cluster
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.alignment = BoxContainer.ALIGNMENT_END

	var burn := HBoxContainer.new()
	burn.add_theme_constant_override("separation", 8)
	burn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	burn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burn_dot = ColorRect.new()
	_burn_dot.color = AMBER
	_burn_dot.custom_minimum_size = Vector2(9, 9)
	_burn_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	burn.add_child(_burn_dot)
	_burn_label = _bar_text("COAST", AMBER, 12)
	burn.add_child(_burn_label)
	right.add_child(_wrap_cell(burn))
	right.add_child(_sep())
	_offpro_label = _bar_text("OFF-PRO 0°", AMBER, 12)
	right.add_child(_wrap_cell(_offpro_label))
	right.add_child(_sep())
	var sas_wrap := PanelContainer.new()
	sas_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sas_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sas_box := StyleBoxFlat.new()
	sas_box.bg_color = Palette.INTENT_DK
	sas_box.set_content_margin(SIDE_LEFT, 14)
	sas_box.set_content_margin(SIDE_RIGHT, 14)
	sas_box.set_content_margin(SIDE_TOP, 8)
	sas_box.set_content_margin(SIDE_BOTTOM, 8)
	sas_wrap.add_theme_stylebox_override("panel", sas_box)
	_sas_label = _bar_text("SAS OFF", AMBER, 12)
	sas_wrap.add_child(_sas_label)
	right.add_child(sas_wrap)

	# center: title chip
	_build_title_chip(bar, level)


func _met_block() -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = GREEN
	box.set_content_margin(SIDE_LEFT, 16)
	box.set_content_margin(SIDE_RIGHT, 18)
	box.set_content_margin(SIDE_TOP, 6)
	box.set_content_margin(SIDE_BOTTOM, 6)
	panel.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var eb := Label.new()
	eb.text = "MET"
	eb.add_theme_font_override("font", UiTheme.MONO_SEMI)
	eb.add_theme_font_size_override("font_size", 9)
	eb.add_theme_color_override("font_color", Palette.VOID)
	col.add_child(eb)
	_v_met = Label.new()
	_v_met.text = "T+ 00:00:00"
	_v_met.add_theme_font_override("font", UiTheme.MONO_SEMI)
	_v_met.add_theme_font_size_override("font_size", 21)
	_v_met.add_theme_color_override("font_color", Palette.VOID)
	col.add_child(_v_met)
	return panel


func _stat_into(parent: HBoxContainer, label: String, color: Color) -> Label:
	var d := UiTheme.stat_cell(label, color)
	parent.add_child(_wrap_cell(d["root"]))
	parent.add_child(_sep())
	return d["value"]


## Vertically-centre a cell inside the top bar and pad it horizontally.
func _wrap_cell(inner: Control) -> Control:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_child(inner)
	return m


func _sep() -> ColorRect:
	var s := ColorRect.new()
	s.color = Palette.HAIRLINE
	s.custom_minimum_size = Vector2(1, 30)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _bar_text(text: String, color: Color, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.MONO_SEMI)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", color)
	return l


func _build_title_chip(bar: Control, level: LevelDef) -> void:
	var parts := level.title.split(":")
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.035, 0.024, 0.6)
	box.set_border_width_all(1)
	box.border_color = Palette.HAIRLINE
	box.border_width_top = 0
	box.set_content_margin(SIDE_LEFT, 22)
	box.set_content_margin(SIDE_RIGHT, 22)
	box.set_content_margin(SIDE_TOP, 7)
	box.set_content_margin(SIDE_BOTTOM, 7)
	panel.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var act := Label.new()
	act.text = parts[0].strip_edges().to_upper()
	act.add_theme_font_override("font", UiTheme.DISPLAY_SEMI)
	act.add_theme_font_size_override("font_size", 15)
	act.add_theme_color_override("font_color", BONE)
	row.add_child(act)
	if parts.size() > 1:
		var dot := Label.new()
		dot.text = "·"
		dot.add_theme_font_override("font", UiTheme.DISPLAY_SEMI)
		dot.add_theme_font_size_override("font_size", 15)
		dot.add_theme_color_override("font_color", DIMC)
		row.add_child(dot)
		var obj := Label.new()
		obj.text = parts[1].strip_edges().to_upper()
		obj.add_theme_font_override("font", UiTheme.DISPLAY_SEMI)
		obj.add_theme_font_size_override("font_size", 15)
		obj.add_theme_color_override("font_color", GREEN)
		row.add_child(obj)
	bar.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH


# ══════════════════════════════════════════════════ LEFT RAIL ══

func _build_left_rail(level: LevelDef) -> void:
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 12)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rail)
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	rail.offset_left = 14
	rail.offset_top = 58
	rail.custom_minimum_size = Vector2(300, 0)

	# ORBIT MAP card: header (chip + zoom buttons) + minimap body
	var mapcard := UiTheme.panel_header_card("ORBIT MAP", GREEN)
	rail.add_child(mapcard["root"])
	(mapcard["root"] as Control).size_flags_horizontal = Control.SIZE_FILL
	_build_minimap_zoom_controls(mapcard["header"])
	var mm_parent := _minimap_aspect.get_parent()
	mm_parent.remove_child(_minimap_aspect)
	_minimap_aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(mapcard["body"] as VBoxContainer).add_child(_minimap_aspect)

	# OBJECTIVE card: green left-border, single mono block (describe + status + PAR)
	var obj_panel := PanelContainer.new()
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var obj_box := UiTheme.panel_box(Palette.PANEL, Palette.HAIRLINE, 2)
	obj_box.border_width_left = 5
	obj_box.border_color = Palette.HAIRLINE
	obj_box.set_content_margin_all(14)
	obj_panel.add_theme_stylebox_override("panel", obj_box)
	var obj_col := VBoxContainer.new()
	obj_col.add_theme_constant_override("separation", 8)
	obj_panel.add_child(obj_col)
	obj_col.add_child(UiTheme.eyebrow("OBJECTIVE", GREEN))
	objective_label = Label.new()
	objective_label.add_theme_font_override("font", _font)
	objective_label.add_theme_font_size_override("font_size", 12)
	objective_label.add_theme_color_override("font_color", BONE)
	objective_label.add_theme_constant_override("line_spacing", 5)
	obj_col.add_child(objective_label)
	rail.add_child(obj_panel)
	obj_panel.size_flags_horizontal = Control.SIZE_FILL


# ══════════════════════════════════════════════════ RIGHT RAIL ══

func _build_right_rail(level: LevelDef) -> void:
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 12)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rail)
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rail.offset_right = -14
	rail.offset_left = -14 - 272
	rail.offset_top = 58

	# GUIDANCE card
	var g := UiTheme.panel_header_card("GUIDANCE", AMBER)
	rail.add_child(g["root"])
	(g["root"] as Control).size_flags_horizontal = Control.SIZE_FILL
	_guid_head = Label.new()
	_guid_head.text = "LOCK OFF"
	_guid_head.add_theme_font_override("font", _font)
	_guid_head.add_theme_font_size_override("font_size", 10)
	_guid_head.add_theme_color_override("font_color", AMBER)
	(g["header"] as HBoxContainer).add_child(_guid_head)
	var gbody := g["body"] as VBoxContainer
	_guidance = AttitudeDirector.new()
	_guidance.custom_minimum_size = Vector2(0, 170)
	_guidance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gbody.add_child(_guidance)
	var arow := UiTheme.data_row("ACC", GREEN); _v_acc = arow["value"]; gbody.add_child(arow["root"])
	var vrow := UiTheme.data_row("VEL", GREEN); _v_gvel = vrow["value"]; gbody.add_child(vrow["root"])
	var drow := UiTheme.data_row("Δv REMAINING", AMBER); _v_dv = drow["value"]; gbody.add_child(drow["root"])

	# WARP card: label + 9-stop bar-graph
	var w := UiTheme.panel_header_card("WARP", GREEN)
	rail.add_child(w["root"])
	(w["root"] as Control).size_flags_horizontal = Control.SIZE_FILL
	warp_label = Label.new()
	warp_label.text = "1x"
	warp_label.add_theme_font_override("font", UiTheme.MONO_SEMI)
	warp_label.add_theme_font_size_override("font_size", 13)
	warp_label.add_theme_color_override("font_color", GREEN)
	(w["header"] as HBoxContainer).add_child(warp_label)
	_warp_meter = BarMeter.new()
	_warp_meter.segments = 9
	_warp_meter.stepped = true
	_warp_meter.fill = GREEN
	_warp_meter.empty = Palette.LIVE_DK
	_warp_meter.custom_minimum_size = Vector2(0, 22)
	_warp_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(w["body"] as VBoxContainer).add_child(_warp_meter)


# ══════════════════════════════════════════════════ BOTTOM STRIP ══

func _build_bottom_strip(level: LevelDef) -> void:
	var strip := Control.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -56

	var bg := ColorRect.new()
	bg.color = Color(0.016, 0.027, 0.02, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rule := ColorRect.new()
	rule.color = Palette.HAIRLINE
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(rule)
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.offset_bottom = 2

	for edge: int in [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT]:
		var cap := HazardStripe.new()
		cap.custom_minimum_size = Vector2(44, 56)
		strip.add_child(cap)
		cap.set_anchors_and_offsets_preset(edge)
		if edge == Control.PRESET_TOP_RIGHT:
			cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		cap.offset_bottom = 56
		cap.size = Vector2(44, 56)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 56
	row.offset_right = -56
	row.offset_top = 7
	row.offset_bottom = -7
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	# fuel/throttle cluster
	_thr_meter = _fuel_row(row, "THR", GREEN)
	_thr_pct = _last_pct
	var prop_cluster := _fuel_row(row, "PROP", GREEN)
	_prop_meter = prop_cluster
	_prop_pct = _last_pct
	_prop_extra = Label.new()
	_prop_extra.add_theme_font_override("font", _font)
	_prop_extra.add_theme_font_size_override("font_size", 11)
	_prop_extra.add_theme_color_override("font_color", DIMC)
	_prop_extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prop_extra)

	_node_label = Label.new()
	_node_label.add_theme_font_override("font", _font)
	_node_label.add_theme_font_size_override("font_size", 11)
	_node_label.add_theme_color_override("font_color", CYAN)
	_node_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_node_label.visible = false
	row.add_child(_node_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# clickable controls console (the toolbar), restyled
	row.add_child(_build_toolbar())


var _last_pct: Label


func _fuel_row(parent: HBoxContainer, label: String, color: Color) -> BarMeter:
	var cluster := HBoxContainer.new()
	cluster.add_theme_constant_override("separation", 10)
	cluster.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := Label.new()
	name_l.text = label
	name_l.add_theme_font_override("font", UiTheme.MONO_SEMI)
	name_l.add_theme_font_size_override("font_size", 11)
	name_l.add_theme_color_override("font_color", DIMC)
	cluster.add_child(name_l)
	var meter := BarMeter.new()
	meter.segments = 10
	meter.fill = color
	meter.empty = Palette.LIVE_DK
	meter.border = color
	meter.custom_minimum_size = Vector2(128, 18)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(meter)
	_last_pct = Label.new()
	_last_pct.text = "0%"
	_last_pct.add_theme_font_override("font", UiTheme.MONO_SEMI)
	_last_pct.add_theme_font_size_override("font_size", 15)
	_last_pct.add_theme_color_override("font_color", color)
	cluster.add_child(_last_pct)
	parent.add_child(cluster)
	return meter


# ══════════════════════════════════════════════════ REFRESH ══

func refresh(ship: ShipSim, level: LevelDef, sim_time: float, warp: int) -> void:
	_sync_minimap_camera(ship, sim_time)

	var el := ship.current_elements()
	_v_met.text = "T+ %s" % _clock(sim_time)
	_v_warp.text = "%dx" % warp
	_v_soi.text = ship.body.name
	_v_alt.text = "%.2f km" % (ship.altitude() / 1000.0)
	_v_vel.text = "%.1f m/s" % ship.speed()
	if el.is_elliptic():
		_v_rap.text = "%.2f km" % (el.radius_apoapsis() / 1000.0)
		_v_rap.add_theme_color_override("font_color", GREEN)
	else:
		_v_rap.text = "ESCAPE"
		_v_rap.add_theme_color_override("font_color", AMBER)
	_v_rpe.text = "%.2f km" % (el.radius_periapsis() / 1000.0)

	_burning = ship.flight_state == ShipSim.FlightState.BURNING
	_burn_label.text = "BURNING" if _burning else "COAST"
	_burn_label.add_theme_color_override("font_color", AMBER if _burning else DIMC)
	_burn_dot.visible = _burning
	_offpro_label.text = "OFF-PRO %.0f°" % rad_to_deg(ship.off_prograde_angle())
	_sas_label.text = "SAS %s" % ShipSim.SAS_NAMES[ship.sas_mode]

	var obj_lines: Array[String] = [level.objective.describe()]
	obj_lines.append_array(level.objective.status_lines(ship))
	obj_lines.append("PAR %.0f m/s" % level.dv_par)
	objective_label.text = "\n".join(obj_lines)

	_guidance.set_attitude(ship)
	_guid_head.text = "LOCK %s · %.0f°" % [
		ShipSim.SAS_NAMES[ship.sas_mode], rad_to_deg(ship.off_prograde_angle())]
	var acc := ship.accel_along_track
	var trend := "▲" if acc > 0.05 else ("▼" if acc < -0.05 else "—")
	_v_acc.text = "%+.2f m/s² %s" % [acc, trend]
	_v_acc.add_theme_color_override("font_color", GREEN if acc >= 0.0 else AMBER)
	_v_gvel.text = "%.1f m/s" % ship.speed()
	_v_dv.text = "%.1f m/s" % ship.dv_remaining()

	var wi := WARP_STEPS.find(warp)
	if wi < 0:
		wi = 0
	warp_label.text = "%dx" % warp
	_warp_meter.set_frac(float(wi + 1) / WARP_STEPS.size())

	_thr_meter.set_frac(ship.throttle)
	_thr_pct.text = "%.0f%%" % (ship.throttle * 100.0)
	var pf := ship.prop_mass / level.prop_mass
	_prop_meter.set_frac(pf)
	_prop_pct.text = "%.0f%%" % (pf * 100.0)
	_prop_extra.text = "Δv %.1f · USED %.1f" % [ship.dv_remaining(), ship.dv_used()]

	_node_label.visible = ship.node != null
	if ship.node != null:
		var dv := ship.node.total_dv()
		var exhaust_v := ship.isp * Integrator.G0
		var burn_time := ship.mass() * (1.0 - exp(-dv / exhaust_v)) / (ship.thrust_max / exhaust_v)
		_node_label.text = "NODE Δv %.1f · T%+.0fs · BURN %.0fs · REM %.1f" % [
			dv, sim_time - ship.node.t_node, burn_time, ship.node.remaining.length()]

	_sync_toolbar_state(ship)


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash_panel.visible = false
	if _burn_dot != null and _burn_dot.visible:
		_burn_dot.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
	if _fps_label != null:
		_fps_label.text = "FPS %d · DEBUG BUILD" % Engine.get_frames_per_second()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F1:
		_keys_panel.visible = not _keys_panel.visible
		get_viewport().set_input_as_handled()


# ══════════════════════════════════════════════════ BANNER / FLASH / PAUSE / KEYS ══

func _build_banner() -> void:
	var panel := PanelContainer.new()
	center_label = panel
	panel.visible = false
	var box := UiTheme.panel_box(Color(0.02, 0.035, 0.024, 0.96), GREEN, 2)
	box.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	_banner_title = Label.new()
	_banner_title.add_theme_font_override("font", UiTheme.DISPLAY)
	_banner_title.add_theme_font_size_override("font_size", 30)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_title)
	_banner_body = Label.new()
	_banner_body.add_theme_font_override("font", _font)
	_banner_body.add_theme_font_size_override("font_size", 15)
	_banner_body.add_theme_color_override("font_color", BONE)
	_banner_body.add_theme_constant_override("line_spacing", 6)
	_banner_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_body)
	_banner_prompt = Label.new()
	_banner_prompt.add_theme_font_override("font", UiTheme.MONO_SEMI)
	_banner_prompt.add_theme_font_size_override("font_size", 14)
	_banner_prompt.add_theme_color_override("font_color", AMBER)
	_banner_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_prompt)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func show_win(level: LevelDef, dv_used: float, has_next: bool, clean := false) -> void:
	_style_banner(GREEN)
	_banner_title.text = "OBJECTIVE COMPLETE"
	_banner_title.add_theme_color_override("font_color", GREEN)
	var body := "ΔV USED %.1f m/s — PAR %.0f\nMEDAL: %s" % [dv_used, level.dv_par, level.medal(dv_used)]
	if clean:
		body += "   ◇ CLEAN"
	_banner_body.text = body
	_banner_prompt.text = "[R] FLY AGAIN" + ("     [N] NEXT MISSION" if has_next else "")
	center_label.visible = true


func show_fail(reason: String, rewinds_left := 0) -> void:
	_style_banner(RED)
	_banner_title.text = reason
	_banner_title.add_theme_color_override("font_color", RED)
	_banner_body.text = ""
	var prompt := "[R] RESTART"
	if rewinds_left > 0:
		prompt = "[Z] REWIND — %d LEFT     %s" % [rewinds_left, prompt]
	_banner_prompt.text = prompt
	center_label.visible = true


func _style_banner(accent: Color) -> void:
	var box := UiTheme.panel_box(Color(0.02, 0.035, 0.024, 0.96), accent, 2)
	box.set_content_margin_all(26)
	(center_label as PanelContainer).add_theme_stylebox_override("panel", box)


func _build_flash() -> void:
	_flash_panel = PanelContainer.new()
	_flash_panel.visible = false
	var box := UiTheme.panel_box(Color(0.02, 0.035, 0.024, 0.92), AMBER, 1)
	box.set_content_margin(SIDE_LEFT, 18)
	box.set_content_margin(SIDE_RIGHT, 18)
	box.set_content_margin(SIDE_TOP, 8)
	box.set_content_margin(SIDE_BOTTOM, 8)
	_flash_panel.add_theme_stylebox_override("panel", box)
	_flash_label = _bar_text("", AMBER, 18)
	_flash_panel.add_child(_flash_label)
	add_child(_flash_panel)
	_flash_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 96)
	_flash_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH


func flash(text: String) -> void:
	_flash_label.text = text
	_flash_panel.visible = true
	_flash_left = 2.5


func _build_paused() -> void:
	_paused_panel = Control.new()
	_paused_panel.visible = false
	_paused_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paused_panel)
	_paused_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.45)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paused_panel.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var chip := UiTheme.eyebrow("‖ PAUSED — SPACE / 0 / ESC TO RESUME", AMBER)
	_paused_panel.add_child(chip)
	chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	chip.grow_horizontal = Control.GROW_DIRECTION_BOTH


func set_paused_indicator(shown: bool) -> void:
	_paused_panel.visible = shown


## The F1 "ALL KEYS" reference panel. help_label carries the InputMap-generated
## binding text (tests read it); the panel is hidden until F1 (or the strip chip).
func _build_keys_overlay(level: LevelDef) -> void:
	_keys_panel = PanelContainer.new()
	_keys_panel.visible = false
	var box := UiTheme.panel_box(Color(0.02, 0.035, 0.024, 0.97), Palette.HAIRLINE, 2)
	box.set_content_margin_all(20)
	(_keys_panel as PanelContainer).add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_keys_panel.add_child(col)
	col.add_child(UiTheme.eyebrow("ALL KEYS · F1", GREEN))
	help_label = Label.new()
	help_label.add_theme_font_override("font", _font)
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.add_theme_color_override("font_color", BONE)
	help_label.add_theme_constant_override("line_spacing", 5)
	help_label.text = _help_text(level)
	col.add_child(help_label)
	add_child(_keys_panel)
	_keys_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_keys_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_keys_panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func _help_text(level: LevelDef) -> String:
	var lines: Array[String] = [
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
		lines.append("SAS: %s PRO  %s RETRO  %s NORM  %s ANTI  %s/%s RADIAL  %s OFF" % [
			_key_label("sas_prograde"), _key_label("sas_retrograde"), _key_label("sas_normal"),
			_key_label("sas_antinormal"), _key_label("sas_radial_out"), _key_label("sas_radial_in"),
			_key_label("sas_off")])
	if level.nodes_enabled:
		lines.append("NODE: %s ADD  %s DEL  %s/%s TIME  %s/%s PRO  %s/%s NORM  %s/%s RAD" % [
			_key_label("node_create"), _key_label("node_delete"),
			_key_label("node_time_earlier"), _key_label("node_time_later"),
			_key_label("node_prograde_increase"), _key_label("node_prograde_decrease"),
			_key_label("node_normal_increase"), _key_label("node_normal_decrease"),
			_key_label("node_radial_increase"), _key_label("node_radial_decrease")])
		lines.append("      SHIFT = COARSE   %s HOLD NODE" % _key_label("sas_node_hold"))
	return "\n".join(lines)


# ══════════════════════════════════════════════════ REWIND ══

func _build_rewind_widgets() -> void:
	_rewind_label = Label.new()
	_rewind_label.add_theme_font_override("font", UiTheme.MONO_SEMI)
	_rewind_label.add_theme_font_size_override("font_size", 13)
	_rewind_label.add_theme_color_override("font_color", AMBER)
	_rewind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rewind_label.visible = false
	var wrap := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.INTENT_DK
	box.set_border_width_all(1)
	box.border_color = AMBER
	box.set_content_margin(SIDE_LEFT, 16)
	box.set_content_margin(SIDE_RIGHT, 16)
	box.set_content_margin(SIDE_TOP, 7)
	box.set_content_margin(SIDE_BOTTOM, 7)
	wrap.add_theme_stylebox_override("panel", box)
	wrap.add_child(_rewind_label)
	# keep the wrap visibility tied to the label so an empty line hides the chip
	_rewind_label.visibility_changed.connect(func() -> void: wrap.visible = _rewind_label.visible)
	wrap.visible = false
	add_child(wrap)
	wrap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 58)
	wrap.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_rewind_timeline = RewindTimeline.new()
	_rewind_timeline.font = _font
	_rewind_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rewind_timeline.custom_minimum_size = Vector2(780, 80)
	_rewind_timeline.visible = false
	add_child(_rewind_timeline)
	_rewind_timeline.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 96)


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


# ══════════════════════════════════════════════════ MINIMAP ══

func _finish_minimap(level: LevelDef) -> void:
	var viewport: SubViewport = minimap_root.get_node("SubViewportContainer/SubViewport")
	_minimap_cam = viewport.get_node("Camera3D")
	_minimap_cam.size = level.map_extent
	_minimap_min_size = level.body.radius * 1.6 * MapView.MAP_SCALE
	_minimap_max_size = level.draw_limit * 2.6 * MapView.MAP_SCALE
	_minimap_manual_size = level.map_extent
	_minimap_zoom_auto = true
	_minimap_cam.make_current()
	if Settings.effects_enabled:
		viewport.add_child(CrtOverlay.new())

	_minimap_overlay = MinimapOverlay.new()
	_minimap_overlay.font = _font
	_minimap_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_root.add_child(_minimap_overlay)
	_minimap_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var back: ColorRect = minimap_root.get_node("Back")
	back.color = Color(0.03, 0.22, 0.12, 0.55)
	var panel_mat := ShaderMaterial.new()
	panel_mat.shader = preload("res://src/shaders/minimap_panel.gdshader")
	back.material = panel_mat


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
		map_view.minimap_ortho_size = s
	var focus := map_view.focus_point(ship, t) if map_view != null else Vector3.ZERO
	var heading := (map_view.velocity_heading_angle(ship) + PI) if map_view != null else 0.0
	_minimap_cam.position = focus + Basis(Vector3.UP, heading) * Vector3(0.0, s * 0.9, s * 0.42)
	_minimap_cam.look_at(focus, Vector3.UP)
	_minimap_cam.far = s * 8.0 + focus.length() + 10.0

	if _minimap_overlay != null and map_view != null:
		_minimap_overlay.cam = _minimap_cam
		_minimap_overlay.points = map_view.marked_points(ship, t)
		_minimap_overlay.queue_redraw()


func _build_minimap_zoom_controls(header: HBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	header.add_child(row)
	_minimap_button("AUTO", 44, "solid", func() -> void: _on_minimap_zoom("auto"), row)
	_minimap_button("+", 24, "ghost", func() -> void: _on_minimap_zoom("in"), row)
	_minimap_button("−", 24, "ghost", func() -> void: _on_minimap_zoom("out"), row)


func _minimap_button(text: String, width: float, kind: String, on_press: Callable, row: HBoxContainer) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 22)
	b.add_theme_font_override("font", UiTheme.MONO_SEMI)
	b.add_theme_font_size_override("font_size", 11)
	var sb := StyleBoxFlat.new()
	if kind == "solid":
		sb.bg_color = AMBER
		b.add_theme_color_override("font_color", Palette.VOID)
		b.add_theme_color_override("font_hover_color", Palette.VOID)
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(1)
		sb.border_color = Palette.HAIRLINE
		b.add_theme_color_override("font_color", BONE)
		b.add_theme_color_override("font_hover_color", AMBER)
	sb.set_content_margin_all(2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)
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


func set_minimap_visible(shown: bool) -> void:
	minimap_root.visible = shown


# ══════════════════════════════════════════════════ TOOLBAR ══

## Real clickable buttons for every non-warp keybind, restyled as ORBITAL-OS
## chips. Clicking one taps (or holds, for SHIFT/CTRL throttle) the matching
## physical key via toolbar_key — the whole integration surface (see the signal).
func _build_toolbar() -> Control:
	var console := PanelContainer.new()
	console.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.036, 0.6)
	style.set_border_width_all(1)
	style.border_color = Palette.HAIRLINE
	style.set_content_margin_all(6)
	console.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console.add_child(row)
	for group: Array in STRIP_GROUPS:
		row.add_child(_make_toolbar_group(group[0], group[1]))
	row.add_child(_make_keys_chip())
	return console


## Inline group: a tiny amber label then its chip buttons, on one row (ref idiom).
func _make_toolbar_group(title: String, entries: Array) -> Control:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 3)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_override("font", UiTheme.MONO_SEMI)
	heading.add_theme_font_size_override("font_size", 9)
	heading.add_theme_color_override("font_color", AMBER)
	group.add_child(heading)
	for entry: Array in entries:
		group.add_child(_make_toolbar_button(entry[0], entry[1], entry[2]))
	return group


## The "F1 · ALL KEYS" chip: toggles the full-keybind reference overlay.
func _make_keys_chip() -> Button:
	var b := Button.new()
	b.text = "F1 · ALL KEYS"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 22)
	b.add_theme_font_override("font", UiTheme.MONO_SEMI)
	b.add_theme_font_size_override("font_size", 11)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(1)
	sb.border_color = Palette.DIM
	sb.set_content_margin(SIDE_LEFT, 8)
	sb.set_content_margin(SIDE_RIGHT, 8)
	sb.set_content_margin(SIDE_TOP, 3)
	sb.set_content_margin(SIDE_BOTTOM, 3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)
	b.add_theme_color_override("font_color", Palette.DIM)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.pressed.connect(func() -> void: _keys_panel.visible = not _keys_panel.visible)
	return b


func _make_toolbar_button(label: String, keycode: int, holdable: bool) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 22)
	button.add_theme_font_override("font", UiTheme.MONO_SEMI)
	button.add_theme_font_size_override("font_size", 11)
	button.focus_mode = Control.FOCUS_NONE
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
	normal.bg_color = Color(0, 0, 0, 0)
	normal.set_border_width_all(1)
	normal.border_color = Palette.HAIRLINE
	normal.set_content_margin(SIDE_LEFT, 6)
	normal.set_content_margin(SIDE_RIGHT, 6)
	normal.set_content_margin(SIDE_TOP, 3)
	normal.set_content_margin(SIDE_BOTTOM, 3)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Palette.LIVE_DK
	hover.border_color = GREEN
	var pressed_style: StyleBoxFlat = normal.duplicate()
	pressed_style.bg_color = Palette.INTENT_DK
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
		KEY_F: ShipSim.SasMode.PROGRADE, KEY_B: ShipSim.SasMode.RETROGRADE,
		KEY_N: ShipSim.SasMode.NORMAL, KEY_G: ShipSim.SasMode.ANTI_NORMAL,
		KEY_U: ShipSim.SasMode.RADIAL_OUT, KEY_I: ShipSim.SasMode.RADIAL_IN,
		KEY_T: ShipSim.SasMode.OFF, KEY_V: ShipSim.SasMode.NODE,
	}
	for keycode: int in active_modes:
		var active: bool = ship.sas_mode == active_modes[keycode]
		for button: Button in _toolbar_buttons.get(keycode, []):
			button.set_pressed_no_signal(active)


# ══════════════════════════════════════════════════ MISC ══

func _build_fps_label() -> void:
	_fps_label = Label.new()
	_fps_label.add_theme_font_override("font", _font)
	_fps_label.add_theme_font_size_override("font_size", 11)
	_fps_label.add_theme_color_override("font_color", DIMC)
	add_child(_fps_label)
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_fps_label.offset_left = 20
	_fps_label.offset_top = -74


## Human-readable key name(s) bound to an InputMap action, uppercased and joined
## with "/" — generated from live bindings so the help text can't drift.
func _key_label(action: String) -> String:
	var parts: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			parts.append(OS.get_keycode_string((event as InputEventKey).physical_keycode).to_upper())
	return "/".join(parts)


func _clock(t: float) -> String:
	var total := int(t)
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]

class_name HudOverlays
extends Control

@onready var mission_panel: PanelContainer = %MissionPanel
@onready var banner_title: Label = %BannerTitle
@onready var banner_body: Label = %BannerBody
@onready var banner_prompt: Label = %BannerPrompt
@onready var flash_panel: PanelContainer = %FlashPanel
@onready var flash_label: Label = %FlashLabel
@onready var paused_panel: Control = %PausedPanel
@onready var keys_panel: PanelContainer = %KeysPanel
@onready var help_label: Label = %HelpLabel
@onready var _rewind: RewindHud = %RewindHud  # rewind readout, its own scene
@onready var fps_label: Label = %FpsLabel

var _flash_left := 0.0


func configure(level: LevelDef, debug_enabled: bool) -> void:
	help_label.text = _help_text(level)
	fps_label.visible = debug_enabled


func show_win(level: LevelDef, delta_v_used: float, has_next: bool, clean: bool) -> void:
	_style_banner(Palette.LIVE)
	banner_title.text = "OBJECTIVE COMPLETE"
	banner_title.add_theme_color_override("font_color", Palette.LIVE)
	var body := tr("ΔV USED %.1f m/s — PAR %.0f\nMEDAL: %s") % [
		delta_v_used, level.dv_par, tr(level.medal(delta_v_used))]
	if clean:
		body += "   " + tr("◇ CLEAN")
	banner_body.text = body
	var restart_key := InputBindings.primary_key_label("reset_or_restart")
	var next_key := InputBindings.primary_key_label("sas_normal")
	banner_prompt.text = tr("[%s] FLY AGAIN") % restart_key + (
		tr("     [%s] NEXT MISSION") % next_key if has_next else "")
	mission_panel.visible = true


func show_fail(reason: String, rewinds_left: int) -> void:
	_style_banner(Palette.WARNING)
	banner_title.text = reason
	banner_title.add_theme_color_override("font_color", Palette.WARNING)
	banner_body.text = ""
	var prompt := tr("[%s] RESTART") % InputBindings.primary_key_label("reset_or_restart")
	if rewinds_left > 0:
		prompt = tr("[%s] REWIND — %d LEFT     %s") % [
			InputBindings.primary_key_label("rewind_open"), rewinds_left, prompt]
	banner_prompt.text = prompt
	mission_panel.visible = true


func flash(text: String) -> void:
	flash_label.text = text
	flash_panel.visible = true
	_flash_left = 2.5


func tick(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			flash_panel.visible = false
	if fps_label.visible:
		fps_label.text = tr("FPS %d · DEBUG BUILD") % Engine.get_frames_per_second()


func toggle_keys() -> void:
	keys_panel.visible = not keys_panel.visible


func set_paused_indicator(shown: bool) -> void:
	paused_panel.visible = shown


func set_rewind_line(text: String) -> void:
	_rewind.set_line(text)


func update_rewind_timeline(
		t_start: float, t_now: float, playhead: float, cursor: int,
		anchors: Array, landmarks: Array) -> void:
	_rewind.update_timeline(t_start, t_now, playhead, cursor, anchors, landmarks)


func hide_rewind_timeline() -> void:
	_rewind.hide_timeline()


func _style_banner(accent: Color) -> void:
	var box := UiTheme.panel_box(Palette.PANEL_BG, accent, 2)
	box.set_content_margin_all(26)
	mission_panel.add_theme_stylebox_override("panel", box)


func _help_text(level: LevelDef) -> String:
	var lines: Array[String] = [
		tr("%s/%s PITCH  %s/%s YAW  %s/%s ROLL") % [
			_key_label("pitch_down"), _key_label("pitch_up"),
			_key_label("yaw_left"), _key_label("yaw_right"),
			_key_label("roll_left"), _key_label("roll_right")],
		tr("%s/%s THROTTLE  %s MAX  %s CUT") % [
			_key_label("throttle_increase"), _key_label("throttle_decrease"),
			_key_label("throttle_full"), _key_label("throttle_cut")],
		tr("1-9 WARP LEVEL  %s/%s WARP STEP") % [
			_key_label("warp_decrease"), _key_label("warp_increase")],
		tr("%s PAUSE  %s PAUSE MENU  %s RESET VIEW") % [
			_key_label("quick_pause"), _key_label("pause_menu"), _key_label("reset_or_restart")],
		tr("%s ORBIT VIEW  DRAG ROTATE  WHEEL/TRACKPAD ZOOM") % _key_label("toggle_side_camera")]
	if level.sas_enabled:
		lines.append(tr("SAS: %s PRO  %s RETRO  %s NORM  %s ANTI  %s/%s RADIAL  %s KILL ROT  %s OFF") % [
			_key_label("sas_prograde"), _key_label("sas_retrograde"), _key_label("sas_normal"),
			_key_label("sas_antinormal"), _key_label("sas_radial_out"), _key_label("sas_radial_in"),
			_key_label("kill_rotation"), _key_label("sas_off")])
	if level.nodes_enabled:
		lines.append(tr("NODE: %s ADD  %s DEL  %s/%s TIME  %s/%s PRO  %s/%s NORM  %s/%s RAD") % [
			_key_label("node_create"), _key_label("node_delete"),
			_key_label("node_time_earlier"), _key_label("node_time_later"),
			_key_label("node_prograde_increase"), _key_label("node_prograde_decrease"),
			_key_label("node_normal_increase"), _key_label("node_normal_decrease"),
			_key_label("node_radial_increase"), _key_label("node_radial_decrease")])
		lines.append(tr("      SHIFT = COARSE   %s HOLD NODE") % _key_label("sas_node_hold"))
	return "\n".join(lines)


func _key_label(action: String) -> String:
	var parts: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			parts.append(OS.get_keycode_string((event as InputEventKey).physical_keycode).to_upper())
	return "/".join(parts)

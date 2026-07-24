class_name CreditsScreen
extends CanvasLayer
## Single-panel credits in the ORBITAL-OS chrome (backdrop + breadcrumb + a
## bordered panel). Esc returns to the main menu.

signal back_pressed

const HINT := "[ESC]  BACK"

var _shell: MenuShell


func build() -> void:
	_shell = MenuShell.new()
	add_child(_shell)
	_shell.configure("MAIN MENU ▶ CREDITS")
	_shell.set_hint(HINT)
	_shell.hide_left()
	_shell.set_right(_build_panel())
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.INSTRUMENT_PANEL
	var pad := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 20)  # +12 panel = 32 gutter
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	pad.add_child(col)

	col.add_child(_lbl(UiTheme.EYEBROW, "CREDITS"))
	col.add_child(_lbl(UiTheme.MENU_TITLE, "LIMITED PROPELLANT"))
	col.add_child(_lbl(UiTheme.MENU_TAGLINE, "Burn fuel. Change orbit. Solve Lambert's problem."))
	col.add_child(HSeparator.new())
	for line: Array in [
		["DESIGN & CODE", "Taowu"],
		["ENGINE", "Godot 4.7"],
		["TYPE", "Chakra Petch · IBM Plex Mono"],
		["PHYSICS", "Kepler · patched conics · the rocket equation"],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		var key := _lbl(UiTheme.MENU_FOOTER, line[0])
		key.custom_minimum_size = Vector2(160, 0)
		row.add_child(key)
		row.add_child(_lbl(UiTheme.MONO_TEXT, line[1]))
		col.add_child(row)
	return panel


func _lbl(variation: StringName, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	return l


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		back_pressed.emit()

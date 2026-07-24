class_name CreditsScreen
extends CanvasLayer
## Single-panel credits in the ORBITAL-OS chrome (backdrop + breadcrumb + a
## bordered panel). Esc returns to the main menu.

signal back_pressed

const HINT := "[ESC]  BACK"

var _shell: MenuShell


func build() -> void:
	_shell = MenuShell.create()
	add_child(_shell)
	_shell.configure("MAIN MENU ▶ CREDITS")
	_shell.set_hint(HINT)
	_shell.hide_left()
	_shell.set_right(_build_panel())
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


## Credits are fully static, so the whole panel is authored in credits_panel.tscn
## (editable in the editor) with no runtime slots.
func _build_panel() -> Control:
	return preload("res://src/ui/credits_panel.tscn").instantiate()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		back_pressed.emit()

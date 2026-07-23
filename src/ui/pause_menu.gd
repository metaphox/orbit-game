class_name PauseMenu
extends CanvasLayer
## In-flight pause overlay: Resume / Save Progress / Restart / Quit to
## mission select. Semi-transparent backdrop (unlike the other full-screen
## menus) so the frozen flight is still visible behind it. Navigate with
## Up/Down (also W/S or K/J) + Enter, matching the title/mission-select menus.
## Key hints are hidden by default; F1 toggles them (and is swallowed here so it
## doesn't also open the in-flight HUD keybind overlay behind the menu).

signal resume_pressed
signal save_pressed
signal restart_pressed
signal quit_pressed

var _text: RichTextLabel
var _items: Array[String] = ["RESUME", "SAVE PROGRESS", "RESTART MISSION", "QUIT TO MISSION SELECT"]
var _cursor := 0
var _saved_flash := false
var _layout: MenuTextLayout


func build() -> void:
	_layout = preload("res://src/ui/menu_text_layout.tscn").instantiate()
	add_child(_layout)
	_layout.configure("■ PAUSED ■", "", "", true)
	_text = _layout.content
	_apply_footer()

	_refresh()


## Footer: the resume keys always show; the up/down nav hints only when F1 is on.
func _apply_footer() -> void:
	var nav := "↑↓ / W S / K J  SELECT   ENTER CONFIRM   [F1] HIDE   " \
		if Settings.menu_hints_on() else "[F1] KEYS   "
	_layout.footer_label.text = nav + "[ESC]/[SPACE]/[0] RESUME"
	_layout.footer_label.visible = true


func show_saved_confirmation() -> void:
	_saved_flash = true
	_refresh()


func _refresh() -> void:
	var green := Palette.hex(Palette.LIVE)
	var dim := Palette.hex(Palette.LIVE_DIM)
	var highlight := Palette.hex(Palette.INTENT)
	var lines: Array[String] = []
	for i in _items.size():
		var selected := i == _cursor
		var color := highlight if selected else green
		var marker := "▶ " if selected else "  "
		lines.append("[color=%s]%s%s[/color]" % [color, marker, _items[i]])
	if _saved_flash:
		lines.append("")
		lines.append("[color=%s]✓ PROGRESS SAVED[/color]" % green)
		lines.append("[color=%s]  (rewind anchors are not saved)[/color]" % dim)
	_text.text = "\n".join(lines)


func _move_cursor(delta: int) -> void:
	_cursor = wrapi(_cursor + delta, 0, _items.size())
	_saved_flash = false
	_refresh()


func _activate(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	_cursor = i
	_saved_flash = false
	match i:
		0:
			resume_pressed.emit()
		1:
			save_pressed.emit()
		2:
			restart_pressed.emit()
		3:
			quit_pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_UP, KEY_W, KEY_K:
			_move_cursor(-1)
		KEY_DOWN, KEY_S, KEY_J:
			_move_cursor(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate(_cursor)
		KEY_F1:
			Settings.toggle_menu_hints()
			_apply_footer()
			get_viewport().set_input_as_handled()

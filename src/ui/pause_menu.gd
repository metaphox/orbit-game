class_name PauseMenu
extends CanvasLayer
## In-flight pause overlay: Resume / Save Progress / Restart / Quit to
## mission select. Semi-transparent backdrop (unlike the other full-screen
## menus) so the frozen flight is still visible behind it. Navigable by
## number key or Up/Down + Enter, matching the title/mission-select menus.

signal resume_pressed
signal save_pressed
signal restart_pressed
signal quit_pressed

const GREEN := "#73ff8c"
const DIM_GREEN := "#4da362"
const HIGHLIGHT := "#fff59d"

var _text: RichTextLabel
var _items := ["RESUME", "SAVE PROGRESS", "RESTART MISSION", "QUIT TO MISSION SELECT"]
var _cursor := 0
var _saved_flash := false


func build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.0, 0.72)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(GREEN))
	title.text = "■ PAUSED ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 130)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(420, 10)
	_text.add_theme_font_override("normal_font", font)
	_text.add_theme_font_size_override("normal_font_size", 20)
	add_child(_text)
	_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_text.grow_vertical = Control.GROW_DIRECTION_BOTH

	var help := Label.new()
	help.add_theme_font_override("font", font)
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(DIM_GREEN))
	help.text = "↑↓ SELECT   ENTER CONFIRM   OR PRESS NUMBER   [ESC]/[SPACE]/[0] RESUME"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)

	_refresh()


func show_saved_confirmation() -> void:
	_saved_flash = true
	_refresh()


func _refresh() -> void:
	var lines: Array = []
	for i in _items.size():
		var selected := i == _cursor
		var color := HIGHLIGHT if selected else GREEN
		var marker := "▶ " if selected else "  "
		lines.append("[color=%s]%s[%d] %s[/color]" % [color, marker, i + 1, _items[i]])
	if _saved_flash:
		lines.append("")
		lines.append("[color=%s]✓ PROGRESS SAVED[/color]" % GREEN)
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
		KEY_UP:
			_move_cursor(-1)
		KEY_DOWN:
			_move_cursor(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate(_cursor)
		KEY_1, KEY_2, KEY_3, KEY_4:
			_activate(key.physical_keycode - KEY_1)

class_name CreditsScreen
extends CanvasLayer

signal back_pressed

const GREEN := "#73ff8c"
const DIM_GREEN := "#4da362"


func build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.008, 0.016)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(GREEN))
	title.text = "■ CREDITS ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)

	var body := Label.new()
	body.add_theme_font_override("font", font)
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", Color(GREEN))
	body.add_theme_constant_override("line_spacing", 10)
	body.text = "\n".join([
		"ORBIT",
		"",
		"A GAME ABOUT BURNING FUEL",
		"TO CHANGE ORBIT",
		"",
		"BUILT WITH GODOT ENGINE 4.7",
	])
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	body.grow_horizontal = Control.GROW_DIRECTION_BOTH
	body.grow_vertical = Control.GROW_DIRECTION_BOTH

	var help := Label.new()
	help.add_theme_font_override("font", font)
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(DIM_GREEN))
	help.text = "[ESC] BACK"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)

	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		back_pressed.emit()

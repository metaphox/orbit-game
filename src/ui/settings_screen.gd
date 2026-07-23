class_name SettingsScreen
extends CanvasLayer
## Device-level settings. Deliberately small: the only toggle that exists
## right now is the visual effects layer (screen grade + CRT overlays),
## since that's the only cross-cutting system built so far. More settings
## (audio, keybinds) join here as those systems land.

signal back_pressed

var store: ProfileStore
var _text: RichTextLabel


func build(profile_store: ProfileStore) -> void:
	store = profile_store

	var bg := ColorRect.new()
	bg.color = Palette.MENU_BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Palette.MENU_GREEN)
	title.text = "■ SETTINGS ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(420, 10)
	_text.add_theme_font_override("normal_font", font)
	_text.add_theme_font_size_override("normal_font_size", 19)
	add_child(_text)
	_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_text.grow_vertical = Control.GROW_DIRECTION_BOTH

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _refresh() -> void:
	var state := "ON" if Settings.effects_enabled else "OFF"
	var green := Palette.hex(Palette.MENU_GREEN)
	var dim := Palette.hex(Palette.MENU_GREEN_DIM)
	var lines := [
		"[color=%s][1] SCREEN EFFECTS: %s[/color]" % [green, state],
		"[color=%s]    (film grade + CRT scanlines)[/color]" % dim,
		"",
		"[color=%s][ESC] BACK[/color]" % dim,
	]
	_text.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		back_pressed.emit()
	elif key.physical_keycode == KEY_1:
		Settings.effects_enabled = not Settings.effects_enabled
		store.save()
		_refresh()

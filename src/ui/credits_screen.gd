class_name CreditsScreen
extends CanvasLayer

signal back_pressed

var _layout: MenuTextLayout


func build() -> void:
	_layout = preload("res://src/ui/menu_text_layout.tscn").instantiate()
	add_child(_layout)
	_layout.configure("■ CREDITS ■", "", "[ESC] BACK")
	_layout.content.add_theme_font_size_override("normal_font_size", 18)
	_layout.content.text = "[center][color=%s]%s[/color][/center]" % [
		Palette.hex(Palette.LIVE), "\n".join([
		"ORBIT",
		"",
		"A GAME ABOUT BURNING FUEL",
		"TO CHANGE ORBIT",
		"",
		"BUILT WITH GODOT ENGINE 4.7",
	])]

	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		back_pressed.emit()

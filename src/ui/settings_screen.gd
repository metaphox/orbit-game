class_name SettingsScreen
extends CanvasLayer
## Device-level settings. Deliberately small: the only toggle that exists
## right now is the visual effects layer (screen grade + CRT overlays),
## since that's the only cross-cutting system built so far. More settings
## (audio, keybinds) join here as those systems land.

signal back_pressed

var store: ProfileStore
var _text: RichTextLabel
var _layout: MenuTextLayout


func build(profile_store: ProfileStore) -> void:
	store = profile_store

	_layout = preload("res://src/ui/menu_text_layout.tscn").instantiate()
	add_child(_layout)
	_layout.configure("■ SETTINGS ■", "", "")
	_text = _layout.content

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _refresh() -> void:
	var state := "ON" if Settings.effects_enabled else "OFF"
	var green := Palette.hex(Palette.LIVE)
	var dim := Palette.hex(Palette.LIVE_DIM)
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

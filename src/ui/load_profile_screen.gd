class_name LoadProfileScreen
extends CanvasLayer
## Lists existing profiles; press the number next to one to switch to it.

signal profile_chosen(profile_name: String)
signal cancelled

var store: ProfileStore
var _text: RichTextLabel
var _layout: MenuTextLayout


func build(profile_store: ProfileStore) -> void:
	store = profile_store

	_layout = preload("res://src/ui/menu_text_layout.tscn").instantiate()
	add_child(_layout)
	_layout.configure("■ LOAD PILOT ■", "", "")
	_text = _layout.content

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _refresh() -> void:
	var green := Palette.hex(Palette.LIVE)
	var dim := Palette.hex(Palette.LIVE_DIM)
	var lines: Array[String] = []
	if store.profiles.is_empty():
		lines.append("[color=%s]NO PROFILES YET[/color]" % dim)
	for i in store.profiles.size():
		var profile: Profile = store.profiles[i]
		var completed := 0
		for index in Campaign.order():
			if profile.medal_for(index) != "":
				completed += 1
		lines.append("[color=%s][%d][/color] %s   [color=%s](%d/%d COMPLETE)[/color]" % [
			green, i + 1, profile.profile_name, dim, completed, Campaign.level_count()])
	lines.append("")
	lines.append("[color=%s][ESC] CANCEL[/color]" % dim)
	_text.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		cancelled.emit()
		return
	if key.physical_keycode < KEY_1 or key.physical_keycode > KEY_9:
		return
	var pos := key.physical_keycode - KEY_1
	if pos < store.profiles.size():
		profile_chosen.emit(store.profiles[pos].profile_name)

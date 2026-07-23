class_name LoadProfileScreen
extends CanvasLayer
## Lists existing profiles; Up/Down (also W/S or K/J) select one, Enter switches
## to it, Esc cancels. Key hints are hidden by default; F1 toggles them.

signal profile_chosen(profile_name: String)
signal cancelled

var store: ProfileStore
var _text: RichTextLabel
var _layout: MenuTextLayout
var _cursor := 0


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
	var highlight := Palette.hex(Palette.INTENT)
	var lines: Array[String] = []
	if store.profiles.is_empty():
		lines.append("[color=%s]NO PROFILES YET[/color]" % dim)
	for i in store.profiles.size():
		var profile: Profile = store.profiles[i]
		var completed := 0
		for index in Campaign.order():
			if profile.medal_for(index) != "":
				completed += 1
		var selected := i == _cursor
		var marker := "▶ " if selected else "  "
		var name_color := highlight if selected else green
		lines.append("%s[color=%s]%s[/color]   [color=%s](%d/%d COMPLETE)[/color]" % [
			marker, name_color, profile.profile_name, dim, completed, Campaign.level_count()])
	lines.append("")
	if store.profiles.is_empty():
		lines.append("[color=%s][ESC] CANCEL[/color]" % dim)
	elif Settings.menu_hints_on():
		lines.append("[color=%s]↑↓ / W S / K J  SELECT   ENTER  LOAD   [ESC]  CANCEL   [F1]  HIDE[/color]" % dim)
	else:
		lines.append("[color=%s][F1] KEYS   [ESC] CANCEL[/color]" % dim)
	_text.text = "\n".join(lines)


func _move_cursor(delta: int) -> void:
	var n := store.profiles.size()
	if n == 0:
		return
	_cursor = wrapi(_cursor + delta, 0, n)
	_refresh()


func _activate() -> void:
	if _cursor >= 0 and _cursor < store.profiles.size():
		profile_chosen.emit(store.profiles[_cursor].profile_name)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_ESCAPE:
			cancelled.emit()
		KEY_UP, KEY_W, KEY_K:
			_move_cursor(-1)
		KEY_DOWN, KEY_S, KEY_J:
			_move_cursor(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate()
		KEY_F1:
			Settings.toggle_menu_hints()
			_refresh()

class_name TitleScreen
extends CanvasLayer
## The splash screen: game title plus the main menu. CONTINUE is disabled
## when no profile has ever been active; NEW is disabled once all profile
## slots are full. Navigable by number key or by Up/Down + Enter.
## Styled with the shared ORBITAL-OS system (UiTheme + Palette).

signal continue_pressed
signal new_pressed
signal load_pressed
signal settings_pressed
signal credits_pressed
signal quit_pressed

var _text: RichTextLabel
var _items: Array = []  # [label: String, enabled: bool]
var _cursor := 0
var _layout: TitleScreenLayout


func build(store: ProfileStore) -> void:
	var last_profile := store.last_active_profile()
	var continue_label := "CONTINUE"
	if last_profile != null and last_profile.mission_save != null:
		var saved_index: int = last_profile.mission_save.get("level_index", 0)
		continue_label = "CONTINUE — %s" % Campaign.title(saved_index)
	_items = [
		[continue_label, last_profile != null],
		["NEW PROFILE", store.can_create_profile()],
		["LOAD PROFILE", true],
		["SETTINGS", true],
		["CREDITS", true],
		["QUIT", true],
	]
	_cursor = _first_enabled()

	_layout = preload("res://src/ui/title_screen_layout.tscn").instantiate()
	add_child(_layout)
	_text = _layout.menu_text
	_layout.warning_label.text = "⚠ %s" % store.load_warning if store.load_warning != "" else ""
	_layout.warning_label.visible = store.load_warning != ""
	_layout.slots_label.text = "%d / %d PROFILE SLOTS   ·   ↑↓ SELECT   ·   ENTER CONFIRM" % [
		store.profiles.size(), ProfileStore.MAX_PROFILES]

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _first_enabled() -> int:
	for i in _items.size():
		if _items[i][1]:
			return i
	return 0


func _refresh() -> void:
	var lines: Array[String] = []
	for i in _items.size():
		var label: String = _items[i][0]
		var enabled: bool = _items[i][1]
		var selected := i == _cursor
		var color: Color
		if selected and enabled:
			color = Palette.SELECT
		elif enabled:
			color = Palette.LIVE
		else:
			color = Palette.DISABLED
		var marker := "▶ " if selected else "  "
		lines.append("[color=%s]%s[%d]  %s[/color]" % [Palette.hex(color), marker, i + 1, label])
	_text.text = "\n".join(lines)


func _move_cursor(delta: int) -> void:
	var n := _items.size()
	var i := _cursor
	for _step in n:
		i = wrapi(i + delta, 0, n)
		if _items[i][1]:
			_cursor = i
			_refresh()
			return


func _select_and_activate(i: int) -> void:
	if i < 0 or i >= _items.size() or not _items[i][1]:
		return
	_cursor = i
	match i:
		0:
			continue_pressed.emit()
		1:
			new_pressed.emit()
		2:
			load_pressed.emit()
		3:
			settings_pressed.emit()
		4:
			credits_pressed.emit()
		5:
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
			_select_and_activate(_cursor)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_select_and_activate(key.physical_keycode - KEY_1)

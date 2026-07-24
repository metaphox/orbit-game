class_name SettingsScreen
extends CanvasLayer
## Two-pane device settings: left column of toggle rows, right pane describing the
## focused setting. Up/Down (also W/S, K/J) select, Enter/click toggles, Esc back.
## More settings (audio, keybinds) join the SETTINGS array as those systems land.

signal back_pressed

const HINT := "↑↓ / W S / K J  SELECT     ENTER  TOGGLE     [ESC]  BACK     [F1]  HIDE"
const SETTINGS := [
	{"key": "effects_enabled", "label": "SCREEN EFFECTS", "desc": "Film grade + CRT scanline overlay on every screen."},
	{"key": "menu_hints", "label": "MENU HINTS", "desc": "Show the navigation key hints in menus by default (F1 toggles them anywhere)."},
]

var store: ProfileStore
var _cursor := 0
var _hover_pos := -1
var _shell: MenuShell
var _cards: Array[OptionCard] = []
var _title: Label
var _desc: Label


func build(profile_store: ProfileStore) -> void:
	store = profile_store
	_shell = MenuShell.create()
	add_child(_shell)
	_shell.configure("MAIN MENU ▶ SETTINGS")
	_shell.set_hint(HINT)
	_shell.set_right(_build_detail())

	for i in SETTINGS.size():
		var card := OptionCard.new()
		_shell.left_column.add_child(card)
		card.set_data(i, _row_label(i), true)
		card.hovered.connect(_on_card_hovered)
		card.clicked.connect(_toggle)
		card.activated.connect(_toggle)
		_cards.append(card)
	_shell.left_column.mouse_exited.connect(_clear_hover)

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


## The detail panel is authored in settings_detail.tscn (editable in the editor).
func _build_detail() -> Control:
	var panel := preload("res://src/ui/menu/settings_detail.tscn").instantiate()
	_title = panel.get_node("%Title")
	_desc = panel.get_node("%Desc")
	return panel


func _row_label(i: int) -> String:
	var on := Settings.get_bool(SETTINGS[i]["key"])
	return "%s   [ %s ]" % [SETTINGS[i]["label"], "ON" if on else "OFF"]


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_data(i, _row_label(i), true)
		_cards[i].set_selected(i == _cursor)
	var shown := _hover_pos if _hover_pos >= 0 else _cursor
	if shown >= 0 and shown < SETTINGS.size():
		_title.text = SETTINGS[shown]["label"]
		_desc.text = SETTINGS[shown]["desc"]


func _toggle(i: int) -> void:
	if i < 0 or i >= SETTINGS.size():
		return
	_cursor = i
	var key: String = SETTINGS[i]["key"]
	Settings.set_value(key, not Settings.get_bool(key))
	store.save()
	_refresh()


func _on_card_hovered(pos: int) -> void:
	_hover_pos = pos
	_refresh()


func _clear_hover() -> void:
	if _hover_pos != -1:
		_hover_pos = -1
		_refresh()


func _move_cursor(delta: int) -> void:
	_cursor = wrapi(_cursor + delta, 0, SETTINGS.size())
	_hover_pos = -1
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_ESCAPE:
			back_pressed.emit()
		KEY_UP, KEY_W, KEY_K:
			_move_cursor(-1)
		KEY_DOWN, KEY_S, KEY_J:
			_move_cursor(1)
		KEY_ENTER, KEY_KP_ENTER:
			_toggle(_cursor)
		KEY_F1:
			Settings.toggle_menu_hints()
			_shell.refresh_hint_visibility()

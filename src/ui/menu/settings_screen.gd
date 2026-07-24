class_name SettingsScreen
extends CanvasLayer
## Two-pane device settings: left column of rows (a language picker + toggles),
## right pane describing the focused row. Up/Down (also W/S, K/J) select,
## Enter/click activates (cycles the language, or flips a toggle), Esc back.

signal back_pressed

const HINT := "↑↓ / W S / K J  SELECT     ENTER  TOGGLE     [ESC]  BACK     [F1]  HIDE"

## Selectable UI locales, in cycle order. Names are endonyms (never translated).
## Untranslated locales fall back to English text but still set the preference.
const LANGUAGES := [
	{"code": "en", "name": "English"},   # i18n-ok: endonym (a language's own name)
	{"code": "de", "name": "Deutsch"},   # i18n-ok: endonym
	{"code": "fr", "name": "Français"},  # i18n-ok: endonym
	{"code": "ru", "name": "Русский"},
	{"code": "zh", "name": "中文"},
	{"code": "ja", "name": "日本語"},
	{"code": "ko", "name": "한국어"},
]

## Left-column rows. "language" cycles the locale; "bool" flips a Settings flag.
const ROWS := [
	{"kind": "language", "label": "LANGUAGE", "desc": "UI display language."},
	{"kind": "bool", "key": "effects_enabled", "label": "SCREEN EFFECTS", "desc": "Film grade + CRT scanline overlay on every screen."},
	{"kind": "bool", "key": "menu_hints", "label": "MENU HINTS", "desc": "Show the navigation key hints in menus by default (F1 toggles them anywhere)."},
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

	for i in ROWS.size():
		var card := OptionCard.new()
		_shell.left_column.add_child(card)
		card.set_data(i, _row_label(i), true)
		card.hovered.connect(_on_card_hovered)
		card.clicked.connect(_activate)
		card.activated.connect(_activate)
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
	var row: Dictionary = ROWS[i]
	if row["kind"] == "language":
		return "%s   [ %s ]" % [tr(row["label"]), _language_name()]
	var on := Settings.get_bool(row["key"])
	return "%s   [ %s ]" % [tr(row["label"]), tr("ON", &"toggle") if on else tr("OFF", &"toggle")]


## The endonym of the currently saved locale (the picker cycles the saved value,
## independent of any --debug-mode --locale override).
func _language_name() -> String:
	var code := String(Settings.get_value(Settings.LANGUAGE))
	for lang: Dictionary in LANGUAGES:
		if lang["code"] == code:
			return lang["name"]
	return LANGUAGES[0]["name"]


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_data(i, _row_label(i), true)
		_cards[i].set_selected(i == _cursor)
	var shown := _hover_pos if _hover_pos >= 0 else _cursor
	if shown >= 0 and shown < ROWS.size():
		_title.text = ROWS[shown]["label"]
		_desc.text = ROWS[shown]["desc"]


func _activate(i: int) -> void:
	if i < 0 or i >= ROWS.size():
		return
	_cursor = i
	var row: Dictionary = ROWS[i]
	if row["kind"] == "language":
		_cycle_language()
	else:
		var key: String = row["key"]
		Settings.set_value(key, not Settings.get_bool(key))
		store.save()
		_refresh()


## Advance to the next locale, apply it live, and persist. The auto-translated
## chrome (breadcrumb, hint bar, detail pane) refreshes itself on the
## TranslationServer locale change; only the format-string row labels need the
## explicit _refresh().
func _cycle_language() -> void:
	var code := String(Settings.get_value(Settings.LANGUAGE))
	var idx := 0
	for i in LANGUAGES.size():
		if LANGUAGES[i]["code"] == code:
			idx = i
			break
	var next_code: String = LANGUAGES[(idx + 1) % LANGUAGES.size()]["code"]
	Settings.set_value(Settings.LANGUAGE, next_code)
	TranslationServer.set_locale(next_code)
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
	_cursor = wrapi(_cursor + delta, 0, ROWS.size())
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
			_activate(_cursor)
		KEY_F1:
			Settings.toggle_menu_hints()
			_shell.refresh_hint_visibility()

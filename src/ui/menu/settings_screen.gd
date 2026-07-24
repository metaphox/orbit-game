class_name SettingsScreen
extends CanvasLayer
## Two-pane device settings: left column of rows (a language picker + toggles),
## right pane. When the LANGUAGE row is the current selection its right pane IS
## the locale list (every autonym, active one highlighted) — no extra click; for
## the toggle rows the right pane describes the focused row. Up/Down (also W/S,
## K/J) move rows, Enter flips a toggle or steps into the locale list, Esc backs.

signal back_pressed

const HINT := "↑↓ / W S / K J  SELECT     ENTER  TOGGLE     [ESC]  BACK     [F1]  HIDE"
const LANG_HINT := "↑↓ / W S / K J  SELECT     ENTER  CONFIRM     [ESC]  CANCEL     [F1]  HIDE"
const GLOBE := preload("res://assets/textures/icons/globe.svg")

## Selectable UI locales, in list order. Names are endonyms (never translated).
## Untranslated locales fall back to English text but still set the preference.
const LANGUAGES := [
	{"code": "en", "name": "English"},   # i18n-ok: endonym (a language's own name)
	{"code": "de", "name": "Deutsch"},   # i18n-ok: endonym
	{"code": "fr", "name": "Français"},  # i18n-ok: endonym
	{"code": "ru", "name": "Русский"},
	{"code": "zh_CN", "name": "简体中文"},
	{"code": "zh_TW", "name": "繁體中文"},
	{"code": "ja", "name": "日本語"},
	{"code": "ko", "name": "한국어"},
]

## Left-column rows. "language" opens the locale list; "bool" flips a Settings flag.
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
var _right_mode := ""  # "detail" | "list" — which content the right pane holds

## _lang_open is keyboard focus INSIDE the locale list (↑↓/Enter pick a language).
## The list is *shown* whenever the LANGUAGE row is selected; focus only decides
## whether ↑↓ move the highlight or move between rows.
var _lang_open := false
var _lang_cursor := 0
var _lang_cards: Array[OptionCard] = []


func build(profile_store: ProfileStore) -> void:
	store = profile_store
	_shell = MenuShell.create()
	add_child(_shell)
	_shell.configure("MAIN MENU ▶ SETTINGS")
	_shell.set_hint(HINT)

	for i in ROWS.size():
		var card := OptionCard.new()
		_shell.left_column.add_child(card)
		card.set_data(i, _row_label(i), true)
		if ROWS[i]["kind"] == "language":
			card.set_icon(GLOBE)
		card.hovered.connect(_on_card_hovered)
		card.unhovered.connect(_on_card_unhovered)
		card.clicked.connect(_activate)
		card.activated.connect(_activate)
		_cards.append(card)
	_shell.left_column.mouse_exited.connect(_clear_hover)

	_refresh()  # cursor starts on the LANGUAGE row, so the list shows immediately
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _language_row() -> int:
	for i in ROWS.size():
		if ROWS[i]["kind"] == "language":
			return i
	return 0


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


## The endonym of the locale actually in effect (so a --debug-mode --locale=
## override, or a just-picked language, is reflected here — not the stale saved
## preference).
func _language_name() -> String:
	return String(LANGUAGES[_current_language_index()]["name"])


## Index of the active locale in LANGUAGES, matched against the live
## TranslationServer locale (exact first, then by language subtag).
func _current_language_index() -> int:
	var cur := TranslationServer.get_locale()
	for i in LANGUAGES.size():
		if String(LANGUAGES[i]["code"]) == cur:
			return i
	for i in LANGUAGES.size():
		if String(LANGUAGES[i]["code"]).split("_")[0] == cur.split("_")[0]:
			return i
	return 0


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_data(i, _row_label(i), true)
		if ROWS[i]["kind"] == "language":
			_cards[i].set_icon(GLOBE)
		_cards[i].set_selected(i == _cursor)
	_sync_right()


## Decide what the right pane holds. The locale list shows when the LANGUAGE row
## is the committed selection and we aren't previewing a different (hovered) row;
## otherwise the text detail of the shown row.
func _sync_right() -> void:
	var lang_row := _language_row()
	var hovering_other := _hover_pos >= 0 and _hover_pos != lang_row
	var want_list := _cursor == lang_row and not hovering_other
	if want_list:
		if _right_mode != "list":
			_right_mode = "list"
			_shell.set_right(_build_language_list())
		_refresh_language_cards()
	else:
		if _right_mode != "detail":
			_right_mode = "detail"
			_shell.set_right(_build_detail())
		_update_detail()


func _update_detail() -> void:
	var shown := _hover_pos if _hover_pos >= 0 else _cursor
	if _title != null and shown >= 0 and shown < ROWS.size():
		_title.text = ROWS[shown]["label"]
		_desc.text = ROWS[shown]["desc"]


func _activate(i: int) -> void:
	if _lang_open or i < 0 or i >= ROWS.size():
		return
	_cursor = i
	var row: Dictionary = ROWS[i]
	if row["kind"] == "language":
		_enter_language_focus()
	else:
		var key: String = row["key"]
		Settings.set_value(key, not Settings.get_bool(key))
		store.save()
		_refresh()


## Step keyboard focus into the already-visible locale list.
func _enter_language_focus() -> void:
	_lang_open = true
	_lang_cursor = _current_language_index()
	_shell.set_hint(LANG_HINT)
	_refresh()


## Apply + persist a locale (the auto-translated chrome refreshes on the
## TranslationServer change) and drop back out of list focus.
func _apply_language(code: String) -> void:
	Settings.set_value(Settings.LANGUAGE, code)
	TranslationServer.set_locale(code)
	UiTheme.apply_locale_fonts(code)  # swap the CJK fallback (M PLUS for ja)
	store.save()


func _confirm_language(pos: int) -> void:
	_apply_language(String(LANGUAGES[pos]["code"]))
	_lang_open = false
	_shell.set_hint(HINT)
	_refresh()


func _cancel_language_focus() -> void:
	_lang_open = false
	_shell.set_hint(HINT)
	_refresh()


## The right pane for the LANGUAGE row: an eyebrow + one card per locale, each
## labelled with its own autonym. Cards are labelled in _refresh_language_cards()
## once the panel is in the tree (so each OptionCard._ready has built its label).
func _build_language_list() -> Control:
	_lang_cards.clear()
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InstrumentPanel"  # i18n-ok: theme variation token
	var pad := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)
	var eyebrow := Label.new()
	eyebrow.theme_type_variation = &"Eyebrow"  # i18n-ok: theme variation token
	eyebrow.text = "LANGUAGE"
	col.add_child(eyebrow)
	for _i in LANGUAGES.size():
		var card := OptionCard.new()
		col.add_child(card)
		card.clicked.connect(_confirm_language)
		card.activated.connect(_confirm_language)
		_lang_cards.append(card)
	return panel


## Label the list + highlight the entry that ↑↓ (when focused) or the active
## locale (when not) points at.
func _refresh_language_cards() -> void:
	var hi := _lang_cursor if _lang_open else _current_language_index()
	for i in _lang_cards.size():
		_lang_cards[i].set_data(i, String(LANGUAGES[i]["name"]), true)  # i18n-ok: endonym list
		_lang_cards[i].set_selected(i == hi)


func _move_language(delta: int) -> void:
	_lang_cursor = wrapi(_lang_cursor + delta, 0, LANGUAGES.size())
	for i in _lang_cards.size():
		_lang_cards[i].set_selected(i == _lang_cursor)


func _on_card_hovered(pos: int) -> void:
	if _lang_open:
		return  # focus is in the locale list; row hovers don't disturb it
	_hover_pos = pos
	_refresh()


func _on_card_unhovered(pos: int) -> void:
	if _lang_open:
		return
	if _hover_pos == pos:
		_hover_pos = -1
		_refresh()


func _clear_hover() -> void:
	if _lang_open:
		return
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
	if key.physical_keycode == KEY_F1:
		Settings.toggle_menu_hints()
		_shell.refresh_hint_visibility()
		return
	if _lang_open:
		_language_input(key.physical_keycode)
	else:
		_settings_input(key.physical_keycode)


func _settings_input(code: int) -> void:
	match code:
		KEY_ESCAPE:
			back_pressed.emit()
		KEY_UP, KEY_W, KEY_K:
			_move_cursor(-1)
		KEY_DOWN, KEY_S, KEY_J:
			_move_cursor(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate(_cursor)


func _language_input(code: int) -> void:
	match code:
		KEY_ESCAPE:
			_cancel_language_focus()  # keep the current locale
		KEY_UP, KEY_W, KEY_K:
			_move_language(-1)
		KEY_DOWN, KEY_S, KEY_J:
			_move_language(1)
		KEY_ENTER, KEY_KP_ENTER:
			_confirm_language(_lang_cursor)

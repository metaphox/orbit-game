class_name LoadProfileScreen
extends CanvasLayer
## Two-pane pilot picker: left column of profile cards, right pane with the
## focused pilot's progress and a LOAD button. Keyboard Up/Down (also W/S, K/J)
## select, Enter loads, Esc cancels; mouse hover previews, click selects,
## LOAD/double-click loads. F1 toggles the compact hint bar.

signal profile_chosen(profile_name: String)
signal cancelled

const HINT := "↑↓ / W S / K J  SELECT     ENTER  LOAD     [ESC]  CANCEL     [F1]  HIDE"

var store: ProfileStore
var _cursor := 0
var _hover_pos := -1
var _shell: MenuShell
var _cards: Array[OptionCard] = []
var _name: Label
var _stats: Label
var _load: Button


func build(profile_store: ProfileStore) -> void:
	store = profile_store
	_shell = MenuShell.new()
	add_child(_shell)
	_shell.configure("MAIN MENU ▶ LOAD PILOT")
	_shell.set_hint(HINT)
	_shell.set_right(_build_detail())

	if store.profiles.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = UiTheme.MENU_SUBTITLE
		empty.text = "NO PROFILES YET"
		_shell.left_column.add_child(empty)
	for i in store.profiles.size():
		var card := OptionCard.new()
		_shell.left_column.add_child(card)
		card.set_data(i, store.profiles[i].profile_name, true)
		card.hovered.connect(_on_card_hovered)
		card.clicked.connect(_on_card_clicked)
		card.activated.connect(func(_p: int) -> void: _activate())
		_cards.append(card)
	_shell.left_column.mouse_exited.connect(_clear_hover)

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _build_detail() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.INSTRUMENT_PANEL
	var pad := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	pad.add_child(col)

	col.add_child(_lbl(UiTheme.EYEBROW, "PILOT"))
	_name = _lbl(UiTheme.MENU_TITLE, "")
	col.add_child(_name)
	_stats = _lbl(UiTheme.MONO_SMALL, "")
	col.add_child(_stats)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grow)
	_load = Button.new()
	_load.theme_type_variation = UiTheme.PRIMARY_BUTTON
	_load.focus_mode = Control.FOCUS_NONE
	_load.text = "LOAD PILOT ▶"
	_load.pressed.connect(func() -> void:
		if not _load.disabled:
			_activate())
	col.add_child(_load)
	return panel


func _lbl(variation: StringName, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	return l


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _cursor)
	var shown := _hover_pos if _hover_pos >= 0 else _cursor
	if shown >= 0 and shown < store.profiles.size():
		var profile: Profile = store.profiles[shown]
		var done := 0
		for index in Campaign.order():
			if profile.medal_for(index) != "":
				done += 1
		_name.text = profile.profile_name
		_stats.text = "COMPLETED  %d / %d\nMODE       %s" % [
			done, Campaign.level_count(), "HARDCORE" if profile.hardcore else "NORMAL"]
		_load.disabled = false
	else:
		_name.text = "—"
		_stats.text = ""
		_load.disabled = true


func _on_card_hovered(pos: int) -> void:
	_hover_pos = pos
	_refresh()


func _clear_hover() -> void:
	if _hover_pos != -1:
		_hover_pos = -1
		_refresh()


func _on_card_clicked(pos: int) -> void:
	_cursor = pos
	_hover_pos = -1
	_refresh()


func _move_cursor(delta: int) -> void:
	var n := store.profiles.size()
	if n == 0:
		return
	_cursor = wrapi(_cursor + delta, 0, n)
	_hover_pos = -1
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
			_shell.refresh_hint_visibility()

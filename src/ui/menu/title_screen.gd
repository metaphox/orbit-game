class_name TitleScreen
extends CanvasLayer
## Two-pane main menu (ORBITAL-OS): left column of option cards, right hero panel
## with the game title, tagline, and a per-option contextual blurb. CONTINUE is
## disabled with no active profile; NEW once profile slots are full. Keyboard
## Up/Down (also W/S, K/J) + Enter; mouse hover previews the blurb, click
## activates. F1 toggles the compact hint bar (hidden by default).

signal continue_pressed
signal new_pressed
signal load_pressed
signal settings_pressed
signal credits_pressed
signal quit_pressed

const HINT := "↑ ↓ / W S / K J  SELECT     ENTER  CONFIRM     [F1]  HIDE"

var _store: ProfileStore
var _items: Array = []  # [label: String, enabled: bool]
var _cursor := 0
var _hover_pos := -1
var _shell: MenuShell
var _cards: Array[OptionCard] = []
var _blurb: Label
var _status: Label


func build(store: ProfileStore) -> void:
	_store = store
	var last_profile := store.last_active_profile()
	_items = [
		["CONTINUE", last_profile != null],
		["NEW PROFILE", store.can_create_profile()],
		["LOAD PROFILE", true],
		["SETTINGS", true],
		["CREDITS", true],
		["QUIT", true],
	]
	_cursor = _first_enabled()

	_shell = MenuShell.create()
	add_child(_shell)
	_shell.configure("MAIN MENU")
	_shell.set_hint(HINT)
	_shell.set_right(_build_hero())

	for i in _items.size():
		var card := OptionCard.new()
		_shell.left_column.add_child(card)
		card.set_data(i, _items[i][0], _items[i][1])
		card.hovered.connect(_on_card_hovered)
		card.clicked.connect(_select_and_activate)
		card.activated.connect(_select_and_activate)
		_cards.append(card)
	_shell.left_column.mouse_exited.connect(_clear_hover)

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


## The right hero panel is authored in title_hero.tscn (editable in the editor);
## this only fills the `%`-named blurb/status slots and appends a load warning.
func _build_hero() -> Control:
	var hero := preload("res://src/ui/menu/title_hero.tscn").instantiate()
	_blurb = hero.get_node("%Blurb")
	_status = hero.get_node("%Status")
	if _store.load_warning != "":
		var warn := Label.new()
		warn.theme_type_variation = UiTheme.MENU_WARNING
		warn.text = "⚠ %s" % _store.load_warning
		(hero.get_node("%Col") as VBoxContainer).add_child(warn)
	return hero


func _first_enabled() -> int:
	for i in _items.size():
		if _items[i][1]:
			return i
	return 0


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _cursor)
	var shown := _hover_pos if _hover_pos >= 0 else _cursor
	_blurb.text = _blurb_for(shown)
	_status.text = tr("%d / %d PROFILE SLOTS") % [_store.profiles.size(), ProfileStore.MAX_PROFILES]


func _blurb_for(i: int) -> String:
	match i:
		0:
			var lp := _store.last_active_profile()
			if lp != null and lp.mission_save != null:
				var idx: int = lp.mission_save.get("level_index", 0)
				return tr("RESUME  %s · %s  %s") % [lp.profile_name, Campaign.code(idx), tr(Campaign.short_title(idx))]
			return "NO MISSION IN PROGRESS"
		1:
			return "CREATE A NEW PILOT" if _items[1][1] else "ALL PROFILE SLOTS ARE FULL"
		2:
			return "SWITCH THE ACTIVE PILOT"
		3:
			return "DISPLAY & EFFECTS"
		4:
			return "ABOUT LIMITED PROPELLANT"
		5:
			return "EXIT TO DESKTOP"
	return ""


func _on_card_hovered(pos: int) -> void:
	_hover_pos = pos
	_refresh()


func _clear_hover() -> void:
	if _hover_pos != -1:
		_hover_pos = -1
		_refresh()


func _move_cursor(delta: int) -> void:
	var n := _items.size()
	var i := _cursor
	for _step in n:
		i = wrapi(i + delta, 0, n)
		if _items[i][1]:
			_cursor = i
			_hover_pos = -1
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
		KEY_UP, KEY_W, KEY_K:
			_move_cursor(-1)
		KEY_DOWN, KEY_S, KEY_J:
			_move_cursor(1)
		KEY_ENTER, KEY_KP_ENTER:
			_select_and_activate(_cursor)
		KEY_F1:
			Settings.toggle_menu_hints()
			_shell.refresh_hint_visibility()

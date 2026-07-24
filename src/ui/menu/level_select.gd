class_name LevelSelect
extends CanvasLayer
## Two-pane mission select (ref/ref-menu-design.png): a left column of act-grouped
## mission cards and a right detail pane (brief + orbit preview + stats + LAUNCH).
## Keyboard: Up/Down (also W/S, K/J) move the selected mission (locked ones
## skipped); Left/Right (also A/D, H/L) jump acts; Enter launches. Mouse: hover
## live-previews a card in the detail pane, click selects, LAUNCH / double-click
## launches. Key hints are hidden by default; F1 toggles the compact hint bar.

signal level_chosen(index: int)
signal back_pressed

const HINT := "↑↓ / W S / K J  MISSION     ← → / A D / H L  ACT     ENTER  LAUNCH     [ESC]  TITLE     [F1]  HIDE"

var _order: Array[int]
var _profile: Profile
var _cursor := 0
var _hover_pos := -1
var _shell: MenuShell
var _detail: MissionDetailPane
var _cards: Array[MissionCard] = []


func build(profile: Profile) -> void:
	_profile = profile
	_order = Campaign.order()
	_cursor = _first_unlocked_pos()

	_shell = MenuShell.create()
	add_child(_shell)
	_shell.configure("MAIN MENU ▶ MISSIONS")
	_shell.set_hint(HINT)

	_detail = MissionDetailPane.create()
	_detail.launch_requested.connect(func(index: int) -> void: level_chosen.emit(index))
	_shell.set_right(_detail)

	_build_cards()
	_shell.left_column.mouse_exited.connect(_clear_hover)

	if Settings.effects_enabled:
		add_child(ScreenGrade.new())
	_refresh()


func _build_cards() -> void:
	_cards.clear()
	var back := Button.new()
	back.theme_type_variation = UiTheme.CARD
	back.focus_mode = Control.FOCUS_NONE
	back.text = "◀  BACK"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.custom_minimum_size = Vector2(0, 48)  # 6×8
	back.pressed.connect(func() -> void: back_pressed.emit())
	_shell.left_column.add_child(back)

	var pos := 0
	for act: Dictionary in Campaign.acts():
		var header := Label.new()
		header.theme_type_variation = UiTheme.ACT_HEADER
		header.text = act["name"]
		var head_wrap := MarginContainer.new()
		head_wrap.add_theme_constant_override("margin_top", 16)   # section break above act
		head_wrap.add_theme_constant_override("margin_left", 16)  # align with card text gutter
		head_wrap.add_theme_constant_override("margin_bottom", 4)
		head_wrap.add_child(header)
		_shell.left_column.add_child(head_wrap)
		for index: int in act["indices"]:
			var card := MissionCard.new()
			_shell.left_column.add_child(card)
			card.set_data(pos, Campaign.code(index), Campaign.short_title(index),
				Campaign.status_label(_profile, index), Campaign.level_at(index).difficulty,
				not _is_selectable(index))
			card.hovered.connect(_on_card_hovered)
			card.clicked.connect(_on_card_clicked)
			card.activated.connect(_on_card_activated)
			_cards.append(card)
			pos += 1


func _first_unlocked_pos() -> int:
	for i in _order.size():
		if _is_selectable(_order[i]):
			return i
	return 0


## True if the mission can be flown right now: unlocked on the profile, or
## Settings.debug_mode is bypassing the lock entirely.
func _is_selectable(index: int) -> bool:
	return Settings.debug_mode or _profile.is_unlocked(index)


## Repaint card selection and drive the detail pane (hovered card if any, else
## the selected one), keeping the selected card scrolled into view.
func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _cursor)
	var shown := _hover_pos if _hover_pos >= 0 else _cursor
	if shown >= 0 and shown < _order.size():
		var index: int = _order[shown]
		_detail.show_level(index, _profile)
		_detail.set_launch_enabled(_is_selectable(index))
	if _cursor >= 0 and _cursor < _cards.size():
		_shell.ensure_visible(_cards[_cursor])


func _on_card_hovered(pos: int) -> void:
	_hover_pos = pos
	_refresh()


func _clear_hover() -> void:
	if _hover_pos != -1:
		_hover_pos = -1
		_refresh()


func _on_card_clicked(pos: int) -> void:
	if pos < 0 or pos >= _order.size() or not _is_selectable(_order[pos]):
		return
	_cursor = pos
	_hover_pos = -1
	_refresh()


func _on_card_activated(pos: int) -> void:
	_select_and_activate(pos)


func _move_cursor(delta: int) -> void:
	var n := _order.size()
	if n == 0:
		return
	var i := _cursor
	for _step in n:
		i = wrapi(i + delta, 0, n)
		if _is_selectable(_order[i]):
			_cursor = i
			_hover_pos = -1
			_refresh()
			return


## Boundaries [start, end) of each act within _order — act order equals play
## order, so the flat _order is the acts' indices concatenated.
func _act_bounds() -> Array:
	var bounds: Array = []
	var start := 0
	for act: Dictionary in Campaign.acts():
		var count: int = act["indices"].size()
		bounds.append([start, start + count])
		start += count
	return bounds


func _current_act(bounds: Array) -> int:
	for a: int in bounds.size():
		if _cursor >= bounds[a][0] and _cursor < bounds[a][1]:
			return a
	return 0


## Jump the cursor to the first selectable mission of the previous/next act,
## skipping acts whose missions are all locked. No-op with a single act.
func _move_act(delta: int) -> void:
	var bounds := _act_bounds()
	var n := bounds.size()
	if n <= 1:
		return
	var a := _current_act(bounds)
	for _step: int in n:
		a = wrapi(a + delta, 0, n)
		for pos: int in range(bounds[a][0], bounds[a][1]):
			if _is_selectable(_order[pos]):
				_cursor = pos
				_hover_pos = -1
				_refresh()
				return


func _select_and_activate(pos: int) -> void:
	if pos < 0 or pos >= _order.size():
		return
	var index: int = _order[pos]
	if not _is_selectable(index):
		return
	_cursor = pos
	level_chosen.emit(index)


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
		KEY_LEFT, KEY_A, KEY_H:
			_move_act(-1)
		KEY_RIGHT, KEY_D, KEY_L:
			_move_act(1)
		KEY_ENTER, KEY_KP_ENTER:
			_select_and_activate(_cursor)
		KEY_F1:
			Settings.toggle_menu_hints()
			_shell.refresh_hint_visibility()

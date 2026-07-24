class_name PauseMenu
extends CanvasLayer
## In-flight pause overlay: a translucent scrim over the frozen flight (so it
## still shows through) with a centered card list — Resume / Save / Restart /
## Quit. Keyboard Up/Down (also W/S, K/J) + Enter; mouse hover outlines, click
## activates. The resume keys always show; F1 adds the nav hints and is swallowed
## so it doesn't also open the in-flight HUD keybind overlay behind the menu.

signal resume_pressed
signal save_pressed
signal restart_pressed
signal quit_pressed

var _items: Array[String] = ["RESUME", "SAVE PROGRESS", "RESTART MISSION", "QUIT TO MISSION SELECT"]
var _cursor := 0
var _saved_flash := false
var _cards: Array[OptionCard] = []
var _saved: Label
var _hint: Label


func build() -> void:
	var root := Control.new()
	root.theme = UiTheme.shared()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var scrim := ColorRect.new()
	scrim.color = Palette.PAUSE_BG  # lint-ok: runtime scrim fill from Palette
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.MODAL_PANEL
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(384, 0)  # 48×8
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)

	var title := Label.new()
	title.theme_type_variation = UiTheme.MENU_TITLE
	title.text = "PAUSED"
	col.add_child(title)

	for i in _items.size():
		var card := OptionCard.new()
		col.add_child(card)
		card.set_data(i, _items[i], true)
		card.hovered.connect(func(p: int) -> void: _select(p))
		card.clicked.connect(_activate)
		card.activated.connect(_activate)
		_cards.append(card)

	_saved = Label.new()
	_saved.theme_type_variation = UiTheme.MENU_SUBTITLE
	_saved.text = "✓ PROGRESS SAVED   (rewind anchors are not saved)"
	_saved.visible = false
	col.add_child(_saved)

	_hint = Label.new()
	_hint.theme_type_variation = UiTheme.MENU_FOOTER
	col.add_child(_hint)
	_refresh()


func show_saved_confirmation() -> void:
	_saved_flash = true
	_refresh()


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _cursor)
	_saved.visible = _saved_flash
	var nav := "↑↓ / W S / K J  SELECT   ENTER CONFIRM   [F1] HIDE   " \
		if Settings.menu_hints_on() else "[F1] KEYS   "
	_hint.text = nav + "[ESC]/[SPACE]/[0] RESUME"


func _select(i: int) -> void:
	_cursor = i
	_saved_flash = false
	_refresh()


func _move_cursor(delta: int) -> void:
	_cursor = wrapi(_cursor + delta, 0, _items.size())
	_saved_flash = false
	_refresh()


func _activate(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	_cursor = i
	_saved_flash = false
	match i:
		0:
			resume_pressed.emit()
		1:
			save_pressed.emit()
		2:
			restart_pressed.emit()
		3:
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
			_activate(_cursor)
		KEY_F1:
			Settings.toggle_menu_hints()
			_refresh()
			get_viewport().set_input_as_handled()

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


## The overlay layout is authored in pause_menu_layout.tscn (editable in the
## editor); this fills the `%CardSlot` with cards and wires the slots. The scrim
## fill stays code-set so it stays sourced from Palette.
func build() -> void:
	var layout := preload("res://src/ui/menu/pause_menu_layout.tscn").instantiate()
	add_child(layout)
	(layout.get_node("%Scrim") as ColorRect).color = Palette.PAUSE_BG  # lint-ok: runtime scrim fill from Palette
	_saved = layout.get_node("%Saved")
	_hint = layout.get_node("%Hint")

	var card_slot: VBoxContainer = layout.get_node("%CardSlot")
	for i in _items.size():
		var card := OptionCard.new()
		card_slot.add_child(card)
		card.set_data(i, _items[i], true)
		card.hovered.connect(func(p: int) -> void: _select(p))
		card.clicked.connect(_activate)
		card.activated.connect(_activate)
		_cards.append(card)
	_refresh()


func show_saved_confirmation() -> void:
	_saved_flash = true
	_refresh()


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _cursor)
	_saved.visible = _saved_flash
	var nav := tr("↑↓ / W S / K J  SELECT   ENTER CONFIRM   [F1] HIDE   ") \
		if Settings.menu_hints_on() else tr("[F1] KEYS   ")
	_hint.text = nav + tr("[ESC]/[SPACE]/[0] RESUME")


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

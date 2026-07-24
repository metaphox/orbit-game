class_name ConfirmPopup
extends CanvasLayer
## A themed modal confirm: a scrim over whatever's behind and a centered panel
## with a title and two stacked cards (confirm / cancel). Keyboard Up/Down move,
## Enter activates, Esc cancels; all key input is swallowed so the screen behind
## stays inert. The cursor defaults to CANCEL — safe for destructive actions.

signal confirmed
signal cancelled

const GRID := 8

var _cards: Array[OptionCard] = []
var _cursor := 1  # default to CANCEL


## Build + show. Labels are English keys (msgids) — they auto-translate.
func open(title_text: String, confirm_label: String, cancel_label: String) -> void:
	layer = 100  # above the menu / HUD layers

	var scrim := ColorRect.new()
	scrim.color = Palette.SCRIM  # lint-ok: runtime scrim fill from Palette
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks meant for behind
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.theme = UiTheme.shared()
	panel.theme_type_variation = &"InstrumentPanel"  # i18n-ok: theme variation token
	panel.custom_minimum_size = Vector2(GRID * 52, 0)  # 416
	center.add_child(panel)

	var pad := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, GRID * 3)  # 24
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", GRID * 2)  # 16
	pad.add_child(col)

	var title := Label.new()
	title.theme_type_variation = UiTheme.MENU_TITLE
	title.text = title_text
	col.add_child(title)

	for i in [confirm_label, cancel_label].size():
		var card := OptionCard.new()
		col.add_child(card)
		card.set_data(i, [confirm_label, cancel_label][i], true)
		card.hovered.connect(func(p: int) -> void: _select(p))
		card.clicked.connect(_activate)
		card.activated.connect(_activate)
		_cards.append(card)
	_refresh()


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _cursor)


func _select(i: int) -> void:
	_cursor = i
	_refresh()


func _activate(i: int) -> void:
	if i == 0:
		confirmed.emit()
	else:
		cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_UP, KEY_W, KEY_K, KEY_DOWN, KEY_S, KEY_J:
			_cursor = wrapi(_cursor + 1, 0, _cards.size())
			_refresh()
		KEY_ENTER, KEY_KP_ENTER:
			_activate(_cursor)
		KEY_ESCAPE:
			cancelled.emit()
	get_viewport().set_input_as_handled()  # modal: nothing leaks to the screen behind

class_name OptionCard
extends Button
## A single-label list card for menus that aren't the mission list (main menu,
## pause). A themed Button with the same selected(green)/hover/disabled states as
## MissionCard, minus the code/status/pips. Selection is applied by the owning
## screen (`set_selected`); mouse hover/click/double-click surface as signals.

signal hovered(pos: int)
signal clicked(pos: int)
signal activated(pos: int)

const GRID := 8

var pos := -1
var _selected := false
var _enabled_flag := true
var _label: Label


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, GRID * 7)  # 56
	theme_type_variation = UiTheme.CARD

	var row := MarginContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	_label = Label.new()
	_label.theme_type_variation = UiTheme.TITLE_OBJECTIVE
	_label.add_theme_font_override("font", UiTheme.DISPLAY_SEMI)
	_label.add_theme_font_size_override("font_size", 18)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)

	mouse_entered.connect(func() -> void: hovered.emit(pos))
	pressed.connect(func() -> void: clicked.emit(pos))
	gui_input.connect(_on_gui_input)
	_apply()


func set_data(p_pos: int, label_text: String, enabled: bool) -> void:
	pos = p_pos
	_enabled_flag = enabled
	disabled = not enabled
	_label.text = label_text
	if is_node_ready():
		_apply()


func set_selected(selected: bool) -> void:
	_selected = selected
	if is_node_ready():
		_apply()


func _apply() -> void:
	theme_type_variation = UiTheme.CARD_SELECTED if _selected else UiTheme.CARD
	var color := Palette.VOID if _selected else (Palette.LIVE if _enabled_flag else Palette.DISABLED)
	_label.add_theme_color_override("font_color", color)


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(pos)

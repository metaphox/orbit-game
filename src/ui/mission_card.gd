class_name MissionCard
extends Button
## One mission row in the two-pane mission select. A themed Button (so hover /
## pressed / disabled states come from the theme) whose content — code chip,
## name, status, difficulty pips, and a selected-cursor arrow — is built here.
## Selection (filled bright green + dark text) is applied by swapping the theme
## variation and overriding the child text to VOID. Locked = a disabled Button.

signal hovered(pos: int)
signal clicked(pos: int)
signal activated(pos: int)

var pos := -1
var _locked := false
var _selected := false
var _status_text := ""

var _code: Label
var _name: Label
var _status: Label
var _pips: DifficultyPips
var _cursor: Label


const GRID := 8


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, GRID * 7)  # 56
	theme_type_variation = UiTheme.CARD

	# The card's stylebox pads 16h/8v; this row fills the padded interior.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", GRID * 2)  # 16
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)

	_code = _mk_label(UiTheme.MONO_SMALL)
	_code.custom_minimum_size = Vector2(GRID * 7, 0)  # 56, aligns names across cards
	_code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_code)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 4)  # half-step between name and status
	row.add_child(col)

	_name = _mk_label(UiTheme.TITLE_OBJECTIVE)
	_name.add_theme_font_override("font", UiTheme.DISPLAY_SEMI)
	_name.add_theme_font_size_override("font_size", 19)
	col.add_child(_name)

	var sub := HBoxContainer.new()
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_constant_override("separation", GRID)  # 8
	col.add_child(sub)
	_status = _mk_label(UiTheme.MENU_FOOTER)
	sub.add_child(_status)
	_pips = DifficultyPips.new()
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.add_child(_pips)

	_cursor = _mk_label(UiTheme.MENU_TITLE)
	_cursor.text = "◀"
	_cursor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cursor.visible = false
	row.add_child(_cursor)

	mouse_entered.connect(func() -> void: hovered.emit(pos))
	pressed.connect(func() -> void: clicked.emit(pos))
	gui_input.connect(_on_gui_input)
	_apply_style()


func _mk_label(variation: StringName) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_data(p_pos: int, code: String, mission_name: String, status_text: String,
		difficulty: int, locked: bool) -> void:
	pos = p_pos
	_locked = locked
	_status_text = status_text
	disabled = locked
	_code.text = code
	_name.text = mission_name
	_status.text = status_text
	_pips.value = difficulty
	if is_node_ready():
		_apply_style()


func set_selected(selected: bool) -> void:
	_selected = selected
	if is_node_ready():
		_apply_style()


func _apply_style() -> void:
	_cursor.visible = _selected
	_pips.dark = _selected
	theme_type_variation = UiTheme.CARD_SELECTED if _selected else UiTheme.CARD
	if _selected:
		for l: Label in [_code, _name, _status, _cursor]:
			l.add_theme_color_override("font_color", Palette.VOID)
		return
	for l: Label in [_code, _name, _status, _cursor]:
		l.remove_theme_color_override("font_color")
	if _locked:
		_name.add_theme_color_override("font_color", Palette.DISABLED)
		_code.add_theme_color_override("font_color", Palette.DISABLED)
		_status.add_theme_color_override("font_color", Palette.DISABLED)
	else:
		_name.add_theme_color_override("font_color", Palette.LIVE)
		_code.add_theme_color_override("font_color", Palette.DIM)
		_status.add_theme_color_override("font_color", _status_color())


func _status_color() -> Color:
	if _status_text.contains("★"):
		return Palette.MEDAL_GOLD
	return Palette.LIVE_DIM


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(pos)

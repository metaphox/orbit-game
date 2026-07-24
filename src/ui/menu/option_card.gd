class_name OptionCard
extends Button
## A single-label list card for menus that aren't the mission list (main menu,
## pause). A themed Button with the same selected(green)/hover/disabled states as
## MissionCard, minus the code/status/pips. Selection is applied by the owning
## screen (`set_selected`); mouse hover/click/double-click surface as signals.

signal hovered(pos: int)
signal unhovered(pos: int)
signal clicked(pos: int)
signal activated(pos: int)

const GRID := 8
## The unhovered signal is held back this long after the mouse leaves, and
## cancelled if the card is re-entered. Moving the pointer straight to another
## card fires that card's `hovered` first, so the owning screen never briefly
## reverts to the selected item's detail between the two (no right-panel flicker).
## Only leaving the list into empty space actually reverts, after this delay.
const HOVER_LINGER := 0.5

var pos := -1
var _selected := false
var _enabled_flag := true
var _label: Label
var _icon: TextureRect
var _icon_tex: Texture2D
var _unhover_timer: Timer


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

	# A trailing status icon (e.g. the settings gear / language globe), anchored
	# to the right edge inside the card's 16px content margin. Overlays the row
	# so the label's position is untouched; hidden until set_icon() gives it one.
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_icon.offset_left = -(16 + GRID * 3)
	_icon.offset_right = -16
	_icon.offset_top = -(GRID * 3) / 2.0
	_icon.offset_bottom = (GRID * 3) / 2.0
	_icon.visible = false
	add_child(_icon)

	_unhover_timer = Timer.new()
	_unhover_timer.one_shot = true
	_unhover_timer.wait_time = HOVER_LINGER
	_unhover_timer.timeout.connect(func() -> void: unhovered.emit(pos))
	add_child(_unhover_timer)

	mouse_entered.connect(func() -> void:
		_unhover_timer.stop()  # cancel a pending revert if we came from another card
		hovered.emit(pos))
	# mouse_exited also fires as the card is torn down on a screen change; by then
	# the timer child may already be out of the tree even if the card reads as in
	# it, so gate on the timer's own membership (start() needs it in the tree).
	mouse_exited.connect(func() -> void:
		if _unhover_timer.is_inside_tree():
			_unhover_timer.start())
	pressed.connect(func() -> void: clicked.emit(pos))
	gui_input.connect(_on_gui_input)
	_apply_icon()
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


## Optional trailing icon (Texture2D or null). White source art is tinted to the
## card's text colour so it inverts on the green selected state, like the label.
func set_icon(tex: Texture2D) -> void:
	_icon_tex = tex
	if is_node_ready():
		_apply_icon()
		_apply()


func _apply_icon() -> void:
	_icon.texture = _icon_tex
	_icon.visible = _icon_tex != null


func _apply() -> void:
	theme_type_variation = UiTheme.CARD_SELECTED if _selected else UiTheme.CARD
	var color := Palette.VOID if _selected else (Palette.LIVE if _enabled_flag else Palette.DISABLED)
	_label.add_theme_color_override("font_color", color)
	if _icon != null:
		_icon.modulate = color


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(pos)

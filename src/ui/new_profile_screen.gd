class_name NewProfileScreen
extends CanvasLayer
## Text-entry screen for creating a new named profile. Validation lives on
## ProfileStore (validate_new_name) so it's testable without simulating
## keystrokes through the LineEdit.

signal profile_created(profile_name: String, hardcore: bool)
signal cancelled

const GREEN := "#73ff8c"
const DIM_GREEN := "#4da362"
const RED := "#ff6b5c"
const AMBER := "#ffcc66"

var store: ProfileStore
var _line_edit: LineEdit
var _error_label: Label
var _hardcore_check: CheckButton
## Hardcore is permanent, so a checked box requires a second ENTER to confirm.
var _confirm_pending := false


func build(profile_store: ProfileStore) -> void:
	store = profile_store

	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.008, 0.016)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(GREEN))
	title.text = "■ NEW PILOT ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)

	var prompt := Label.new()
	prompt.add_theme_font_override("font", font)
	prompt.add_theme_font_size_override("font_size", 15)
	prompt.add_theme_color_override("font_color", Color(DIM_GREEN))
	prompt.text = "ENTER CALLSIGN"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 300)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_line_edit = LineEdit.new()
	_line_edit.max_length = ProfileStore.NAME_MAX_LENGTH
	_line_edit.add_theme_font_override("font", font)
	_line_edit.add_theme_font_size_override("font_size", 22)
	_line_edit.custom_minimum_size = Vector2(320, 40)
	_line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_line_edit)
	_line_edit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 330)
	_line_edit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_line_edit.text_submitted.connect(func(_t: String) -> void: _attempt_create())

	_error_label = Label.new()
	_error_label.add_theme_font_override("font", font)
	_error_label.add_theme_font_size_override("font_size", 14)
	_error_label.add_theme_color_override("font_color", Color(RED))
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_error_label)
	_error_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 392)
	_error_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_hardcore_check = CheckButton.new()
	_hardcore_check.add_theme_font_override("font", font)
	_hardcore_check.add_theme_font_size_override("font_size", 15)
	_hardcore_check.add_theme_color_override("font_color", Color(AMBER))
	_hardcore_check.text = "HARDCORE — no rewind, no guidance (PERMANENT)"
	_hardcore_check.focus_mode = Control.FOCUS_NONE  # keep typing focus on the name field
	add_child(_hardcore_check)
	_hardcore_check.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 430)
	_hardcore_check.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Re-checking or un-checking resets the pending confirmation.
	_hardcore_check.toggled.connect(func(_on: bool) -> void:
		_confirm_pending = false
		_error_label.text = "")

	var help := Label.new()
	help.add_theme_font_override("font", font)
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(DIM_GREEN))
	help.text = "[ENTER] CREATE   [ESC] CANCEL"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)

	if Settings.effects_enabled:
		add_child(ScreenGrade.new())
	_line_edit.grab_focus()


func _attempt_create() -> void:
	var error := store.validate_new_name(_line_edit.text)
	if error != "":
		_error_label.text = error
		return
	var hardcore := _hardcore_check.button_pressed
	# Hardcore can never be changed later, so make the player confirm it once.
	if hardcore and not _confirm_pending:
		_confirm_pending = true
		_error_label.add_theme_color_override("font_color", Color(AMBER))
		_error_label.text = "⚠ HARDCORE IS PERMANENT — PRESS ENTER AGAIN TO CONFIRM"
		return
	profile_created.emit(_line_edit.text.strip_edges(), hardcore)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		cancelled.emit()

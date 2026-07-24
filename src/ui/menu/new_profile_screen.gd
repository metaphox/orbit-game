class_name NewProfileScreen
extends CanvasLayer
## Text-entry screen for creating a new named profile. Validation lives on
## ProfileStore (validate_new_name) so it's testable without simulating
## keystrokes through the LineEdit.

signal profile_created(profile_name: String, hardcore: bool)
signal cancelled

var store: ProfileStore
var _line_edit: LineEdit
var _error_label: Label
var _hardcore_check: CheckButton
## Hardcore is permanent, so a checked box requires a second ENTER to confirm.
var _confirm_pending := false
var _layout: NewProfileLayout


func build(profile_store: ProfileStore) -> void:
	store = profile_store

	_layout = preload("res://src/ui/menu/new_profile_layout.tscn").instantiate()
	add_child(_layout)
	_line_edit = _layout.line_edit
	_line_edit.max_length = ProfileStore.NAME_MAX_LENGTH
	_line_edit.text_submitted.connect(func(_t: String) -> void: _attempt_create())

	_error_label = _layout.error_label
	_hardcore_check = _layout.hardcore_check
	# Re-checking or un-checking resets the pending confirmation.
	_hardcore_check.toggled.connect(func(_on: bool) -> void:
		_confirm_pending = false
		_error_label.text = "")

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
		_error_label.add_theme_color_override("font_color", Palette.INTENT)
		_error_label.text = "⚠ HARDCORE IS PERMANENT — PRESS ENTER AGAIN TO CONFIRM"
		return
	profile_created.emit(_line_edit.text.strip_edges(), hardcore)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		cancelled.emit()

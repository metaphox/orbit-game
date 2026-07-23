@tool
class_name FlightToolbar
extends PanelContainer
## Capability-aware clickable controls. Commands stay semantic so live rebinds work.

signal command(action: String, pressed: bool)
signal keys_requested

const STRIP_GROUPS := [
	["VIEW", [{"action": "toggle_side_camera"}, {"action": "reset_or_restart"}]],
	["THROTTLE", [
		{"action": "throttle_full"}, {"action": "throttle_cut"},
		{"action": "throttle_increase", "hold": true},
		{"action": "throttle_decrease", "hold": true}]],
	["WARP", [{"action": "warp_increase"}, {"action": "warp_decrease"}]],
	["SAS", [
		{"action": "sas_prograde", "cap": "sas"}, {"action": "sas_retrograde", "cap": "sas"},
		{"action": "sas_normal", "cap": "sas"}, {"action": "sas_antinormal", "cap": "sas"},
		{"action": "sas_radial_out", "cap": "sas"}, {"action": "sas_radial_in", "cap": "sas"},
		{"action": "kill_rotation", "cap": "sas"}, {"action": "sas_off", "cap": "sas"},
		{"action": "sas_node_hold", "cap": "nodes"}]],
	["NODE", [
		{"action": "node_create", "cap": "nodes"}, {"action": "node_delete", "cap": "nodes"},
		{"action": "node_time_earlier", "cap": "nodes"}, {"action": "node_time_later", "cap": "nodes"},
		{"action": "node_prograde_increase", "cap": "nodes"},
		{"action": "node_prograde_decrease", "cap": "nodes"},
		{"action": "node_normal_increase", "cap": "nodes"},
		{"action": "node_normal_decrease", "cap": "nodes"},
		{"action": "node_radial_increase", "cap": "nodes"},
		{"action": "node_radial_decrease", "cap": "nodes"}]],
]

const SAS_MODES := {
	"sas_prograde": ShipSim.SasMode.PROGRADE,
	"sas_retrograde": ShipSim.SasMode.RETROGRADE,
	"sas_normal": ShipSim.SasMode.NORMAL,
	"sas_antinormal": ShipSim.SasMode.ANTI_NORMAL,
	"sas_radial_out": ShipSim.SasMode.RADIAL_OUT,
	"sas_radial_in": ShipSim.SasMode.RADIAL_IN,
	"kill_rotation": ShipSim.SasMode.STABILITY,
	"sas_off": ShipSim.SasMode.OFF,
	"sas_node_hold": ShipSim.SasMode.NODE,
}

@onready var groups: HFlowContainer = %Groups

var _buttons: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_groups(null)


func build(level: LevelDef) -> void:
	_clear_groups()
	_build_groups(level)


func _build_groups(level: LevelDef) -> void:
	for group_data: Array in STRIP_GROUPS:
		var group := _make_group(group_data[0], group_data[1], level)
		if group != null:
			groups.add_child(group)
	_add_keys_button()


func _add_keys_button() -> void:
	var keys_button := Button.new()
	keys_button.text = "F1 · ALL KEYS"
	keys_button.focus_mode = Control.FOCUS_NONE
	keys_button.custom_minimum_size = Vector2(0, 22)
	keys_button.theme_type_variation = UiTheme.TOOLBAR_BUTTON
	keys_button.pressed.connect(func() -> void: keys_requested.emit())
	groups.add_child(keys_button)


func _clear_groups() -> void:
	_buttons.clear()
	for child: Node in groups.get_children():
		child.free()


func sync_state(ship: ShipSim) -> void:
	for action: String in SAS_MODES:
		var active: bool = ship.sas_mode == SAS_MODES[action]
		for button: Button in _buttons.get(action, []):
			button.set_pressed_no_signal(active)


func _command_available(entry: Dictionary, level: LevelDef) -> bool:
	if level == null:
		return true
	match entry.get("cap", ""):
		"sas": return level.sas_enabled
		"nodes": return level.nodes_enabled
		_: return true


func _make_group(title: String, entries: Array, level: LevelDef) -> Control:
	var available: Array = entries.filter(
		func(entry: Dictionary) -> bool: return _command_available(entry, level))
	if available.is_empty():
		return null
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 3)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = UiTheme.HUD_VALUE_INTENT
	heading.add_theme_font_size_override("font_size", 9)
	group.add_child(heading)
	for entry: Dictionary in available:
		group.add_child(_make_button(entry))
	return group


func _make_button(entry: Dictionary) -> Button:
	var action: String = entry["action"]
	var button := Button.new()
	button.text = InputBindings.primary_key_label(action)
	button.tooltip_text = action
	button.custom_minimum_size = Vector2(0, 22)
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = UiTheme.TOOLBAR_BUTTON
	if SAS_MODES.has(action):
		button.toggle_mode = true
	if not _buttons.has(action):
		_buttons[action] = []
	(_buttons[action] as Array).append(button)
	if entry.get("hold", false):
		button.button_down.connect(func() -> void: command.emit(action, true))
		button.button_up.connect(func() -> void: command.emit(action, false))
	else:
		button.pressed.connect(func() -> void:
			command.emit(action, true)
			command.emit(action, false))
	return button

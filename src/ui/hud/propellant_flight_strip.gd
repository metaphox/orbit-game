@tool
class_name PropellantFlightStrip
extends Control

signal command(action: String, pressed: bool)
signal keys_requested

@onready var throttle_meter: BarMeter = %ThrottleMeter
@onready var throttle_percent: Label = %ThrottlePercent
@onready var propellant_meter: BarMeter = %PropellantMeter
@onready var propellant_percent: Label = %PropellantPercent
@onready var propellant_extra: Label = %PropellantExtra
@onready var node_label: Label = %NodeLabel
@onready var toolbar: FlightToolbar = %FlightToolbar


func _ready() -> void:
	if not toolbar.command.is_connected(_forward_command):
		toolbar.command.connect(_forward_command)
	if not toolbar.keys_requested.is_connected(_forward_keys_requested):
		toolbar.keys_requested.connect(_forward_keys_requested)
	if not resized.is_connected(_update_responsive_height):
		resized.connect(_update_responsive_height)
	if Engine.is_editor_hint():
		node_label.visible = true
	_update_responsive_height()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		offset_top = -56.0
		node_label.visible = false
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		node_label.visible = true
		_update_responsive_height()


func _forward_command(action: String, pressed: bool) -> void:
	command.emit(action, pressed)


func _forward_keys_requested() -> void:
	keys_requested.emit()


func configure(level: LevelDef) -> void:
	toolbar.build(level)


func refresh(ship: ShipSim, level: LevelDef, sim_time: float) -> void:
	throttle_meter.set_frac(ship.throttle)
	throttle_percent.text = "%.0f%%" % (ship.throttle * 100.0)
	var propellant_fraction := ship.prop_mass / level.prop_mass
	propellant_meter.set_frac(propellant_fraction)
	propellant_percent.text = "%.0f%%" % (propellant_fraction * 100.0)
	propellant_extra.text = tr("Δv %.1f · USED %.1f") % [ship.dv_remaining(), ship.dv_used()]

	node_label.visible = ship.node != null
	if ship.node != null:
		var delta_v := ship.node.total_dv()
		var exhaust_velocity := ship.isp * Integrator.G0
		var burn_time := ship.mass() * (1.0 - exp(-delta_v / exhaust_velocity)) / (
			ship.thrust_max / exhaust_velocity)
		node_label.text = tr("NODE Δv %.1f · T%+.0fs · BURN %.0fs · REM %.1f") % [
			delta_v, sim_time - ship.node.t_node, burn_time, ship.node.remaining.length()]
	toolbar.sync_state(ship)

func _update_responsive_height() -> void:
	offset_top = -116.0 if size.x < 1500.0 else -56.0

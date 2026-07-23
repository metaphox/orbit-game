@tool
class_name TopTelemetryBar
extends Control

@onready var met_value: Label = %MetValue
@onready var warp_value: Label = %WarpValue
@onready var soi_value: Label = %SoiValue
@onready var altitude_value: Label = %AltitudeValue
@onready var velocity_value: Label = %VelocityValue
@onready var apoapsis_value: Label = %ApoapsisValue
@onready var periapsis_value: Label = %PeriapsisValue
@onready var burn_dot: Panel = %BurnDot
@onready var burn_label: Label = %BurnLabel
@onready var off_prograde_label: Label = %OffProgradeLabel
@onready var sas_label: Label = %SasLabel
@onready var act_label: Label = %ActLabel
@onready var title_separator: Label = %TitleSeparator
@onready var objective_label: Label = %TitleObjective
@onready var velocity_cell: VBoxContainer = %VelocityCell
@onready var apoapsis_cell: VBoxContainer = %ApoapsisCell
@onready var periapsis_cell: VBoxContainer = %PeriapsisCell


func _ready() -> void:
	if not resized.is_connected(_update_responsive_visibility):
		resized.connect(_update_responsive_visibility)
	_update_responsive_visibility()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_set_extended_visibility(true)
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_update_responsive_visibility()


func configure(level: LevelDef) -> void:
	var parts := level.title.split(":")
	act_label.text = parts[0].strip_edges().to_upper()
	var has_objective := parts.size() > 1
	title_separator.visible = has_objective
	objective_label.visible = has_objective
	if has_objective:
		objective_label.text = parts[1].strip_edges().to_upper()


func refresh(ship: ShipSim, sim_time: float, warp: int) -> void:
	var elements := ship.current_elements()
	met_value.text = "T+ %s" % _clock(sim_time)
	warp_value.text = "%dx" % warp
	soi_value.text = ship.body.name
	altitude_value.text = "%.2f km" % (ship.altitude() / 1000.0)
	velocity_value.text = "%.1f m/s" % ship.speed()
	if elements.is_elliptic():
		apoapsis_value.text = "%.2f km" % (elements.radius_apoapsis() / 1000.0)
		apoapsis_value.add_theme_color_override("font_color", Palette.LIVE)
	else:
		apoapsis_value.text = "ESCAPE"
		apoapsis_value.add_theme_color_override("font_color", Palette.INTENT)
	periapsis_value.text = "%.2f km" % (elements.radius_periapsis() / 1000.0)

	var burning := ship.flight_state == ShipSim.FlightState.BURNING
	burn_label.text = "BURNING" if burning else "COAST"
	burn_label.add_theme_color_override("font_color", Palette.INTENT if burning else Palette.DIM)
	burn_dot.visible = burning
	off_prograde_label.text = "OFF-PRO %.0f°" % rad_to_deg(ship.off_prograde_angle())
	sas_label.text = "SAS %s" % ShipSim.SAS_NAMES[ship.sas_mode]


func animate_burn_dot() -> void:
	if burn_dot.visible:
		burn_dot.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))


func _update_responsive_visibility() -> void:
	_set_extended_visibility(size.x >= 1500.0)


func _set_extended_visibility(shown: bool) -> void:
	velocity_cell.visible = shown
	apoapsis_cell.visible = shown
	periapsis_cell.visible = shown


func _clock(time: float) -> String:
	var total := int(time)
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]

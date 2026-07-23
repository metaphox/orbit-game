class_name GuidanceWarpRail
extends VBoxContainer

const WARP_STEPS := [1, 5, 10, 25, 50, 100, 200, 500, 1000]

@onready var guidance: AttitudeDirector = %GuidanceDirector
@onready var guidance_heading: Label = %GuidanceHeading
@onready var acceleration_value: Label = %AccelerationValue
@onready var velocity_value: Label = %VelocityValue
@onready var delta_v_value: Label = %DeltaVValue
@onready var warp_label: Label = %WarpValue
@onready var warp_meter: BarMeter = %WarpMeter

func refresh(ship: ShipSim, warp: int) -> void:
	guidance.set_attitude(ship)
	guidance_heading.text = "LOCK %s · %.0f°" % [
		ShipSim.SAS_NAMES[ship.sas_mode], rad_to_deg(ship.off_prograde_angle())]
	var acceleration := ship.accel_along_track
	var trend := "▲" if acceleration > 0.05 else ("▼" if acceleration < -0.05 else "—")
	acceleration_value.text = "%+.2f m/s² %s" % [acceleration, trend]
	acceleration_value.add_theme_color_override(
		"font_color", Palette.LIVE if acceleration >= 0.0 else Palette.INTENT)
	velocity_value.text = "%.1f m/s" % ship.speed()
	delta_v_value.text = "%.1f m/s" % ship.dv_remaining()

	var warp_index := WARP_STEPS.find(warp)
	if warp_index < 0:
		warp_index = 0
	warp_label.text = "%dx" % warp
	warp_meter.set_frac(float(warp_index + 1) / WARP_STEPS.size())

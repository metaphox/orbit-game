class_name AccelGauge
extends Control
## The ship's virtual status dial, rendered into a SubViewport and floated
## beside the hull as a hologram. Inner dial: along-track acceleration —
## arc sweeps with |accel|, rings pulse outward while gaining speed and
## inward while losing it (green = speeding up, amber = slowing down).
## Outer ring: propellant remaining.

const GREEN := Color(0.45, 1.0, 0.55)
const DIM_GREEN := Color(0.3, 0.65, 0.38, 0.7)
const AMBER := Color(1.0, 0.72, 0.25)
const DEADBAND := 0.05  # m/s^2 below which we call it steady

var font: Font
var speed := 0.0
var accel := 0.0  # signed along-track, m/s^2
var accel_max := 6.0
var prop_frac := 1.0
var dv_left := 0.0

var _phase := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])
	font = sys_font


func _process(delta: float) -> void:
	var frac := clampf(absf(accel) / accel_max, 0.0, 1.0)
	if absf(accel) > DEADBAND:
		_phase = fposmod(_phase + delta * (0.5 + 2.2 * frac), 1.0)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.5 - 26.0)
	var radius := 58.0

	# translucent backdrop so the hologram reads against any background
	draw_circle(center, radius + 18.0, Color(0.0, 0.09, 0.03, 0.4))

	# --- propellant: outer ring, clockwise from 12 o'clock
	var prop_color := GREEN if prop_frac > 0.25 else AMBER
	draw_arc(center, radius + 10.0, 0.0, TAU, 72, Color(prop_color, 0.25), 1.5, true)
	if prop_frac > 0.001:
		draw_arc(center, radius + 10.0, -PI / 2, -PI / 2 + TAU * clampf(prop_frac, 0.0, 1.0),
			72, prop_color, 3.0, true)

	# --- acceleration dial
	draw_arc(center, radius, 0.0, TAU, 72, DIM_GREEN, 1.5, true)
	for i in 12:
		var dir := Vector2.from_angle(TAU * i / 12.0)
		draw_line(center + dir * (radius - 4.0), center + dir * radius, DIM_GREEN, 1.5)

	var frac := clampf(absf(accel) / accel_max, 0.0, 1.0)
	var active := absf(accel) > DEADBAND
	var color := GREEN if accel >= 0.0 else AMBER
	if active:
		# sweep clockwise from 12 o'clock while gaining, counter-clockwise
		# while losing
		if accel >= 0.0:
			draw_arc(center, radius - 8.0, -PI / 2, -PI / 2 + TAU * frac, 72, color, 4.0, true)
		else:
			draw_arc(center, radius - 8.0, -PI / 2 - TAU * frac, -PI / 2, 72, color, 4.0, true)
		for k in 3:
			var p := fposmod(_phase + k / 3.0, 1.0)
			var ring_r: float
			if accel >= 0.0:
				ring_r = lerpf(radius * 0.25, radius * 0.92, p)
			else:
				ring_r = lerpf(radius * 0.92, radius * 0.25, p)
			var fade := (1.0 - absf(p * 2.0 - 1.0)) * 0.55
			draw_arc(center, ring_r, 0.0, TAU, 48, Color(color, fade), 1.5, true)

	var trend := "▲" if accel > DEADBAND else ("▼" if accel < -DEADBAND else "—")
	_text(center + Vector2(0, radius + 30.0), "ACC %+5.2f m/s² %s" % [accel, trend],
		color if active else DIM_GREEN)
	_text(center + Vector2(0, radius + 48.0), "VEL %7.1f m/s" % speed, GREEN)
	_text(center + Vector2(0, radius + 66.0),
		"PROP %3.0f%%  Δv %5.1f" % [prop_frac * 100.0, dv_left], prop_color)


func _text(at: Vector2, text: String, color: Color) -> void:
	draw_string(font, at + Vector2(-110.0, 0.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, 220.0, 14, color)

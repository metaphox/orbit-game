class_name AccelGauge
extends Control
## Circular digital gauge for along-track acceleration: an arc sweeps with
## |accel|, rings pulse outward while gaining speed and inward while
## losing it. Green = speeding up, amber = slowing down.

const GREEN := Color(0.45, 1.0, 0.55)
const DIM_GREEN := Color(0.3, 0.65, 0.38, 0.7)
const AMBER := Color(1.0, 0.72, 0.25)
const DEADBAND := 0.05  # m/s^2 below which we call it steady

var font: Font
var speed := 0.0
var accel := 0.0  # signed along-track, m/s^2
var accel_max := 6.0

var _phase := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(230, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var frac := clampf(absf(accel) / accel_max, 0.0, 1.0)
	if absf(accel) > DEADBAND:
		_phase = fposmod(_phase + delta * (0.5 + 2.2 * frac), 1.0)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.5 - 14.0)
	var radius := 58.0

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
	_text(center + Vector2(0, radius + 24.0), "ACC %+5.2f m/s² %s" % [accel, trend],
		color if active else DIM_GREEN)
	_text(center + Vector2(0, radius + 42.0), "VEL %7.1f m/s" % speed, GREEN)


func _text(at: Vector2, text: String, color: Color) -> void:
	if font == null:
		return
	draw_string(font, at + Vector2(-110.0, 0.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, 220.0, 14, color)

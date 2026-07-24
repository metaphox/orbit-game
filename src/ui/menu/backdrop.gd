@tool
class_name Backdrop
extends Control
## The subtle static menu backdrop: a dark vertical gradient plus one faint
## diagonal light streak, in Palette tones. Sits under the menu chrome and the
## ScreenGrade CRT layer. Pure decoration, no per-frame cost (redraws on resize).

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	# Vertical gradient VOID -> a hair lighter, so the screen isn't flat black.
	var top := Palette.VOID
	var bottom := Palette.PANEL
	draw_rect(Rect2(Vector2.ZERO, size), top, true)
	var steps := 24
	for i in steps:
		var t := float(i) / float(steps - 1)
		var band := Rect2(0.0, size.y * t, size.x, size.y / float(steps) + 1.0)
		draw_rect(band, top.lerp(bottom, t * t), true)
	# One faint diagonal streak from the top toward the lower-right.
	var streak := Color(Palette.INK, 0.05)
	var a := Vector2(size.x * 0.62, -20.0)
	var b := Vector2(size.x * 0.28, size.y + 20.0)
	draw_line(a, b, streak, 2.0, true)

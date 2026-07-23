@tool
class_name HazardStripe
extends Control
## Diagonal amber/void hazard bands — the bottom-strip end caps in the ORBITAL-OS
## HUD. Purely decorative; clips to its own rect.

var stripe := Palette.INTENT


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.VOID)
	var step := 22.0
	var x := -size.y
	while x < size.x:
		draw_line(Vector2(x, size.y), Vector2(x + size.y, 0.0), stripe, 11.0)
		x += step

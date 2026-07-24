@tool
class_name DifficultyPips
extends Control
## Four square pips showing a level's 1–4 difficulty rating (mission-select UI).
## Colours come from Palette; `dark` flips them for use on a filled-green card.

const PIP_COUNT := 4
const PIP := 9.0
const GAP := 5.0

@export_range(1, 4) var value := 1:
	set(v):
		value = clampi(v, 1, PIP_COUNT)
		queue_redraw()

## True on a selected (filled-green) card, where pips must read dark for contrast.
var dark := false:
	set(v):
		dark = v
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(PIP_COUNT * PIP + (PIP_COUNT - 1) * GAP, PIP)


func _draw() -> void:
	var filled := Palette.VOID if dark else Palette.LIVE
	var empty := Color(Palette.VOID, 0.3) if dark else Palette.DISABLED
	var y := (size.y - PIP) * 0.5
	for i in PIP_COUNT:
		var col := filled if i < value else empty
		draw_rect(Rect2(i * (PIP + GAP), y, PIP, PIP), col, true)

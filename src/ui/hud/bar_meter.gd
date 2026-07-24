@tool
class_name BarMeter
extends Control
## A segmented bar readout in the ORBITAL-OS idiom: THR / PROP fuel strips and
## the 9-stop WARP graph. `frac` (0..1) fills segments left-to-right; `stepped`
## grows the segments in height for the warp graph. Colours come from Palette.

var frac := 0.0

@export_range(1, 32, 1) var segments := 10:
	set(value):
		segments = value
		queue_redraw()
@export var stepped := false:
	set(value):
		stepped = value
		queue_redraw()
@export var outlined := false:
	set(value):
		outlined = value
		queue_redraw()


func set_frac(f: float) -> void:
	frac = clampf(f, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var border := Palette.LIVE if outlined else Palette.TRANSPARENT
	var pad := 0.0
	if border.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), border, false, 2.0)
		pad = 4.0
	var origin := Vector2(pad, pad)
	var area := size - Vector2(pad, pad) * 2.0
	var gap := 2.0
	var seg_w := (area.x - gap * (segments - 1)) / segments
	var shown_fraction := 0.7 if Engine.is_editor_hint() else frac
	var filled := int(round(shown_fraction * segments))
	for i: int in segments:
		var x := origin.x + i * (seg_w + gap)
		var h := area.y
		var y := origin.y
		if stepped:
			h = lerpf(area.y * 0.35, area.y, float(i) / maxf(1.0, segments - 1))
			y = origin.y + area.y - h
		draw_rect(Rect2(x, y, seg_w, h), Palette.LIVE if i < filled else Palette.LIVE_DK)

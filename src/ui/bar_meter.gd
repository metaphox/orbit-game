class_name BarMeter
extends Control
## A segmented bar readout in the ORBITAL-OS idiom: THR / PROP fuel strips and
## the 9-stop WARP graph. `frac` (0..1) fills segments left-to-right; `stepped`
## grows the segments in height for the warp graph. Colours come from Palette.

var frac := 0.0
var segments := 10
var fill := Palette.LIVE
var empty := Palette.LIVE_DK
var border := Palette.TRANSPARENT  # no outline (warp graph)
var stepped := false             # variable segment heights (warp graph)


func set_frac(f: float) -> void:
	frac = clampf(f, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var pad := 0.0
	if border.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), border, false, 2.0)
		pad = 4.0
	var origin := Vector2(pad, pad)
	var area := size - Vector2(pad, pad) * 2.0
	var gap := 2.0
	var seg_w := (area.x - gap * (segments - 1)) / segments
	var filled := int(round(frac * segments))
	for i in segments:
		var x := origin.x + i * (seg_w + gap)
		var h := area.y
		var y := origin.y
		if stepped:
			h = lerpf(area.y * 0.35, area.y, float(i) / maxf(1.0, segments - 1))
			y = origin.y + area.y - h
		draw_rect(Rect2(x, y, seg_w, h), fill if i < filled else empty)

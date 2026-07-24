class_name MinimapOverlay
extends Control
## Draws the minimap's marker dots and tiny labels (UI-DESIGN.md → Minimap) by
## projecting 3D map-scene positions through the minimap camera onto this 2D
## panel. Sits on top of the SubViewport; game_root/hud feeds it the camera and
## the point list each frame. Labels stay horizontal while the map rotates
## heading-up, because projection accounts for the camera's rotation.

var cam: Camera3D
var font: Font
# [{ "pos": Vector3 (map-scene coords), "color": Color, "label": String }]
var points: Array = []


func _draw() -> void:
	if cam == null or font == null or points.is_empty():
		return
	var vp := cam.get_viewport()
	if vp == null:
		return
	var vp_size := Vector2(vp.size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var to_panel := size / vp_size  # SubViewport px -> this control's px
	for pt: Dictionary in points:
		var world: Vector3 = pt["pos"]
		if cam.is_position_behind(world):
			continue
		var p: Vector2 = cam.unproject_position(world) * to_panel
		if p.x < -6.0 or p.y < -6.0 or p.x > size.x + 6.0 or p.y > size.y + 6.0:
			continue  # off-panel; AUTO/zoom-out brings it back
		var color: Color = pt["color"]
		draw_circle(p, 4.0, Color(color, 0.28))  # soft halo
		draw_circle(p, 2.4, color)
		var label: String = pt["label"]
		if label != "":
			_label(label, p + Vector2(7.0, -6.0), color)


## Draw a short tag, nudged fully on-panel if it would spill off the right/top.
func _label(text: String, at: Vector2, color: Color) -> void:
	text = tr(text)  # body names / NODE translate; AP/PE/TGT notation has no msgid -> stays English
	var fs := 11
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := at
	pos.x = minf(pos.x, size.x - w - 2.0)
	pos.y = clampf(pos.y, fs + 1.0, size.y - 2.0)
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.LABEL_SHADOW)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

class_name OrbitLabels
extends Control
## Blueprint-style callout labels for the orbit reference marks (apoapsis,
## periapsis, ascending/descending node, impact, encounter, intercept), shown in
## the orbit (side) camera when zoomed out. Each mark's 3D render-space point is
## projected to the screen every frame and annotated with a screen-aligned label:
## a thin leader line runs outward from the mark to a filled "chip" carrying the
## name in inverted ink — like a part callout on a blueprint.
##
## The chip fill is the mark's own RenderTheme hue (fed in with each point), so
## the callout reads in the mark's colour with high-contrast ink text on top.
## Appearance is exported, so the styling is editable in the Godot inspector
## (see orbit_labels.tscn); positions are dynamic (projected each frame) and the
## colours are per-mark, so only the shared look lives here.

## Leader length, mark -> chip, in pixels.
@export var leader_length := 46.0
@export var font_size := 13
## Inner padding of the chip around its text, pixels (x = ends, y = top/bottom).
@export var pad_x := 6.0
@export var pad_y := 3.0
## Anchor dot drawn on the mark itself, pixels.
@export var dot_radius := 3.0
## Text colour on the mark-coloured chip. Black by default for the inverted look.
@export var ink_color := Color.BLACK
## Label typeface; falls back to the UI mono font when unset.
@export var label_font: Font

var _camera: Camera3D
var _marks: Array = []  # [{pos: Vector3, color: Color, text: String}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Feed this frame's callouts. Pass an empty array (or a non-current camera) to
## draw nothing — e.g. when the orbit camera isn't the active view.
func show_marks(camera: Camera3D, marks: Array) -> void:
	_camera = camera
	_marks = marks
	queue_redraw()


func _font() -> Font:
	return label_font if label_font != null else UiTheme.MONO


## A short world-space step along a mark's outward radial, projected to give the
## leader its on-screen direction. Small vs any orbit so it reads as the local
## radial (perpendicular to the tangent), not a chord across the orbit.
const RADIAL_SAMPLE := 1000.0


func _draw() -> void:
	if _camera == null or not _camera.is_current() or _marks.is_empty():
		return
	var center := size * 0.5
	for m: Dictionary in _marks:
		var world: Vector3 = m["pos"]
		if _camera.is_position_behind(world):
			continue
		_draw_callout(_camera.unproject_position(world), center, world,
			m.get("outward", Vector3.ZERO), m["color"], m["text"])


## One blueprint callout: an anchor dot on the mark, a leader out to a filled chip
## carrying the name in inverted ink. The leader runs along the mark's outward
## radial (perpendicular to the orbit tangent, away from the body); the chip sits
## on that outboard side so it never overruns the point. Falls back to a
## screen-centre radial when the radial projects to nothing (points at the camera).
func _draw_callout(p: Vector2, center: Vector2, world: Vector3, outward: Vector3,
		color: Color, text: String) -> void:
	var dir := Vector2.ZERO
	if outward.length_squared() > 0.0 and not _camera.is_position_behind(world + outward):
		dir = _camera.unproject_position(world + outward * RADIAL_SAMPLE) - p
	if dir.length() < 1.0:
		dir = p - center  # radial points near-along the view axis: fan from screen centre
	dir = dir.normalized() if dir.length() > 1.0 else Vector2(0.0, -1.0)
	var knee := p + dir * leader_length
	var font := _font()

	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent := font.get_ascent(font_size)
	var chip_w := text_w + 2.0 * pad_x
	var chip_h := ascent + font.get_descent(font_size) + 2.0 * pad_y
	# Chip grows away from the mark (outboard); its near edge midpoint is the knee.
	var chip_left := (knee.x - chip_w) if dir.x < 0.0 else knee.x
	var chip := Rect2(chip_left, knee.y - chip_h * 0.5, chip_w, chip_h)

	draw_circle(p, dot_radius, color)
	draw_line(p, knee, color, 1.0, true)
	draw_rect(chip, color)
	draw_string(font, Vector2(chip.position.x + pad_x, chip.position.y + pad_y + ascent),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink_color)

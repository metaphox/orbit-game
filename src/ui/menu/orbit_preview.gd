class_name OrbitPreview
extends Control
## A clean 2D schematic of a mission for the detail pane: the central body, your
## start orbit (green), the target (cyan ring / marker), a dotted rough transfer
## arc, and labels. Normalised to always fit the panel regardless of real scale
## (LEO vs an interplanetary transfer), so it reads as a brief — unlike a raw
## minimap render. `build(level)` picks the right frame per objective type.

var _built := false
var _center_name := ""
var _center_radius := 0.0
var _r_start := 0.0    # start orbit radius (m)
var _r_target := 0.0   # target radius (m); 0 = none
var _target_label := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)


func build(level: LevelDef) -> void:
	var start_body: BodyDef = level.start_body if level.start_body != null else level.body
	var center := start_body
	_r_start = level.start_radius
	_r_target = 0.0
	_target_label = ""
	var obj := level.objective
	if obj is OrbitMatchObjective:
		_r_target = (obj as OrbitMatchObjective).target_radius
		_target_label = "TARGET"
	elif obj is RendezvousObjective:
		_r_target = (obj as RendezvousObjective).station_orbit.a
		_target_label = "STATION"
	elif obj is EntryCorridorObjective:
		_r_target = (obj as EntryCorridorObjective).target_periapsis
		_target_label = "REENTRY"
	elif obj is AirlessLandingObjective:
		center = (obj as AirlessLandingObjective).target
		_r_target = center.radius
		_target_label = "SURFACE"
	elif obj is TransferCaptureObjective:
		var target: BodyDef = (obj as TransferCaptureObjective).target
		if target.parent == start_body:  # e.g. LEO -> the Moon's orbit around Earth
			_r_target = target.orbit.a
			_target_label = target.name
		elif target.parent != null:      # heliocentric: departure body's orbit -> target's orbit
			center = target.parent
			_r_start = start_body.orbit.a
			_r_target = target.orbit.a
			_target_label = target.name
	_center_name = center.name
	_center_radius = center.radius
	_built = true
	queue_redraw()


func _draw() -> void:
	if not _built or size.x < 40.0 or size.y < 40.0:
		return
	var mid := size * 0.5
	var budget := minf(size.x, size.y) * 0.5 - 26.0
	var r_max := maxf(maxf(_r_start, _r_target), _center_radius * 1.4)
	if r_max <= 0.0 or budget <= 0.0:
		return
	var s := budget / r_max
	var font := UiTheme.MONO

	# central body: a tinted disc with a faint rim, sized to scale (but visible).
	var body_px := clampf(_center_radius * s, 8.0, budget * 0.55)
	draw_circle(mid, body_px, Palette.body_tint(_center_name))
	draw_arc(mid, body_px, 0.0, TAU, 48, Palette.DIM, 1.0, true)
	_label(font, _center_name, mid + Vector2(0.0, body_px + 12.0), Palette.DIM, true)

	# your start orbit (green)
	if _r_start * s > body_px + 2.0:
		var rs := _r_start * s
		draw_arc(mid, rs, 0.0, TAU, 96, Palette.LIVE, 1.5, true)
		_label(font, "YOUR ORBIT", mid + Vector2(0.0, -rs - 4.0), Palette.LIVE, true)

	# the target: a ring for an orbit/station, skipped when it's just the surface.
	if _r_target > 0.0 and _r_target > _center_radius * 1.05:
		var rt := _r_target * s
		draw_arc(mid, rt, 0.0, TAU, 96, Palette.TARGET, 1.5, true)
		var mk := mid + Vector2(rt, 0.0).rotated(-0.7)
		draw_circle(mk, 3.0, Palette.TARGET)
		_label(font, _target_label, mk + Vector2(7.0, -5.0), Palette.TARGET, false)

	# dotted rough transfer arc between the two radii (amber "planned path").
	_draw_transfer(mid, _r_start * s, _r_target * s)


## A dashed half-ellipse (Hohmann-ish) from the inner radius to the outer, with
## its focus at the body — hints the journey without pretending to be exact.
func _draw_transfer(mid: Vector2, r_a: float, r_b: float) -> void:
	var peri := minf(r_a, r_b)
	var apo := maxf(r_a, r_b)
	if peri <= 1.0 or apo <= 1.0 or apo - peri < 2.0:
		return
	var a := (peri + apo) * 0.5
	var e := (apo - peri) / (apo + peri)
	var pts := PackedVector2Array()
	for i in 41:
		var th := PI * float(i) / 40.0
		var r := a * (1.0 - e * e) / (1.0 + e * cos(th))
		pts.append(mid + Vector2(cos(th) * r, sin(th) * r))
	for i in range(0, pts.size() - 1, 2):
		draw_line(pts[i], pts[i + 1], Palette.INTENT, 1.5, true)


func _label(font: Font, text: String, at: Vector2, color: Color, centered: bool) -> void:
	text = tr(text)  # body name / YOUR ORBIT / TARGET / STATION / REENTRY / SURFACE
	var fs := 10
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := at - Vector2(w * 0.5, 0.0) if centered else at
	pos.x = clampf(pos.x, 2.0, size.x - w - 2.0)
	pos.y = clampf(pos.y, fs + 1.0, size.y - 2.0)
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.LABEL_SHADOW)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

@tool
class_name RewindTimeline
extends Control
## The rewind scrubber's visual timeline (DESIGN.md §14.2): a horizontal line
## from the mission start to "now" (the right end, where you are). Burn anchors
## are ticks; the selected one is highlighted with its label and time; SOI
## crossings show as dim landmarks. A playhead marks the currently displayed
## moment (it slides during the reverse-sweep). Pure display - game_root feeds
## it state each frame and calls queue_redraw.

const LINE := Palette.REWIND_LINE
const ANCHOR := Palette.REWIND_ANCHOR
const SELECTED := Palette.REWIND_SELECTED
const LANDMARK := Palette.REWIND_LANDMARK
const LABEL := Palette.REWIND_LABEL

var font: Font
var t_start := 0.0
var t_now := 1.0
var playhead := 0.0
var cursor := 0
var anchors: Array = []    # [{ "sim_time": float, "label": String }]
var landmarks: Array = []  # [{ "sim_time": float, "label": String }]


func _ready() -> void:
	if Engine.is_editor_hint():
		font = UiTheme.MONO
		t_now = 300.0
		playhead = 180.0
		cursor = 1
		anchors = [
			{"sim_time": 60.0, "label": "BURN 1"},   # i18n-ok: editor preview only
			{"sim_time": 180.0, "label": "BURN 2"},  # i18n-ok: editor preview only
		]
		landmarks = [{"sim_time": 245.0, "label": "SOI"}]


func _draw() -> void:
	if anchors.is_empty() or font == null:
		return
	var x0 := 30.0
	var x1 := size.x - 66.0  # room for the NOW cap + label on the right
	var y := size.y * 0.5
	var span: float = maxf(t_now - t_start, 1e-6)

	draw_line(Vector2(x0, y), Vector2(x1, y), LINE, 2.0)

	for lm: Dictionary in landmarks:
		var lx := _x(lm["sim_time"], x0, x1, span)
		var d := 4.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(lx, y - 9 - d), Vector2(lx + d, y - 9),
			Vector2(lx, y - 9 + d), Vector2(lx - d, y - 9)]), LANDMARK)

	# "NOW" cap at the right end - where you are before rewinding.
	draw_line(Vector2(x1, y - 13), Vector2(x1, y + 13), ANCHOR, 3.0)
	_centered(tr("NOW"), x1, y - 20, ANCHOR, 13)
	_centered(tr("you are here"), x1, y + 28, LABEL, 11)

	for i in anchors.size():
		var ax := _x(anchors[i]["sim_time"], x0, x1, span)
		var selected := i == cursor
		draw_circle(Vector2(ax, y), 7.0 if selected else 4.0, SELECTED if selected else ANCHOR)
		if selected:
			_centered(tr(str(anchors[i]["label"])), ax, y - 20, SELECTED, 14)
			_centered("T+" + _clock(anchors[i]["sim_time"]), ax, y + 28, LABEL, 12)

	var px := _x(playhead, x0, x1, span)
	draw_line(Vector2(px, y - 17), Vector2(px, y + 17), SELECTED, 1.5)


func _x(t: float, x0: float, x1: float, span: float) -> float:
	return lerpf(x0, x1, clampf((t - t_start) / span, 0.0, 1.0))


func _centered(text: String, cx: float, baseline_y: float, color: Color, fs: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(cx - w * 0.5, baseline_y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _clock(t: float) -> String:
	var s := int(t)
	@warning_ignore("integer_division")  # HH:MM:SS wants the floored quotient
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]

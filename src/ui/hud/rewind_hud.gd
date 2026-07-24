class_name RewindHud
extends Control
## The in-flight rewind readout, extracted from hud_overlays so it is editable in
## isolation (rewind_hud.tscn): the persistent charge/prompt line (RewindPanel)
## and the scrubber timeline (RewindTimeline). game_root drives it through
## Hud -> HudOverlays -> here; the line/prompt text is computed there since it is
## data-driven (pip counts, key labels, resume prompts).

@onready var _panel: PanelContainer = %RewindPanel
@onready var _label: Label = %RewindLabel
@onready var _timeline: RewindTimeline = %RewindTimeline


func _ready() -> void:
	_timeline.font = UiTheme.MONO


## The persistent charge/prompt line; hidden when the text is empty.
func set_line(text: String) -> void:
	_label.text = text
	_panel.visible = text != ""


func update_timeline(t_start: float, t_now: float, playhead: float, cursor: int,
		anchors: Array, landmarks: Array) -> void:
	_timeline.t_start = t_start
	_timeline.t_now = t_now
	_timeline.playhead = playhead
	_timeline.cursor = cursor
	_timeline.anchors = anchors
	_timeline.landmarks = landmarks
	_timeline.visible = true
	_timeline.queue_redraw()


func hide_timeline() -> void:
	_timeline.visible = false

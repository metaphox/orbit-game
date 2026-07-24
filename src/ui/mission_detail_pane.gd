class_name MissionDetailPane
extends PanelContainer
## The mission-select right pane: MISSIONS chip + SORTIE nn/NN, big title,
## code·status, brief, difficulty pips, a cached orbit preview, a stats block,
## and the amber LAUNCH button. `show_level` renders one mission (hovered or
## selected); `set_launch_enabled` greys LAUNCH for a locked mission.

signal launch_requested(index: int)

const GRID := 8
const PREVIEW_MIN := Vector2(360, GRID * 26)  # 208

var _index := -1
var _sortie: Label
var _title: Label
var _code_status: Label
var _brief: Label
var _pips: DifficultyPips
var _preview_slot: Control
var _previews: Dictionary[int, OrbitPreview] = {}
var _stats: Label
var _launch: Button


func _ready() -> void:
	theme_type_variation = UiTheme.INSTRUMENT_PANEL
	# INSTRUMENT_PANEL pads 12; this margin brings the interior to a 24px gutter
	# so text never sits against the panel edge.
	var pad := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 12)  # +12 panel = 24px interior gutter
	add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", GRID * 2)  # 16
	pad.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var chip := _lbl(UiTheme.EYEBROW, "MISSIONS")
	header.add_child(chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_sortie = _lbl(UiTheme.MENU_FOOTER, "")
	header.add_child(_sortie)

	_title = _lbl(UiTheme.MENU_TITLE, "")
	col.add_child(_title)
	_code_status = _lbl(UiTheme.MENU_WARNING, "")
	col.add_child(_code_status)
	_brief = _lbl(UiTheme.MONO_TEXT, "")
	_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief.custom_minimum_size = Vector2(360, 0)
	col.add_child(_brief)

	var diff := HBoxContainer.new()
	diff.add_theme_constant_override("separation", GRID)  # 8
	col.add_child(diff)
	diff.add_child(_lbl(UiTheme.MENU_FOOTER, "DIFFICULTY"))
	_pips = DifficultyPips.new()
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	diff.add_child(_pips)

	_preview_slot = Control.new()
	_preview_slot.custom_minimum_size = PREVIEW_MIN
	col.add_child(_preview_slot)

	_stats = _lbl(UiTheme.MONO_SMALL, "")
	col.add_child(_stats)

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grow)

	_launch = Button.new()
	_launch.theme_type_variation = UiTheme.LAUNCH_BUTTON
	_launch.focus_mode = Control.FOCUS_NONE
	_launch.text = "LAUNCH ▶"
	_launch.pressed.connect(func() -> void:
		if _index >= 0 and not _launch.disabled:
			launch_requested.emit(_index))
	col.add_child(_launch)


func _lbl(variation: StringName, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	return l


func show_level(index: int, profile: Profile) -> void:
	_index = index
	var level := Campaign.level_at(index)
	var s := Campaign.sortie(index)
	_sortie.text = "SORTIE %02d / %02d" % [s.x, s.y]
	_title.text = Campaign.short_title(index)
	_code_status.text = "%s · %s" % [Campaign.code(index), profile.status_for(index)]
	_brief.text = level.objective.describe()
	_pips.value = level.difficulty
	var medal := profile.medal_for(index)
	_stats.text = "Δv PAR   %d m/s\nBEST     %s\nREWINDS  %d\nAVIONICS %s" % [
		int(level.dv_par), medal if medal != "" else "—", level.rewind_budget, _avionics(level)]
	_show_preview(index, level)


func set_launch_enabled(enabled: bool) -> void:
	_launch.disabled = not enabled


func _avionics(level: LevelDef) -> String:
	var parts: Array[String] = []
	if level.sas_enabled:
		parts.append("SAS")
	if level.nodes_enabled:
		parts.append("NODES")
	return " · ".join(parts) if not parts.is_empty() else "MANUAL"


func _show_preview(index: int, level: LevelDef) -> void:
	for p: OrbitPreview in _previews.values():
		p.visible = false
	if not _previews.has(index):
		var preview := OrbitPreview.new()
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_preview_slot.add_child(preview)
		_previews[index] = preview
		preview.build(level)
	_previews[index].visible = true

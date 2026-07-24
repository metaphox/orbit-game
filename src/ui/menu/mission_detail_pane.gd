class_name MissionDetailPane
extends PanelContainer
## The mission-select right pane: MISSIONS chip + SORTIE nn/NN, big title,
## code·status, brief, difficulty pips, a cached orbit preview, a stats block,
## and the amber LAUNCH button. `show_level` renders one mission (hovered or
## selected); `set_launch_enabled` greys LAUNCH for a locked mission.

signal launch_requested(index: int)


## The panel layout is authored in mission_detail_pane.tscn (editable in the
## editor); this script fills the `%`-named slots and drives the orbit preview.
static func create() -> MissionDetailPane:
	return preload("res://src/ui/menu/mission_detail_pane.tscn").instantiate()


var _index := -1
var _previews: Dictionary[int, OrbitPreview] = {}

@onready var _sortie: Label = %Sortie
@onready var _title: Label = %Title
@onready var _code_status: Label = %CodeStatus
@onready var _brief: Label = %Brief
@onready var _pips: DifficultyPips = %Pips
@onready var _preview_slot: Control = %PreviewSlot
@onready var _stats: Label = %Stats
@onready var _launch: Button = %Launch


func _ready() -> void:
	_launch.pressed.connect(func() -> void:
		if _index >= 0 and not _launch.disabled:
			launch_requested.emit(_index))


func show_level(index: int, profile: Profile) -> void:
	_index = index
	var level := Campaign.level_at(index)
	var s := Campaign.sortie(index)
	_sortie.text = tr("SORTIE %02d / %02d") % [s.x, s.y]
	_title.text = Campaign.short_title(index)
	_code_status.text = "%s · %s" % [Campaign.code(index), Campaign.status_label(profile, index)]
	_brief.text = level.objective.describe()
	_pips.value = level.difficulty
	var medal := profile.medal_for(index)
	_stats.text = tr("Δv PAR   %d m/s\nBEST     %s\nREWINDS  %d\nAVIONICS %s") % [
		int(level.dv_par), tr(medal) if medal != "" else "—", level.rewind_budget, _avionics(level)]
	_show_preview(index, level)


func set_launch_enabled(enabled: bool) -> void:
	_launch.disabled = not enabled


func _avionics(level: LevelDef) -> String:
	var parts: Array[String] = []
	if level.sas_enabled:
		parts.append(tr("SAS"))
	if level.nodes_enabled:
		parts.append(tr("NODES"))
	return " · ".join(parts) if not parts.is_empty() else tr("MANUAL", &"mode")


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

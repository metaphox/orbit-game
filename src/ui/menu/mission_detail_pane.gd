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
@onready var _plan_header: Label = %PlanHeader
@onready var _flight_plan: RichTextLabel = %FlightPlan
@onready var _stats: Label = %Stats
@onready var _launch: Button = %Launch


func _ready() -> void:
	_style_flight_plan()
	_launch.pressed.connect(func() -> void:
		if _index >= 0 and not _launch.disabled:
			launch_requested.emit(_index))


## The FLIGHT PLAN body is a RichTextLabel (for **bold** / *italic*); style it to
## match MonoText (the base RichTextLabel theme is a larger heading font), with
## synthesised bold/italic faces so the markdown emphasis renders on the mono
## font (which ships only a regular weight).
func _style_flight_plan() -> void:
	_flight_plan.add_theme_font_override("normal_font", UiTheme.MONO)
	_flight_plan.add_theme_font_size_override("normal_font_size", 14)
	_flight_plan.add_theme_color_override("default_color", Palette.INK)
	var bold := FontVariation.new()
	bold.base_font = UiTheme.MONO
	bold.variation_embolden = 0.65
	_flight_plan.add_theme_font_override("bold_font", bold)
	var italic := FontVariation.new()
	italic.base_font = UiTheme.MONO
	italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.22, 1.0), Vector2.ZERO)
	_flight_plan.add_theme_font_override("italics_font", italic)  # Godot names it plural


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
	# Authored FLIGHT PLAN prose (per-locale file, English fallback); hide the
	# whole section for levels that don't have one yet.
	var plan := BriefText.md_to_bbcode(BriefText.flight_plan(index))
	_flight_plan.text = plan
	_flight_plan.visible = not plan.is_empty()
	_plan_header.visible = not plan.is_empty()


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

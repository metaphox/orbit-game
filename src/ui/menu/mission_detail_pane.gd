class_name MissionDetailPane
extends PanelContainer
## The mission-select right pane: MISSIONS chip + SORTIE nn/NN, big title,
## code·status, brief, difficulty pips, a cached orbit preview, a stats block,
## and the amber LAUNCH button. `show_level` renders one mission (hovered or
## selected); `set_launch_enabled` greys LAUNCH for a locked mission.

signal launch_requested  # launch whatever the pane currently shows (owner resolves it)


## The panel layout is authored in mission_detail_pane.tscn (editable in the
## editor); this script fills the `%`-named slots and drives the orbit preview.
static func create() -> MissionDetailPane:
	return preload("res://src/ui/menu/mission_detail_pane.tscn").instantiate()


var _index := -1  # built-in index currently shown (-1 for a community level)
var _previews: Dictionary[String, OrbitPreview] = {}  # keyed by level id (community levels have no index)

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
		if not _launch.disabled:
			launch_requested.emit())


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
	_fill(level, Campaign.short_title(index),
		"%s · %s" % [Campaign.code(index), Campaign.status_label(profile, index)],
		profile.medal_for(index), true)
	# Authored FLIGHT PLAN prose (per-locale file, English fallback).
	_set_plan(BriefText.md_to_bbcode(BriefText.flight_plan(index)))


## Fill the pane for a drop-in community level (no Campaign index): its own
## title/brief/preview, a COMMUNITY chip + sandbox medal, and a ready-made plan.
func show_community(level: LevelDef, medal: String, plan_bbcode: String) -> void:
	_index = -1
	_sortie.text = tr("COMMUNITY")
	_fill(level, _short_title(level.title), "%s · %s" % [
		tr("COMMUNITY"), medal if medal != "" else String(TranslationServer.translate("ACTIVE", &"status"))],
		medal, false)
	_set_plan(plan_bbcode)


## Shared body of the two show_* methods: brief, difficulty pips, stats, preview.
func _fill(level: LevelDef, title: String, code_status: String, medal: String, translate_medal: bool) -> void:
	_title.text = title
	_code_status.text = code_status
	_brief.text = level.objective.describe()
	_pips.value = level.difficulty
	var medal_txt := (tr(medal) if translate_medal else medal) if medal != "" else "—"
	_stats.text = tr("Δv PAR   %d m/s\nBEST     %s\nREWINDS  %d\nAVIONICS %s") % [
		int(level.dv_par), medal_txt, level.rewind_budget, _avionics(level)]
	_show_preview(level)


func _set_plan(plan_bbcode: String) -> void:
	_flight_plan.text = plan_bbcode
	_flight_plan.visible = not plan_bbcode.is_empty()
	_plan_header.visible = not plan_bbcode.is_empty()


func _short_title(full: String) -> String:
	var parts := full.split(":")
	return (parts[1] if parts.size() > 1 else parts[0]).strip_edges()


func set_launch_enabled(enabled: bool) -> void:
	_launch.disabled = not enabled


func _avionics(level: LevelDef) -> String:
	var parts: Array[String] = []
	if level.sas_enabled:
		parts.append(tr("SAS"))
	if level.nodes_enabled:
		parts.append(tr("NODES"))
	return " · ".join(parts) if not parts.is_empty() else tr("MANUAL", &"mode")


func _show_preview(level: LevelDef) -> void:
	for p: OrbitPreview in _previews.values():
		p.visible = false
	var key := level.id if level.id != "" else level.title
	if not _previews.has(key):
		var preview := OrbitPreview.new()
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_preview_slot.add_child(preview)
		_previews[key] = preview
		preview.build(level)
	_previews[key].visible = true

@tool
class_name UiTheme
extends RefCounted
## Builds the one Godot Theme for the "ORBITAL OS" look (ref/design-ref.html):
## `populate(theme)` fills a Theme with the bundled fonts and ~40 type-variation
## tokens (titles, HUD values, panels, chips, separators, buttons), every colour
## sourced from Palette (and Palette itself mirrored under the "Palette" theme
## type for the inspector). `generated_ui_theme.tres` is that Theme — its script
## just calls populate() — and every menu/HUD scene inherits it, styling nodes
## purely via `theme_type_variation` (no per-node colour overrides). This is the
## single source of truth for menu/HUD chrome (TECH_DEBTS.md TD-1); the old
## per-screen SystemFont.new() + duplicated colour constants are gone.

const DISPLAY := preload("res://assets/fonts/ChakraPetch-Bold.ttf")       # loud headings
const DISPLAY_SEMI := preload("res://assets/fonts/ChakraPetch-SemiBold.ttf")
const MONO := preload("res://assets/fonts/IBMPlexMono-Regular.ttf")       # data / body text
const MONO_MED := preload("res://assets/fonts/IBMPlexMono-Medium.ttf")
const MONO_SEMI := preload("res://assets/fonts/IBMPlexMono-SemiBold.ttf")  # labels / eyebrows

const DISPLAY_TITLE := &"DisplayTitle"
const MENU_TITLE := &"MenuTitle"
const MONO_TEXT := &"MonoText"
const MONO_SMALL := &"MonoSmall"
const EYEBROW := &"Eyebrow"
const EYEBROW_INTENT := &"EyebrowIntent"
const TOP_MET_LABEL := &"TopMetLabel"
const TOP_MET_VALUE := &"TopMetValue"
const HUD_VALUE := &"HudValue"
const HUD_VALUE_INTENT := &"HudValueIntent"
const HUD_VALUE_TARGET := &"HudValueTarget"
const HUD_VALUE_INK := &"HudValueInk"
const TITLE_ACT := &"TitleAct"
const TITLE_OBJECTIVE := &"TitleObjective"
const MENU_SUBTITLE := &"MenuSubtitle"
const MENU_TAGLINE := &"MenuTagline"
const MENU_FOOTER := &"MenuFooter"
const MENU_WARNING := &"MenuWarning"
const MENU_DANGER := &"MenuDanger"
const MENU_TEXT := &"MenuText"
const TITLE_MENU_TEXT := &"TitleMenuText"
const INSTRUMENT_PANEL := &"InstrumentPanel"
const MODAL_PANEL := &"ModalPanel"
const MENU_TOP_BAR := &"MenuTopBar"
const TOOLBAR_CONSOLE := &"ToolbarConsole"
const HUD_BAR_BACKGROUND := &"HudBarBackground"
const HUD_DIVIDER := &"HudDivider"
const TOP_MET_PANEL := &"TopMetPanel"
const HUD_RULE := &"HudRule"
const INTENT_INDICATOR := &"IntentIndicator"
const MAP_BACKDROP := &"MapBackdrop"
const PAUSE_SCRIM := &"PauseScrim"
const TITLE_CHIP := &"TitleChip"
const SAS_CHIP := &"SasChip"
const OBJECTIVE_PANEL := &"ObjectivePanel"
const REWIND_PANEL := &"RewindPanel"
const TOOLBAR_BUTTON := &"ToolbarButton"
const PRIMARY_BUTTON := &"PrimaryButton"
const DANGER_BUTTON := &"DangerButton"
const SHARED_THEME_PATH := "res://src/ui/generated_ui_theme.tres"

static var _shared_theme: Theme


## The one runtime Godot Theme used by every flight and menu scene. It is built
## once from Palette and the bundled fonts, then inherited by each scene root.
static func shared() -> Theme:
	if _shared_theme == null:
		_shared_theme = load(SHARED_THEME_PATH) as Theme
	return _shared_theme


## Populates the external generated Theme resource. The resource is referenced
## directly by scenes, so its exact font metrics are available in the editor.
static func populate(theme: Theme) -> void:
	_register_palette_colors(theme)
	theme.default_font = MONO
	theme.default_font_size = 14

	_set_label_variation(theme, DISPLAY_TITLE, DISPLAY, 60, Palette.LIVE)
	_set_label_variation(theme, MENU_TITLE, DISPLAY, 30, Palette.LIVE)
	_set_label_variation(theme, MONO_TEXT, MONO, 14, Palette.INK)
	_set_label_variation(theme, MONO_SMALL, MONO, 11, Palette.DIM)
	_set_label_variation(theme, EYEBROW, MONO_SEMI, 12, Palette.VOID)
	_set_label_variation(theme, EYEBROW_INTENT, MONO_SEMI, 12, Palette.VOID)
	_set_label_variation(theme, TOP_MET_LABEL, MONO_SEMI, 9, Palette.VOID)
	_set_label_variation(theme, TOP_MET_VALUE, MONO_SEMI, 21, Palette.VOID)
	_set_label_variation(theme, HUD_VALUE, MONO_SEMI, 18, Palette.LIVE)
	_set_label_variation(theme, HUD_VALUE_INTENT, MONO_SEMI, 18, Palette.INTENT)
	_set_label_variation(theme, HUD_VALUE_TARGET, MONO_SEMI, 18, Palette.TARGET)
	_set_label_variation(theme, HUD_VALUE_INK, MONO_SEMI, 18, Palette.INK)
	_set_label_variation(theme, TITLE_ACT, DISPLAY_SEMI, 15, Palette.INK)
	_set_label_variation(theme, TITLE_OBJECTIVE, DISPLAY_SEMI, 15, Palette.LIVE)
	_set_label_variation(theme, MENU_SUBTITLE, MONO, 15, Palette.LIVE_DIM)
	_set_label_variation(theme, MENU_TAGLINE, MONO, 15, Palette.DIM)
	_set_label_variation(theme, MENU_FOOTER, MONO, 12, Palette.DIM)
	_set_label_variation(theme, MENU_WARNING, MONO_MED, 13, Palette.INTENT)
	_set_label_variation(theme, MENU_DANGER, MONO_MED, 14, Palette.WARNING)
	theme.set_type_variation(MENU_TEXT, &"RichTextLabel")
	theme.set_font("normal_font", MENU_TEXT, MONO_MED)
	theme.set_font_size("normal_font_size", MENU_TEXT, 19)
	theme.set_type_variation(TITLE_MENU_TEXT, &"RichTextLabel")
	theme.set_font("normal_font", TITLE_MENU_TEXT, MONO_MED)
	theme.set_font_size("normal_font_size", TITLE_MENU_TEXT, 21)

	theme.set_stylebox("normal", EYEBROW, _flat_box(Palette.LIVE, Palette.TRANSPARENT,
		0, 10, 10, 5, 5))
	theme.set_stylebox("normal", EYEBROW_INTENT, _flat_box(Palette.INTENT,
		Palette.TRANSPARENT, 0, 10, 10, 5, 5))

	theme.set_type_variation(INSTRUMENT_PANEL, &"PanelContainer")
	theme.set_stylebox("panel", INSTRUMENT_PANEL,
		_flat_box(Palette.PANEL, Palette.HAIRLINE, 2, 12, 12, 12, 12))
	theme.set_type_variation(MODAL_PANEL, &"PanelContainer")
	theme.set_stylebox("panel", MODAL_PANEL,
		_flat_box(Palette.PANEL_BG, Palette.HAIRLINE, 2, 26, 26, 26, 26))
	theme.set_type_variation(MENU_TOP_BAR, &"PanelContainer")
	var top_bar := _flat_box(Palette.VOID, Palette.LIVE, 0, 26, 26, 12, 12)
	top_bar.border_width_bottom = 2
	theme.set_stylebox("panel", MENU_TOP_BAR, top_bar)
	theme.set_type_variation(TOOLBAR_CONSOLE, &"PanelContainer")
	theme.set_stylebox("panel", TOOLBAR_CONSOLE,
		_flat_box(Palette.CONSOLE_BG, Palette.HAIRLINE, 1, 6, 6, 6, 6))
	theme.set_type_variation(HUD_BAR_BACKGROUND, &"Panel")
	theme.set_stylebox("panel", HUD_BAR_BACKGROUND,
		_flat_box(Palette.BAR_BG, Palette.TRANSPARENT, 0, 0, 0, 0, 0))
	theme.set_type_variation(HUD_DIVIDER, &"VSeparator")
	var hud_divider := StyleBoxLine.new()
	hud_divider.color = Palette.HAIRLINE
	hud_divider.thickness = 1
	hud_divider.vertical = true
	theme.set_stylebox("separator", HUD_DIVIDER, hud_divider)
	theme.set_type_variation(TOP_MET_PANEL, &"PanelContainer")
	theme.set_stylebox("panel", TOP_MET_PANEL,
		_flat_box(Palette.LIVE, Palette.TRANSPARENT, 0, 16, 18, 2, 2))
	theme.set_type_variation(HUD_RULE, &"HSeparator")
	var hud_rule := StyleBoxLine.new()
	hud_rule.color = Palette.HAIRLINE
	hud_rule.thickness = 2
	theme.set_stylebox("separator", HUD_RULE, hud_rule)
	theme.set_type_variation(INTENT_INDICATOR, &"Panel")
	theme.set_stylebox("panel", INTENT_INDICATOR,
		_flat_box(Palette.INTENT, Palette.TRANSPARENT, 0, 0, 0, 0, 0))
	theme.set_type_variation(MAP_BACKDROP, &"Panel")
	theme.set_stylebox("panel", MAP_BACKDROP,
		_flat_box(Palette.MAP_BG, Palette.TRANSPARENT, 0, 0, 0, 0, 0))
	theme.set_type_variation(PAUSE_SCRIM, &"Panel")
	theme.set_stylebox("panel", PAUSE_SCRIM,
		_flat_box(Palette.SCRIM, Palette.TRANSPARENT, 0, 0, 0, 0, 0))
	theme.set_type_variation(TITLE_CHIP, &"PanelContainer")
	var title_chip := _flat_box(Palette.PANEL_BG_SOFT, Palette.HAIRLINE, 1, 22, 22, 7, 7)
	title_chip.border_width_top = 0
	theme.set_stylebox("panel", TITLE_CHIP, title_chip)
	theme.set_type_variation(SAS_CHIP, &"PanelContainer")
	theme.set_stylebox("panel", SAS_CHIP,
		_flat_box(Palette.INTENT_DK, Palette.TRANSPARENT, 0, 14, 14, 8, 8))
	theme.set_type_variation(OBJECTIVE_PANEL, &"PanelContainer")
	var objective_panel := _flat_box(Palette.PANEL, Palette.HAIRLINE, 2, 14, 14, 14, 14)
	objective_panel.border_width_left = 5
	theme.set_stylebox("panel", OBJECTIVE_PANEL, objective_panel)
	theme.set_type_variation(REWIND_PANEL, &"PanelContainer")
	theme.set_stylebox("panel", REWIND_PANEL,
		_flat_box(Palette.INTENT_DK, Palette.INTENT, 1, 16, 16, 7, 7))

	_configure_button_variation(theme, TOOLBAR_BUTTON, Palette.TRANSPARENT,
		Palette.HAIRLINE, Palette.INK, Palette.LIVE, 6, 3)
	_configure_button_variation(theme, PRIMARY_BUTTON, Palette.LIVE,
		Palette.LIVE, Palette.VOID, Palette.VOID, 20, 11)
	_configure_button_variation(theme, DANGER_BUTTON, Palette.WARNING,
		Palette.WARNING, Palette.VOID, Palette.VOID, 20, 11)

	_configure_base_widgets(theme)


## Mirrors Palette into the generated Theme so Godot's Theme inspector exposes
## the authoritative values as swatches without serializing copies into scenes.
static func _register_palette_colors(theme: Theme) -> void:
	var palette_script := load("res://src/ui/palette.gd") as Script
	var constants := palette_script.get_script_constant_map()
	for constant_name: StringName in constants:
		var value: Variant = constants[constant_name]
		if value is Color:
			var palette_color: Color = value
			theme.set_color(constant_name, &"Palette", palette_color)
	var body_tints: Dictionary = constants[&"BODY_TINTS"]
	for body_name: String in body_tints:
		var body_color: Color = body_tints[body_name]
		theme.set_color(StringName("BODY_%s" % body_name), &"Palette", body_color)


static func _set_label_variation(
		theme: Theme, variation: StringName, font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_font("font", variation, font)
	theme.set_font_size("font_size", variation, size)
	theme.set_color("font_color", variation, color)


static func _configure_button_variation(
		theme: Theme, variation: StringName, fill: Color, edge: Color,
		foreground: Color, hover_foreground: Color, horizontal_padding: int,
		vertical_padding: int) -> void:
	theme.set_type_variation(variation, &"Button")
	theme.set_font("font", variation, MONO_SEMI if variation == TOOLBAR_BUTTON else DISPLAY_SEMI)
	theme.set_font_size("font_size", variation, 11 if variation == TOOLBAR_BUTTON else 15)
	var normal := _flat_box(fill, edge, 1 if variation == TOOLBAR_BUTTON else 2,
		horizontal_padding, horizontal_padding, vertical_padding, vertical_padding)
	var hover: StyleBoxFlat = normal.duplicate()
	var pressed: StyleBoxFlat = normal.duplicate()
	if variation == TOOLBAR_BUTTON:
		hover.bg_color = Palette.LIVE_DK
		hover.border_color = Palette.LIVE
		pressed.bg_color = Palette.INTENT_DK
		pressed.border_color = Palette.INTENT
	else:
		hover.bg_color = fill.lightened(0.12)
		pressed.bg_color = hover.bg_color
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, hover)
	theme.set_stylebox("pressed", variation, pressed)
	theme.set_stylebox("hover_pressed", variation, pressed)
	theme.set_stylebox("focus", variation, hover)
	theme.set_color("font_color", variation, foreground)
	theme.set_color("font_hover_color", variation, hover_foreground)
	theme.set_color("font_pressed_color", variation,
		Palette.INTENT if variation == TOOLBAR_BUTTON else hover_foreground)
	theme.set_color("font_hover_pressed_color", variation,
		Palette.INTENT if variation == TOOLBAR_BUTTON else hover_foreground)


static func _configure_base_widgets(theme: Theme) -> void:
	theme.set_font("font", &"Label", MONO)
	theme.set_color("font_color", &"Label", Palette.INK)
	theme.set_font("normal_font", &"RichTextLabel", MONO_MED)
	theme.set_font_size("normal_font_size", &"RichTextLabel", 19)
	theme.set_color("default_color", &"RichTextLabel", Palette.INK)
	theme.set_font("font", &"LineEdit", MONO_MED)
	theme.set_font_size("font_size", &"LineEdit", 22)
	theme.set_color("font_color", &"LineEdit", Palette.INK)
	theme.set_color("caret_color", &"LineEdit", Palette.LIVE)
	theme.set_stylebox("normal", &"LineEdit",
		_flat_box(Palette.PANEL, Palette.HAIRLINE, 2, 10, 10, 6, 6))
	theme.set_stylebox("focus", &"LineEdit",
		_flat_box(Palette.PANEL, Palette.LIVE, 2, 10, 10, 6, 6))
	theme.set_font("font", &"CheckButton", MONO_MED)
	theme.set_font_size("font_size", &"CheckButton", 15)
	theme.set_color("font_color", &"CheckButton", Palette.INTENT)


static func _flat_box(
		fill: Color, edge: Color, edge_width: int, margin_left: int,
		margin_right: int, margin_top: int, margin_bottom: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_border_width_all(edge_width)
	box.border_color = edge
	box.set_content_margin(SIDE_LEFT, margin_left)
	box.set_content_margin(SIDE_RIGHT, margin_right)
	box.set_content_margin(SIDE_TOP, margin_top)
	box.set_content_margin(SIDE_BOTTOM, margin_bottom)
	return box


## A bordered panel/card background in the design-ref idiom.
static func panel_box(
		bg: Color = Palette.PANEL, border: Color = Palette.HAIRLINE,
		border_width: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border_width)
	s.border_color = border
	s.set_content_margin_all(12)
	return s

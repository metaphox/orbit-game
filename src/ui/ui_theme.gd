class_name UiTheme
extends RefCounted
## Central UI fonts + style helpers for the "ORBITAL OS" look (ref/design-ref.html).
## The single source of truth for menu/HUD chrome, replacing per-screen
## SystemFont.new() and duplicated colour constants (TECH_DEBTS.md TD-1).
## Colours come from Palette; this owns fonts and the shared widget styles.

const DISPLAY := preload("res://assets/fonts/ChakraPetch-Bold.ttf")       # loud headings
const DISPLAY_SEMI := preload("res://assets/fonts/ChakraPetch-SemiBold.ttf")
const MONO := preload("res://assets/fonts/IBMPlexMono-Regular.ttf")       # data / body text
const MONO_MED := preload("res://assets/fonts/IBMPlexMono-Medium.ttf")
const MONO_SEMI := preload("res://assets/fonts/IBMPlexMono-SemiBold.ttf")  # labels / eyebrows


## A bordered panel/card background in the design-ref idiom.
static func panel_box(bg := Palette.PANEL, border := Palette.HAIRLINE, border_w := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border_w)
	s.border_color = border
	s.set_content_margin_all(12)
	return s


## Full-bleed void background for a screen. Returns a ColorRect anchored to the
## whole rect (caller adds it first so it sits behind everything).
static func background() -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Palette.VOID
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


## Uppercase eyebrow label (mono, tracked, on an accent chip).
static func eyebrow(text: String, accent := Palette.LIVE) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", MONO_SEMI)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Palette.VOID)
	l.add_theme_constant_override("outline_size", 0)
	var box := StyleBoxFlat.new()
	box.bg_color = accent
	box.set_content_margin(SIDE_LEFT, 10)
	box.set_content_margin(SIDE_RIGHT, 10)
	box.set_content_margin(SIDE_TOP, 5)
	box.set_content_margin(SIDE_BOTTOM, 5)
	l.add_theme_stylebox_override("normal", box)
	return l


## Style a Button in the design-ref idiom.
## kind: "primary" (solid phosphor), "danger" (solid red), "" (ghost/outline).
static func style_button(b: Button, kind := "") -> void:
	b.add_theme_font_override("font", DISPLAY_SEMI)
	b.add_theme_font_size_override("font_size", 15)

	var fill := Color(0, 0, 0, 0)
	var edge := Palette.INK
	var fg := Palette.INK
	var fg_hover := Palette.LIVE
	match kind:
		"primary":
			fill = Palette.LIVE; edge = Palette.LIVE; fg = Palette.VOID; fg_hover = Palette.VOID
		"danger":
			fill = Palette.WARNING; edge = Palette.WARNING; fg = Palette.VOID; fg_hover = Palette.VOID

	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.set_border_width_all(2)
	normal.border_color = edge
	normal.set_content_margin(SIDE_LEFT, 20)
	normal.set_content_margin(SIDE_RIGHT, 20)
	normal.set_content_margin(SIDE_TOP, 11)
	normal.set_content_margin(SIDE_BOTTOM, 11)

	var hover: StyleBoxFlat = normal.duplicate()
	if kind == "":
		hover.border_color = Palette.LIVE
	else:
		hover.bg_color = fill.lightened(0.12)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg_hover)
	b.add_theme_color_override("font_pressed_color", fg_hover)
	b.add_theme_color_override("font_focus_color", fg)

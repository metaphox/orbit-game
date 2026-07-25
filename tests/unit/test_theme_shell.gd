extends GutTest
## DA-1: the shared UI Theme is generated from Palette by UiTheme.populate() in
## the resource's _init, so generated_ui_theme.tres must stay a minimal
## script-only SHELL. Any baked sub_resource or theme property is a second copy
## that deserializes OVER populate()'s output on load - the drift the
## single-source theme guarantee (AGENTS.md) forbids.

const THEME_PATH := "res://src/ui/theme/generated_ui_theme.tres"


func test_theme_tres_is_a_script_only_shell() -> void:
	var text := FileAccess.get_file_as_string(THEME_PATH)
	assert_false(text.contains("[sub_resource"),
		"no baked sub_resources (StyleBoxFlat etc.) - populate() builds them")
	assert_false(text.contains("FontFile"),
		"no baked FontFile ext_resources - populate() preloads the fonts")
	# The only property assignment in [resource] is the script; a baked theme token
	# looks like "MonoText/colors/font_color = ...".
	for line: String in text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("[") or l == "" or l.begins_with("script ="):
			continue
		assert_false(l.contains("/") and l.contains("="),
			"unexpected baked theme property (populate() owns these): %s" % l)


func test_populate_rebuilds_the_theme_live_from_palette() -> void:
	# Loading the shell runs _init -> populate(); nothing baked shadows it.
	var theme := UiTheme.shared()
	assert_eq(theme.default_font_size, 14, "populate() set the default font size")
	assert_eq(theme.default_font, UiTheme.MONO, "populate() set the default font from the bundled face")
	assert_eq(theme.get_color("font_color", UiTheme.MONO_TEXT), Palette.INK,
		"a variation colour is sourced live from Palette, not a baked literal")

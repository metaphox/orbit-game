class_name TitleScreen
extends CanvasLayer
## The splash screen: game title plus the main menu. CONTINUE is disabled
## when no profile has ever been active; NEW is disabled once all profile
## slots are full.

signal continue_pressed
signal new_pressed
signal load_pressed
signal settings_pressed
signal credits_pressed
signal quit_pressed

const GREEN := "#73ff8c"
const DIM_GREEN := "#4da362"
const DISABLED := "#4a4a4a"

var _text: RichTextLabel
var _can_continue := false
var _can_new := false


func build(store: ProfileStore) -> void:
	_can_continue = store.last_active_profile() != null
	_can_new = store.can_create_profile()

	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.008, 0.016)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(GREEN))
	title.text = "■ O R B I T ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)

	var tagline := Label.new()
	tagline.add_theme_font_override("font", font)
	tagline.add_theme_font_size_override("font_size", 16)
	tagline.add_theme_color_override("font_color", Color(DIM_GREEN))
	tagline.text = "BURN FUEL. CHANGE ORBIT."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tagline)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 150)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(360, 10)
	_text.add_theme_font_override("normal_font", font)
	_text.add_theme_font_size_override("normal_font_size", 20)
	add_child(_text)
	_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_text.grow_vertical = Control.GROW_DIRECTION_BOTH

	var slots := Label.new()
	slots.add_theme_font_override("font", font)
	slots.add_theme_font_size_override("font_size", 13)
	slots.add_theme_color_override("font_color", Color(DIM_GREEN))
	slots.text = "%d / %d PROFILE SLOTS USED" % [store.profiles.size(), ProfileStore.MAX_PROFILES]
	slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(slots)
	slots.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _refresh() -> void:
	var items := [
		["CONTINUE", _can_continue],
		["NEW PROFILE", _can_new],
		["LOAD PROFILE", true],
		["SETTINGS", true],
		["CREDITS", true],
		["QUIT", true],
	]
	var lines: Array = []
	for i in items.size():
		var label: String = items[i][0]
		var enabled: bool = items[i][1]
		var color := GREEN if enabled else DISABLED
		lines.append("[color=%s][%d] %s[/color]" % [color, i + 1, label])
	_text.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			if _can_continue:
				continue_pressed.emit()
		KEY_2:
			if _can_new:
				new_pressed.emit()
		KEY_3:
			load_pressed.emit()
		KEY_4:
			settings_pressed.emit()
		KEY_5:
			credits_pressed.emit()
		KEY_6:
			quit_pressed.emit()

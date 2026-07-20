class_name LoadProfileScreen
extends CanvasLayer
## Lists existing profiles; press the number next to one to switch to it.

signal profile_chosen(profile_name: String)
signal cancelled

const GREEN := "#73ff8c"
const DIM_GREEN := "#4da362"

var store: ProfileStore
var _text: RichTextLabel


func build(profile_store: ProfileStore) -> void:
	store = profile_store

	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.008, 0.016)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(GREEN))
	title.text = "■ LOAD PILOT ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(420, 10)
	_text.add_theme_font_override("normal_font", font)
	_text.add_theme_font_size_override("normal_font_size", 19)
	add_child(_text)
	_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_text.grow_vertical = Control.GROW_DIRECTION_BOTH

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _refresh() -> void:
	var lines: Array = []
	if store.profiles.is_empty():
		lines.append("[color=%s]NO PROFILES YET[/color]" % DIM_GREEN)
	for i in store.profiles.size():
		var profile: Profile = store.profiles[i]
		var completed := 0
		for index in Campaign.order():
			if profile.medal_for(index) != "":
				completed += 1
		lines.append("[color=%s][%d][/color] %s   [color=%s](%d/%d COMPLETE)[/color]" % [
			GREEN, i + 1, profile.profile_name, DIM_GREEN, completed, Campaign.level_count()])
	lines.append("")
	lines.append("[color=%s][ESC] CANCEL[/color]" % DIM_GREEN)
	_text.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		cancelled.emit()
		return
	if key.physical_keycode < KEY_1 or key.physical_keycode > KEY_9:
		return
	var pos := key.physical_keycode - KEY_1
	if pos < store.profiles.size():
		profile_chosen.emit(store.profiles[pos].profile_name)

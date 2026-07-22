class_name TitleScreen
extends CanvasLayer
## The splash screen: game title plus the main menu. CONTINUE is disabled
## when no profile has ever been active; NEW is disabled once all profile
## slots are full. Navigable by number key or by Up/Down + Enter.

signal continue_pressed
signal new_pressed
signal load_pressed
signal settings_pressed
signal credits_pressed
signal quit_pressed

const GREEN := "#73ff8c"
const DIM_GREEN := "#4da362"
const DISABLED := "#4a4a4a"
const HIGHLIGHT := "#fff59d"
const WARNING := "#ffcc66"

var _text: RichTextLabel
var _items: Array = []  # [label: String, enabled: bool]
var _cursor := 0


func build(store: ProfileStore) -> void:
	var last_profile := store.last_active_profile()
	var continue_label := "CONTINUE"
	if last_profile != null and last_profile.mission_save != null:
		var saved_index: int = last_profile.mission_save.get("level_index", 0)
		continue_label = "CONTINUE (%s)" % Campaign.title(saved_index)
	_items = [
		[continue_label, last_profile != null],
		["NEW PROFILE", store.can_create_profile()],
		["LOAD PROFILE", true],
		["SETTINGS", true],
		["CREDITS", true],
		["QUIT", true],
	]
	_cursor = _first_enabled()

	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.008, 0.016)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(GREEN))
	title.text = "■ LIMITED PROPELLANT ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 90

	var tagline := Label.new()
	tagline.add_theme_font_override("font", font)
	tagline.add_theme_font_size_override("font_size", 16)
	tagline.add_theme_color_override("font_color", Color(DIM_GREEN))
	tagline.text = "LP · BURN FUEL. CHANGE ORBIT. SOLVE LAMBERT'S PROBLEM."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tagline)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tagline.offset_top = 155

	if store.load_warning != "":
		var warning := Label.new()
		warning.add_theme_font_override("font", font)
		warning.add_theme_font_size_override("font_size", 14)
		warning.add_theme_color_override("font_color", Color(WARNING))
		warning.text = "⚠ %s" % store.load_warning
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(warning)
		warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 185)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(380, 10)
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
	slots.text = "%d / %d PROFILE SLOTS USED   ↑↓ SELECT   ENTER CONFIRM" % [
		store.profiles.size(), ProfileStore.MAX_PROFILES]
	slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(slots)
	slots.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _first_enabled() -> int:
	for i in _items.size():
		if _items[i][1]:
			return i
	return 0


func _refresh() -> void:
	var lines: Array[String] = []
	for i in _items.size():
		var label: String = _items[i][0]
		var enabled: bool = _items[i][1]
		var selected := i == _cursor
		var color: String
		if selected and enabled:
			color = HIGHLIGHT
		elif enabled:
			color = GREEN
		else:
			color = DISABLED
		var marker := "▶ " if selected else "  "
		lines.append("[color=%s]%s[%d] %s[/color]" % [color, marker, i + 1, label])
	_text.text = "\n".join(lines)


func _move_cursor(delta: int) -> void:
	var n := _items.size()
	var i := _cursor
	for _step in n:
		i = wrapi(i + delta, 0, n)
		if _items[i][1]:
			_cursor = i
			_refresh()
			return


func _select_and_activate(i: int) -> void:
	if i < 0 or i >= _items.size() or not _items[i][1]:
		return
	_cursor = i
	match i:
		0:
			continue_pressed.emit()
		1:
			new_pressed.emit()
		2:
			load_pressed.emit()
		3:
			settings_pressed.emit()
		4:
			credits_pressed.emit()
		5:
			quit_pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_UP:
			_move_cursor(-1)
		KEY_DOWN:
			_move_cursor(1)
		KEY_ENTER, KEY_KP_ENTER:
			_select_and_activate(_cursor)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_select_and_activate(key.physical_keycode - KEY_1)

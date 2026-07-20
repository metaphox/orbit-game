class_name LevelSelect
extends CanvasLayer
## Mission-select menu: acts and levels with lock/medal state. Press the
## number shown next to a mission to fly it. Placeholder styling shared
## with the HUD's green-on-black look; the CRT shader pass arrives in M7.

signal level_chosen(index: int)

const GREEN := "#73ff8c"
const DIM_GREEN := "#4da362"
const GOLD := "#ffd94d"
const LOCKED := "#555555"

var _text: RichTextLabel
var _order: Array
var _save: SaveData


func build(save_data: SaveData) -> void:
	_save = save_data
	_order = Campaign.order()

	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.008, 0.016)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(GREEN))
	title.text = "■ ORBIT — MISSION SELECT ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 48)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(620, 10)
	_text.add_theme_font_override("normal_font", font)
	_text.add_theme_font_size_override("normal_font_size", 19)
	add_child(_text)
	_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_text.grow_vertical = Control.GROW_DIRECTION_BOTH

	_refresh()
	add_child(ScreenGrade.new())


func _refresh() -> void:
	var lines: Array = []
	var pos := 1
	for act in Campaign.acts():
		lines.append("")
		lines.append("[color=%s]%s[/color]" % [DIM_GREEN, act["name"]])
		for index in act["indices"]:
			var mission_title: String = Campaign.title(index)
			if _save.is_unlocked(index):
				var medal := _save.medal_for(index)
				var medal_tag := "  [color=%s][%s][/color]" % [GOLD, medal] if medal != "" else ""
				lines.append("  [color=%s][%d][/color] %s%s" % [GREEN, pos, mission_title, medal_tag])
			else:
				lines.append("  [color=%s][ ] --- LOCKED ---[/color]" % LOCKED)
			pos += 1
	lines.append("")
	lines.append("[color=%s]PRESS THE MISSION NUMBER TO LAUNCH[/color]" % DIM_GREEN)
	_text.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode < KEY_1 or key.physical_keycode > KEY_9:
		return
	var pos := key.physical_keycode - KEY_1
	if pos < _order.size():
		var index: int = _order[pos]
		if _save.is_unlocked(index):
			level_chosen.emit(index)

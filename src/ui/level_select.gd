class_name LevelSelect
extends CanvasLayer
## Mission-select menu: acts and levels with lock/medal state. Press the
## number shown next to a mission to fly it, or navigate with Up/Down +
## Enter (locked missions are skipped). Placeholder styling shared with
## the HUD's green-on-black look; the CRT shader pass arrives in M7.

signal level_chosen(index: int)
signal back_pressed

var _text: RichTextLabel
var _order: Array[int]
var _profile: Profile
var _cursor := 0


func build(profile: Profile) -> void:
	_profile = profile
	_order = Campaign.order()
	_cursor = _first_unlocked_pos()

	var bg := ColorRect.new()
	bg.color = Palette.MENU_BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Palette.MENU_GREEN)
	title.text = "■ ORBIT — MISSION SELECT ■"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 48)

	var pilot := Label.new()
	pilot.add_theme_font_override("font", font)
	pilot.add_theme_font_size_override("font_size", 15)
	pilot.add_theme_color_override("font_color", Palette.MENU_GREEN_DIM)
	pilot.text = "PILOT: %s" % profile.profile_name
	pilot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(pilot)
	pilot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 84)

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
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _first_unlocked_pos() -> int:
	for i in _order.size():
		if _is_selectable(_order[i]):
			return i
	return 0


## True if the mission can be flown right now: either actually unlocked on
## the profile, or Settings.debug_mode is bypassing the lock entirely.
func _is_selectable(index: int) -> bool:
	return Settings.debug_mode or _profile.is_unlocked(index)


func _refresh() -> void:
	var green := Palette.hex(Palette.MENU_GREEN)
	var dim := Palette.hex(Palette.MENU_GREEN_DIM)
	var gold := Palette.hex(Palette.MENU_GOLD)
	var locked := Palette.hex(Palette.MENU_LOCKED)
	var highlight := Palette.hex(Palette.MENU_HIGHLIGHT)
	var lines: Array[String] = []
	var pos := 0  # 0-based; matches _order index and the number-key mapping
	for act in Campaign.acts():
		lines.append("")
		lines.append("[color=%s]%s[/color]" % [dim, act["name"]])
		for index: int in act["indices"]:
			var mission_title: String = Campaign.title(index)
			var selected := pos == _cursor
			var marker := "▶ " if selected else "  "
			var unlocked := _profile.is_unlocked(index)
			if unlocked or Settings.debug_mode:
				var medal := _profile.medal_for(index)
				var medal_tag := "  [color=%s][%s][/color]" % [gold, medal] if medal != "" else ""
				var debug_tag := "  [color=%s][DEBUG][/color]" % gold if not unlocked else ""
				var num_color := highlight if selected else green
				var title_text := (
					"[color=%s]%s[/color]" % [highlight, mission_title] if selected
					else mission_title)
				lines.append("%s[color=%s][%d][/color] %s%s%s" % [
					marker, num_color, pos + 1, title_text, medal_tag, debug_tag])
			else:
				lines.append("%s[color=%s][ ] --- LOCKED ---[/color]" % [marker, locked])
			pos += 1
	lines.append("")
	if Settings.debug_mode:
		lines.append("[color=%s][DEBUG MODE — ALL LEVELS UNLOCKED][/color]" % gold)
	lines.append("[color=%s]↑↓ SELECT  ENTER LAUNCH  OR PRESS NUMBER   [ESC] TITLE SCREEN[/color]"
		% dim)
	_text.text = "\n".join(lines)


func _move_cursor(delta: int) -> void:
	var n := _order.size()
	if n == 0:
		return
	var i := _cursor
	for _step in n:
		i = wrapi(i + delta, 0, n)
		if _is_selectable(_order[i]):
			_cursor = i
			_refresh()
			return


func _select_and_activate(pos: int) -> void:
	if pos < 0 or pos >= _order.size():
		return
	var index: int = _order[pos]
	if not _is_selectable(index):
		return
	_cursor = pos
	level_chosen.emit(index)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_ESCAPE:
			back_pressed.emit()
		KEY_UP:
			_move_cursor(-1)
		KEY_DOWN:
			_move_cursor(1)
		KEY_ENTER, KEY_KP_ENTER:
			_select_and_activate(_cursor)
		_:
			if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
				_select_and_activate(key.physical_keycode - KEY_1)

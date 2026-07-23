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
var _layout: MenuTextLayout


func build(profile: Profile) -> void:
	_profile = profile
	_order = Campaign.order()
	_cursor = _first_unlocked_pos()

	_layout = preload("res://src/ui/menu_text_layout.tscn").instantiate()
	add_child(_layout)
	_layout.configure("■ ORBIT — MISSION SELECT ■", "PILOT: %s" % profile.profile_name, "")
	_text = _layout.content
	_text.custom_minimum_size = Vector2(620, 10)

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
	var green := Palette.hex(Palette.LIVE)
	var dim := Palette.hex(Palette.LIVE_DIM)
	var gold := Palette.hex(Palette.MEDAL_GOLD)
	var locked := Palette.hex(Palette.DISABLED)
	var highlight := Palette.hex(Palette.INTENT)
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

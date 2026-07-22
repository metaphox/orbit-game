class_name TitleScreen
extends CanvasLayer
## The splash screen: game title plus the main menu. CONTINUE is disabled
## when no profile has ever been active; NEW is disabled once all profile
## slots are full. Navigable by number key or by Up/Down + Enter.
## Styled with the shared ORBITAL-OS system (UiTheme + Palette).

signal continue_pressed
signal new_pressed
signal load_pressed
signal settings_pressed
signal credits_pressed
signal quit_pressed

var _text: RichTextLabel
var _items: Array = []  # [label: String, enabled: bool]
var _cursor := 0


func build(store: ProfileStore) -> void:
	var last_profile := store.last_active_profile()
	var continue_label := "CONTINUE"
	if last_profile != null and last_profile.mission_save != null:
		var saved_index: int = last_profile.mission_save.get("level_index", 0)
		continue_label = "CONTINUE — %s" % Campaign.title(saved_index)
	_items = [
		[continue_label, last_profile != null],
		["NEW PROFILE", store.can_create_profile()],
		["LOAD PROFILE", true],
		["SETTINGS", true],
		["CREDITS", true],
		["QUIT", true],
	]
	_cursor = _first_enabled()

	add_child(UiTheme.background())
	_build_top_bar()

	var eyebrow := UiTheme.eyebrow("Flight Computer · Main Menu", Palette.LIVE)
	add_child(eyebrow)
	eyebrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 178)

	var title := Label.new()
	title.add_theme_font_override("font", UiTheme.DISPLAY)
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Palette.LIVE)
	title.text = "LIMITED PROPELLANT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 214

	var tagline := Label.new()
	tagline.add_theme_font_override("font", UiTheme.MONO)
	tagline.add_theme_font_size_override("font_size", 15)
	tagline.add_theme_color_override("font_color", Palette.DIM)
	tagline.text = "LP // BURN FUEL. CHANGE ORBIT. SOLVE LAMBERT'S PROBLEM."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tagline)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tagline.offset_top = 296

	_hazard_divider(330)

	if store.load_warning != "":
		var warn := Label.new()
		warn.add_theme_font_override("font", UiTheme.MONO_MED)
		warn.add_theme_font_size_override("font_size", 13)
		warn.add_theme_color_override("font_color", Palette.INTENT)
		warn.text = "⚠ %s" % store.load_warning
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(warn)
		warn.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		warn.offset_top = 352

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(440, 10)
	_text.add_theme_font_override("normal_font", UiTheme.MONO_MED)
	_text.add_theme_font_size_override("normal_font_size", 21)
	add_child(_text)
	_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 384)
	_text.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var slots := Label.new()
	slots.add_theme_font_override("font", UiTheme.MONO)
	slots.add_theme_font_size_override("font_size", 12)
	slots.add_theme_color_override("font_color", Palette.DIM)
	slots.text = "%d / %d PROFILE SLOTS   ·   ↑↓ SELECT   ·   ENTER CONFIRM" % [
		store.profiles.size(), ProfileStore.MAX_PROFILES]
	slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(slots)
	slots.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 44)

	_refresh()
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.VOID
	box.set_border_width(SIDE_BOTTOM, 2)
	box.border_color = Palette.LIVE
	box.set_content_margin(SIDE_LEFT, 26)
	box.set_content_margin(SIDE_RIGHT, 26)
	box.set_content_margin(SIDE_TOP, 12)
	box.set_content_margin(SIDE_BOTTOM, 12)
	bar.add_theme_stylebox_override("panel", box)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	var diamond := Control.new()
	diamond.custom_minimum_size = Vector2(14, 14)
	diamond.draw.connect(func() -> void:
		diamond.draw_colored_polygon(PackedVector2Array([
			Vector2(7, 0), Vector2(14, 7), Vector2(7, 14), Vector2(0, 7)]), Palette.LIVE))
	row.add_child(diamond)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_override("font", UiTheme.MONO_SEMI)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Palette.INK)
	name_lbl.text = "ORBITAL OS"
	row.add_child(name_lbl)

	row.add_child(UiTheme.eyebrow("v2 · Flight", Palette.INTENT))

	var status := Label.new()
	status.add_theme_font_override("font", UiTheme.MONO)
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Palette.LIVE)
	status.text = "■ SYS NOMINAL"
	status.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	row.add_child(status)


func _hazard_divider(offset_top: int) -> void:
	var d := Control.new()
	d.custom_minimum_size = Vector2(360, 6)
	add_child(d)
	d.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, offset_top)
	d.grow_horizontal = Control.GROW_DIRECTION_BOTH
	d.draw.connect(func() -> void:
		var w := d.size.x
		var step := 16.0
		var x := 0.0
		while x < w:
			d.draw_colored_polygon(PackedVector2Array([
				Vector2(x, 0), Vector2(x + step * 0.5, 0),
				Vector2(x + step * 0.5, 6), Vector2(x, 6)]), Palette.INTENT)
			x += step)


func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


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
		var color: Color
		if selected and enabled:
			color = Palette.SELECT
		elif enabled:
			color = Palette.LIVE
		else:
			color = Palette.DISABLED
		var marker := "▶ " if selected else "  "
		lines.append("[color=%s]%s[%d]  %s[/color]" % [_hex(color), marker, i + 1, label])
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

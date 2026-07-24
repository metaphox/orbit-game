class_name LevelSelect
extends CanvasLayer
## Two-pane mission select: a left column of act-grouped mission cards and a right
## detail pane (brief + orbit preview + stats + LAUNCH). Built-in acts come from
## Campaign (integer indices); an optional COMMUNITY act lists drop-in levels
## (string IDs, all unlocked, progress in the sandbox). Keyboard: Up/Down move the
## selection (locked skipped); Left/Right jump acts; Enter launches. Mouse: hover
## previews, click selects, LAUNCH / double-click launches. F1 toggles hints.

signal level_chosen(index: int)             # a built-in level
signal community_chosen(id: String, level: LevelDef)  # a drop-in level
signal back_pressed

const HINT := "↑↓ / W S / K J  MISSION     ← → / A D / H L  ACT     ENTER  LAUNCH     [ESC]  TITLE     [F1]  HIDE"

## One per card, in display order. Built-in: {community:false, index:int}.
## Community: {community:true, id:String, level:LevelDef, dir:String}.
var _entries: Array[Dictionary] = []
var _bounds: Array = []  # [start, end) per section, for Left/Right act jumps
var _profile: Profile
var _sandbox: SandboxStore
var _cursor := 0
var _hover_pos := -1
var _shell: MenuShell
var _detail: MissionDetailPane
var _cards: Array[MissionCard] = []


func build(profile: Profile, sandbox: SandboxStore = null) -> void:
	_profile = profile
	_sandbox = sandbox

	_shell = MenuShell.create()
	add_child(_shell)
	_shell.configure("MAIN MENU ▶ MISSIONS")
	_shell.set_hint(HINT)

	_detail = MissionDetailPane.create()
	_detail.launch_requested.connect(_launch_shown)
	_shell.set_right(_detail)

	_build_cards()
	_cursor = _first_selectable_pos()
	_shell.add_back(func() -> void: back_pressed.emit())
	_shell.left_column.mouse_exited.connect(_clear_hover)

	if Settings.effects_enabled:
		add_child(ScreenGrade.new())
	_refresh()


func _build_cards() -> void:
	_cards.clear()
	_entries.clear()
	_bounds.clear()
	for act: Dictionary in Campaign.acts():
		_add_section(act["name"])
		for index: int in act["indices"]:
			_add_card({"community": false, "index": index})
	# Drop-in community levels that loaded cleanly, as their own section.
	var community: Array = []
	for e: Dictionary in CommunityLevels.all():
		if e["level"] != null:
			community.append(e)
	if not community.is_empty():
		_add_section("COMMUNITY")
		var n := 1
		for e: Dictionary in community:
			_add_card({"community": true, "id": e["id"], "level": e["level"], "dir": e["dir"], "num": n})
			n += 1
	_add_open_mods_button()  # always, so modding is discoverable even with no levels yet


## A mouse-only affordance at the foot of the list that opens the writable mods
## folder in the OS file browser (kept out of _entries so it isn't a launch target).
func _add_open_mods_button() -> void:
	var btn := Button.new()
	btn.theme_type_variation = UiTheme.CARD
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "OPEN MODS FOLDER"
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 48)
	btn.pressed.connect(func() -> void:
		ModPaths.ensure_scaffold()  # create it on demand if this is the very first click
		OS.shell_open(ModPaths.documents_dir()))
	_shell.left_column.add_child(btn)


func _add_section(title: String) -> void:
	if not _bounds.is_empty():
		_bounds[-1][1] = _entries.size()
	_bounds.append([_entries.size(), _entries.size()])
	var header := Label.new()
	header.theme_type_variation = UiTheme.ACT_HEADER
	header.text = title
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 16)
	wrap.add_theme_constant_override("margin_left", 16)
	wrap.add_theme_constant_override("margin_bottom", 4)
	wrap.add_child(header)
	_shell.left_column.add_child(wrap)


func _add_card(entry: Dictionary) -> void:
	var pos := _entries.size()
	_entries.append(entry)
	_bounds[-1][1] = _entries.size()
	var card := MissionCard.new()
	_shell.left_column.add_child(card)
	if entry["community"]:
		var lvl: LevelDef = entry["level"]
		card.set_data(pos, "MOD-%02d" % entry["num"], _short_title(lvl.title),  # i18n-ok: mission code (like ORB/LUN)
			_community_status(entry["id"]), lvl.difficulty, false)
	else:
		var index: int = entry["index"]
		card.set_data(pos, Campaign.code(index), Campaign.short_title(index),
			Campaign.status_label(_profile, index), Campaign.level_at(index).difficulty,
			not _is_selectable(pos))
	card.hovered.connect(_on_card_hovered)
	card.unhovered.connect(_on_card_unhovered)
	card.clicked.connect(_on_card_clicked)
	card.activated.connect(_on_card_activated)
	_cards.append(card)


func _short_title(title: String) -> String:
	var parts := title.split(":")
	return (parts[1] if parts.size() > 1 else parts[0]).strip_edges()


func _community_status(id: String) -> String:
	var medal := _sandbox.medal_for(id) if _sandbox != null else ""
	return medal if medal != "" else TranslationServer.translate("ACTIVE", &"status")


func _first_selectable_pos() -> int:
	for i in _entries.size():
		if _is_selectable(i):
			return i
	return 0


## Community levels are always selectable; built-ins depend on profile unlock
## (or --debug-mode).
func _is_selectable(pos: int) -> bool:
	if pos < 0 or pos >= _entries.size():
		return false
	var e: Dictionary = _entries[pos]
	if e["community"]:
		return true
	return Settings.debug_mode or _profile.is_unlocked(e["index"])


func _refresh() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _cursor)
	var shown := _hover_pos if _hover_pos >= 0 else _cursor
	if shown >= 0 and shown < _entries.size():
		var e: Dictionary = _entries[shown]
		if e["community"]:
			_detail.show_community(e["level"], _sandbox_medal(e["id"]), _community_plan(e))
		else:
			_detail.show_level(e["index"], _profile)
		_detail.set_launch_enabled(_is_selectable(shown))
	if _cursor >= 0 and _cursor < _cards.size():
		_shell.ensure_visible(_cards[_cursor])


func _sandbox_medal(id: String) -> String:
	return _sandbox.medal_for(id) if _sandbox != null else ""


func _community_plan(entry: Dictionary) -> String:
	var path: String = (entry["dir"] as String).path_join(entry["id"] + ".md")  # i18n-ok: file extension
	if FileAccess.file_exists(path):
		return BriefText.md_to_bbcode(FileAccess.open(path, FileAccess.READ).get_as_text().strip_edges())
	return ""


func _on_card_hovered(pos: int) -> void:
	_hover_pos = pos
	_refresh()


func _on_card_unhovered(pos: int) -> void:
	if _hover_pos == pos:
		_hover_pos = -1
		_refresh()


func _clear_hover() -> void:
	if _hover_pos != -1:
		_hover_pos = -1
		_refresh()


func _on_card_clicked(pos: int) -> void:
	if not _is_selectable(pos):
		return
	_cursor = pos
	_hover_pos = -1
	_refresh()


func _on_card_activated(pos: int) -> void:
	_select_and_activate(pos)


func _launch_shown() -> void:
	_select_and_activate(_hover_pos if _hover_pos >= 0 else _cursor)


func _move_cursor(delta: int) -> void:
	var n := _entries.size()
	if n == 0:
		return
	var i := _cursor
	for _step in n:
		i = wrapi(i + delta, 0, n)
		if _is_selectable(i):
			_cursor = i
			_hover_pos = -1
			_refresh()
			return


func _current_section() -> int:
	for a: int in _bounds.size():
		if _cursor >= _bounds[a][0] and _cursor < _bounds[a][1]:
			return a
	return 0


## Jump to the first selectable card of the previous/next section, skipping
## empty/all-locked ones.
func _move_act(delta: int) -> void:
	var n := _bounds.size()
	if n <= 1:
		return
	var a := _current_section()
	for _step: int in n:
		a = wrapi(a + delta, 0, n)
		for pos: int in range(_bounds[a][0], _bounds[a][1]):
			if _is_selectable(pos):
				_cursor = pos
				_hover_pos = -1
				_refresh()
				return


func _select_and_activate(pos: int) -> void:
	if not _is_selectable(pos):
		return
	_cursor = pos
	var e: Dictionary = _entries[pos]
	if e["community"]:
		community_chosen.emit(e["id"], e["level"])
	else:
		level_chosen.emit(e["index"])


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_ESCAPE:
			back_pressed.emit()
		KEY_UP, KEY_W, KEY_K:
			_move_cursor(-1)
		KEY_DOWN, KEY_S, KEY_J:
			_move_cursor(1)
		KEY_LEFT, KEY_A, KEY_H:
			_move_act(-1)
		KEY_RIGHT, KEY_D, KEY_L:
			_move_act(1)
		KEY_ENTER, KEY_KP_ENTER:
			_select_and_activate(_cursor)
		KEY_F1:
			Settings.toggle_menu_hints()
			_shell.refresh_hint_visibility()

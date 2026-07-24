extends "res://tests/unit/base_orbit_test.gd"
## The shared menu-redesign components: cards, the shell, the detail pane, and the
## orbit preview (a SubViewport schematic) all build headless without error and
## expose the behaviour the mission-select screen drives.


func test_mission_card_reflects_data_and_selection() -> void:
	var card := MissionCard.new()
	add_child_autofree(card)
	card.set_data(3, "LUN-01", "TRANSLUNAR INJECTION", "ACTIVE", 3, false)
	assert_eq(card.pos, 3)
	assert_false(card.disabled, "an unlocked mission is not a disabled button")
	assert_eq(card.theme_type_variation, UiTheme.CARD, "unselected uses the plain card style")
	assert_eq(card._pips.value, 3, "difficulty drives the pips")

	card.set_selected(true)
	assert_eq(card.theme_type_variation, UiTheme.CARD_SELECTED, "selected fills green")
	assert_true(card._cursor.visible, "the ◀ cursor shows on the selected card")

	card.set_data(4, "LUN-02", "MARE SERENITATIS", "LOCKED", 3, true)
	assert_true(card.disabled, "a locked mission is a disabled button")


func test_mission_card_emits_click_and_double_click() -> void:
	var card := MissionCard.new()
	add_child_autofree(card)
	card.set_data(2, "ORB-03", "PLANE CHANGE", "ACTIVE", 2, false)
	var clicked := [-1]
	var activated := [-1]
	card.clicked.connect(func(p: int) -> void: clicked[0] = p)
	card.activated.connect(func(p: int) -> void: activated[0] = p)
	card.pressed.emit()  # single click selects
	assert_eq(clicked[0], 2)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.double_click = true
	card._on_gui_input(ev)  # double click launches
	assert_eq(activated[0], 2)


func test_menu_shell_builds_the_two_pane_frame() -> void:
	var shell := MenuShell.new()
	add_child_autofree(shell)
	shell.configure("MAIN MENU ▶ MISSIONS")
	shell.set_hint("↑↓ NAVIGATE   ENTER LAUNCH")
	assert_not_null(shell.left_column, "left card column exists")
	assert_not_null(shell.right_pane, "right detail pane exists")
	assert_same(shell.theme, UiTheme.shared(), "the shell carries the shared theme for its children")
	var content := Label.new()
	shell.set_right(content)
	assert_eq(content.get_parent(), shell.right_pane, "set_right hosts the content")


func test_orbit_preview_builds_for_every_level() -> void:
	for i: int in Campaign.level_count():
		var preview := OrbitPreview.new()
		add_child_autofree(preview)
		preview.build(Campaign.level_at(i))
		assert_true(preview._built, "%s preview built without error" % Campaign.title(i))


func test_mission_detail_pane_shows_a_level_and_launches() -> void:
	var detail := MissionDetailPane.new()
	add_child_autofree(detail)
	var profile := Profile.new()  # level 0 unlocked, none cleared
	detail.show_level(0, profile)
	assert_eq(detail._title.text, "RAISE ORBIT", "title is the short mission name")
	assert_true(detail._code_status.text.begins_with("ORB-01"), "code · status line")

	var launched := [-1]
	detail.launch_requested.connect(func(idx: int) -> void: launched[0] = idx)
	detail.set_launch_enabled(false)
	detail._launch.pressed.emit()
	assert_eq(launched[0], -1, "a disabled LAUNCH does not fire")
	detail.set_launch_enabled(true)
	detail._launch.pressed.emit()
	assert_eq(launched[0], 0, "LAUNCH emits the shown mission index")

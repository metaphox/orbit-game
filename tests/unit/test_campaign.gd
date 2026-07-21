extends "res://tests/unit/base_orbit_test.gd"
## Campaign registry, multi-profile save persistence, settings, and the
## title -> profile -> mission-select -> flight menu-shell scene.

const CampaignRootScene := preload("res://src/campaign_root.tscn")
const GameRootScript := preload("res://src/game_root.gd")
const SAVE_TEST_PATH := "user://test_save.json"


func before_each() -> void:
	_clear_save()
	Settings.effects_enabled = true
	Settings.debug_mode = false


func after_each() -> void:
	_clear_save()
	GameRootScript.level_index = 0
	Settings.effects_enabled = true
	Settings.debug_mode = false


func _clear_save() -> void:
	var suffixes: Array[String] = ["", ProfileStore.BACKUP_SUFFIX, ProfileStore.TMP_SUFFIX]
	for suffix in suffixes:
		var p: String = SAVE_TEST_PATH + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_campaign_order_and_next() -> void:
	assert_eq(Campaign.order(), [0, 1, 2, 3, 4, 5, 6], "act-grouped play order")
	assert_eq(Campaign.next_after(0), 1, "orbit school 1 unlocks rendezvous")
	assert_eq(Campaign.next_after(2), 3, "plane change unlocks the lunar program act")
	assert_eq(Campaign.next_after(5), 6, "lunar return unlocks the interplanetary act")
	assert_eq(Campaign.next_after(6), -1, "no level after the last one")


func test_profile_progress_round_trip_and_unlock() -> void:
	var profile := Profile.new()
	profile.profile_name = "Ada"
	assert_true(profile.is_unlocked(0), "first level starts unlocked")
	assert_false(profile.is_unlocked(1), "later levels start locked")

	profile.record_win(0, "GOLD ★★★", 60.0)
	assert_true(profile.is_unlocked(1), "winning unlocks the next campaign level")
	assert_eq(profile.medal_for(0), "GOLD ★★★")

	profile.record_win(0, "BRONZE ★", 90.0)
	assert_eq(profile.medal_for(0), "GOLD ★★★", "a worse run does not overwrite the best medal")


func test_profile_name_validation() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_eq(store.validate_new_name(""), "ENTER A NAME")
	assert_eq(store.validate_new_name("   "), "ENTER A NAME", "whitespace-only is empty")
	assert_eq(store.validate_new_name("a".repeat(21)), "NAME TOO LONG (20 CHARS MAX)")
	assert_eq(store.validate_new_name("Ada"), "", "a fresh valid name passes")

	store.create_profile("Ada")
	assert_eq(store.validate_new_name("Ada"), "NAME ALREADY TAKEN")
	assert_eq(store.validate_new_name(" Ada "), "NAME ALREADY TAKEN", "trims before comparing")


func test_profile_slots_limited_to_five() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	for i in ProfileStore.MAX_PROFILES:
		assert_true(store.can_create_profile(), "slot %d available" % i)
		store.create_profile("Pilot%d" % i)
	assert_false(store.can_create_profile(), "all five slots used")
	assert_eq(store.validate_new_name("OneMore"), "ALL 5 PROFILE SLOTS FULL")


func test_multiple_profiles_persist_independently() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	var ada := store.create_profile("Ada")
	var grace := store.create_profile("Grace")
	ada.record_win(0, "GOLD ★★★", 60.0)
	store.save()

	var reloaded := ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_eq(reloaded.profiles.size(), 2, "both profiles persisted")
	var reloaded_ada := reloaded.find_profile("Ada")
	var reloaded_grace := reloaded.find_profile("Grace")
	assert_true(reloaded_ada.is_unlocked(1), "Ada's progress persisted")
	assert_false(reloaded_grace.is_unlocked(1), "Grace's progress is independent of Ada's")
	assert_eq(reloaded.last_active_name, "Grace", "last-created profile is active")
	assert_eq(reloaded.last_active_profile().profile_name, "Grace")


func test_settings_persist_across_reload() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	Settings.effects_enabled = false
	store.save()
	Settings.effects_enabled = true  # simulate a fresh process before reload

	ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_false(Settings.effects_enabled, "effects toggle persisted to disk")


func test_save_includes_schema_version() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	store.create_profile("Ada")
	var f := FileAccess.open(SAVE_TEST_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	# JSON has no int type - everything numeric round-trips as float.
	assert_eq(parsed.get("version"), 2.0)


func test_save_reports_success_and_failure() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_true(store.save(), "happy path succeeds")

	var broken := ProfileStore.load_or_new("user://no_such_dir/save.json")
	assert_false(broken.save(), "an unwritable path fails cleanly instead of throwing")
	assert_push_error("could not open", "the failure is logged, not silent")


func test_corrupt_save_recovers_from_backup() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	store.create_profile("Ada")  # save #1: no prior primary, so no backup yet
	store.create_profile("Grace")  # save #2: save #1's primary (Ada only) becomes the backup
	_write_raw(SAVE_TEST_PATH, "{not valid json")  # simulate a crash mid-write

	var reloaded := ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_eq(reloaded.load_warning, "SAVE FILE WAS DAMAGED - RECOVERED FROM BACKUP")
	assert_not_null(reloaded.find_profile("Ada"), "recovered from the one-save-behind backup")
	assert_null(reloaded.find_profile("Grace"), "backup is one save behind - Grace isn't in it")
	assert_engine_error("Variant()", "malformed JSON logs an engine-level parse error")
	assert_push_error("does not contain a valid save", "and ProfileStore logs its own detail")


func test_corrupt_save_with_no_backup_starts_fresh_with_a_warning() -> void:
	_write_raw(SAVE_TEST_PATH, "not json at all")
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_eq(store.profiles.size(), 0, "nothing to recover, so starts empty")
	assert_eq(store.load_warning, "SAVE FILE WAS UNREADABLE - STARTING FRESH")
	assert_engine_error("Variant()", "malformed JSON logs an engine-level parse error")
	assert_push_error("does not contain a valid save", "and ProfileStore logs its own detail")


func test_missing_save_file_has_no_warning() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_eq(store.load_warning, "", "a first-ever run isn't a save failure")


func test_malformed_profile_entry_is_skipped_not_fatal() -> void:
	_write_raw(SAVE_TEST_PATH, JSON.stringify({
		"version": 2,
		"last_active": "Ada",
		"profiles": [
			{"name": "Ada", "unlocked": [0, 2], "medals": {}, "mission_save": null},
			"not even a dictionary",
		],
	}))
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_eq(store.profiles.size(), 1, "the malformed entry is skipped, not fatal")
	assert_not_null(store.find_profile("Ada"))
	assert_true(store.find_profile("Ada").is_unlocked(2))


func test_campaign_root_starts_on_title_screen() -> void:
	var root: Node = CampaignRootScene.instantiate()
	add_child_autofree(root)
	simulate(root, 2, 1.0 / 60.0)
	assert_true(root._current_ui is TitleScreen, "boots to the title screen, not the menu")
	assert_null(root.game, "no flight scene yet")


func test_new_profile_flow_reaches_mission_select_and_flies() -> void:
	var root: Node = CampaignRootScene.instantiate()
	root.store = ProfileStore.load_or_new(SAVE_TEST_PATH)
	add_child_autofree(root)
	simulate(root, 2, 1.0 / 60.0)

	root._on_profile_created("Ada")
	simulate(root, 2, 1.0 / 60.0)
	assert_eq(root.active_profile.profile_name, "Ada")
	assert_true(root._current_ui is LevelSelect, "new profile lands on mission select")

	root._launch(0)
	simulate(root, 2, 1.0 / 60.0)
	assert_not_null(root.game, "flight scene instantiated")
	assert_eq(root.game.level.title, Campaign.title(0))

	root.game.restart_requested.emit()
	simulate(root, 2, 1.0 / 60.0)
	assert_not_null(root.game, "restart rebuilds the flight scene")

	root.game.exit_requested.emit()
	simulate(root, 2, 1.0 / 60.0)
	assert_true(root._current_ui is LevelSelect, "exit returns to mission select")
	assert_null(root.game, "flight scene torn down on exit")

	root._current_ui.back_pressed.emit()
	simulate(root, 2, 1.0 / 60.0)
	assert_true(root._current_ui is TitleScreen, "mission select can return to the title")


func test_win_persists_to_active_profile_and_advances_campaign() -> void:
	var root: Node = CampaignRootScene.instantiate()
	root.store = ProfileStore.load_or_new(SAVE_TEST_PATH)
	add_child_autofree(root)
	root._on_profile_created("Ada")
	root._launch(0)
	simulate(root, 2, 1.0 / 60.0)

	var ship: ShipSim = root.game.ship
	var target: float = root.game.level.objective.target_radius
	ship.elements = OrbitElements.from_state(
		DVec3.new(target, 0.0, 0.0),
		DVec3.new(0.0, 0.0, -sqrt(root.game.level.body.mu / target)),
		root.game.level.body.mu, root.game.sim_time)
	simulate(root, 5, 1.0 / 60.0)
	assert_eq(root.game.phase, root.game.Phase.WON, "objective met")
	assert_true(root.active_profile.is_unlocked(1), "win unlocked the next mission")
	assert_true(root.store.find_profile("Ada").is_unlocked(1), "and it's saved to the store")

	root.game.next_requested.emit(0)
	simulate(root, 2, 1.0 / 60.0)
	assert_eq(root.game.level.title, Campaign.title(1), "N advanced to the next mission")


func test_load_profile_switches_active_profile() -> void:
	var root: Node = CampaignRootScene.instantiate()
	root.store = ProfileStore.load_or_new(SAVE_TEST_PATH)
	add_child_autofree(root)
	root.store.create_profile("Ada")
	root.store.create_profile("Grace")  # becomes last-active
	simulate(root, 2, 1.0 / 60.0)

	root._on_profile_chosen("Ada")
	simulate(root, 2, 1.0 / 60.0)
	assert_eq(root.active_profile.profile_name, "Ada", "explicitly switched profile")
	assert_eq(root.store.last_active_name, "Ada", "switch persists as the new default")


func test_title_screen_arrow_navigation_skips_disabled_items() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)  # no profiles -> CONTINUE disabled
	var screen := TitleScreen.new()
	add_child_autofree(screen)
	screen.build(store)
	assert_eq(screen._cursor, 1, "starts on the first enabled item (NEW PROFILE, not CONTINUE)")

	screen._move_cursor(-1)
	assert_eq(screen._cursor, 5, "moving up from the top wraps to the last item (QUIT)")

	screen._move_cursor(1)
	assert_eq(screen._cursor, 1, "moving down from QUIT wraps back around, skipping CONTINUE")

	# GDScript lambdas capture locals by value, so use a 1-element array as
	# a mutable box the closure can actually write through.
	var quit_signaled := [false]
	screen.quit_pressed.connect(func(): quit_signaled[0] = true)
	screen._move_cursor(-1)
	screen._select_and_activate(screen._cursor)
	assert_true(quit_signaled[0], "Enter on the highlighted item activates it")


func test_title_screen_number_key_still_works_and_moves_cursor() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	store.create_profile("Ada")  # now CONTINUE is enabled
	var screen := TitleScreen.new()
	add_child_autofree(screen)
	screen.build(store)

	var settings_signaled := [false]
	screen.settings_pressed.connect(func(): settings_signaled[0] = true)
	screen._select_and_activate(3)  # [4] SETTINGS
	assert_true(settings_signaled[0], "direct activation still works")
	assert_eq(screen._cursor, 3, "activating an item also moves the cursor there")


func test_level_select_arrow_navigation_skips_locked_missions() -> void:
	var profile := Profile.new()  # only level 0 unlocked
	var screen := LevelSelect.new()
	add_child_autofree(screen)
	screen.build(profile)
	assert_eq(screen._cursor, 0, "starts on the only unlocked mission")

	screen._move_cursor(1)
	assert_eq(screen._cursor, 0, "no other mission is unlocked, so cursor can't move")

	profile.record_win(0, "GOLD ★★★", 60.0)  # unlocks Campaign.order()[1] (level 2)
	screen._refresh()  # profile mutated in place; screen doesn't poll on its own
	screen._move_cursor(1)
	assert_eq(screen._cursor, 1, "cursor now advances to the newly-unlocked mission")

	var chosen := [-1]
	screen.level_chosen.connect(func(index): chosen[0] = index)
	screen._select_and_activate(screen._cursor)
	assert_eq(chosen[0], Campaign.order()[1], "Enter launches the highlighted, unlocked mission")


func test_level_select_debug_mode_unlocks_everything() -> void:
	Settings.debug_mode = true
	var profile := Profile.new()  # only level 0 unlocked
	var screen := LevelSelect.new()
	add_child_autofree(screen)
	screen.build(profile)

	screen._move_cursor(1)
	assert_eq(screen._cursor, 1, "debug mode lets the cursor reach a locked mission")

	var chosen := [-1]
	screen.level_chosen.connect(func(index): chosen[0] = index)
	screen._select_and_activate(screen._cursor)
	assert_eq(chosen[0], Campaign.order()[1], "and launch it even though it's not actually unlocked")
	assert_false(profile.is_unlocked(Campaign.order()[1]), "debug mode doesn't touch profile save data")


func test_apply_cmdline_args_reads_debug_flag() -> void:
	Settings.debug_mode = true
	Settings.apply_cmdline_args()
	assert_false(Settings.debug_mode, "the test runner isn't launched with --debug-mode")


func test_level_select_escape_returns_to_title() -> void:
	var profile := Profile.new()
	var screen := LevelSelect.new()
	add_child_autofree(screen)
	screen.build(profile)
	var back_signaled := [false]
	screen.back_pressed.connect(func(): back_signaled[0] = true)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	screen._unhandled_input(esc)
	assert_true(back_signaled[0], "Escape returns to the title screen")


func test_save_progress_persists_to_active_profile() -> void:
	var root: Node = CampaignRootScene.instantiate()
	root.store = ProfileStore.load_or_new(SAVE_TEST_PATH)
	add_child_autofree(root)
	root._on_profile_created("Ada")
	root._launch(3)  # the lunar TLI mission (translunar)
	simulate(root, 2, 1.0 / 60.0)

	root.game.sim_time = 12345.0
	root.game.ship.advance_to(12345.0)
	root.game.warp_index = 2
	root.game._save_progress()

	assert_not_null(root.active_profile.mission_save, "save landed on the active profile")
	assert_eq(root.active_profile.mission_save["level_index"], 3)
	assert_eq(root.active_profile.mission_save["sim_time"], 12345.0)
	assert_eq(root.active_profile.mission_save["warp_index"], 2)

	var reloaded := ProfileStore.load_or_new(SAVE_TEST_PATH)
	var reloaded_save = reloaded.find_profile("Ada").mission_save
	assert_not_null(reloaded_save, "save persisted to disk")
	# JSON has no int type - everything numeric round-trips as float.
	assert_eq(reloaded_save["level_index"], 3.0)


func test_continue_resumes_saved_mission_exactly() -> void:
	var root: Node = CampaignRootScene.instantiate()
	root.store = ProfileStore.load_or_new(SAVE_TEST_PATH)
	add_child_autofree(root)
	root._on_profile_created("Ada")
	root._launch(3)
	simulate(root, 2, 1.0 / 60.0)

	# fly a bit so the state isn't just the launch defaults
	root.game.ship.throttle = 1.0
	simulate(root, 60, 1.0 / 60.0)
	root.game.ship.throttle = 0.0
	var saved_r: DVec3 = root.game.ship.r
	var saved_v: DVec3 = root.game.ship.v
	var saved_prop: float = root.game.ship.prop_mass
	var saved_time: float = root.game.sim_time

	root.game._save_progress()
	root.game.exit_requested.emit()
	simulate(root, 2, 1.0 / 60.0)
	assert_true(root._current_ui is LevelSelect, "quit without losing the save")

	root._current_ui.back_pressed.emit()
	simulate(root, 2, 1.0 / 60.0)
	assert_true(root._current_ui is TitleScreen)

	# load_saved_state() runs synchronously inside _on_continue() (right
	# after add_child triggers _ready), so check before any further
	# simulate() call - otherwise the freshly-resumed ship legitimately
	# coasts a bit further and no longer matches the captured snapshot.
	root._on_continue()
	assert_not_null(root.game, "continue resumed straight into flight")
	assert_eq(root.game.level_index, 3)
	assert_close(root.game.sim_time, saved_time, 1e-6)
	assert_dvec_close(root.game.ship.r, saved_r, 1e-6)
	assert_dvec_close(root.game.ship.v, saved_v, 1e-6)
	assert_close(root.game.ship.prop_mass, saved_prop, 1e-9)


func test_continue_resumes_correctly_after_a_simulated_app_restart() -> void:
	# Unlike test_continue_resumes_saved_mission_exactly (which resumes via
	# the same in-memory Profile object), this reloads the store from disk
	# first - JSON has no int type, so level_index/warp_index/sas_mode
	# arrive as floats here. Real risk: a typed `var x: int = data.get(...)`
	# coerces fine, but this is the actual boundary a real app restart
	# hits, so it's worth checking directly rather than assuming.
	var writer: Node = CampaignRootScene.instantiate()
	writer.store = ProfileStore.load_or_new(SAVE_TEST_PATH)
	add_child_autofree(writer)
	writer._on_profile_created("Ada")
	writer._launch(3)
	simulate(writer, 2, 1.0 / 60.0)
	writer.game.warp_index = 3
	writer.game._save_progress()
	var saved_r: DVec3 = writer.game.ship.r
	var saved_v: DVec3 = writer.game.ship.v

	var root: Node = CampaignRootScene.instantiate()
	root.store = ProfileStore.load_or_new(SAVE_TEST_PATH)  # fresh load from disk
	add_child_autofree(root)
	root._on_continue()
	assert_not_null(root.game, "resumed from a disk-loaded store")
	assert_eq(root.game.level_index, 3)
	assert_eq(root.game.warp_index, 3)
	assert_dvec_close(root.game.ship.r, saved_r, 1e-6)
	assert_dvec_close(root.game.ship.v, saved_v, 1e-6)
	assert_eq(root.game.ship.body.name, "EARTH")


func test_winning_clears_the_mission_save() -> void:
	var root: Node = CampaignRootScene.instantiate()
	root.store = ProfileStore.load_or_new(SAVE_TEST_PATH)
	add_child_autofree(root)
	root._on_profile_created("Ada")
	root._launch(0)
	simulate(root, 2, 1.0 / 60.0)
	root.game._save_progress()
	assert_not_null(root.active_profile.mission_save)

	var target: float = root.game.level.objective.target_radius
	root.game.ship.elements = OrbitElements.from_state(
		DVec3.new(target, 0.0, 0.0),
		DVec3.new(0.0, 0.0, -sqrt(root.game.level.body.mu / target)),
		root.game.level.body.mu, root.game.sim_time)
	simulate(root, 5, 1.0 / 60.0)
	assert_eq(root.game.phase, root.game.Phase.WON)
	assert_null(root.active_profile.mission_save, "no point resuming an already-won mission")

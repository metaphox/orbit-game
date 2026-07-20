extends "res://tests/unit/base_orbit_test.gd"
## Campaign registry, multi-profile save persistence, settings, and the
## title -> profile -> mission-select -> flight menu-shell scene.

const CampaignRootScene := preload("res://src/campaign_root.tscn")
const GameRootScript := preload("res://src/game_root.gd")
const SAVE_TEST_PATH := "user://test_save.json"


func before_each() -> void:
	_clear_save()
	Settings.effects_enabled = true


func after_each() -> void:
	_clear_save()
	GameRootScript.level_index = 0
	Settings.effects_enabled = true


func _clear_save() -> void:
	if FileAccess.file_exists(SAVE_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH))


func test_campaign_order_and_next() -> void:
	assert_eq(Campaign.order(), [0, 2, 5, 1, 3, 4, 6], "act-grouped play order")
	assert_eq(Campaign.next_after(0), 2, "orbit school 1 unlocks rendezvous")
	assert_eq(Campaign.next_after(5), 1, "plane change unlocks the lunar program act")
	assert_eq(Campaign.next_after(4), 6, "lunar return unlocks the interplanetary act")
	assert_eq(Campaign.next_after(6), -1, "no level after the last one")


func test_profile_progress_round_trip_and_unlock() -> void:
	var profile := Profile.new()
	profile.profile_name = "Ada"
	assert_true(profile.is_unlocked(0), "first level starts unlocked")
	assert_false(profile.is_unlocked(2), "later levels start locked")

	profile.record_win(0, "GOLD ★★★", 60.0)
	assert_true(profile.is_unlocked(2), "winning unlocks the next campaign level")
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
	assert_true(reloaded_ada.is_unlocked(2), "Ada's progress persisted")
	assert_false(reloaded_grace.is_unlocked(2), "Grace's progress is independent of Ada's")
	assert_eq(reloaded.last_active_name, "Grace", "last-created profile is active")
	assert_eq(reloaded.last_active_profile().profile_name, "Grace")


func test_settings_persist_across_reload() -> void:
	var store := ProfileStore.load_or_new(SAVE_TEST_PATH)
	Settings.effects_enabled = false
	store.save()
	Settings.effects_enabled = true  # simulate a fresh process before reload

	ProfileStore.load_or_new(SAVE_TEST_PATH)
	assert_false(Settings.effects_enabled, "effects toggle persisted to disk")


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
	assert_true(root.active_profile.is_unlocked(2), "win unlocked the next mission")
	assert_true(root.store.find_profile("Ada").is_unlocked(2), "and it's saved to the store")

	root.game.next_requested.emit(0)
	simulate(root, 2, 1.0 / 60.0)
	assert_eq(root.game.level.title, Campaign.title(2), "N advanced to the next mission")


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

extends "res://tests/unit/base_orbit_test.gd"
## M6: campaign registry, save persistence, and the menu-shell scene.

const CampaignRootScene := preload("res://src/campaign_root.tscn")
const GameRootScript := preload("res://src/game_root.gd")
const SAVE_TEST_PATH := "user://test_save.json"


func before_each() -> void:
	_clear_save()


func after_each() -> void:
	_clear_save()
	GameRootScript.level_index = 0


func _clear_save() -> void:
	if FileAccess.file_exists(SAVE_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH))


func test_campaign_order_and_next() -> void:
	assert_eq(Campaign.order(), [0, 2, 1, 3, 4], "act-grouped play order")
	assert_eq(Campaign.next_after(0), 2, "orbit school 1 unlocks rendezvous")
	assert_eq(Campaign.next_after(2), 1, "rendezvous unlocks the lunar program act")
	assert_eq(Campaign.next_after(4), -1, "no level after the last one")


func test_save_data_round_trip_and_unlock() -> void:
	var save := SaveData.load_or_new(SAVE_TEST_PATH)
	assert_true(save.is_unlocked(0), "first level starts unlocked")
	assert_false(save.is_unlocked(2), "later levels start locked")

	save.record_win(0, "GOLD ★★★", 60.0)
	assert_true(save.is_unlocked(2), "winning unlocks the next campaign level")
	assert_eq(save.medal_for(0), "GOLD ★★★")

	save.record_win(0, "BRONZE ★", 90.0)
	assert_eq(save.medal_for(0), "GOLD ★★★", "a worse run does not overwrite the best medal")

	var reloaded := SaveData.load_or_new(SAVE_TEST_PATH)
	assert_true(reloaded.is_unlocked(2), "unlock persisted to disk")
	assert_eq(reloaded.medal_for(0), "GOLD ★★★", "medal persisted to disk")


func test_campaign_root_menu_then_flies_then_restarts() -> void:
	var root: Node = CampaignRootScene.instantiate()
	add_child_autofree(root)
	simulate(root, 2, 1.0 / 60.0)
	assert_not_null(root.menu, "starts on the mission-select menu")
	assert_null(root.game, "no flight scene until a mission is picked")

	root._launch(0)
	simulate(root, 2, 1.0 / 60.0)
	assert_null(root.menu, "menu closed on launch")
	assert_not_null(root.game, "flight scene instantiated")
	assert_eq(root.game.level.title, Campaign.title(0), "launched the requested mission")

	root.game.restart_requested.emit()
	simulate(root, 2, 1.0 / 60.0)
	assert_not_null(root.game, "restart rebuilds the flight scene")
	assert_eq(root.game.level.title, Campaign.title(0), "restart keeps the same mission")

	root.game.exit_requested.emit()
	simulate(root, 2, 1.0 / 60.0)
	assert_not_null(root.menu, "exit returns to the menu")
	assert_null(root.game, "flight scene torn down on exit")


func test_win_signal_persists_and_advances_campaign() -> void:
	var root: Node = CampaignRootScene.instantiate()
	root.save_data = SaveData.load_or_new(SAVE_TEST_PATH)
	add_child_autofree(root)
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
	assert_true(root.save_data.is_unlocked(2), "win unlocked the next mission")

	root.game.next_requested.emit(0)
	simulate(root, 2, 1.0 / 60.0)
	assert_eq(root.game.level.title, Campaign.title(2), "N advanced to the next mission")

extends "res://tests/unit/base_orbit_test.gd"
## The LIVE autopilot (src/autopilot/flight_director) flown through the REAL
## game loop: each level engages the director on launch and is stepped frame
## by frame through game_root._physics_process (the same path a player's frames
## take), then must reach Phase.WON. This proves the frame-driven director -
## with its time-warp management - actually completes every mission in the
## running game, not just in the headless solver.

const GameRootScene := preload("res://src/main.tscn")
const GameRootScript := preload("res://src/game_root.gd")


func after_each() -> void:
	GameRootScript.level_index = 0
	GameRootScript.autopilot_on_launch = false


## Launches the level with the director engaged and steps physics frames (fixed
## 1/60 s, the director's assumed cadence) until the mission ends or the frame
## budget runs out. Returns the game node for assertions.
var _frames := 0


func _fly(index: int, max_frames: int) -> Node:
	GameRootScript.level_index = index
	GameRootScript.autopilot_on_launch = true
	var game: Node = GameRootScene.instantiate()
	add_child_autofree(game)
	assert_not_null(game.director, "director engaged on launch")
	var dt := 1.0 / 60.0
	_frames = 0
	while game.phase == game.Phase.FLYING and _frames < max_frames:
		game._physics_process(dt)
		_frames += 1
	return game


func _assert_won(index: int, max_frames: int) -> void:
	var game := _fly(index, max_frames)
	var el: OrbitElements = game.ship.current_elements()
	gut.p("  %s: phase=%d frames=%d status='%s' Ap=%.0f Pe=%.0f dv=%.1f" % [
		Campaign.title(index), game.phase, _frames, game.director.status() if game.director else "-",
		el.radius_apoapsis(), el.radius_periapsis(), game.ship.dv_used()])
	assert_eq(game.phase, game.Phase.WON, "%s: director reached WON" % Campaign.title(index))


func test_director_wins_level_01_01_raise() -> void:
	_assert_won(0, 30000)


func test_director_wins_level_01_03_plane_change() -> void:
	_assert_won(2, 30000)


func test_director_wins_level_01_02_rendezvous() -> void:
	_assert_won(1, 60000)


func test_director_wins_level_02_01_translunar() -> void:
	_assert_won(3, 120000)


func test_director_wins_level_02_03_come_home() -> void:
	_assert_won(5, 120000)


func test_director_wins_level_02_02_landing() -> void:
	_assert_won(4, 120000)


func test_director_wins_level_03_01_earth_to_mars() -> void:
	_assert_won(6, 200000)

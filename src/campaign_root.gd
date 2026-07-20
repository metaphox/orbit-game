extends Node
## The project's actual entry point (project.godot run/main_scene): shows
## the mission-select menu, then instantiates the flyable scene (the same
## res://src/main.tscn every headless test loads directly) as a child, and
## reacts to its signals to persist progress and navigate. main.tscn stays
## a self-contained, directly-testable flight scene; this is purely the
## shell around it.

const GameRootScript := preload("res://src/game_root.gd")
const GameRootScene := preload("res://src/main.tscn")

var save_data: SaveData
var menu: LevelSelect
var game: Node


func _ready() -> void:
	save_data = SaveData.load_or_new()
	_show_menu()


func _show_menu() -> void:
	if game != null:
		game.queue_free()
		game = null
	menu = LevelSelect.new()
	add_child(menu)
	menu.build(save_data)
	menu.level_chosen.connect(_launch)


func _launch(index: int) -> void:
	if menu != null:
		menu.queue_free()
		menu = null
	if game != null:
		game.queue_free()
		game = null
	GameRootScript.level_index = index
	game = GameRootScene.instantiate()
	add_child(game)
	game.mission_won.connect(_on_win)
	game.restart_requested.connect(_on_restart)
	game.exit_requested.connect(_show_menu)
	game.next_requested.connect(_on_next)


func _on_win(index: int, dv_used: float, medal: String) -> void:
	save_data.record_win(index, medal, dv_used)


func _on_restart() -> void:
	_launch(GameRootScript.level_index)


func _on_next(index: int) -> void:
	var next_index := Campaign.next_after(index)
	if next_index != -1:
		_launch(next_index)
	else:
		_show_menu()

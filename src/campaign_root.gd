extends Node
## The project's actual entry point (project.godot run/main_scene): title
## screen -> profile selection -> mission select -> flight, and back.
## main.tscn (the flyable scene every headless test loads directly) is
## instantiated as a child here and reacted to via signals; it has no
## knowledge of profiles or the menu shell around it.

const GameRootScript := preload("res://src/game_root.gd")
const GameRootScene := preload("res://src/main.tscn")

var store: ProfileStore
var active_profile: Profile

var _current_ui: Node
var game: Node


func _ready() -> void:
	# Belt-and-suspenders alongside project.godot's display/window/size/
	# min_* settings: guarantees the floor even if that project setting
	# doesn't apply on a given platform. Skipped headless (tests) since
	# there's no real window to constrain.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(Vector2i(1024, 768))
	Settings.apply_cmdline_args()
	# Only initialize if a test (or future caller) hasn't already injected
	# one - previously this unconditionally clobbered a pre-set store,
	# silently redirecting to the default save path.
	if store == null:
		store = ProfileStore.load_or_new()
	InputBindings.install()  # register extra actions + apply saved rebinds (after settings load)
	_show_title()


func _clear_ui() -> void:
	if _current_ui != null:
		_current_ui.queue_free()
		_current_ui = null


func _clear_game() -> void:
	if game != null:
		game.queue_free()
		game = null


func _show_title() -> void:
	_clear_ui()
	_clear_game()
	var screen := TitleScreen.new()
	add_child(screen)
	screen.build(store)
	screen.continue_pressed.connect(_on_continue)
	screen.new_pressed.connect(_show_new_profile)
	screen.load_pressed.connect(_show_load_profile)
	screen.settings_pressed.connect(_show_settings)
	screen.credits_pressed.connect(_show_credits)
	screen.quit_pressed.connect(func() -> void: get_tree().quit())
	_current_ui = screen


func _on_continue() -> void:
	var profile := store.last_active_profile()
	if profile == null:
		return  # TitleScreen disables this option in this state; defensive only
	active_profile = profile
	if profile.mission_save != null:
		_resume_mission(profile.mission_save)
	else:
		_show_mission_select()


func _resume_mission(save_data: Dictionary) -> void:
	_clear_ui()
	_clear_game()
	var index: int = save_data.get("level_index", 0)
	GameRootScript.level_index = index
	GameRootScript.hardcore = active_profile.hardcore
	game = GameRootScene.instantiate()
	add_child(game)
	game.load_saved_state(save_data)
	_connect_game_signals()


func _show_new_profile() -> void:
	_clear_ui()
	var screen := NewProfileScreen.new()
	add_child(screen)
	screen.build(store)
	screen.profile_created.connect(_on_profile_created)
	screen.cancelled.connect(_show_title)
	_current_ui = screen


func _on_profile_created(profile_name: String, hardcore: bool) -> void:
	active_profile = store.create_profile(profile_name, hardcore)
	_show_mission_select()


func _show_load_profile() -> void:
	_clear_ui()
	var screen := LoadProfileScreen.new()
	add_child(screen)
	screen.build(store)
	screen.profile_chosen.connect(_on_profile_chosen)
	screen.cancelled.connect(_show_title)
	_current_ui = screen


func _on_profile_chosen(profile_name: String) -> void:
	active_profile = store.find_profile(profile_name)
	store.set_active(profile_name)
	_show_mission_select()


func _show_settings() -> void:
	_clear_ui()
	var screen := SettingsScreen.new()
	add_child(screen)
	screen.build(store)
	screen.back_pressed.connect(_show_title)
	_current_ui = screen


func _show_credits() -> void:
	_clear_ui()
	var screen := CreditsScreen.new()
	add_child(screen)
	screen.build()
	screen.back_pressed.connect(_show_title)
	_current_ui = screen


func _show_mission_select() -> void:
	_clear_ui()
	_clear_game()
	var menu := LevelSelect.new()
	add_child(menu)
	menu.build(active_profile)
	menu.level_chosen.connect(_launch)
	menu.back_pressed.connect(_show_title)
	_current_ui = menu


func _launch(index: int) -> void:
	_clear_ui()
	_clear_game()
	GameRootScript.level_index = index
	GameRootScript.hardcore = active_profile.hardcore
	game = GameRootScene.instantiate()
	add_child(game)
	_connect_game_signals()


func _connect_game_signals() -> void:
	game.mission_won.connect(_on_win)
	game.restart_requested.connect(_on_restart)
	game.exit_requested.connect(_show_mission_select)
	game.next_requested.connect(_on_next)
	game.save_requested.connect(_on_save)


func _on_win(index: int, dv_used: float, medal: String, rewinds_used: int) -> void:
	active_profile.record_win(index, medal, dv_used, rewinds_used)
	if not store.save():
		game.hud.flash("SAVE FAILED - PROGRESS MAY NOT PERSIST")


func _on_save(payload: Dictionary) -> void:
	active_profile.mission_save = payload
	if not store.save():
		game.hud.flash("SAVE FAILED - PROGRESS MAY NOT PERSIST")


func _on_restart() -> void:
	_launch(GameRootScript.level_index)


func _on_next(index: int) -> void:
	var next_index := Campaign.next_after(index)
	if next_index != -1:
		_launch(next_index)
	else:
		_show_mission_select()

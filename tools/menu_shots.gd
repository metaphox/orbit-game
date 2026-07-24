extends Node
## Throwaway visual-QA harness (not part of the game). Boots each redesigned
## menu screen with a demo profile, renders a frame, and dumps a PNG so the
## code-built layouts can be eyeballed without the editor. Run with:
##   godot --path . res://tools/menu_shots.tscn
##   godot --path . res://tools/menu_shots.tscn --locale=ja   # font/overflow QA
## Screenshots land in user://menu_shots (globalized path is printed).
##
## Run WITHOUT --headless: it needs a real window. The headless dummy renderer
## never emits RenderingServer.frame_post_draw, so _capture() awaits forever and
## the process just hangs after the engine banner.

const SHOT_DIR := "user://menu_shots"

var _shot_dir := SHOT_DIR


func _ready() -> void:
	await _run()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size = Vector2i(1280, 720)
	# --locale=<code> renders every screen in that language (font/tofu + overflow QA).
	var locale := "en"
	for a: String in OS.get_cmdline_args():
		if a.begins_with("--locale="):
			locale = a.trim_prefix("--locale=")
	TranslationServer.set_locale(locale)
	UiTheme.apply_locale_fonts(locale)
	var shot_dir := "%s_%s" % [SHOT_DIR, locale] if locale != "en" else SHOT_DIR
	_shot_dir = shot_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))

	var store := ProfileStore.load_or_new("user://menu_shots_demo.json")
	var profile: Profile = store.find_profile("ARES")
	if profile == null:
		profile = store.create_profile("ARES", false)
	profile.record_win(0, "GOLD ★★★", 118.0, 0)
	profile.record_win(1, "SILVER ★★", 244.0, 1)
	store.set_active("ARES")

	var title := TitleScreen.new()
	await _capture(title, "1_main_menu", func() -> void: title.build(store))

	var missions := LevelSelect.new()
	await _capture(missions, "2_missions", func() -> void: missions.build(profile))

	var load_scr := LoadProfileScreen.new()
	await _capture(load_scr, "3_load", func() -> void: load_scr.build(store))

	var settings := SettingsScreen.new()
	await _capture(settings, "4_settings", func() -> void: settings.build(store))

	var language := SettingsScreen.new()
	await _capture(language, "4b_language", _open_language_list.bind(language, store))

	var credits := CreditsScreen.new()
	await _capture(credits, "5_credits", func() -> void: credits.build())

	var pause := PauseMenu.new()
	await _capture(pause, "6_pause", func() -> void: pause.build())

	print("MENU_SHOTS_DONE")
	get_tree().quit()


func _open_language_list(screen: SettingsScreen, store: ProfileStore) -> void:
	screen.build(store)
	screen._enter_language_focus()


func _capture(screen: Node, shot_name: String, builder: Callable) -> void:
	add_child(screen)
	builder.call()
	for _i: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shot_dir, shot_name]
	var err := img.save_png(path)
	print("SHOT %s -> %s (%dx%d) err=%d" % [
		shot_name, ProjectSettings.globalize_path(path), img.get_width(), img.get_height(), err])
	screen.queue_free()
	await get_tree().process_frame

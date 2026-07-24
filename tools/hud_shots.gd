extends Node
## Throwaway: boot the in-flight HUD (like game_root) and screenshot it in a
## given locale, to eyeball HUD label translation + column alignment. Run:
##   godot --path . res://tools/hud_shots.tscn --locale=zh

const SHOT_DIR := "user://hud_shots"


func _ready() -> void:
	await _run()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size = Vector2i(1920, 1080)
	var locale := "en"
	for a: String in OS.get_cmdline_args():
		if a.begins_with("--locale="):
			locale = a.trim_prefix("--locale=")
	TranslationServer.set_locale(locale)
	UiTheme.apply_locale_fonts(locale)
	var dir := "%s_%s" % [SHOT_DIR, locale] if locale != "en" else SHOT_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var level := Campaign.level_at(0)
	var ship := ShipSim.new()
	ship.setup(level)
	ship.sas_mode = ShipSim.SasMode.PROGRADE  # exercise the translated SAS mode

	var flight_view := FlightView.new()
	add_child(flight_view)
	flight_view.build(level)
	var map_view := MapView.new()
	add_child(map_view)
	map_view.build(level)
	var hud := Hud.new()
	add_child(hud)
	hud.build(level)
	hud.map_view = map_view

	for _i: int in 8:
		await get_tree().process_frame
	hud.refresh(ship, level, 125.0, 10)
	hud.set_rewind_line(hud.tr("REWIND %s%s   [%s]") % ["●●", "○", "H"])
	await _shoot(dir, "hud", locale)

	# Result banner (centered), captured alone.
	hud.show_win(level, 118.0, true, true)
	await _shoot(dir, "hud_banner", locale)
	# F1 help panel (also centered — hide the banner first).
	hud._overlays.mission_panel.visible = false
	hud._overlays.toggle_keys()
	await _shoot(dir, "hud_help", locale)
	# Fail banner + rewind prompt.
	hud._overlays.toggle_keys()
	hud.show_fail("TOUCHDOWN TOO HARD", 2)
	await _shoot(dir, "hud_fail", locale)
	get_tree().quit()


func _shoot(dir: String, name: String, locale: String) -> void:
	for _i: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [dir, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("HUD_SHOT -> %s (%s)" % [ProjectSettings.globalize_path(path), locale])

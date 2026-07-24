extends Node
## Throwaway: render a CJK+Cyrillic sample in each themed font face to confirm the
## Noto fallback renders real glyphs (not tofu). Run:
##   godot --path . res://tools/font_check.tscn

const SAMPLES := {
	"MenuTitle": "轨道 ORBIT Орбита",
	"MonoText": "予圏 궤道 燃料 · DELTA-V Δv",
	"HudValue": "한국어 日本語 中文",
	"Eyebrow": "ПРОПЕЛЛАНТ ПАУЗА",
	"MenuFooter": "轨道学校 · МЕНЮ · メニュー",
}


func _ready() -> void:
	get_window().size = Vector2i(900, 500)
	var root := ColorRect.new()
	root.color = Color(0.02, 0.03, 0.03)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.shared()
	add_child(root)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 18)
	root.add_child(col)
	for variation: String in SAMPLES:
		var l := Label.new()
		l.theme_type_variation = variation
		l.text = "%s:  %s" % [variation, SAMPLES[variation]]
		col.add_child(l)
	await _shoot()


func _shoot() -> void:
	for _i: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://font_check.png"
	img.save_png(path)
	print("FONT_CHECK -> %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()

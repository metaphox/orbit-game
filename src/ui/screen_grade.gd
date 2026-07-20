class_name ScreenGrade
extends ColorRect
## Add as the last child of a full-screen CanvasLayer for the whole-screen
## NASA-hardware film grade (see screen_grade.gdshader).

const SHADER := preload("res://src/shaders/screen_grade.gdshader")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

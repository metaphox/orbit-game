class_name CrtOverlay
extends ColorRect
## Drop into a SubViewport as the last child to give that viewport's own
## render the vector-CRT mission-computer treatment (see vector_crt.gdshader).

const SHADER := preload("res://src/shaders/vector_crt.gdshader")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

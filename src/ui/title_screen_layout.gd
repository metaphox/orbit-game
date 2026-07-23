class_name TitleScreenLayout
extends Control

@onready var warning_label: Label = %WarningLabel
@onready var menu_text: RichTextLabel = %MenuText
@onready var slots_label: Label = %SlotsLabel
@onready var diamond: Control = %Diamond


func _ready() -> void:
	%Background.color = Palette.VOID
	diamond.draw.connect(_draw_diamond)


func _draw_diamond() -> void:
	diamond.draw_colored_polygon(PackedVector2Array([
		Vector2(7, 0), Vector2(14, 7), Vector2(7, 14), Vector2(0, 7)]), Palette.LIVE)

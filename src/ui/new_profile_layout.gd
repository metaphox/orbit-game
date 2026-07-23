class_name NewProfileLayout
extends Control

@onready var line_edit: LineEdit = %CallsignEdit
@onready var error_label: Label = %ErrorLabel
@onready var hardcore_check: CheckButton = %HardcoreCheck


func _ready() -> void:
	%Background.color = Palette.VOID

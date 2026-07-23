class_name MenuTextLayout
extends Control
## Shared scene-owned chrome for the mission, load, settings, credits, and pause screens.

@onready var background: ColorRect = %Background
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var content: RichTextLabel = %Content
@onready var footer_label: Label = %FooterLabel


func _ready() -> void:
	background.color = Palette.VOID


func configure(title: String, subtitle: String, footer: String, paused := false) -> void:
	title_label.text = title
	subtitle_label.text = subtitle
	subtitle_label.visible = subtitle != ""
	footer_label.text = footer
	footer_label.visible = footer != ""
	background.color = Palette.PAUSE_BG if paused else Palette.VOID
	if paused:
		title_label.offset_top = 130.0
		content.add_theme_font_size_override("normal_font_size", 20)

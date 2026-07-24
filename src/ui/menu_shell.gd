class_name MenuShell
extends Control
## The reusable two-pane ORBITAL-OS menu frame: a static backdrop, an always-on
## breadcrumb, a scrollable left column (cards/headers get added to `left_column`),
## a right pane (`right_pane`, holds the detail/hero), and a bottom key-hint bar
## shown only when Settings.menu_hints is on (F1). The layout lives in
## menu_shell.tscn (editable in the Godot editor); this script only wires the
## `%`-named slots and behavior. Used by MISSIONS / MAIN MENU / LOAD / SETTINGS.


## Instantiate the frame from its scene. Screens use this instead of `.new()`
## so they get the editor-authored node tree, not a bare Control.
static func create() -> MenuShell:
	return preload("res://src/ui/menu_shell.tscn").instantiate()


@onready var left_column: VBoxContainer = %LeftColumn
@onready var right_pane: MarginContainer = %RightPane

@onready var _breadcrumb: Label = %Breadcrumb
@onready var _scroll: ScrollContainer = %Scroll
@onready var _hint_bar: PanelContainer = %HintBar
@onready var _hint_label: Label = %HintLabel


func _ready() -> void:
	refresh_hint_visibility()


func configure(breadcrumb: String) -> void:
	_breadcrumb.text = breadcrumb


func set_hint(text: String) -> void:
	_hint_label.text = text


## Replace the right pane's content (detail pane / hero).
func set_right(node: Control) -> void:
	for c in right_pane.get_children():
		c.queue_free()
	right_pane.add_child(node)


func refresh_hint_visibility() -> void:
	if _hint_bar != null:
		_hint_bar.visible = Settings.menu_hints_on()


func hints_visible() -> bool:
	return _hint_bar != null and _hint_bar.visible


## Collapse the left list so the right pane fills the width (single-panel
## screens like CREDITS). Invisible children are excluded from container layout.
func hide_left() -> void:
	if _scroll != null:
		_scroll.visible = false


## Keep the cursor card in view as the selection / act jumps around.
func ensure_visible(control: Control) -> void:
	if _scroll != null and control != null:
		_scroll.ensure_control_visible(control)

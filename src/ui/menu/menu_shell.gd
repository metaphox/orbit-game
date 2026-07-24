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
	return preload("res://src/ui/menu/menu_shell.tscn").instantiate()


@onready var left_column: VBoxContainer = %LeftColumn
@onready var right_pane: MarginContainer = %RightPane

## The menu content block (columns + padding) never grows past this; beyond it
## the extra width becomes equal side gutters so the menu stays centred instead
## of the panes stretching edge to edge on ultrawide / 4K displays.
const MAX_WIDTH := 2560.0
const BASE_PAD := 48.0

@onready var _breadcrumb: Label = %Breadcrumb
@onready var _scroll: ScrollContainer = %Scroll
@onready var _hint_bar: PanelContainer = %HintBar
@onready var _hint_label: Label = %HintLabel
@onready var _margin: MarginContainer = $Margin


func _ready() -> void:
	refresh_hint_visibility()
	get_viewport().size_changed.connect(_clamp_width)
	_clamp_width()


func _clamp_width() -> void:
	var w := get_viewport_rect().size.x
	var side := int(BASE_PAD + maxf(0.0, w - MAX_WIDTH) * 0.5)
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)


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


## Prepend the standard "◀ BACK" card to the left column, wired to `on_back`.
## Every non-root menu calls this so the affordance looks and sits identically
## (keyboard still leaves via Esc; this is the mouse + visual affordance).
func add_back(on_back: Callable) -> void:
	var back := Button.new()
	back.theme_type_variation = UiTheme.CARD
	back.focus_mode = Control.FOCUS_NONE
	back.text = "◀  BACK"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.custom_minimum_size = Vector2(0, 48)  # 6×8, matches an act-header row
	back.pressed.connect(on_back)
	left_column.add_child(back)
	left_column.move_child(back, 0)


## Keep the cursor card in view as the selection / act jumps around.
func ensure_visible(control: Control) -> void:
	if _scroll != null and control != null:
		_scroll.ensure_control_visible(control)

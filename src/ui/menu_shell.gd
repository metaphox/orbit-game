class_name MenuShell
extends Control
## The reusable two-pane ORBITAL-OS menu frame: a static backdrop, an always-on
## breadcrumb, a scrollable left column (cards/headers get added to `left_column`),
## a right pane (`right_pane`, holds the detail/hero), and a bottom key-hint bar
## shown only when Settings.menu_hints is on (F1). Carries the shared Theme so
## code-built children inherit it. Used by MISSIONS / MAIN MENU / LOAD / SETTINGS.

var left_column: VBoxContainer
var right_pane: MarginContainer

var _backdrop: Backdrop
var _breadcrumb: Label
var _scroll: ScrollContainer
var _hint_bar: PanelContainer
var _hint_label: Label


func _init() -> void:
	theme = UiTheme.shared()


const GRID := 8


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_backdrop = Backdrop.new()
	add_child(_backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", GRID * 6)   # 48
	margin.add_theme_constant_override("margin_right", GRID * 6)
	margin.add_theme_constant_override("margin_top", GRID * 4)    # 32
	margin.add_theme_constant_override("margin_bottom", GRID * 3) # 24
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", GRID * 3)  # 24
	margin.add_child(root)

	_breadcrumb = Label.new()
	_breadcrumb.theme_type_variation = UiTheme.BREADCRUMB
	root.add_child(_breadcrumb)

	var panes := HBoxContainer.new()
	panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panes.add_theme_constant_override("separation", GRID * 3)  # 24
	root.add_child(panes)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(GRID * 56, 0)  # 448
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panes.add_child(_scroll)
	left_column = VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left_column.add_theme_constant_override("separation", 8)
	_scroll.add_child(left_column)

	right_pane = MarginContainer.new()
	right_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panes.add_child(right_pane)

	_hint_bar = PanelContainer.new()
	_hint_bar.theme_type_variation = UiTheme.HINT_BAR
	_hint_label = Label.new()
	_hint_label.theme_type_variation = UiTheme.MENU_FOOTER
	_hint_bar.add_child(_hint_label)
	root.add_child(_hint_bar)
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

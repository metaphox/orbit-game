extends CanvasLayer
## Dev design-grid: a 16 px reference grid toggled off → white → black → red by
## pressing "#" (shift+3). Debug-mode only (`--debug-mode`) — the toggle is inert
## in a normal build. Purely guidelines — draws above everything and never eats
## input except the toggle key. Registered as an autoload so it is available on
## every screen. 16 px is the base unit the UI is laid out against (the 1920×1080
## base is 120×67.5 cells).

enum Mode { OFF, WHITE, BLACK, RED }

var _mode := Mode.OFF
var _canvas: _Canvas


func _ready() -> void:
	layer = 128  # above the HUD and every other CanvasLayer
	_canvas = _Canvas.new()
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.visible = false
	get_viewport().size_changed.connect(func() -> void: _canvas.queue_redraw())


func _input(event: InputEvent) -> void:
	if not Settings.debug_mode:  # dev aid only; inert in a normal build
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.unicode == 0x23:  # '#'
		_mode = (int(_mode) + 1) % Mode.size()
		match _mode:
			Mode.WHITE:
				_canvas.line = Color(1.0, 1.0, 1.0)
			Mode.BLACK:
				_canvas.line = Color(0.0, 0.0, 0.0)
			Mode.RED:
				_canvas.line = Color(1.0, 0.23, 0.16)
		_canvas.visible = _mode != Mode.OFF
		_canvas.queue_redraw()
		get_viewport().set_input_as_handled()


class _Canvas:
	extends Control

	const CELL := 16.0
	const MAJOR := 8  # brighter rule every N cells, for quick counting

	var line := Color(1.0, 1.0, 1.0)

	func _draw() -> void:
		var minor := Color(line.r, line.g, line.b, 0.16)
		var major := Color(line.r, line.g, line.b, 0.36)
		var col := 0
		var x := 0.0
		while x <= size.x:
			draw_line(Vector2(x, 0.0), Vector2(x, size.y),
				major if col % MAJOR == 0 else minor, 1.0)
			x += CELL
			col += 1
		var rowi := 0
		var y := 0.0
		while y <= size.y:
			draw_line(Vector2(0.0, y), Vector2(size.x, y),
				major if rowi % MAJOR == 0 else minor, 1.0)
			y += CELL
			rowi += 1

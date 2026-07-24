class_name Hud
extends CanvasLayer
## NASA-punk "ORBITAL OS" flight HUD (ref/hud-ref.html): a top telemetry bar,
## left/right instrument rails, a bottom fuel/throttle strip, a functional
## attitude director, and every non-flying state (win/fail/pause/flash/keys)
## styled from the shared Palette/UiTheme — one colour source (TD-1).

## Emitted by toolbar buttons as a semantic ACTION name (not a physical key), so
## a click dispatches the same command a rebound key would and never drifts when
## a binding changes (CR-5). game_root replays the action's current binding.
signal toolbar_command(action: String, pressed: bool)

# --- fields read by game_root / tests (contract; keep the names) ---
var objective_label: Label
var help_label: Label
var center_label: Control       # win/fail banner panel (game_root sets .visible=false)
var minimap_root: Control
var warp_label: Label
var _fps_label: Label
## Set by game_root after both are built; the minimap needs it for auto-fit,
## the parent-centred focus, and the marked-point list.
var map_view: MapView

# --- scene components ---
var _layout: HudLayout
var _top_bar: TopTelemetryBar
var _left_rail: MinimapObjectiveRail
var _right_rail: GuidanceWarpRail
var _flight_strip: PropellantFlightStrip
var _overlays: HudOverlays

# Compatibility alias read by pause/save tests.
var _prop_pct: Label

var _banner_title: Label
var _banner_body: Label
var _banner_prompt: Label

func build(level: LevelDef) -> void:
	_layout = preload("res://src/ui/hud/hud_layout.tscn").instantiate()
	add_child(_layout)
	_top_bar = _layout.get_node("%TopTelemetryBar")
	_top_bar.configure(level)
	_left_rail = _layout.get_node("%MinimapObjectiveRail")
	_left_rail.configure(level)
	objective_label = _left_rail.objective_label
	minimap_root = _left_rail.minimap_root
	_right_rail = _layout.get_node("%GuidanceWarpRail")
	warp_label = _right_rail.warp_label
	_flight_strip = _layout.get_node("%PropellantFlightStrip")
	_flight_strip.command.connect(func(action: String, pressed: bool) -> void:
		toolbar_command.emit(action, pressed))
	_flight_strip.keys_requested.connect(func() -> void:
		_overlays.toggle_keys())
	_flight_strip.configure(level)
	_prop_pct = _flight_strip.propellant_percent
	_overlays = _layout.get_node("%HudOverlays")
	_overlays.configure(level, Settings.debug_mode)
	center_label = _overlays.mission_panel
	help_label = _overlays.help_label
	_banner_title = _overlays.banner_title
	_banner_body = _overlays.banner_body
	_banner_prompt = _overlays.banner_prompt
	_fps_label = _overlays.fps_label if Settings.debug_mode else null
	if Settings.effects_enabled:
		add_child(ScreenGrade.new())  # drawn last: whole-screen film grade on top


# ══════════════════════════════════════════════════ REFRESH ══

func refresh(ship: ShipSim, level: LevelDef, sim_time: float, warp: int) -> void:
	_left_rail.map_view = map_view
	_left_rail.refresh(ship, sim_time)
	_left_rail.update_objective(ship, level)
	_top_bar.refresh(ship, sim_time, warp)
	_right_rail.refresh(ship, warp)
	_flight_strip.refresh(ship, level, sim_time)


func _process(delta: float) -> void:
	if _top_bar != null:
		_top_bar.animate_burn_dot()
	if _overlays != null:
		_overlays.tick(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F1:
		_overlays.toggle_keys()
		get_viewport().set_input_as_handled()


# ══════════════════════════════════════════════════ BANNER / FLASH / PAUSE / KEYS ══

func show_win(level: LevelDef, dv_used: float, has_next: bool, clean := false) -> void:
	_overlays.show_win(level, dv_used, has_next, clean)


func show_fail(reason: String, rewinds_left := 0) -> void:
	_overlays.show_fail(reason, rewinds_left)


func flash(text: String) -> void:
	_overlays.flash(text)


func set_paused_indicator(shown: bool) -> void:
	_overlays.set_paused_indicator(shown)


# ══════════════════════════════════════════════════ REWIND ══

func set_rewind_line(text: String) -> void:
	_overlays.set_rewind_line(text)


func update_rewind_timeline(
		t_start: float, t_now: float, playhead: float, cursor: int,
		anchors: Array, landmarks: Array) -> void:
	_overlays.update_rewind_timeline(t_start, t_now, playhead, cursor, anchors, landmarks)


func hide_rewind_timeline() -> void:
	_overlays.hide_rewind_timeline()


# ══════════════════════════════════════════════════ MINIMAP ══

func set_minimap_visible(shown: bool) -> void:
	_left_rail.set_map_visible(shown)

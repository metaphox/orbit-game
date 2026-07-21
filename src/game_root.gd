extends Node3D
## A single flyable mission: sim clock, event-aware warp, input, win/fail
## state, view toggle. Self-contained and directly loadable (every headless
## test does this); src/campaign_root.gd is the menu shell that wraps it
## for normal play and reacts to the signals below. Gameplay input goes
## through InputMap actions (project.godot's [input] section) rather than
## raw keycodes, so remapping/controller support just needs a settings UI
## on top of this - not touched here. Menu-navigation screens are a
## separate, lower-risk convention (arrow keys/Enter/number-select) and are
## intentionally not part of this migration.

signal mission_won(index: int, dv_used: float, medal: String)
signal restart_requested
signal exit_requested
signal next_requested(index: int)
signal save_requested(payload: Dictionary)

enum Phase { FLYING, WON, FAILED, PAUSED }
enum NodeField { T_NODE, PROGRADE, NORMAL, RADIAL }

## Keys 1-9 jump straight to the matching step; -/= walk one step at a time.
const WARP_STEPS: Array[int] = [1, 5, 10, 25, 50, 100, 200, 500, 1000]
const WARP_STEP_ACTIONS := [
	"warp_step_1", "warp_step_2", "warp_step_3", "warp_step_4", "warp_step_5",
	"warp_step_6", "warp_step_7", "warp_step_8", "warp_step_9",
]
const ROT_RATE := Vector3(0.6, 0.6, 1.1)  # pitch/yaw/roll, rad/s
const THROTTLE_RATE := 1.4  # full throttle sweep per second
const ZOOM_PAN_SIGN := -1.0  # flip if trackpad scroll-up zooms out instead of in
const ZOOM_PAN_SENSITIVITY := 0.01

## Which mission to build: set by campaign_root before instantiating this
## scene, or directly by tests/the temp jump before loading it.
static var level_index := 0

var level: LevelDef
var ship: ShipSim
var sim_time := 0.0
var warp_index := 0
var phase := Phase.FLYING
var side_active := false

var flight_view: FlightView
var map_view: MapView
var hud: Hud

var _pause_menu: PauseMenu = null
var _event_revision := -1
var _event_horizon := -1.0
var _next_event := INF


func _ready() -> void:
	level_index = clampi(level_index, 0, Campaign.level_count() - 1)
	level = Campaign.level_at(level_index)
	ship = ShipSim.new()
	ship.setup(level)

	flight_view = FlightView.new()
	add_child(flight_view)
	flight_view.build(level)

	map_view = MapView.new()
	add_child(map_view)
	map_view.build(level)

	hud = Hud.new()
	add_child(hud)
	hud.build(level)
	hud.toolbar_key.connect(_on_toolbar_key)

	flight_view.camera.make_current()


## Toolbar buttons don't duplicate any input logic - they just construct
## the same InputEventKey a real keypress would and call _unhandled_input
## directly, the exact call every test in this project already makes.
## SHIFT/CTRL are the one exception: _apply_flight_input reads the
## throttle axis via Input.get_axis(), which - like is_physical_key_
## pressed() before it - only reflects real OS-level key state, never a
## synthetic event passed to _unhandled_input. Input.action_press()/
## action_release() are Godot's actual mechanism for synthetic action
## input, so the toolbar drives those directly instead.
func _on_toolbar_key(keycode: int, pressed: bool) -> void:
	if keycode == KEY_SHIFT:
		if pressed:
			Input.action_press("throttle_increase")
		else:
			Input.action_release("throttle_increase")
		return
	if keycode == KEY_CTRL:
		if pressed:
			Input.action_press("throttle_decrease")
		else:
			Input.action_release("throttle_decrease")
		return
	var event := InputEventKey.new()
	event.physical_keycode = keycode as Key
	event.pressed = pressed
	_unhandled_input(event)


## Overrides the just-built fresh ship with a saved mid-mission state.
## Called by campaign_root right after add_child() (so _ready has already
## run ship.setup(level)) and before the first _physics_process.
func load_saved_state(data: Dictionary) -> void:
	sim_time = data.get("sim_time", 0.0)
	warp_index = clampi(data.get("warp_index", 0), 0, WARP_STEPS.size() - 1)
	ship.apply_serialized(data, sim_time)
	flight_view.mark_traj_dirty()


func _physics_process(delta: float) -> void:
	if phase != Phase.FLYING:
		return
	_apply_flight_input(delta)
	var t_target := sim_time + delta * WARP_STEPS[warp_index]
	# Rails warp must not step across an SOI boundary or impact: clamp the
	# jump to the precomputed next event and drop out of warp there.
	if ship.flight_state == ShipSim.FlightState.COASTING and ship.throttle == 0.0:
		var event_t := _next_event_time()
		if event_t < t_target:
			t_target = event_t + 0.001  # land just past the boundary
			warp_index = 0
	sim_time = t_target
	ship.advance_to(sim_time)
	var notice := ship.apply_soi_transitions(sim_time)
	if notice != "":
		warp_index = 0
		hud.flash(notice)
	if ship.node_completed:
		ship.node_completed = false
		hud.flash("NODE COMPLETE")
		flight_view.mark_traj_dirty()
	_check_end_conditions()


func _process(delta: float) -> void:
	flight_view.sync(ship, delta)
	map_view.sync(ship, sim_time, delta)
	hud.refresh(ship, level, sim_time, WARP_STEPS[warp_index])
	# star dust runs its own clock independent of sim_time, so it needs an
	# explicit freeze whenever the sim itself isn't advancing (paused, or
	# the mission already ended) - covers every path that can reach a
	# non-FLYING phase (pause menu, space/0 quick-pause, win, fail) from
	# one place instead of duplicating the call at each transition site.
	flight_view.star_dust.set_frozen(phase != Phase.FLYING)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if side_active:
				flight_view.side_drag(motion.relative)
			else:
				flight_view.chase_drag(motion.relative)
		return
	var wheel := event as InputEventMouseButton
	if wheel != null:
		if wheel.pressed:
			if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				if side_active:
					flight_view.side_zoom(0.88)
				else:
					flight_view.chase_zoom(0.88)
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if side_active:
					flight_view.side_zoom(1.14)
				else:
					flight_view.chase_zoom(1.14)
		return
	# Trackpad two-finger scroll (macOS): arrives as InputEventPanGesture
	# rather than wheel button events. Sign/scale is a best-effort guess -
	# untested on real trackpad hardware; flip ZOOM_PAN_SIGN below if it
	# feels backwards.
	var pan := event as InputEventPanGesture
	if pan != null:
		var pan_factor := 1.0 + pan.delta.y * ZOOM_PAN_SIGN * ZOOM_PAN_SENSITIVITY
		if side_active:
			flight_view.side_zoom(pan_factor)
		else:
			flight_view.chase_zoom(pan_factor)
		return
	# Pinch-to-zoom, offered as a bonus alongside the requested two-finger
	# scroll: factor > 1 is a pinch-out (spreading fingers), which reads as
	# "zoom in" - our side_zoom shrinks distance for zoom-in, hence 1/factor.
	var magnify := event as InputEventMagnifyGesture
	if magnify != null and magnify.factor > 0.0:
		var magnify_factor := 1.0 / magnify.factor
		if side_active:
			flight_view.side_zoom(magnify_factor)
		else:
			flight_view.chase_zoom(magnify_factor)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _dispatch_warp_step(key):
		return
	if key.is_action_pressed("toggle_side_camera"):
		side_active = not side_active
		flight_view.set_side_active(side_active)
	elif key.is_action_pressed("warp_increase"):
		if phase == Phase.FLYING and ship.throttle == 0.0:
			warp_index = mini(warp_index + 1, WARP_STEPS.size() - 1)
	elif key.is_action_pressed("warp_decrease"):
		warp_index = maxi(warp_index - 1, 0)
	elif key.is_action_pressed("throttle_full"):
		if phase == Phase.FLYING:
			ship.throttle = 1.0
			warp_index = 0
	elif key.is_action_pressed("throttle_cut"):
		ship.throttle = 0.0
	elif key.is_action_pressed("reset_or_restart"):
		if phase == Phase.FLYING or phase == Phase.PAUSED:
			flight_view.reset_view()
		else:  # WON or FAILED: matches the on-screen "[R] RESTART" prompt
			restart_requested.emit()
	elif key.is_action_pressed("pause_menu"):
		if phase == Phase.FLYING or phase == Phase.PAUSED:
			if _pause_menu != null:
				_close_pause_menu()
			else:
				_open_pause_menu()
		else:  # WON or FAILED: no pause concept once the mission has ended
			exit_requested.emit()
	elif key.is_action_pressed("quick_pause"):
		_toggle_quick_pause()
	elif key.is_action_pressed("sas_off"):
		if phase == Phase.FLYING:
			ship.sas_mode = ShipSim.SasMode.OFF
	elif key.is_action_pressed("sas_prograde"):
		_toggle_sas(ShipSim.SasMode.PROGRADE)
	elif key.is_action_pressed("sas_retrograde"):
		_toggle_sas(ShipSim.SasMode.RETROGRADE)
	elif key.is_action_pressed("sas_normal"):
		if phase == Phase.FLYING:
			_toggle_sas(ShipSim.SasMode.NORMAL)
		elif phase == Phase.WON:
			next_requested.emit(level_index)
	elif key.is_action_pressed("sas_antinormal"):
		_toggle_sas(ShipSim.SasMode.ANTI_NORMAL)
	elif key.is_action_pressed("sas_radial_out"):
		_toggle_sas(ShipSim.SasMode.RADIAL_OUT)
	elif key.is_action_pressed("sas_radial_in"):
		_toggle_sas(ShipSim.SasMode.RADIAL_IN)
	elif key.is_action_pressed("node_create"):
		_node_create()
	elif key.is_action_pressed("node_delete"):
		if ship.node != null:
			ship.node = null
			if ship.sas_mode == ShipSim.SasMode.NODE:
				ship.sas_mode = ShipSim.SasMode.OFF
			flight_view.mark_traj_dirty()
	elif key.is_action_pressed("node_time_earlier"):
		_node_adjust(NodeField.T_NODE, -60.0 if key.shift_pressed else -5.0)
	elif key.is_action_pressed("node_time_later"):
		_node_adjust(NodeField.T_NODE, 60.0 if key.shift_pressed else 5.0)
	elif key.is_action_pressed("node_prograde_increase"):
		_node_adjust(NodeField.PROGRADE, 10.0 if key.shift_pressed else 1.0)
	elif key.is_action_pressed("node_prograde_decrease"):
		_node_adjust(NodeField.PROGRADE, -10.0 if key.shift_pressed else -1.0)
	elif key.is_action_pressed("node_normal_increase"):
		_node_adjust(NodeField.NORMAL, 10.0 if key.shift_pressed else 1.0)
	elif key.is_action_pressed("node_normal_decrease"):
		_node_adjust(NodeField.NORMAL, -10.0 if key.shift_pressed else -1.0)
	elif key.is_action_pressed("node_radial_increase"):
		_node_adjust(NodeField.RADIAL, 10.0 if key.shift_pressed else 1.0)
	elif key.is_action_pressed("node_radial_decrease"):
		_node_adjust(NodeField.RADIAL, -10.0 if key.shift_pressed else -1.0)
	elif key.is_action_pressed("sas_node_hold"):
		if phase == Phase.FLYING and level.nodes_enabled and ship.node != null:
			ship.sas_mode = (ShipSim.SasMode.OFF
				if ship.sas_mode == ShipSim.SasMode.NODE
				else ShipSim.SasMode.NODE)


func _dispatch_warp_step(key: InputEventKey) -> bool:
	for i in WARP_STEP_ACTIONS.size():
		if key.is_action_pressed(WARP_STEP_ACTIONS[i]):
			if phase == Phase.FLYING and ship.throttle == 0.0:
				warp_index = i
			return true
	return false


func _open_pause_menu() -> void:
	phase = Phase.PAUSED
	if _pause_menu != null:
		return
	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_pause_menu.build()
	_pause_menu.resume_pressed.connect(_close_pause_menu)
	_pause_menu.save_pressed.connect(_save_progress)
	_pause_menu.restart_pressed.connect(func() -> void: restart_requested.emit())
	_pause_menu.quit_pressed.connect(func() -> void: exit_requested.emit())
	hud.set_paused_indicator(false)  # the full menu already reads "PAUSED"


func _close_pause_menu() -> void:
	if _pause_menu != null:
		_pause_menu.queue_free()
		_pause_menu = null
	phase = Phase.FLYING
	hud.set_paused_indicator(false)


func _save_progress() -> void:
	var payload := ship.serialize()
	payload["level_index"] = level_index
	payload["sim_time"] = sim_time
	payload["warp_index"] = warp_index
	save_requested.emit(payload)
	if _pause_menu != null:
		_pause_menu.show_saved_confirmation()


## SPACE and 0 are aliases for the same quick pause/unpause toggle; also
## dismisses the full pause menu if one is open.
func _toggle_quick_pause() -> void:
	if _pause_menu != null:
		_close_pause_menu()
	elif phase == Phase.FLYING:
		phase = Phase.PAUSED
		hud.set_paused_indicator(true)
	elif phase == Phase.PAUSED:
		phase = Phase.FLYING
		hud.set_paused_indicator(false)


func _apply_flight_input(delta: float) -> void:
	var rot := Vector3(
		Input.get_axis("pitch_down", "pitch_up"),  # W noses down, S noses up (KSP convention)
		Input.get_axis("yaw_right", "yaw_left"),
		Input.get_axis("roll_right", "roll_left"))
	if rot != Vector3.ZERO:
		ship.rotate_local(rot * ROT_RATE * delta)
		ship.sas_mode = ShipSim.SasMode.OFF  # manual stick overrides the hold
	elif ship.sas_mode != ShipSim.SasMode.OFF:
		_run_sas(delta)

	var throttle_input := Input.get_axis("throttle_decrease", "throttle_increase")
	if throttle_input != 0.0:
		ship.throttle = clampf(
			ship.throttle + throttle_input * THROTTLE_RATE * delta, 0.0, 1.0)
	if ship.throttle > 0.0 and warp_index > 0:
		warp_index = 0


func _check_end_conditions() -> void:
	if not ship.elements.is_valid:
		phase = Phase.FAILED
		hud.show_fail("ORBIT TRAJECTORY DEGENERATE")
	elif ship.r.length() <= ship.body.radius:
		match level.objective.contact_result(ship):
			Objective.ContactResult.WIN:
				_win()
			Objective.ContactResult.CRASH:
				phase = Phase.FAILED
				hud.show_fail("TOUCHDOWN TOO HARD")
			_:
				phase = Phase.FAILED
				hud.show_fail("%s SURFACE IMPACT" % ship.body.name)
	elif (level.fail_radius > 0.0 and ship.body.parent == null
			and ship.r.length() > level.fail_radius):
		phase = Phase.FAILED
		hud.show_fail("MISSION ENVELOPE EXCEEDED")
	elif level.objective.is_met(ship):
		_win()


func _win() -> void:
	phase = Phase.WON
	var dv_used := ship.dv_used()
	var medal := level.medal(dv_used)
	hud.show_win(level, dv_used, Campaign.next_after(level_index) != -1)
	mission_won.emit(level_index, dv_used, medal)


## Next impact/SOI/scheduled-node event on the current coasting orbit.
## Impact and SOI are cached per elements revision (analytic where
## possible; child-SOI entries use OrbitEvents.child_soi_entry_time's
## interval-minimum scan, which cannot skip an encounter window); the node
## time is re-checked every call since editing the node doesn't bump
## ship.revision (no elements refit happens).
func _next_event_time() -> float:
	if ship.revision != _event_revision or sim_time > _event_horizon:
		_recompute_events()
	if ship.node != null and ship.node.t_node > sim_time:
		return minf(_next_event, ship.node.t_node)
	return _next_event


func _recompute_events() -> void:
	_event_revision = ship.revision
	var el := ship.elements
	var events: Array[float] = []
	var impact := OrbitEvents.impact_time(el, ship.body.radius, sim_time)
	if not is_nan(impact):
		events.append(impact)
	var horizon := sim_time + _scan_span(el)
	if ship.body.parent != null:
		var exit_t := OrbitEvents.soi_exit_time(el, ship.body.soi_radius, sim_time)
		if not is_nan(exit_t):
			events.append(exit_t)
	# not an elif: a ship inside a non-root body's SOI can still enter one
	# of that body's own children (e.g. a moon of Earth while Earth is
	# itself a child of the Sun) - see ShipSim.apply_soi_transitions.
	for moon in level.moons:
		if moon.parent != ship.body:
			continue
		var entry := OrbitEvents.child_soi_entry_time(
			el, moon.orbit, moon.soi_radius, sim_time, horizon,
			maxf((horizon - sim_time) / 400.0, 1.0))
		if not is_nan(entry):
			events.append(entry)
	_event_horizon = horizon
	_next_event = events.min() if not events.is_empty() else INF


func _scan_span(el: OrbitElements) -> float:
	if el.is_elliptic():
		return el.period()
	var exit_t := OrbitEvents.radius_crossing_time(el, level.draw_limit, sim_time, true)
	return (exit_t - sim_time) if not is_nan(exit_t) else 2.0e4


func _node_create() -> void:
	if phase != Phase.FLYING:
		return
	if not level.nodes_enabled:
		hud.flash("FLIGHT COMPUTER NOT INSTALLED")
		return
	if ship.node == null:
		ship.create_node(sim_time + 120.0)
		flight_view.mark_traj_dirty()


func _node_adjust(field: NodeField, amount: float) -> void:
	if phase != Phase.FLYING or ship.node == null:
		return
	match field:
		NodeField.T_NODE:
			ship.node.t_node = maxf(ship.node.t_node + amount, sim_time + 1.0)
		NodeField.PROGRADE:
			ship.node.prograde += amount
		NodeField.NORMAL:
			ship.node.normal += amount
		NodeField.RADIAL:
			ship.node.radial += amount
	ship.refresh_node_plan()
	flight_view.mark_traj_dirty()


func _toggle_sas(mode: ShipSim.SasMode) -> void:
	if phase != Phase.FLYING:
		return
	if not level.sas_enabled:
		hud.flash("SAS NOT INSTALLED")
		return
	ship.sas_mode = ShipSim.SasMode.OFF if ship.sas_mode == mode else mode


## Turn the nose toward the SAS target at the manual turn rate.
func _run_sas(delta: float) -> void:
	var target := ship.sas_target_dir().to_vector3()
	var forward := ship.attitude * Vector3(0, 0, -1)
	var angle := acos(clampf(forward.dot(target), -1.0, 1.0))
	if angle < 0.0005:
		return
	var axis := forward.cross(target)
	if axis.length_squared() < 1e-12:  # anti-parallel: any perpendicular works
		axis = ship.attitude.x
	var step := minf(angle, ROT_RATE.x * delta)
	ship.attitude = (Basis(axis.normalized(), step) * ship.attitude).orthonormalized()

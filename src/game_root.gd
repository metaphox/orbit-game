extends Node3D
## Level orchestrator: sim clock, warp, input, win/fail state, view toggle.
## Keys are polled directly for M2; migrating to InputMap (rebindable) is
## part of the M6 settings work.

enum Phase { FLYING, WON, FAILED }

const WARP_STEPS: Array[int] = [1, 5, 25, 100]
const ROT_RATE := Vector3(0.6, 0.6, 1.1)  # pitch/yaw/roll, rad/s
const THROTTLE_RATE := 1.4  # full throttle sweep per second

var level: LevelDef
var ship: ShipSim
var sim_time := 0.0
var warp_index := 0
var phase := Phase.FLYING
var side_active := false

var flight_view: FlightView
var map_view: MapView
var hud: Hud


func _ready() -> void:
	level = Level01.make()
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

	flight_view.camera.make_current()


func _physics_process(delta: float) -> void:
	if phase != Phase.FLYING:
		return
	_apply_flight_input(delta)
	sim_time += delta * WARP_STEPS[warp_index]
	ship.advance_to(sim_time)
	_check_end_conditions()


func _process(delta: float) -> void:
	flight_view.sync(ship, delta)
	map_view.sync(ship, delta)
	hud.refresh(ship, level, sim_time, WARP_STEPS[warp_index])


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
		if side_active and wheel.pressed:
			if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				flight_view.side_zoom(0.88)
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				flight_view.side_zoom(1.14)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_TAB:
			side_active = not side_active
			flight_view.set_side_active(side_active)
		KEY_PERIOD:
			if phase == Phase.FLYING and ship.throttle == 0.0:
				warp_index = mini(warp_index + 1, WARP_STEPS.size() - 1)
		KEY_COMMA:
			warp_index = maxi(warp_index - 1, 0)
		KEY_Z:
			if phase == Phase.FLYING:
				ship.throttle = 1.0
				warp_index = 0
		KEY_X:
			ship.throttle = 0.0
		KEY_R:
			get_tree().reload_current_scene()


func _apply_flight_input(delta: float) -> void:
	var rot := Vector3(
		_axis(KEY_W, KEY_S),  # W noses down, S noses up (KSP convention)
		_axis(KEY_D, KEY_A),
		_axis(KEY_E, KEY_Q))
	if rot != Vector3.ZERO:
		ship.rotate_local(rot * ROT_RATE * delta)

	var throttle_input := _axis(KEY_CTRL, KEY_SHIFT)
	if throttle_input != 0.0:
		ship.throttle = clampf(
			ship.throttle + throttle_input * THROTTLE_RATE * delta, 0.0, 1.0)
	if ship.throttle > 0.0 and warp_index > 0:
		warp_index = 0


func _check_end_conditions() -> void:
	if ship.r.length() <= level.body.radius:
		phase = Phase.FAILED
		hud.show_fail("SURFACE IMPACT")
	elif level.objective.is_met(ship):
		phase = Phase.WON
		hud.show_win(level, ship.dv_used())


func _axis(neg: Key, pos: Key) -> float:
	var value := 0.0
	if Input.is_physical_key_pressed(pos):
		value += 1.0
	if Input.is_physical_key_pressed(neg):
		value -= 1.0
	return value

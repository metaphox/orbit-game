extends "res://tests/unit/base_orbit_test.gd"
## Build + per-frame behaviour for ShipVisuals, extracted from FlightView (TD-2):
## the craft markers are built up front, and the engine flame tracks throttle and
## remaining propellant. (Propellant % now reads on the screen HUD, not a gauge.)


func _built() -> ShipVisuals:
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	var sv := ShipVisuals.new()
	add_child_autofree(sv)
	var ship_root := Node3D.new()
	sv.add_child(ship_root)
	var flame := MeshInstance3D.new()
	ship_root.add_child(flame)
	sv.build(level, ship_root, flame)
	return sv


func test_build_creates_markers_and_star_dust() -> void:
	var sv := _built()
	assert_not_null(sv.prograde_marker, "prograde velocity marker is built")
	assert_not_null(sv.retrograde_marker, "retrograde velocity marker is built")
	assert_not_null(sv.star_dust, "the drifting star dust is built")


func test_flame_shows_only_while_burning_with_propellant() -> void:
	var level: LevelDef = load("res://src/levels/data/level_01_01.tres")
	var sv := ShipVisuals.new()
	add_child_autofree(sv)
	var ship_root := Node3D.new()
	sv.add_child(ship_root)
	var flame := MeshInstance3D.new()
	ship_root.add_child(flame)
	sv.build(level, ship_root, flame)

	var ship := ShipSim.new()
	ship.setup(level)
	var ship_abs := ship.absolute_position(0.0)

	ship.throttle = 0.6
	sv.sync(ship, ship_abs, 0.0, 3.0e5)
	assert_true(flame.visible, "the flame lights when the throttle is open")

	ship.throttle = 0.0
	sv.sync(ship, ship_abs, 0.0, 3.0e5)
	assert_false(flame.visible, "the flame dies when the throttle closes")

	ship.throttle = 0.6
	ship.prop_mass = 0.0
	sv.sync(ship, ship_abs, 0.0, 3.0e5)
	assert_false(flame.visible, "a dry tank keeps the flame out even at full throttle")

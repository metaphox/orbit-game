class_name AttitudeDirector
extends Control
## The GUIDANCE panel's functional attitude director. The center crosshair is the
## ship's nose (local -Z); the prograde marker sits off-center by the REAL
## off-prograde angle AND direction, found by projecting world velocity into the
## ship's local frame. Fly the crosshair onto the marker to burn along prograde.

## Off-prograde angle mapped to the ring edge; beyond this the marker pins to the
## rim (and recolours to WARNING) so a retrograde-facing craft still reads.
const MAX_SHOWN_ANGLE := PI / 2

var off_prograde := 0.0          # radians (== ship.off_prograde_angle())
var prograde_dir := Vector2.ZERO # unit screen-space direction toward prograde
var velocity_valid := false      # false when |v| ~ 0: marker hidden

var _phase := 0.0


func set_attitude(ship: ShipSim) -> void:
	velocity_valid = ship.v.length() > 1.0  # below ~1 m/s "prograde" is meaningless
	if not velocity_valid:
		prograde_dir = Vector2.ZERO
		off_prograde = 0.0
		queue_redraw()
		return
	# world velocity into the ship's local frame. attitude maps local->world and
	# is orthonormal, so world->local is its transpose (cheaper + stable).
	var v_local := ship.attitude.transposed() * ship.v.normalized().to_vector3()
	# nose = local -Z; this matches ShipSim.off_prograde_angle() exactly.
	off_prograde = acos(clampf(-v_local.z, -1.0, 1.0))
	# on-ring direction from the components perpendicular to the nose. Screen Y is
	# down, so negate the local-up (+Y) component.
	var planar := Vector2(v_local.x, -v_local.y)
	prograde_dir = planar.normalized() if planar.length() > 1.0e-5 else Vector2(0.0, -1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * 0.12, 1.0)  # slow, calm accent sweep
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0

	draw_circle(c, r, Color(Palette.LIVE_DK, 0.35))
	draw_arc(c, r, 0.0, TAU, 64, Palette.LIVE_DK, 6.0, true)
	var a0 := _phase * TAU
	draw_arc(c, r, a0, a0 + PI * 0.5, 24, Color(Palette.LIVE, 0.7), 3.0, true)
	draw_arc(c, r * 0.68, 0.0, TAU, 48, Palette.HAIRLINE, 2.0, true)

	# center crosshair = ship nose
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * 3.0, c + d * 11.0, Palette.INK, 2.0)
	draw_circle(c, 2.0, Palette.INK)

	if velocity_valid:
		var frac := clampf(off_prograde / MAX_SHOWN_ANGLE, 0.0, 1.0)
		var col := Palette.WARNING if off_prograde > MAX_SHOWN_ANGLE else Palette.INTENT
		var pos := c + prograde_dir * (r * 0.85 * frac)
		draw_arc(pos, 7.0, 0.0, TAU, 20, col, 2.4, true)
		draw_line(pos + Vector2(0.0, -11.0), pos + Vector2(0.0, -7.0), col, 2.4)

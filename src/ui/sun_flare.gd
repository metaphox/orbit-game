class_name SunFlare
extends Control
## Screen-space lens flare for the decorative Sun: a blooming core, a starburst,
## and a row of coloured ghosts along the sun→centre axis. Purely cosmetic and
## additive. FlightView feeds it the sun's screen position + an intensity each
## frame (0 when the sun is off-screen, behind the camera, or eclipsed by a body).

## Flare tints come from here (set by FlightView); default() for standalone use.
var render_theme: RenderTheme = RenderTheme.default()

var _screen := Vector2.ZERO
var _intensity := 0.0
var _glow: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_glow = _radial_texture()


func set_flare(screen: Vector2, intensity: float) -> void:
	_screen = screen
	_intensity = intensity
	queue_redraw()


func _draw() -> void:
	if _intensity <= 0.001:
		return
	var i := _intensity
	var centre := size * 0.5

	# blooming core: a broad soft halo under a small blinding-white centre
	_blob(_screen, 260.0 * (0.6 + 0.7 * i), Color(render_theme.flare_halo, 0.55 * i))
	_blob(_screen, 120.0, Color(render_theme.flare_core, 0.8 * i))
	_blob(_screen, 46.0, Color(render_theme.flare_center, i))

	# starburst spikes: four long, the rest short
	var n := 12
	for k in n:
		var ang := TAU * float(k) / float(n)
		var dir := Vector2.from_angle(ang)
		var long := k % 3 == 0
		var length := (200.0 if long else 90.0) * (0.6 + 0.7 * i)
		var width := 3.0 if long else 1.6
		var a := (1.0 if long else 0.45) * 0.8 * i
		draw_line(_screen, _screen + dir * length, Color(render_theme.flare_spike, a), width, true)

	# lens ghosts along the sun→centre line (strongest when the sun is centred)
	var axis := centre - _screen
	var focus := clampf(1.0 - axis.length() / maxf(size.length() * 0.5, 1.0), 0.0, 1.0)
	for g: Array in render_theme.flare_ghosts:
		var pos: Vector2 = _screen + axis * float(g[0])
		var col: Color = g[2]
		_blob(pos, float(g[1]) * (0.6 + 0.5 * i), Color(col, 0.5 * i * focus))


func _blob(at: Vector2, radius: float, col: Color) -> void:
	var s := Vector2(radius, radius) * 2.0
	draw_texture_rect(_glow, Rect2(at - s * 0.5, s), false, col)


## Soft white radial gradient (opaque centre → transparent edge) used for every
## glow/ghost, tinted per-draw.
static func _radial_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0)])  # lint-ok: generic white glow ramp, tinted per-draw
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex

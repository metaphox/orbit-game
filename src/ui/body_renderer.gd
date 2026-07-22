class_name BodyRenderer
extends Node3D
## Renders the level's celestial bodies in the flight view: faceted spheres,
## per-kind materials from the RenderTheme, Earth's atmosphere shell, axial
## rotation, and the chase-view far-body proxy (distant bodies pulled inside the
## tight chase far plane at true angular size). Extracted from FlightView
## (TECH_DEBTS.md TD-2/TD-3) so body visuals live in one themeable place.

const BODY_GENERIC := 0
const BODY_EARTH := 1
const BODY_MOON := 2
const BODY_SUN := 3
const BODY_MARS := 4

## Chase view: bodies past this distance are drawn as billboard proxies pulled
## to this range and shrunk by the same factor (true angular size preserved),
## so a distant Sun/planet still shows despite the tight chase far plane.
const CHASE_BODY_CAP := 3.0e5

## Farthest body from the ship as of the last sync() - FlightView reads it to
## size the orbit-view far plane.
var max_body_dist := 0.0

var _theme: RenderTheme
var _bodies: Array[BodyDef] = []
var _meshes: Array[MeshInstance3D] = []
var _rotation_rates: Array[float] = []


func build(level: LevelDef, theme: RenderTheme) -> void:
	_theme = theme
	_bodies = [level.body]
	for moon in level.moons:
		_bodies.append(moon)
	for body in _bodies:
		var mesh_instance := MeshInstance3D.new()
		var kind := _body_kind(body.name)
		var segments := 42 if kind == BODY_EARTH else 30
		var rings := 22 if kind == BODY_EARTH else 16
		mesh_instance.mesh = _make_faceted_sphere(body.radius, segments, rings)
		mesh_instance.material_override = _make_body_material(body, kind)
		add_child(mesh_instance)
		_meshes.append(mesh_instance)
		_rotation_rates.append(_rotation_rate_for(kind))

		if kind == BODY_EARTH:
			mesh_instance.add_child(_make_atmosphere(body))


## Reposition/scale/rotate every body for this frame. `side_active` selects the
## orbit view (true positions) vs the chase view (far-body proxy). Updates
## max_body_dist for the caller's far-plane sizing.
func sync(t: float, ship_abs: DVec3, side_active: bool) -> void:
	max_body_dist = 0.0
	for i in _bodies.size():
		var rel := _bodies[i].position_at(t).sub(ship_abs)
		max_body_dist = maxf(max_body_dist, rel.length())
		var body_scale := 1.0
		if not side_active:
			var dist := rel.length()
			if dist > CHASE_BODY_CAP:
				body_scale = CHASE_BODY_CAP / dist
		_meshes[i].position = rel.scaled(body_scale).to_vector3()
		_meshes[i].scale = Vector3.ONE * body_scale
		_meshes[i].rotation.y = fposmod(t * _rotation_rates[i], TAU)


func _make_atmosphere(body: BodyDef) -> MeshInstance3D:
	# A separate translucent shell lets the edge glow remain crisp even while the
	# low-poly surface beneath it catches hard facet lighting.
	var atmosphere := MeshInstance3D.new()
	var shell := SphereMesh.new()
	shell.radius = body.radius * 1.028
	shell.height = body.radius * 2.056
	shell.radial_segments = 64
	shell.rings = 32
	var mat := ShaderMaterial.new()
	mat.shader = _theme.atmosphere_shader
	mat.set_shader_parameter("glow_color", _theme.atmosphere_glow_color)
	mat.set_shader_parameter("glow_strength", _theme.atmosphere_glow_strength)
	shell.material = mat
	atmosphere.mesh = shell
	atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return atmosphere


static func _body_kind(body_name: String) -> int:
	match body_name.to_upper():
		"EARTH":
			return BODY_EARTH
		"MOON":
			return BODY_MOON
		"SOL", "SUN":
			return BODY_SUN
		"MARS":
			return BODY_MARS
		_:
			return BODY_GENERIC


static func _rotation_rate_for(kind: int) -> float:
	match kind:
		BODY_EARTH:
			return TAU / 86164.0
		BODY_MOON:
			return TAU / (27.3 * 86400.0)
		BODY_MARS:
			return TAU / 88642.0
		BODY_SUN:
			return TAU / (25.0 * 86400.0)
		_:
			return 0.0


func _make_body_material(body: BodyDef, kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _theme.body_shader
	material.set_shader_parameter("body_kind", kind)
	material.set_shader_parameter("base_color", body.color)
	material.set_shader_parameter("seed", float(absi(body.name.hash() % 2048)) / 173.0)
	if kind == BODY_EARTH:
		material.set_shader_parameter("earth_map", _theme.earth_map)
	return material


## A deliberately low-poly UV sphere with a distinct normal per triangle.
## SurfaceTool duplicates the vertices for us here, so the directional light
## reveals the polygon model while fixed equirectangular UVs anchor Earth art.
static func _make_faceted_sphere(radius: float, segments: int, rings: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in rings:
		var lat_0 := -PI * 0.5 + PI * float(ring) / float(rings)
		var lat_1 := -PI * 0.5 + PI * float(ring + 1) / float(rings)
		var v_0 := float(ring) / float(rings)
		var v_1 := float(ring + 1) / float(rings)
		for segment in segments:
			var lon_0 := TAU * float(segment) / float(segments)
			var lon_1 := TAU * float(segment + 1) / float(segments)
			var u_0 := float(segment) / float(segments)
			var u_1 := float(segment + 1) / float(segments)
			var p_00 := _sphere_point(radius, lat_0, lon_0)
			var p_01 := _sphere_point(radius, lat_0, lon_1)
			var p_10 := _sphere_point(radius, lat_1, lon_0)
			var p_11 := _sphere_point(radius, lat_1, lon_1)
			if ring == 0:
				_add_faceted_triangle(tool,
					p_00, Vector2(u_0, v_0),
					p_11, Vector2(u_1, v_1),
					p_10, Vector2(u_0, v_1))
			elif ring == rings - 1:
				_add_faceted_triangle(tool,
					p_00, Vector2(u_0, v_0),
					p_01, Vector2(u_1, v_0),
					p_10, Vector2(u_0, v_1))
			else:
				_add_faceted_triangle(tool,
					p_00, Vector2(u_0, v_0),
					p_01, Vector2(u_1, v_0),
					p_11, Vector2(u_1, v_1))
				_add_faceted_triangle(tool,
					p_00, Vector2(u_0, v_0),
					p_11, Vector2(u_1, v_1),
					p_10, Vector2(u_0, v_1))
	return tool.commit()


static func _sphere_point(radius: float, latitude: float, longitude: float) -> Vector3:
	var latitude_radius := cos(latitude)
	return Vector3(
		latitude_radius * cos(longitude),
		sin(latitude),
		latitude_radius * sin(longitude)) * radius


static func _add_faceted_triangle(
		tool: SurfaceTool,
		a: Vector3, uv_a: Vector2,
		b: Vector3, uv_b: Vector2,
		c: Vector3, uv_c: Vector2) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1.0e-10:
		return
	normal = normal.normalized()
	# Godot treats clockwise triangles as front-facing. Keep the submitted
	# winding's geometric normal inward (clockwise when viewed from outside),
	# while the explicit lighting normal remains outward. The opposite winding
	# renders the far hemisphere through the globe, like an inside-painted shell.
	if normal.dot(a + b + c) > 0.0:
		var swap := b
		b = c
		c = swap
		var uv_swap := uv_b
		uv_b = uv_c
		uv_c = uv_swap
	else:
		normal = -normal
	tool.set_normal(normal)
	tool.set_uv(uv_a)
	tool.add_vertex(a)
	tool.set_normal(normal)
	tool.set_uv(uv_b)
	tool.add_vertex(b)
	tool.set_normal(normal)
	tool.set_uv(uv_c)
	tool.add_vertex(c)

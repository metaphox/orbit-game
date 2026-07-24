class_name MapView
extends Node3D
## The schematic mission-computer map feeding the HUD minimap: bodies,
## the ship's current orbit conic, target ghosts (orbit ring or moon SOI),
## moon orbit tracks. 1 render unit = 1 km, everything on visual layer 2
## so only the minimap camera sees it. Vector-CRT styling arrives in M7.

const MAP_SCALE := 0.001
const MAP_LAYER := 2
const ORBIT_SAMPLES := 160
const REFRESH_INTERVAL := 0.2
## Ship/object marker size as a fraction of the map's on-screen height, so they
## stay legible at any zoom (world size = this * camera ortho size).
const MARKER_SCREEN_FRAC := 0.045
## Minimum on-screen radius for a moon disc (fraction of the map height), so a
## distant moon stays a visible dot without ballooning when you zoom in on it.
const MOON_MIN_SCREEN_FRAC := 0.018
## Same idea for the focused/root body - keeps the Sun visible (and prominent)
## at heliocentric zoom, where its true radius is a sub-pixel dot. Generous, so
## the central star clearly reads as the biggest body when everything is floored.
const PLANET_MIN_SCREEN_FRAC := 0.065

var orbit_mesh: ImmediateMesh
var orbit_instance: MeshInstance3D
var _planet: MeshInstance3D  # the root body's disc (kept for zoom-aware sizing)
var ship_marker: Node3D  # 3D glyph oriented by the ship's real attitude
## Set each frame by the HUD to the eased minimap camera ortho size; markers
## scale off it to keep a constant on-screen size.
var minimap_ortho_size := 0.0

var _level: LevelDef
var _moon_markers: Array[MeshInstance3D] = []
var _moon_tracks: Array[MeshInstance3D] = []
var _soi_rings: Array[MeshInstance3D] = []
# Tracked flying objects (station now; any future traffic later):
# [{ "marker": MeshInstance3D, "orbit": OrbitElements, "label": String, "color": Color }]
var _tracked: Array[Dictionary] = []
var _refresh_left := 0.0
var _last_heading := 0.0  # prograde-up camera azimuth, held across zero-velocity


## Planet/OrbitInstance/ShipMarker - the three nodes always present exactly
## once regardless of level - come from map_view_layout.tscn. Everything
## else here is genuinely level-variable (the ghost ring depends on which
## of five objective types the level uses; moon tracks/markers/SOI rings
## depend on level.moons.size()), so it stays runtime-built, matching
## flight_view.gd's planet meshes for the same reason.
func build(level: LevelDef) -> void:
	_level = level
	var layout := preload("res://src/ui/world/map_view_layout.tscn").instantiate()
	add_child(layout)

	_planet = layout.get_node("Planet")
	var planet_mesh: SphereMesh = _planet.mesh
	planet_mesh.radius = level.body.radius * MAP_SCALE
	planet_mesh.height = level.body.radius * MAP_SCALE * 2.0
	# Dark, faintly body-tinted fill, no bright rim: the tint alone says which
	# world this is (UI-DESIGN.md → Celestial body tints).
	_planet.material_override = _line_material(Palette.body_tint(level.body.name))

	orbit_instance = layout.get_node("OrbitInstance")
	orbit_mesh = orbit_instance.mesh
	orbit_instance.material_override = _line_material(Palette.LIVE)  # own orbit = live green

	# The flat layout triangle only encoded yaw. Replace it with a small 3D
	# glyph oriented by the real ship.attitude, so normal/antinormal/radial
	# pointing shows too (map is prograde-up - see velocity_heading_angle).
	layout.get_node("ShipMarker").queue_free()
	ship_marker = _build_ship_glyph()
	add_child(ship_marker)

	if level.objective is OrbitMatchObjective:
		var target := level.objective as OrbitMatchObjective
		var pts := _circle_points(target.target_radius * MAP_SCALE)
		if target.target_inclination > 0.0:
			var tilt := Basis(Vector3(1, 0, 0), target.target_inclination)
			for i in pts.size():
				pts[i] = tilt * pts[i]
		add_child(_line_instance(pts, Palette.TARGET))
	elif level.objective is RendezvousObjective:
		var rdv := level.objective as RendezvousObjective
		add_child(_line_instance(
			_circle_points(rdv.station_orbit.a * MAP_SCALE), Palette.TARGET))
		var station := _make_object_marker(Palette.TARGET)
		add_child(station)
		_tracked.append({
			"marker": station, "orbit": rdv.station_orbit,
			"label": "TGT", "color": Palette.TARGET})
	elif level.objective is EntryCorridorObjective:
		var corridor := level.objective as EntryCorridorObjective
		add_child(_line_instance(
			_circle_points(corridor.target_periapsis * MAP_SCALE), Palette.TARGET))

	for moon in level.moons:
		# the moon's orbit track around the root (hidden by sync when you're
		# zoomed deep inside the moon's SOI, where it's just a stray line)
		var track := _line_instance(
			_circle_points(moon.orbit.a * MAP_SCALE), Color(Palette.DIM, 0.5))
		add_child(track)
		_moon_tracks.append(track)
		var marker := MeshInstance3D.new()
		var dot := SphereMesh.new()
		# True physical radius; sync() enforces a minimum ON-SCREEN size only
		# when zoomed out, so zooming in shows the moon at its real size (a
		# proper disc with your orbit around it) instead of a fixed blob.
		var dot_radius := moon.radius * MAP_SCALE
		dot.radius = dot_radius
		dot.height = dot_radius * 2.0
		dot.material = _line_material(Palette.body_tint(moon.name))
		marker.mesh = dot
		marker.layers = MAP_LAYER
		add_child(marker)
		_moon_markers.append(marker)

		var soi := _dashed_ring(moon.soi_radius * MAP_SCALE, Palette.SOI)
		add_child(soi)
		_soi_rings.append(soi)


## The map is prograde-up: the minimap camera (hud.gd) rotates so the ship's
## velocity points to the top. Velocity is used rather than the nose so the
## frame stays stable and well-defined whatever way the nose points - which is
## what lets the attitude glyph actually show off-prograde pointing. Holds the
## last angle across a momentary zero-velocity so the map never spins.
func velocity_heading_angle(ship: ShipSim) -> float:
	var v := ship.v
	if v.length() > 1e-6:
		_last_heading = atan2(v.x, v.z)
	return _last_heading


func sync(ship: ShipSim, t: float, delta: float) -> void:
	# Markers keep a constant on-screen size: world size tracks the camera's
	# ortho size (fed by the HUD). Fall back to the level default on the very
	# first frame, before the HUD has pushed a value.
	var os := minimap_ortho_size if minimap_ortho_size > 0.0 else _level.map_extent
	var marker_scale := os * MARKER_SCREEN_FRAC

	ship_marker.position = ship.absolute_position(t).scaled(MAP_SCALE).to_vector3()
	# Orient by the real 3D attitude; the prograde-up camera turns nose-prograde
	# into "points up", radial into "points outward", normal into "points at you".
	ship_marker.basis = ship.attitude.scaled(Vector3.ONE * marker_scale)
	# Keep the root body (esp. the tiny-at-heliocentric-zoom Sun) visible.
	var planet_true_r := _level.body.radius * MAP_SCALE
	_planet.scale = Vector3.ONE * maxf(1.0, (os * PLANET_MIN_SCREEN_FRAC) / planet_true_r)

	var moon_min_r := os * MOON_MIN_SCREEN_FRAC  # floor on the moon's on-screen radius
	for i in _level.moons.size():
		var moon_pos := _level.moons[i].position_at(t).scaled(MAP_SCALE).to_vector3()
		_moon_markers[i].position = moon_pos
		# Scale up only if the true radius would be sub-visible at this zoom.
		var true_r := _level.moons[i].radius * MAP_SCALE
		_moon_markers[i].scale = Vector3.ONE * maxf(1.0, moon_min_r / true_r)
		# The track is a circle of the moon's orbital radius centered on the body
		# it orbits — its PARENT, not the scene root. For a moon of the root body
		# the parent sits at the origin (unchanged); for a moon of a planet that
		# itself orbits the Sun, the track must ride the planet.
		_moon_tracks[i].position = Frames.root_position(
			_level.moons[i].parent, t).scaled(MAP_SCALE).to_vector3()
		# Only useful when zoomed out enough to take it in; inside the SOI it's
		# just a line through the view.
		_moon_tracks[i].visible = os >= _level.moons[i].orbit.a * MAP_SCALE
		_soi_rings[i].position = moon_pos
	for obj in _tracked:
		var marker: MeshInstance3D = obj["marker"]
		marker.position = (obj["orbit"] as OrbitElements) \
			.state_at_time(t).r.scaled(MAP_SCALE).to_vector3()
		marker.scale = Vector3.ONE * marker_scale
	# orbit conic is parent-centered; offset the node by the parent's spot
	orbit_instance.position = ship.body.position_at(t).scaled(MAP_SCALE).to_vector3()
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_INTERVAL
	var r_max := minf(_level.draw_limit, ship.body.soi_radius * 1.15)
	_rebuild_orbit_line(ship.current_elements(), r_max)


## Map-scene position of the body the ship currently orbits - the point the
## minimap camera frames and rotates around (Earth, or the Moon inside its SOI).
func focus_point(ship: ShipSim, t: float) -> Vector3:
	return ship.body.position_at(t).scaled(MAP_SCALE).to_vector3()


## Orthographic size (render units) that frames the ship's current orbit and,
## when the ship is at the root body, its target - so AUTO zoom fills the panel
## instead of leaving dead margin. Measured from the current parent centre.
func auto_extent(ship: ShipSim, _t: float) -> float:
	var el := ship.current_elements()
	var r_max := minf(_level.draw_limit, ship.body.soi_radius * 1.15)
	var reach := ship.r.length()
	if el.is_elliptic():
		reach = maxf(reach, minf(el.radius_apoapsis(), r_max))
	if ship.body == _level.body:
		reach = maxf(reach, _target_reach())
	reach = maxf(reach, ship.body.radius * 1.2)
	return reach * 3.0 * MAP_SCALE  # *2 for diameter, *1.5 margin inside the round bezel


## The marked points (dots + labels) for the overlay, in map-scene coords.
## See UI-DESIGN.md for the colour/label convention.
func marked_points(ship: ShipSim, t: float) -> Array:
	var out: Array = []
	var el := ship.current_elements()
	var parent := focus_point(ship, t)
	var r_max := minf(_level.draw_limit, ship.body.soi_radius * 1.15)
	# AP/PE only when the orbit is eccentric enough for them to be distinct.
	if el.is_elliptic() and el.radius_apoapsis() <= r_max \
			and el.radius_apoapsis() - el.radius_periapsis() > el.a * 0.03:
		out.append({
			"pos": parent + el.state_at_true_anomaly(PI).r.scaled(MAP_SCALE).to_vector3(),
			"color": Palette.LIVE, "label": "AP"})
		out.append({
			"pos": parent + el.state_at_true_anomaly(0.0).r.scaled(MAP_SCALE).to_vector3(),
			"color": Palette.LIVE, "label": "PE"})
	if ship.node != null:
		out.append({
			"pos": parent + el.state_at_time(ship.node.t_node).r.scaled(MAP_SCALE).to_vector3(),
			"color": Palette.INTENT, "label": "NODE"})
	for obj in _tracked:
		out.append({
			"pos": (obj["orbit"] as OrbitElements).state_at_time(t).r
				.scaled(MAP_SCALE).to_vector3(),
			"color": obj["color"], "label": obj["label"]})
	for moon in _level.moons:
		out.append({
			"pos": moon.position_at(t).scaled(MAP_SCALE).to_vector3(),
			"color": Palette.DIM, "label": moon.name})
	return out


func _target_reach() -> float:
	var o := _level.objective
	if o is OrbitMatchObjective:
		return (o as OrbitMatchObjective).target_radius
	if o is RendezvousObjective:
		return (o as RendezvousObjective).station_orbit.a
	if o is EntryCorridorObjective:
		return (o as EntryCorridorObjective).target_periapsis
	return 0.0


func _rebuild_orbit_line(el: OrbitElements, r_max: float) -> void:
	var pts: Array[DVec3] = el.sample_positions(ORBIT_SAMPLES, r_max)
	orbit_mesh.clear_surfaces()
	orbit_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: DVec3 in pts:
		orbit_mesh.surface_add_vertex(p.scaled(MAP_SCALE).to_vector3())
	if el.is_elliptic() and el.radius_apoapsis() <= r_max:
		var first: DVec3 = pts[0]
		orbit_mesh.surface_add_vertex(first.scaled(MAP_SCALE).to_vector3())
	orbit_mesh.surface_end()


func _circle_points(radius: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 129:
		var ang := TAU * i / 128.0
		pts.append(Vector3(cos(ang) * radius, 0.0, sin(ang) * radius))
	return pts


## A dotted ring for an SOI boundary (UI-DESIGN.md): PRIMITIVE_LINES dashes so
## it reads as "a boundary you cross", distinct from the solid orbit conics and
## planet orbit tracks. 1 render unit = 1 km, like everything else here.
func _dashed_ring(radius: float, color: Color) -> MeshInstance3D:
	const DASHES := 72
	const ON := 0.42  # fraction of each segment actually drawn
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in DASHES:
		var a0 := TAU * float(i) / DASHES
		var a1 := TAU * (float(i) + ON) / DASHES
		mesh.surface_add_vertex(Vector3(cos(a0) * radius, 0.0, sin(a0) * radius))
		mesh.surface_add_vertex(Vector3(cos(a1) * radius, 0.0, sin(a1) * radius))
	mesh.surface_end()
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _line_material(color)
	inst.layers = MAP_LAYER
	return inst


func _line_instance(pts: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pts:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _line_material(color)
	inst.layers = MAP_LAYER
	return inst


func _line_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


## Unshaded, depth-test off, high priority: markers always draw on top so a
## craft on the far side of the orbit or over the planet disc still reads.
func _marker_material(color: Color) -> StandardMaterial3D:
	var mat := _line_material(color)
	mat.no_depth_test = true
	mat.render_priority = 4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # ship wedge is one flat tri - show both faces
	return mat


## The ship glyph: a compact dart oriented by ship.attitude (sync sets the
## basis). Forward is -Z; a bright nose tip makes the pointing direction
## unambiguous and a dorsal fin (+Y = ship's up) reads out-of-plane pointing.
## All parts use the draw-on-top marker material; the parent's basis scales it.
func _build_ship_glyph() -> Node3D:
	var glyph := Node3D.new()

	var body := MeshInstance3D.new()
	var fuselage := CylinderMesh.new()
	fuselage.top_radius = 0.16
	fuselage.bottom_radius = 0.16
	fuselage.height = 1.3
	fuselage.material = _marker_material(Palette.LIVE)
	body.mesh = fuselage
	body.rotation.x = -PI / 2  # cylinder axis (+Y) -> forward (-Z)
	body.layers = MAP_LAYER
	glyph.add_child(body)

	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.30
	cone.height = 0.7
	cone.material = _marker_material(Palette.MAP_NOSE)  # bright tip = "this way is forward"
	nose.mesh = cone
	nose.rotation.x = -PI / 2  # cone tip (+Y) -> forward (-Z)
	nose.position = Vector3(0, 0, -0.95)
	nose.layers = MAP_LAYER
	glyph.add_child(nose)

	var fin := MeshInstance3D.new()
	var fin_mesh := BoxMesh.new()
	fin_mesh.size = Vector3(0.07, 0.62, 0.5)
	fin_mesh.material = _marker_material(Palette.LIVE)
	fin.mesh = fin_mesh
	fin.position = Vector3(0, 0.34, 0.5)  # dorsal (+Y), aft (+Z)
	fin.layers = MAP_LAYER
	glyph.add_child(fin)

	return glyph


## A small 3D diamond (octahedron) for a tracked flying object - visually
## distinct from the ship glyph. Sized 1 unit; sync() scales it to a
## constant on-screen size.
func _make_object_marker(color: Color) -> MeshInstance3D:
	var gem := SphereMesh.new()
	gem.radius = 0.6
	gem.height = 1.2
	gem.radial_segments = 4
	gem.rings = 2
	gem.material = _marker_material(color)
	var inst := MeshInstance3D.new()
	inst.mesh = gem
	inst.layers = MAP_LAYER
	return inst

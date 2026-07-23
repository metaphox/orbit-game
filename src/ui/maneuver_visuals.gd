class_name ManeuverVisuals
extends Node3D
## Orbit-view planning overlays, extracted from FlightView (TECH_DEBTS.md TD-2):
## the maneuver-node ghost (predicted post-burn conic) and its moon-encounter
## preview arc, the node position marker, and the orbit marks (apoapsis,
## periapsis, ascending/descending nodes, impact, SOI encounter, closest
## approach). Also owns the throttle that keeps these expensive rebuilds off the
## per-frame path, and the child-SOI encounter-scan cache. Sits at the render
## origin (identity transform); its children are posed ship-relative just as they
## were as FlightView's own children.

const SIDE_MARKER_LAYER := 8  # markers only the orbit (side) camera can see

# The node ghost / SOI-encounter preview and the orbit marks are throttled to
# this interval (they can be expensive). The orbit LINE itself is rebuilt every
# frame in TrajectoryRenderer so it stays glued to the ship.
const TRAJ_REFRESH := 0.25

var _theme: RenderTheme
var _objective: Objective
var _draw_limit := 4.0e5
var _level: LevelDef
var _traj_timer := 0.0

var _node_mesh: ImmediateMesh
var _node_instance: MeshInstance3D
var _preview_mesh: ImmediateMesh
var _preview_instance: MeshInstance3D
var _preview_anchor: DVec3  # parent-frame moon position at predicted entry
var _preview_active := false
## [ship.revision, node.t_node, node.prograde, node.normal, node.radial] as of
## the last child-SOI encounter scan - see _rebuild_node_ghost.
var _ghost_key: Array = []
var _node_marker: MeshInstance3D

var _ap_marker: MeshInstance3D
var _pe_marker: MeshInstance3D
var _an_marker: MeshInstance3D
var _dn_marker: MeshInstance3D
var _impact_marker: MeshInstance3D
var _encounter_marker: MeshInstance3D
var _closest_approach_marker: MeshInstance3D
## Cache for the current-orbit child-SOI encounter scan - see
## _encounter_entry_time.
var _encounter_revision := -1
var _encounter_horizon := -INF
var _encounter_entry_t := NAN


func build(level: LevelDef, theme: RenderTheme = null) -> void:
	_theme = theme if theme != null else RenderTheme.default()
	_objective = level.objective
	_draw_limit = level.draw_limit
	_level = level
	_build_node_visuals()
	_build_orbit_marks()


## Force the throttled node ghost / orbit marks to refresh on the next sync
## (e.g. after a burn, a node edit, or an SOI transition).
func mark_dirty() -> void:
	_traj_timer = 0.0


## Position the node ghost/preview/marker for this frame and, on the throttled
## tick, rebuild the ghost and re-place the orbit marks. `guidance_enabled` false
## (hardcore) hides the node ghost, preview and node marker.
func sync(ship: ShipSim, delta: float, side_distance: float, guidance_enabled: bool) -> void:
	_node_instance.position = ship.r.neg().to_vector3()
	if _preview_active:
		_preview_instance.position = _preview_anchor.sub(ship.r).to_vector3()

	var has_maneuver_node := ship.node != null
	_node_marker.visible = has_maneuver_node
	if has_maneuver_node:
		_node_marker.position = ship.current_elements() \
			.state_at_time(ship.node.t_node).r.sub(ship.r).to_vector3()
		_node_marker.scale = Vector3.ONE * maxf(side_distance * 0.004, 4.0)

	_traj_timer -= delta
	if _traj_timer <= 0.0:
		_traj_timer = TRAJ_REFRESH
		_rebuild_node_ghost(ship)
		_update_orbit_marks(ship, ship.current_elements(), side_distance)

	if not guidance_enabled:  # hardcore: no node ghost / preview
		_node_instance.visible = false
		_preview_instance.visible = false
		_node_marker.visible = false


func _build_node_visuals() -> void:
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.albedo_color = _theme.node_ghost_color
	ghost_mat.emission_enabled = true
	ghost_mat.emission = _theme.node_ghost_color
	ghost_mat.emission_energy_multiplier = 1.8

	_node_mesh = ImmediateMesh.new()
	_node_instance = MeshInstance3D.new()
	_node_instance.mesh = _node_mesh
	_node_instance.material_override = ghost_mat
	add_child(_node_instance)

	_preview_mesh = ImmediateMesh.new()
	_preview_instance = MeshInstance3D.new()
	_preview_instance.mesh = _preview_mesh
	_preview_instance.material_override = ghost_mat
	add_child(_preview_instance)

	_node_marker = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 1.0
	dot.height = 2.0
	var marker_mat := StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = _theme.node_ghost_color
	dot.material = marker_mat
	_node_marker.mesh = dot
	_node_marker.layers = 1 | SIDE_MARKER_LAYER
	_node_marker.visible = false
	add_child(_node_marker)


## Apoapsis/periapsis/nodes/impact/encounter/closest-approach: small colored
## dots, orbit-view only, positioned each throttled refresh in
## _update_orbit_marks. Built once here and toggled visible/hidden rather than
## recreated, since most of them don't apply to every level.
func _build_orbit_marks() -> void:
	_ap_marker = _make_orbit_mark(_theme.mark_ap)
	_pe_marker = _make_orbit_mark(_theme.mark_pe)
	_an_marker = _make_orbit_mark(_theme.mark_an)
	_dn_marker = _make_orbit_mark(_theme.mark_dn)
	_impact_marker = _make_orbit_mark(_theme.mark_impact)
	_encounter_marker = _make_orbit_mark(_theme.mark_encounter)
	_closest_approach_marker = _make_orbit_mark(_theme.mark_closest)


func _make_orbit_mark(color: Color) -> MeshInstance3D:
	var mark := MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 1.0
	dot.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	dot.material = mat
	mark.mesh = dot
	mark.layers = SIDE_MARKER_LAYER
	mark.visible = false
	add_child(mark)
	return mark


## Whether a true anomaly is physically reachable on this trajectory - for
## a hyperbolic arc only |nu| < acos(-1/e) is ever actually visited.
func _nu_reachable(el: OrbitElements, nu: float) -> bool:
	if el.is_elliptic():
		return true
	return absf(wrapf(nu, -PI, PI)) < acos(-1.0 / el.e)


func _update_orbit_marks(ship: ShipSim, el: OrbitElements, side_distance: float) -> void:
	var mark_scale := Vector3.ONE * maxf(side_distance * 0.006, 1.0)

	_pe_marker.visible = true
	_pe_marker.position = el.state_at_true_anomaly(0.0).r.sub(ship.r).to_vector3()
	_pe_marker.scale = mark_scale

	_ap_marker.visible = el.is_elliptic()
	if _ap_marker.visible:
		_ap_marker.position = el.state_at_true_anomaly(PI).r.sub(ship.r).to_vector3()
		_ap_marker.scale = mark_scale

	var crossings: Array[float] = el.xz_plane_crossings()
	var nodes_valid := (crossings.size() == 2
		and _nu_reachable(el, crossings[0]) and _nu_reachable(el, crossings[1]))
	_an_marker.visible = nodes_valid
	_dn_marker.visible = nodes_valid
	if nodes_valid:
		_an_marker.position = el.state_at_true_anomaly(crossings[0]).r.sub(ship.r).to_vector3()
		_dn_marker.position = el.state_at_true_anomaly(crossings[1]).r.sub(ship.r).to_vector3()
		_an_marker.scale = mark_scale
		_dn_marker.scale = mark_scale

	var t := ship.last_time
	var impact_t := OrbitEvents.impact_time(el, ship.body.radius, t)
	_impact_marker.visible = not is_nan(impact_t)
	if _impact_marker.visible:
		_impact_marker.position = el.state_at_time(impact_t).r.sub(ship.r).to_vector3()
		_impact_marker.scale = mark_scale

	var encounter_t := _encounter_entry_time(ship, el)
	_encounter_marker.visible = not is_nan(encounter_t)
	if _encounter_marker.visible:
		_encounter_marker.position = el.state_at_time(encounter_t).r.sub(ship.r).to_vector3()
		_encounter_marker.scale = mark_scale

	_closest_approach_marker.visible = false
	if _objective is RendezvousObjective and ship.body.parent == null:
		var ca := (_objective as RendezvousObjective).closest_approach(ship)
		_closest_approach_marker.visible = true
		_closest_approach_marker.position = el.state_at_time(ca.time).r.sub(ship.r).to_vector3()
		_closest_approach_marker.scale = mark_scale


## Next time the current coasting orbit enters a child body's SOI, or NAN.
## OrbitEvents.child_soi_entry_time is a ~150 ms numerical scan for a
## lunar-distance window; the elements only change on a refit, so this caches
## on ship.revision (plus the scanned horizon) instead of re-running every
## TRAJ_REFRESH tick. That per-tick rescan was what dropped lunar-return
## framerate to ~10 FPS: inside the Moon's SOI the loop is skipped (the Moon
## has no children of its own), but the moment the ship hands back to Earth's
## SOI the big return ellipse made every rebuild pay the full scan again.
## Mirrors game_root._recompute_events, which caches the same scan the same
## way for the physics-side event clamp.
func _encounter_entry_time(ship: ShipSim, el: OrbitElements) -> float:
	var t := ship.last_time
	if ship.revision == _encounter_revision and t <= _encounter_horizon:
		return _encounter_entry_t
	_encounter_revision = ship.revision
	var span := el.period() if el.is_elliptic() else 6.0e4
	_encounter_horizon = t + span
	_encounter_entry_t = NAN
	for moon in _level.moons:
		if moon.parent != ship.body:
			continue
		var entry := OrbitEvents.child_soi_entry_time(
			el, moon.orbit, moon.soi_radius, t, t + span, maxf(span / 400.0, 1.0))
		if not is_nan(entry):
			_encounter_entry_t = entry
			break
	return _encounter_entry_t


## Predicted post-burn conic (cyan), plus a moon-centric arc when the
## prediction enters a moon's SOI — anchored at the moon's position at the
## predicted entry time, KSP-style.
func _rebuild_node_ghost(ship: ShipSim) -> void:
	_node_mesh.clear_surfaces()
	if ship.node == null:
		_preview_mesh.clear_surfaces()
		_preview_active = false
		_ghost_key = []
		return
	var pred := ship.predicted_elements()
	var r_max := minf(_draw_limit, ship.body.soi_radius * 1.15)
	var pts: Array[DVec3] = pred.sample_positions(TrajectoryRenderer.TRAJ_SAMPLES, r_max)
	var closed := pred.is_elliptic() and pred.radius_apoapsis() <= r_max
	_node_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: DVec3 in pts:
		_node_mesh.surface_add_vertex(p.to_vector3())
	if closed:
		var first: DVec3 = pts[0]
		_node_mesh.surface_add_vertex(first.to_vector3())
	_node_mesh.surface_end()

	# OrbitEvents.child_soi_entry_time below is a numerical root-find with no
	# closed form - a coarse scan (up to a few hundred steps, tightened
	# further for slow relative speeds) each refined by 40 ternary-search
	# iterations, so potentially thousands of Kepler solves per call. Redoing
	# that from scratch every TRAJ_REFRESH tick (4x/second) for as long as a
	# node exists was the actual cost of lunar missions: pred only changes
	# when the ship refits (ship.revision) or the node's plan is edited, so
	# while coasting toward an untouched node - the common case, e.g. most of
	# a TLI/LOI coast - the scan was pure repeated waste. Cache on that
	# signature and skip the whole moon loop (leaving the preview mesh/
	# anchor exactly as they were, which is still correct) when neither
	# moved since the last call.
	var node := ship.node
	var key: Array = [ship.revision, node.t_node, node.prograde, node.normal, node.radial]
	if key == _ghost_key:
		return
	_ghost_key = key

	_preview_mesh.clear_surfaces()
	_preview_active = false
	for moon in _level.moons:
		if moon.parent != ship.body:
			continue
		var span := pred.period() if pred.is_elliptic() else 6.0e4
		var entry := OrbitEvents.child_soi_entry_time(
			pred, moon.orbit, moon.soi_radius, node.t_node,
			node.t_node + span, maxf(span / 400.0, 1.0))
		if is_nan(entry):
			continue
		var rel := Frames.to_child_frame(pred.state_at_time(entry), moon.orbit, entry)
		var arc := OrbitElements.from_state(rel.r, rel.v, moon.mu, entry)
		var arc_pts: Array[DVec3] = arc.sample_positions(96, moon.soi_radius)
		_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p: DVec3 in arc_pts:
			_preview_mesh.surface_add_vertex(p.to_vector3())
		_preview_mesh.surface_end()
		# Anchor the moon-centric arc at the moon's position in the ship's own
		# (parent) frame, matching the ship-relative posing every child here
		# uses (sync subtracts ship.r). moon.parent == ship.body in this loop,
		# so this is the moon relative to the frame the ship coasts in - the
		# root-frame moon.position_at only lined up inside the root body's SOI.
		_preview_anchor = Frames.position_relative_to(moon, ship.body, entry)
		_preview_active = true
		break

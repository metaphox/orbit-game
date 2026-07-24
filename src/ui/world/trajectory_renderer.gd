class_name TrajectoryRenderer
extends Node3D
## The current-orbit prediction line - rebuilt every frame and glued to the ship
## via the floating origin - plus the objective's target ring or entry-corridor
## band. Reads its line colours from the RenderTheme. Extracted from FlightView
## (TECH_DEBTS.md TD-2/TD-3) so the forward-path visuals live in one themeable
## place. Sits at the render origin (identity transform); its children are posed
## in ship-relative space just as they were as FlightView's own children.

const TRAJ_SAMPLES := 256
# Adaptive orbit-line sampling: the camera rides ON the line, so chords near the
# ship are seen edge-on and must be near-tangent-continuous. Steps in true
# anomaly start fine at the ship and grow geometrically. The coarse cap also
# bounds how angular the foreshortened apoapsis fold looks.
const TRAJ_FINE_STEP := 0.002
const TRAJ_COARSE_STEP := 0.03
const TRAJ_STEP_GROWTH := 1.18

var _theme: RenderTheme
var _objective: Objective
var _draw_limit := 4.0e5
var _ring_body: BodyDef
var _traj_mesh: ImmediateMesh
var _traj_instance: MeshInstance3D
var _traj_material: StandardMaterial3D
var _target_mesh: ImmediateMesh
var _target_instance: MeshInstance3D

# Target-ring geometry, resolved once in build() and re-emitted every stale frame
# by _rebuild_target() in ship-relative double precision (same reason as the
# prediction line: a ring at radius ~1e5 baked in its own frame would quantize to
# the float32 ULP at that magnitude). corridor_tol > 0 switches to the band render.
var _ring_radius := 0.0
var _ring_tilt := 0.0
var _ring_corridor_tol := 0.0
var _dash_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D

# The conic geometry is a pure function of (elements revision, ship anomaly);
# these track what the current mesh was built for so an unchanged frame - a
# frozen phase, or a settled rewind scrub - skips the resample entirely.
var _cached_revision := -1
var _cached_time := INF


func build(level: LevelDef, theme: RenderTheme) -> void:
	_theme = theme
	_objective = level.objective
	_draw_limit = level.draw_limit

	_traj_mesh = ImmediateMesh.new()
	_traj_material = StandardMaterial3D.new()
	_traj_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_traj_material.emission_enabled = true
	_traj_material.emission_energy_multiplier = 2.5
	_traj_instance = MeshInstance3D.new()
	_traj_instance.mesh = _traj_mesh
	_traj_instance.material_override = _traj_material
	add_child(_traj_instance)

	# target ring: whatever circle best marks the goal for this objective.
	# _ring_tilt inclines it off the equatorial plane so a plane-change goal
	# reads as a tilted hoop the ship must line its orbit up with, not just a
	# number - the flat radius circle alone hid the inclination target.
	if _objective is TransferCaptureObjective:
		var capture := _objective as TransferCaptureObjective
		_ring_body = capture.target
		_ring_radius = capture.target.soi_radius
	elif _objective is RendezvousObjective:
		var rdv := _objective as RendezvousObjective
		_ring_body = level.body
		_ring_radius = rdv.station_orbit.a
	elif _objective is AirlessLandingObjective:
		var landing := _objective as AirlessLandingObjective
		_ring_body = landing.target
		_ring_radius = landing.target.radius * 1.03
	elif _objective is EntryCorridorObjective:
		var corridor := _objective as EntryCorridorObjective
		_ring_body = level.body
		_ring_radius = corridor.target_periapsis
		_ring_corridor_tol = corridor.tolerance
	else:
		var match_obj := _objective as OrbitMatchObjective
		_ring_body = level.body
		_ring_radius = match_obj.target_radius
		_ring_tilt = match_obj.target_inclination

	_build_ring_materials()
	_target_mesh = ImmediateMesh.new()
	_target_instance = MeshInstance3D.new()
	_target_instance.mesh = _target_mesh
	# The dashed ring is one uniform line material (an instance override); the
	# corridor band carries per-surface materials, so it takes no override.
	if _ring_corridor_tol <= 0.0:
		_target_instance.material_override = _dash_mat
	add_child(_target_instance)
	# Seed an origin-centred ring so the mesh is valid before the first sync();
	# sync() re-emits it ship-relative every stale frame.
	_rebuild_target(DVec3.new())


## The ring's materials, built once. A dashed circle for most goals; a filled
## amber band + bright edge rings for an entry corridor (see _rebuild_corridor).
func _build_ring_materials() -> void:
	if _ring_corridor_tol > 0.0:
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fill_mat.albedo_color = Color(_theme.corridor_color, 0.16)
		_edge_mat = StandardMaterial3D.new()
		_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_edge_mat.albedo_color = Color(_theme.corridor_color, 0.9)
		_edge_mat.emission_enabled = true
		_edge_mat.emission = _theme.corridor_color
		_edge_mat.emission_energy_multiplier = 1.5
	else:
		_dash_mat = StandardMaterial3D.new()
		_dash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dash_mat.albedo_color = Color(_theme.ring_color, 0.55)
		_dash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dash_mat.emission_enabled = true
		_dash_mat.emission = _theme.ring_color
		_dash_mat.emission_energy_multiplier = 1.2


## Rebuild both meshes for this frame in ship-relative coordinates so they stay
## glued to the ship (first vertex exactly on it). `guidance_enabled` false
## (hardcore) hides the prediction line; the target ring always stays.
##
## Both instances sit at the render origin (identity) — the ship-relative offset
## is folded into the vertices in DOUBLE precision (`.sub(ship.r)` before the
## float32 cast), not applied afterwards as a large float32 node translation.
## That is the whole floating-origin correctness point: near the ship a conic
## point p ≈ ship.r, so p - ship.r is a small double that casts to float32
## losslessly. The old path cast p (~1e5) and -ship.r (~1e5) to float32
## separately and let the GPU subtract them, so the ~0.008-unit ULP at that
## magnitude quantized every vertex — the line jittered frame-to-frame, drifted
## off the ship, and looked faceted when zoomed in.
func sync(ship: ShipSim, ship_abs: DVec3, t: float, guidance_enabled: bool) -> void:
	_traj_instance.visible = guidance_enabled
	# The geometry only changes when the elements are refit (ship.revision) or the
	# ship walks along the conic (ship.last_time). When a phase is frozen
	# (PAUSED/FAILED, or a settled rewind scrub) both hold and the ship-relative
	# meshes are still valid, so skip the rebuild - camera orbiting moves nothing
	# relative to the ship.
	if ship.revision == _cached_revision and ship.last_time == _cached_time:
		return
	_cached_revision = ship.revision
	_cached_time = ship.last_time
	# The ring always shows (even in hardcore); the prediction line is guidance-only.
	_rebuild_target(_ring_body.position_at(t).sub(ship_abs))
	if guidance_enabled:
		_rebuild_line(ship)


## Re-emit the target ring for this frame, centred on `center` = the ring body's
## position relative to the ship (DVec3). Every vertex is (center + ring point)
## built in double and cast once, so the ring - like the prediction line - keeps
## full precision near the ship instead of quantizing at its own ~1e5 radius.
func _rebuild_target(center: DVec3) -> void:
	_target_mesh.clear_surfaces()
	if _ring_corridor_tol > 0.0:
		_rebuild_corridor(center)
	else:
		_rebuild_dashes(center)


## A vertex on a circle of the given radius at angle `ang`, tilted about the +X
## apsis line by _ring_tilt and translated by `center` — all in double so the
## float32 cast happens only on the final ship-relative (small-near-ship) value.
func _ring_vertex(center: DVec3, radius: float, ang: float) -> Vector3:
	var x := cos(ang) * radius
	var z := sin(ang) * radius
	# Basis(+X, tilt) with y=0: (x, -z*sin(tilt), z*cos(tilt)).
	var p := DVec3.new(x, -z * sin(_ring_tilt), z * cos(_ring_tilt))
	return center.add(p).to_vector3()


func _rebuild_dashes(center: DVec3) -> void:
	_target_mesh.surface_begin(Mesh.PRIMITIVE_LINES)  # uses the instance override
	var dashes := 96
	for i in dashes:
		if i % 2 == 1:
			continue
		for k in 2:
			var ang := TAU * (i + k * 0.85) / dashes
			_target_mesh.surface_add_vertex(_ring_vertex(center, _ring_radius, ang))
	_target_mesh.surface_end()


## The entry-corridor gate: a faint filled amber annulus between the periapsis
## tolerance bounds plus a bright ring on each edge, so the shallow corridor
## reads as a distinct band above the surface instead of a hairline circle.
func _rebuild_corridor(center: DVec3) -> void:
	var inner := _ring_radius - _ring_corridor_tol
	var outer := _ring_radius + _ring_corridor_tol
	var seg := 96
	_target_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _fill_mat)
	for i in seg + 1:
		var ang := TAU * i / seg
		_target_mesh.surface_add_vertex(_ring_vertex(center, inner, ang))
		_target_mesh.surface_add_vertex(_ring_vertex(center, outer, ang))
	_target_mesh.surface_end()
	for edge_radius: float in [inner, outer]:
		_target_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _edge_mat)
		for i in seg + 1:
			var ang := TAU * i / seg
			_target_mesh.surface_add_vertex(_ring_vertex(center, edge_radius, ang))
		_target_mesh.surface_end()


## The orbit line itself, rebuilt every frame. Cheap (analytic sampling of a
## conic) and it keeps the first vertex sitting exactly on the ship, so the
## ship never drifts off the line and the far-side fold never twitches at the
## old 4 Hz refresh rate. The pricier node ghost / orbit marks stay throttled.
func _rebuild_line(ship: ShipSim) -> void:
	var el := ship.current_elements()
	var color := _theme.traj_far_color.lerp(_theme.traj_match_color, _objective.trajectory_closeness(ship))
	_traj_material.albedo_color = color
	_traj_material.emission = color

	var r_max := minf(_draw_limit, ship.body.soi_radius * 1.15)
	var closed := el.is_elliptic() and el.radius_apoapsis() <= r_max
	var pts: Array[DVec3]
	if closed:
		pts = _adaptive_loop_points(el, el.true_anomaly_at_time(ship.last_time))
	else:
		pts = el.sample_positions(TRAJ_SAMPLES, r_max)
	# Ship-relative in double precision: p - ship.r is small near the ship (where
	# the camera sits) so its float32 cast is exact, killing the jitter/facet the
	# old cast-then-subtract-on-GPU produced. Far-side vertices are large but far
	# away, where the same ULP is sub-pixel.
	var origin := ship.r
	_traj_mesh.clear_surfaces()
	_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: DVec3 in pts:
		_traj_mesh.surface_add_vertex(p.sub(origin).to_vector3())
	if closed:
		var first: DVec3 = pts[0]
		_traj_mesh.surface_add_vertex(first.sub(origin).to_vector3())
	_traj_mesh.surface_end()


## Full loop with vertex density concentrated at the ship: the first point
## sits exactly on the ship, neighbors ~0.1 degrees apart (invisible bends
## at grazing view), widening to coarse steps on the far side.
func _adaptive_loop_points(el: OrbitElements, nu_ship: float) -> Array[DVec3]:
	var offsets: Array[float] = []
	var step := TRAJ_FINE_STEP
	var off := 0.0
	while off < PI:
		offsets.append(off)
		off += step
		step = minf(step * TRAJ_STEP_GROWTH, TRAJ_COARSE_STEP)
	# Position-only sampler: the perifocal basis is invariant along the orbit,
	# so compute it once for the whole loop instead of per point (PF-2).
	var s := el.make_position_sampler()
	var pts: Array[DVec3] = []
	for i in range(offsets.size() - 1, 0, -1):
		pts.append(OrbitElements.sample_position(s, nu_ship - offsets[i]))
	for i in offsets.size():
		pts.append(OrbitElements.sample_position(s, nu_ship + offsets[i]))
	return pts

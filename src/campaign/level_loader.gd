class_name LevelLoader
extends RefCounted
## Builds a LevelDef from a human-authored level dict (friendly units — km/deg —
## and bodies referenced by catalog name). from_dict returns
## {"level": LevelDef, "error": String}: a non-empty error means the spec was
## rejected with a readable reason (never a crash). Objective params convert
## km→m / deg→rad; RendezvousObjective.station_mu auto-fills from the root body;
## objective.target is the SAME instance placed in `moons` (identity matters).

const KM := 1000.0

## Anti-nightmare caps (tunable). Total bodies bound render/iteration cost
## (measured cheap: a 48-body render sync is <1 ms/frame — see
## test_perf_heavy_level). Active (non-decorative) moons bound the expensive
## per-refit SOI scan: a no-encounter child_soi_entry_time is ~0.45 s, and the
## physics event clamp scans every reachable active child. A broad-phase radial
## rejection (OrbitEvents.child_soi_entry_time) drops the common case — a
## confined/parking orbit among distant moons — to microseconds (unreachable
## moons rejected O(1)), and PF-1 shares the one scan between the clamp and the
## visual marker. The residual worst case is one orbit whose [peri, apo] band
## radially spans many reachable active moons: ~0.45 s each, only at a
## burn/SOI-refit (cached while coasting). If that ceiling matters on target
## hardware, lower MAX_ACTIVE_MOONS. Scenery is cheap — mark distant bodies
## "decorative": true to stay under the active cap.
const MAX_BODIES := 48
const MAX_ACTIVE_MOONS := 12


static func from_dict(spec: Dictionary, id: String) -> Dictionary:
	var root_name := String(spec.get("system", ""))
	if not BodyCatalog.has_body(root_name):
		return _err("unknown system body '%s'" % root_name)

	var bodies_v: Variant = spec.get("bodies", [])
	if not (bodies_v is Array):
		return _err("'bodies' must be a list")
	var moon_specs: Array = bodies_v
	for ms_v: Variant in moon_specs:
		if not (ms_v is Dictionary):
			return _err("each 'bodies' entry must be an object")
	if 1 + moon_specs.size() > MAX_BODIES:
		return _err("too many bodies: %d (limit %d). Use fewer, or drop distant scenery." % [
			1 + moon_specs.size(), MAX_BODIES])
	var active := 0
	for ms: Dictionary in moon_specs:
		if not bool(ms.get("decorative", false)):
			active += 1
	if active > MAX_ACTIVE_MOONS:
		return _err("too many active (non-decorative) bodies: %d (limit %d). Mark scenery \"decorative\": true." % [
			active, MAX_ACTIVE_MOONS])

	var seen := {root_name: true}
	for ms: Dictionary in moon_specs:
		var nm := String(ms.get("name", ""))
		if not BodyCatalog.has_body(nm):
			return _err("unknown body '%s'" % nm)
		if seen.has(nm):
			return _err("body '%s' appears more than once in this level" % nm)
		seen[nm] = true

	var g := BodyCatalog.build(root_name, moon_specs)
	for m: BodyDef in g.moons:
		if m.parent == null:
			return _err("body '%s' has no parent in this level (its catalogued parent isn't listed under 'bodies')" % m.name)

	var lvl := LevelDef.new()
	lvl.id = id
	lvl.title = String(spec.get("title", ""))
	lvl.body = g.root
	lvl.moons = g.moons

	# start / ship / objective / avionics must be objects if present (untrusted).
	for section: String in ["start", "ship", "objective", "avionics"]:
		var oe := _object_or_absent(spec, section)
		if oe != "":
			return _err(oe)

	var start: Dictionary = spec.get("start", {})
	var start_name := String(start.get("body", root_name))
	if not g.by_name.has(start_name):
		return _err("start body '%s' isn't in this level" % start_name)
	var start_body: BodyDef = g.by_name[start_name]
	if start_body.decorative:
		return _err("start body '%s' can't be decorative" % start_name)
	lvl.start_body = null if start_body == g.root else start_body  # null = start at root (matches legacy .tres)
	if not start.is_empty():
		var start_err := _apply_start(lvl, start, start_body)
		if start_err != "":
			return _err(start_err)
	if lvl.start_radius <= 0.0:  # no start block: default to a low circular orbit
		lvl.start_radius = start_body.radius * 1.15

	# Absent ship block -> a sensible playable craft; present values are validated
	# (an explicit 0/negative/wrong-type is rejected, never silently accepted).
	var ship: Dictionary = spec.get("ship", {})
	lvl.dry_mass = _num(ship, "dry_mass", 1000.0)
	lvl.prop_mass = _num(ship, "prop_mass", 300.0)
	lvl.thrust = _num(ship, "thrust", 6000.0)
	lvl.isp = _num(ship, "isp", 82.0)
	var ship_err := _validate_nums([
		[lvl.dry_mass, "ship.dry_mass", "pos"],   # mass()/rocket-equation divide by it
		[lvl.prop_mass, "ship.prop_mass", "nonneg"],
		[lvl.thrust, "ship.thrust", "pos"],
		[lvl.isp, "ship.isp", "pos"]])            # mass_flow divides by isp
	if ship_err != "":
		return _err(ship_err)

	var ob := _build_objective(spec.get("objective", {}), g)
	if ob.error != "":
		return _err(ob.error)
	lvl.objective = ob.objective

	lvl.dv_par = _num(spec, "dv_par", 0.0)
	lvl.difficulty = clampi(int(_num(spec, "difficulty", 1.0)), 1, 4)  # cosmetic; clamp
	lvl.rewind_budget = maxi(0, int(_num(spec, "rewind_budget", 1.0)))
	var av: Dictionary = spec.get("avionics", {})
	lvl.sas_enabled = bool(av.get("sas", false))
	lvl.nodes_enabled = bool(av.get("nodes", false))

	lvl.map_extent = _num(spec, "map_extent_km", 360.0)          # minimap ortho, km units
	lvl.draw_limit = _num(spec, "draw_limit_km", 400.0) * KM     # clip radius, metres
	lvl.fail_radius = _num(spec, "fail_radius_km", 0.0) * KM     # 0 = no envelope
	var view_err := _validate_nums([
		[lvl.dv_par, "dv_par", "nonneg"],
		[lvl.map_extent, "map_extent_km", "pos"],
		[lvl.draw_limit, "draw_limit_km", "pos"],
		[lvl.fail_radius, "fail_radius_km", "nonneg"]])
	if view_err != "":
		return _err(view_err)

	return {"level": lvl, "error": ""}


## Build the Objective subclass from its typed block. Returns
## {"objective": Objective, "error": String}. Bodies referenced by name resolve
## to the shared graph instance so identity checks (ship.body != target) hold.
static func _build_objective(o: Dictionary, g: Dictionary) -> Dictionary:
	var t := String(o.get("type", ""))
	match t:
		"orbit_match":
			if not o.has("radius_km"):
				return _oerr("orbit_match needs radius_km")
			var ob := OrbitMatchObjective.new()
			ob.target_radius = _num(o, "radius_km", 0.0) * KM
			ob.tolerance = _num(o, "tolerance_km", 0.0) * KM
			var e := _validate_nums([
				[ob.target_radius, "orbit_match.radius_km", "pos"],
				[ob.tolerance, "orbit_match.tolerance_km", "nonneg"]])
			if e != "":
				return _oerr(e)
			if o.has("inclination_deg"):
				var inc := _num(o, "inclination_deg", 0.0)
				if not is_finite(inc):
					return _oerr("orbit_match.inclination_deg must be a finite number")
				ob.target_inclination = deg_to_rad(inc)
			if o.has("inclination_tolerance_deg"):
				var it := _num(o, "inclination_tolerance_deg", 0.0)
				if not is_finite(it) or it < 0.0:
					return _oerr("orbit_match.inclination_tolerance_deg must be >= 0")
				ob.inclination_tolerance = deg_to_rad(it)
			return {"objective": ob, "error": ""}
		"rendezvous":
			if not o.has("station_radius_km"):
				return _oerr("rendezvous needs station_radius_km")
			var ob := RendezvousObjective.new()
			ob.station_orbit_radius = _num(o, "station_radius_km", 0.0) * KM
			ob.station_orbit_phase_deg = _num(o, "station_phase_deg", 0.0)
			ob.station_mu = (g.root as BodyDef).mu  # auto: authors never copy μ
			if o.has("max_distance_m"):
				ob.max_distance = _num(o, "max_distance_m", 0.0)
			if o.has("max_rel_speed_ms"):
				ob.max_rel_speed = _num(o, "max_rel_speed_ms", 0.0)
			var e := _validate_nums([
				[ob.station_orbit_radius, "rendezvous.station_radius_km", "pos"],
				[ob.station_orbit_phase_deg, "rendezvous.station_phase_deg", "finite"],
				[ob.max_distance, "rendezvous.max_distance_m", "pos"],
				[ob.max_rel_speed, "rendezvous.max_rel_speed_ms", "nonneg"]])
			if e != "":
				return _oerr(e)
			return {"objective": ob, "error": ""}
		"transfer_capture":
			var tn := String(o.get("target", ""))
			if not g.by_name.has(tn):
				return _oerr("transfer_capture target '%s' isn't a body in this level" % tn)
			if (g.by_name[tn] as BodyDef).decorative:
				return _oerr("transfer_capture target '%s' is decorative (scenery can't be a target)" % tn)
			var ob := TransferCaptureObjective.new()
			ob.target = g.by_name[tn]
			if o.has("approach_falloff_km"):
				ob.approach_falloff = _num(o, "approach_falloff_km", 0.0) * KM
				var e := _validate_nums([[ob.approach_falloff, "transfer_capture.approach_falloff_km", "pos"]])
				if e != "":
					return _oerr(e)
			return {"objective": ob, "error": ""}
		"airless_landing":
			var tn := String(o.get("target", ""))
			if not g.by_name.has(tn):
				return _oerr("airless_landing target '%s' isn't a body in this level" % tn)
			if (g.by_name[tn] as BodyDef).decorative:
				return _oerr("airless_landing target '%s' is decorative (scenery can't be a target)" % tn)
			var ob := AirlessLandingObjective.new()
			ob.target = g.by_name[tn]
			if o.has("max_vertical_ms"):
				ob.max_vertical = _num(o, "max_vertical_ms", 0.0)
			if o.has("max_horizontal_ms"):
				ob.max_horizontal = _num(o, "max_horizontal_ms", 0.0)
			var e := _validate_nums([
				[ob.max_vertical, "airless_landing.max_vertical_ms", "nonneg"],
				[ob.max_horizontal, "airless_landing.max_horizontal_ms", "nonneg"]])
			if e != "":
				return _oerr(e)
			return {"objective": ob, "error": ""}
		"entry_corridor":
			if not o.has("periapsis_km"):
				return _oerr("entry_corridor needs periapsis_km")
			var ob := EntryCorridorObjective.new()
			ob.target_periapsis = _num(o, "periapsis_km", 0.0) * KM
			ob.tolerance = _num(o, "tolerance_km", 0.0) * KM
			var e := _validate_nums([
				[ob.target_periapsis, "entry_corridor.periapsis_km", "pos"],
				[ob.tolerance, "entry_corridor.tolerance_km", "nonneg"]])
			if e != "":
				return _oerr(e)
			return {"objective": ob, "error": ""}
		_:
			return _oerr("unknown objective type '%s'" % t)


## Map the friendly `start` block to LevelDef's start-orbit fields. base radius =
## periapsis (or circular radius); shape = apoapsis_km OR eccentricity (≥1 open);
## `at` chooses periapsis (default) or apoapsis; plus inclination/retrograde.
## Returns "" on success or a readable error.
static func _apply_start(lvl: LevelDef, start: Dictionary, start_body: BodyDef) -> String:
	if start.has("radius_km"):
		lvl.start_radius = _num(start, "radius_km", 0.0) * KM
	elif start.has("periapsis_km"):
		lvl.start_radius = _num(start, "periapsis_km", 0.0) * KM
	elif start.has("altitude_km"):
		lvl.start_radius = start_body.radius + _num(start, "altitude_km", 0.0) * KM
	else:
		return "start needs radius_km, periapsis_km, or altitude_km"
	# vis-viva divides by the start radius, so it must be a finite value > 0.
	if not is_finite(lvl.start_radius) or lvl.start_radius <= 0.0:
		return "start: radius/periapsis/altitude must give a finite radius above 0"

	if start.has("apoapsis_km") and start.has("eccentricity"):
		return "start: give apoapsis_km OR eccentricity, not both"
	if start.has("apoapsis_km"):
		lvl.start_apoapsis = _num(start, "apoapsis_km", 0.0) * KM
		if not is_finite(lvl.start_apoapsis) or lvl.start_apoapsis <= lvl.start_radius:
			return "start: apoapsis_km must be a finite value above the periapsis"
	elif start.has("eccentricity"):
		lvl.start_eccentricity = _num(start, "eccentricity", 0.0)
		if not is_finite(lvl.start_eccentricity) or lvl.start_eccentricity < 0.0:
			return "start: eccentricity must be a finite value >= 0"

	if String(start.get("at", "periapsis")) == "apoapsis":
		lvl.start_at_apoapsis = true
		if lvl.start_eccentricity >= 1.0:
			return "start: 'at: apoapsis' is invalid for an open (e>=1) orbit"
	if start.has("inclination_deg"):
		var inc := _num(start, "inclination_deg", 0.0)
		if not is_finite(inc):
			return "start: inclination_deg must be a finite number"
		lvl.start_inclination = deg_to_rad(inc)
	lvl.start_retrograde = bool(start.get("retrograde", false))
	return ""


static func _err(msg: String) -> Dictionary:
	return {"level": null, "error": msg}


static func _oerr(msg: String) -> Dictionary:
	return {"objective": null, "error": msg}


# --- untrusted-input guards -----------------------------------------------------
# A drop-in mod is untrusted JSON: any value can be the wrong type. These read
# values defensively so a malformed spec returns a readable error (never a crash
# from a typed coercion, and never a NaN/INF reaching the physics).

## `d[key]` as a finite float; `default` if absent; NAN if present but not a
## number (so callers reject via is_finite). Also catches JSON overflow to INF.
static func _num(d: Dictionary, key: String, default: float) -> float:
	if not d.has(key):
		return default
	var v: Variant = d[key]
	return float(v) if (v is int or v is float) else NAN


## "" if every checked number is finite and in range, else a readable error.
## `checks` entries are [value, name, mode] with mode "pos" (>0) / "nonneg" (>=0)
## / "finite".
static func _validate_nums(checks: Array) -> String:
	for c: Array in checks:
		var v: float = c[0]
		var name: String = c[1]
		if not is_finite(v):
			return "%s must be a finite number" % name
		if c[2] == "pos" and v <= 0.0:
			return "%s must be > 0" % name
		if c[2] == "nonneg" and v < 0.0:
			return "%s must be >= 0" % name
	return ""


## "" if `spec[key]` is absent or an object, else a readable error.
static func _object_or_absent(spec: Dictionary, key: String) -> String:
	if spec.has(key) and not (spec[key] is Dictionary):
		return "'%s' must be an object" % key
	return ""

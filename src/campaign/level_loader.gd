class_name LevelLoader
extends RefCounted
## Builds a LevelDef from a human-authored level dict (friendly units — km/deg —
## and bodies referenced by catalog name). from_dict returns
## {"level": LevelDef, "error": String}: a non-empty error means the spec was
## rejected with a readable reason (never a crash). Objective params convert
## km→m / deg→rad; RendezvousObjective.station_mu auto-fills from the root body;
## objective.target is the SAME instance placed in `moons` (identity matters).

const KM := 1000.0

## Anti-nightmare caps (tunable). Total bodies bound render/iteration cost;
## active (non-decorative) moons bound the expensive per-frame/refit SOI scan
## (child_soi_entry_time ~165ms/call). Scenery bodies are cheap — mark distant
## ones "decorative": true to stay under MAX_ACTIVE_MOONS.
const MAX_BODIES := 48
const MAX_ACTIVE_MOONS := 12


static func from_dict(spec: Dictionary, id: String) -> Dictionary:
	var root_name := String(spec.get("system", ""))
	if not BodyCatalog.has_body(root_name):
		return _err("unknown system body '%s'" % root_name)

	var moon_specs: Array = spec.get("bodies", [])
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

	var ship: Dictionary = spec.get("ship", {})
	lvl.dry_mass = float(ship.get("dry_mass", 0.0))
	lvl.prop_mass = float(ship.get("prop_mass", 0.0))
	lvl.thrust = float(ship.get("thrust", 0.0))
	lvl.isp = float(ship.get("isp", 0.0))

	var ob := _build_objective(spec.get("objective", {}), g)
	if ob.error != "":
		return _err(ob.error)
	lvl.objective = ob.objective

	lvl.dv_par = float(spec.get("dv_par", 0.0))
	lvl.difficulty = int(spec.get("difficulty", 1))
	lvl.rewind_budget = int(spec.get("rewind_budget", 1))
	var av: Dictionary = spec.get("avionics", {})
	lvl.sas_enabled = bool(av.get("sas", false))
	lvl.nodes_enabled = bool(av.get("nodes", false))

	lvl.map_extent = float(spec.get("map_extent_km", 360.0))       # minimap ortho, km units
	lvl.draw_limit = float(spec.get("draw_limit_km", 400.0)) * KM  # clip radius, metres
	lvl.fail_radius = float(spec.get("fail_radius_km", 0.0)) * KM  # 0 = no envelope

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
			ob.target_radius = float(o["radius_km"]) * KM
			ob.tolerance = float(o.get("tolerance_km", 0.0)) * KM
			if o.has("inclination_deg"):
				ob.target_inclination = deg_to_rad(float(o["inclination_deg"]))
			if o.has("inclination_tolerance_deg"):
				ob.inclination_tolerance = deg_to_rad(float(o["inclination_tolerance_deg"]))
			return {"objective": ob, "error": ""}
		"rendezvous":
			if not o.has("station_radius_km"):
				return _oerr("rendezvous needs station_radius_km")
			var ob := RendezvousObjective.new()
			ob.station_orbit_radius = float(o["station_radius_km"]) * KM
			ob.station_orbit_phase_deg = float(o.get("station_phase_deg", 0.0))
			ob.station_mu = (g.root as BodyDef).mu  # auto: authors never copy μ
			if o.has("max_distance_m"):
				ob.max_distance = float(o["max_distance_m"])
			if o.has("max_rel_speed_ms"):
				ob.max_rel_speed = float(o["max_rel_speed_ms"])
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
				ob.approach_falloff = float(o["approach_falloff_km"]) * KM
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
				ob.max_vertical = float(o["max_vertical_ms"])
			if o.has("max_horizontal_ms"):
				ob.max_horizontal = float(o["max_horizontal_ms"])
			return {"objective": ob, "error": ""}
		"entry_corridor":
			if not o.has("periapsis_km"):
				return _oerr("entry_corridor needs periapsis_km")
			var ob := EntryCorridorObjective.new()
			ob.target_periapsis = float(o["periapsis_km"]) * KM
			ob.tolerance = float(o.get("tolerance_km", 0.0)) * KM
			return {"objective": ob, "error": ""}
		_:
			return _oerr("unknown objective type '%s'" % t)


## Map the friendly `start` block to LevelDef's start-orbit fields. base radius =
## periapsis (or circular radius); shape = apoapsis_km OR eccentricity (≥1 open);
## `at` chooses periapsis (default) or apoapsis; plus inclination/retrograde.
## Returns "" on success or a readable error.
static func _apply_start(lvl: LevelDef, start: Dictionary, start_body: BodyDef) -> String:
	if start.has("radius_km"):
		lvl.start_radius = float(start["radius_km"]) * KM
	elif start.has("periapsis_km"):
		lvl.start_radius = float(start["periapsis_km"]) * KM
	elif start.has("altitude_km"):
		lvl.start_radius = start_body.radius + float(start["altitude_km"]) * KM
	else:
		return "start needs radius_km, periapsis_km, or altitude_km"

	if start.has("apoapsis_km") and start.has("eccentricity"):
		return "start: give apoapsis_km OR eccentricity, not both"
	if start.has("apoapsis_km"):
		lvl.start_apoapsis = float(start["apoapsis_km"]) * KM
		if lvl.start_apoapsis <= lvl.start_radius:
			return "start: apoapsis_km (%.0f) must exceed periapsis (%.0f)" % [
				lvl.start_apoapsis / KM, lvl.start_radius / KM]
	elif start.has("eccentricity"):
		lvl.start_eccentricity = float(start["eccentricity"])
		if lvl.start_eccentricity < 0.0:
			return "start: eccentricity must be >= 0"

	if String(start.get("at", "periapsis")) == "apoapsis":
		lvl.start_at_apoapsis = true
		if lvl.start_eccentricity >= 1.0:
			return "start: 'at: apoapsis' is invalid for an open (e>=1) orbit"
	if start.has("inclination_deg"):
		lvl.start_inclination = deg_to_rad(float(start["inclination_deg"]))
	lvl.start_retrograde = bool(start.get("retrograde", false))
	return ""


static func _err(msg: String) -> Dictionary:
	return {"level": null, "error": msg}


static func _oerr(msg: String) -> Dictionary:
	return {"objective": null, "error": msg}

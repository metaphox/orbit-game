class_name LevelDef
extends Resource
## Everything that defines a level. The runtime object is built by LevelLoader
## from a human-authored JSON file (assets/levels/ for the built-ins, the mods
## folders for community levels — the single authoring pipeline; see docs/LEVELS.md);
## it is no longer hand-authored as a .tres.

@export var id := ""       # stable slug (JSON/brief filename stem)
@export var title := ""
@export var body: BodyDef  # root body of the system
@export var moons: Array[BodyDef] = []
@export var start_body: BodyDef  # where the ship starts; null = the root body
## Starting orbit. start_radius is the circular radius, or the periapsis when a
## shape is given. Provide EITHER start_apoapsis (>periapsis, an ellipse) OR
## start_eccentricity (0=circular, <1 ellipse, ≥1 open/hyperbolic). start_at_apo
## begins the ship at apoapsis instead of periapsis (ellipses only). Defaults
## give the legacy circular-equatorial-prograde start, so old .tres are unchanged.
@export var start_radius := 0.0
@export var start_apoapsis := 0.0
@export var start_eccentricity := 0.0
@export var start_inclination := 0.0  # radians; tilts the starting plane about the apsis line
@export var start_at_apoapsis := false
@export var start_retrograde := false
@export var dry_mass := 0.0
@export var prop_mass := 0.0
@export var thrust := 0.0
@export var isp := 0.0
@export var objective: Objective
@export var dv_par := 0.0
## Informational challenge rating shown in the mission-select UI as 1–4 pips.
## Purely cosmetic — dv_par / medals / rewind_budget remain the real challenge.
@export_range(1, 4) var difficulty := 1
## Do-overs granted in this level for a Normal profile (DESIGN.md §14); a
## Hardcore profile forces this to 0. Authored per level to reflect its
## length/difficulty - a trainer grants 1, a long interplanetary run more.
@export var rewind_budget := 1
@export var map_extent := 360.0  # minimap ortho height, km units
@export var draw_limit := 4.0e5  # trajectory clip radius around the root body, m
@export var fail_radius := 0.0  # mission envelope around the root body; 0 = none

# Capability flags ("the flight computer"): granted per level as in-fiction
# avionics upgrades at act boundaries (DESIGN.md section 6).
@export var sas_enabled := false
@export var nodes_enabled := false


## The ship's initial {r, v} (DVec3, start-body frame) for the starting orbit.
## Defaults (e=0, no shape) reproduce the legacy circular-equatorial-prograde
## state exactly. Periapsis on +X, apoapsis on −X; prograde is −Z at periapsis,
## tilted by start_inclination about the +X apsis line.
func start_state(mu: float) -> Dictionary:
	var rp := start_radius
	var e := start_eccentricity
	if e == 0.0 and start_apoapsis > rp:
		e = (start_apoapsis - rp) / (start_apoapsis + rp)
	var at_apo := start_at_apoapsis and e < 1.0
	var r_mag := rp
	var speed := sqrt(mu * (1.0 + e) / rp)  # vis-viva at periapsis
	if at_apo:
		r_mag = rp * (1.0 + e) / (1.0 - e)   # apoapsis radius
		speed = sqrt(mu * (1.0 - e) / r_mag)  # vis-viva at apoapsis
	var pos := DVec3.new(-r_mag if at_apo else r_mag, 0.0, 0.0)
	var vz := speed if at_apo else -speed  # prograde: −Z at peri, +Z at apo
	if start_retrograde:
		vz = -vz
	var vel := DVec3.new(0.0, -vz * sin(start_inclination), vz * cos(start_inclination))
	return {"r": pos, "v": vel}


func medal(dv_used: float) -> String:
	if dv_used <= dv_par:
		return "GOLD ★★★"
	if dv_used <= dv_par * 1.2:
		return "SILVER ★★"
	return "BRONZE ★"

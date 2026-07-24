extends GutTest
## Characterization snapshot of the 7 built-in levels. It passes against the
## current registry and must stay green after the .tres → JSON migration — that's
## the proof the migration is behaviour-neutral. Values transcribed from the
## original src/levels/data/*.tres.

const EXPECTED := [
	{
		"index": 0, "title": "ORBIT SCHOOL 1: RAISE ORBIT",
		"body": "EARTH", "moons": [], "start": "EARTH", "start_radius": 70000.0,
		"ship": [1000.0, 250.0, 6000.0, 82.0],
		"dv_par": 75.0, "difficulty": 1, "map": 360.0, "draw": 4.0e5, "fail": 0.0,
		"sas": false, "nodes": false,
		"obj": {"type": "OrbitMatchObjective", "target_radius": 80000.0, "tolerance": 1500.0,
			"target_inclination": 0.0, "inclination_tolerance": PI},
	},
	{
		"index": 1, "title": "ORBIT SCHOOL 2: RENDEZVOUS",
		"body": "EARTH", "moons": [], "start": "EARTH", "start_radius": 70000.0,
		"ship": [1000.0, 250.0, 6000.0, 82.0],
		"dv_par": 160.0, "difficulty": 2, "map": 360.0, "draw": 4.0e5, "fail": 0.0,
		"sas": true, "nodes": false,
		"obj": {"type": "RendezvousObjective", "station_orbit_radius": 90000.0,
			"station_orbit_phase_deg": 40.10704565915762, "station_mu": 76760000000.0},
	},
	{
		"index": 2, "title": "ORBIT SCHOOL 3: PLANE CHANGE",
		"body": "EARTH", "moons": [], "start": "EARTH", "start_radius": 70000.0,
		"ship": [1000.0, 750.0, 6000.0, 82.0],
		"dv_par": 350.0, "difficulty": 2, "map": 360.0, "draw": 4.0e5, "fail": 0.0,
		"sas": true, "nodes": false,
		"obj": {"type": "OrbitMatchObjective", "target_radius": 70000.0, "tolerance": 1500.0,
			"target_inclination": 0.2617993877991494, "inclination_tolerance": 0.01745329251994329},
	},
	{
		"index": 3, "title": "LUNAR PROGRAM 1: TRANSLUNAR INJECTION",
		"body": "EARTH", "start": "EARTH", "start_radius": 70000.0,
		"moons": [{"name": "MOON", "orbit": 3844000.0, "phase": 114.59155902616465, "soi": 660000.0}],
		"ship": [1000.0, 1500.0, 12000.0, 82.0],
		"dv_par": 600.0, "difficulty": 3, "map": 9200.0, "draw": 6.0e6, "fail": 8.0e6,
		"sas": true, "nodes": true,
		"obj": {"type": "TransferCaptureObjective", "target": "MOON"},
	},
	{
		"index": 4, "title": "LUNAR PROGRAM 2: MARE SERENITATIS",
		"body": "EARTH", "start": "MOON", "start_radius": 25000.0,
		"moons": [{"name": "MOON", "orbit": 3844000.0, "phase": 114.59155902616465, "soi": 660000.0}],
		"ship": [1000.0, 650.0, 12000.0, 82.0],
		"dv_par": 280.0, "difficulty": 3, "map": 9200.0, "draw": 6.0e6, "fail": 8.0e6,
		"sas": true, "nodes": true,
		"obj": {"type": "AirlessLandingObjective", "target": "MOON"},
	},
	{
		"index": 5, "title": "LUNAR PROGRAM 3: COME HOME",
		"body": "EARTH", "start": "MOON", "start_radius": 25000.0,
		"moons": [{"name": "MOON", "orbit": 3844000.0, "phase": 114.59155902616465, "soi": 660000.0}],
		"ship": [1000.0, 450.0, 12000.0, 82.0],
		"dv_par": 150.0, "difficulty": 3, "map": 9200.0, "draw": 6.0e6, "fail": 8.0e6,
		"sas": true, "nodes": true,
		"obj": {"type": "EntryCorridorObjective", "target_periapsis": 66000.0, "tolerance": 800.0},
	},
	{
		"index": 6, "title": "INTERPLANETARY 1: EARTH TO MARS",
		"body": "SOL", "start": "EARTH", "start_radius": 70000.0,
		"moons": [
			{"name": "EARTH", "orbit": 40000000.0, "phase": 0.0, "soi": 9240000.0},
			{"name": "MARS", "orbit": 60000000.0, "phase": 43.76, "soi": 3000000.0}],
		"ship": [1200.0, 2300.0, 15000.0, 90.0],
		"dv_par": 700.0, "difficulty": 4, "map": 145000.0, "draw": 9.0e7, "fail": 1.3e8,
		"sas": true, "nodes": true,
		"obj": {"type": "TransferCaptureObjective", "target": "MARS", "approach_falloff": 3000000.0},
	},
]


func test_all_seven_levels_match_snapshot() -> void:
	assert_eq(Campaign.level_count(), EXPECTED.size(), "still 7 built-in levels")
	for e: Dictionary in EXPECTED:
		var lvl := Campaign.level_at(e["index"])
		var tag: String = e["title"]
		assert_eq(lvl.title, e["title"], "%s: title" % tag)
		assert_eq(lvl.body.name, e["body"], "%s: root body" % tag)
		var start_name := lvl.start_body.name if lvl.start_body != null else lvl.body.name
		assert_eq(start_name, e["start"], "%s: effective start body" % tag)
		assert_almost_eq(lvl.start_radius, e["start_radius"], 0.001, "%s: start_radius" % tag)
		assert_almost_eq(lvl.dv_par, e["dv_par"], 0.001, "%s: dv_par" % tag)
		assert_eq(lvl.difficulty, e["difficulty"], "%s: difficulty" % tag)
		assert_almost_eq(lvl.map_extent, e["map"], 0.001, "%s: map_extent" % tag)
		assert_almost_eq(lvl.draw_limit, e["draw"], 1.0, "%s: draw_limit" % tag)
		assert_almost_eq(lvl.fail_radius, e["fail"], 1.0, "%s: fail_radius" % tag)
		assert_eq(lvl.sas_enabled, e["sas"], "%s: sas" % tag)
		assert_eq(lvl.nodes_enabled, e["nodes"], "%s: nodes" % tag)
		var ship: Array = e["ship"]
		assert_almost_eq(lvl.dry_mass, ship[0], 0.001, "%s: dry_mass" % tag)
		assert_almost_eq(lvl.prop_mass, ship[1], 0.001, "%s: prop_mass" % tag)
		assert_almost_eq(lvl.thrust, ship[2], 0.001, "%s: thrust" % tag)
		assert_almost_eq(lvl.isp, ship[3], 0.001, "%s: isp" % tag)
		_check_moons(lvl, e["moons"], tag)
		_check_objective(lvl, e["obj"], tag)


func _check_moons(lvl: LevelDef, expected: Array, tag: String) -> void:
	assert_eq(lvl.moons.size(), expected.size(), "%s: moon count" % tag)
	for i in expected.size():
		var m: BodyDef = lvl.moons[i]
		var em: Dictionary = expected[i]
		assert_eq(m.name, em["name"], "%s: moon %d name" % [tag, i])
		assert_almost_eq(m.orbit_radius, em["orbit"], 0.001, "%s: %s orbit" % [tag, m.name])
		assert_almost_eq(m.orbit_phase_deg, em["phase"], 1e-6, "%s: %s phase" % [tag, m.name])
		assert_almost_eq(m.soi_radius, em["soi"], 0.001, "%s: %s soi" % [tag, m.name])


func _check_objective(lvl: LevelDef, exp: Dictionary, tag: String) -> void:
	var o := lvl.objective
	match exp["type"]:
		"OrbitMatchObjective":
			assert_true(o is OrbitMatchObjective, "%s: OrbitMatch" % tag)
			var om := o as OrbitMatchObjective
			assert_almost_eq(om.target_radius, exp["target_radius"], 0.001, "%s: target_radius" % tag)
			assert_almost_eq(om.tolerance, exp["tolerance"], 0.001, "%s: tolerance" % tag)
			assert_almost_eq(om.target_inclination, exp["target_inclination"], 1e-9, "%s: inc" % tag)
			assert_almost_eq(om.inclination_tolerance, exp["inclination_tolerance"], 1e-9, "%s: inc_tol" % tag)
		"RendezvousObjective":
			assert_true(o is RendezvousObjective, "%s: Rendezvous" % tag)
			var rv := o as RendezvousObjective
			assert_almost_eq(rv.station_orbit_radius, exp["station_orbit_radius"], 0.001, "%s: station r" % tag)
			assert_almost_eq(rv.station_orbit_phase_deg, exp["station_orbit_phase_deg"], 1e-6, "%s: station phase" % tag)
			assert_almost_eq(rv.station_mu, exp["station_mu"], 0.001, "%s: station mu" % tag)
		"TransferCaptureObjective":
			assert_true(o is TransferCaptureObjective, "%s: Transfer" % tag)
			var tc := o as TransferCaptureObjective
			assert_eq(tc.target.name, exp["target"], "%s: target" % tag)
			assert_same(tc.target, _moon_named(lvl, exp["target"]), "%s: target IS the moons entry" % tag)
			if exp.has("approach_falloff"):
				assert_almost_eq(tc.approach_falloff, exp["approach_falloff"], 1.0, "%s: falloff" % tag)
		"AirlessLandingObjective":
			assert_true(o is AirlessLandingObjective, "%s: Landing" % tag)
			var al := o as AirlessLandingObjective
			assert_eq(al.target.name, exp["target"], "%s: target" % tag)
			assert_same(al.target, _moon_named(lvl, exp["target"]), "%s: target IS the moons entry" % tag)
		"EntryCorridorObjective":
			assert_true(o is EntryCorridorObjective, "%s: Entry" % tag)
			var ec := o as EntryCorridorObjective
			assert_almost_eq(ec.target_periapsis, exp["target_periapsis"], 0.001, "%s: periapsis" % tag)
			assert_almost_eq(ec.tolerance, exp["tolerance"], 0.001, "%s: tolerance" % tag)


func _moon_named(lvl: LevelDef, body_name: String) -> BodyDef:
	for m: BodyDef in lvl.moons:
		if m.name == body_name:
			return m
	return null

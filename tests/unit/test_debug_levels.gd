extends "res://tests/unit/base_orbit_test.gd"
## Debug-only performance test levels: a full solar system (real epoch positions,
## moons decorative — a rendering/ephemeris showcase) and a pathological
## 12-active-moon belt (the ~3.6 s worst-case SOI scan, the living companion to
## test_perf_heavy_level). Available only in a debug build (OS.has_feature
## "debug"); surfaced as a DEBUG section in LevelSelect via the custom-launch path.

const SOLAR := "res://levels/debug/solar_system.json"
const PATHO := "res://levels/debug/pathological_12moon.json"
const GameRootScript := preload("res://src/game_root.gd")


func before_each() -> void:
	CommunityLevels.override_for_test([])  # isolate from the dev machine's real mods folder


func after_each() -> void:
	DebugLevels.reload()
	CommunityLevels.reload()
	GameRootScript.custom_level = null  # static; don't leak a debug launch across tests


func _load(path: String) -> Dictionary:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(path)), OK, "%s is valid JSON" % path)
	return LevelLoader.from_dict(json.data, path.get_file().get_basename())


# --- debug body catalog: twelve moons of one planet --------------------------

func test_debug_catalog_supplies_twelve_moons_of_one_planet() -> void:
	for i in 12:
		assert_true(BodyCatalog.has_body("DBG_MOON_%02d" % i), "debug moon %02d is catalogued" % i)
	var g := BodyCatalog.build("EARTH", [{"name": "DBG_MOON_00"}, {"name": "DBG_MOON_01"}])
	for m: BodyDef in g.moons:
		assert_same(m.parent, g.root, "each debug moon orbits the level root (EARTH)")


# --- the two levels load and have the intended shape -------------------------

func test_solar_system_level_loads_with_decorative_moons() -> void:
	var r := _load(SOLAR)
	assert_eq(r.error, "", "solar system loads without error")
	var lvl: LevelDef = r.level
	assert_gt(lvl.moons.size(), 12, "the whole catalogued system is present")
	var active := 0
	for m: BodyDef in lvl.moons:
		if not m.decorative:
			active += 1
	assert_lte(active, LevelLoader.MAX_ACTIVE_MOONS,
		"moons are decorative, so active bodies stay under the loader cap")


func test_pathological_level_has_twelve_active_children() -> void:
	var r := _load(PATHO)
	assert_eq(r.error, "", "pathological level loads without error")
	var lvl: LevelDef = r.level
	var active := 0
	for m: BodyDef in lvl.moons:
		if not m.decorative and m.parent == lvl.body:
			active += 1
	assert_eq(active, 12, "twelve active children of the root — the SOI-scan stress")


func test_pathological_start_orbit_spans_the_whole_belt() -> void:
	# The level only stresses the scan if the ship's start-orbit radial band spans
	# the belt, so broad-phase can't reject any moon (the ~3.6 s worst case). If it
	# didn't, the level would silently be cheap and stop testing what it's for.
	var r := _load(PATHO)
	var lvl: LevelDef = r.level
	var ship := ShipSim.new()
	ship.setup(lvl)
	var reachable := 0
	for m: BodyDef in lvl.moons:
		if not m.decorative and OrbitEvents._radial_bands_gap(ship.elements, m.orbit) <= m.soi_radius:
			reachable += 1
	assert_eq(reachable, 12, "all 12 moons lie within the start orbit's band — none broad-phase-rejected")


# --- DebugLevels source (gated to debug builds) ------------------------------

func test_debug_levels_load_in_a_debug_build() -> void:
	# Tests run with OS.has_feature("debug") == true, so the bundled levels load.
	var ids: Array = []
	for e: Dictionary in DebugLevels.all():
		ids.append(e["id"])
		assert_not_null(e["level"], "debug level '%s' loaded cleanly" % e["id"])
	assert_true(ids.has("solar_system"), "the solar system is offered")
	assert_true(ids.has("pathological_12moon"), "the 12-moon stress level is offered")


func _section_titles(menu: LevelSelect) -> Array:
	var titles: Array = []
	for child in menu._shell.left_column.get_children():
		if child is MarginContainer and child.get_child_count() > 0 and child.get_child(0) is Label:
			titles.append((child.get_child(0) as Label).text)
	return titles


func test_debug_section_absent_when_source_is_empty() -> void:
	DebugLevels.override_for_test([])
	var menu := LevelSelect.new()
	add_child_autofree(menu)
	menu.build(Profile.new(), SandboxStore.new())
	assert_false(_section_titles(menu).has("DEBUG"), "no DEBUG section when the source is empty")


func test_debug_section_present_with_debug_levels() -> void:
	var r := _load(PATHO)
	DebugLevels.override_for_test([
		{"id": "pathological_12moon", "level": r.level, "dir": "res://levels/debug", "error": ""}])
	var menu := LevelSelect.new()
	add_child_autofree(menu)
	menu.build(Profile.new(), SandboxStore.new())
	assert_true(_section_titles(menu).has("DEBUG"), "a DEBUG section appears when debug levels exist")


func test_debug_card_launches_via_the_custom_path() -> void:
	# End-to-end: activating a DEBUG card routes through the same custom-launch
	# path community levels use (community_chosen -> _launch_custom), so debug
	# levels fly without a campaign index and don't touch profile progression.
	var r := _load(SOLAR)
	DebugLevels.override_for_test([
		{"id": "solar_system", "level": r.level, "dir": "res://levels/debug", "error": ""}])
	var screen := LevelSelect.new()
	add_child_autofree(screen)
	screen.build(Profile.new(), SandboxStore.new())

	var pos := -1
	for i in screen._entries.size():
		if screen._entries[i].get("id", "") == "solar_system":
			pos = i
	assert_gt(pos, -1, "the debug level has a selectable card")

	var chosen := {}
	screen.community_chosen.connect(func(id: String, lvl: LevelDef) -> void:
		chosen["id"] = id
		chosen["lvl"] = lvl)
	screen._select_and_activate(pos)
	assert_eq(chosen.get("id", ""), "solar_system", "activating the debug card fires the custom-launch path")
	assert_same(chosen.get("lvl"), r.level, "with the debug LevelDef")


func test_solar_system_boots_and_flies_in_the_real_game_loop() -> void:
	# End-to-end: fly the debug level as GameRoot.custom_level and confirm the full
	# body graph builds and it reaches FLYING (the pathological level's scan cost is
	# covered by test_perf_heavy_level, so only the cheap one boots here).
	var r := _load(SOLAR)
	GameRootScript.custom_level = r.level
	var game: Node = load("res://src/main.tscn").instantiate()
	add_child_autofree(game)
	simulate(game, 3, 1.0 / 60.0)
	assert_eq(game.phase, game.Phase.FLYING, "the solar system boots into flight")
	assert_eq(game.level.moons.size(), 18, "all 18 non-root bodies are present")
	assert_eq(game.ship.body.name, "EARTH", "the ship starts parked at Earth")

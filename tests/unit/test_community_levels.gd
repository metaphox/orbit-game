extends GutTest
## CommunityLevels loads drop-in level files, skipping bad ones without crashing.

const DIR := "user://test_mods"

const GOOD := '{"title":"Custom","system":"EARTH","start":{"radius_km":70},' \
	+ '"ship":{"dry_mass":1000,"prop_mass":300,"thrust":6000,"isp":82},' \
	+ '"objective":{"type":"orbit_match","radius_km":120,"tolerance_km":2},"dv_par":140}'


func before_each() -> void:
	var root := DirAccess.open("user://")
	if not root.dir_exists("test_mods"):
		root.make_dir("test_mods")
	var d := DirAccess.open(DIR)
	for f: String in d.get_files():
		d.remove(f)


func _write(name: String, text: String) -> void:
	var f := FileAccess.open(DIR.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_scan_dir_lists_only_json() -> void:
	_write("a.json", GOOD)
	_write("notes.txt", "ignore me")
	var found := ModPaths.scan_dir(DIR)
	assert_eq(found.size(), 1, "only .json files are scanned")
	assert_eq(found[0]["id"], "a", "id is the filename stem")


func test_loads_valid_and_skips_malformed() -> void:
	_write("cool_mission.json", GOOD)
	_write("broken.json", "not json at all")
	_write("bad_body.json", '{"system":"PLANET_X","objective":{"type":"orbit_match","radius_km":1,"tolerance_km":1}}')
	var levels := CommunityLevels.load_from_dirs([DIR])
	var by := {}
	for e: Dictionary in levels:
		by[e["id"]] = e
	assert_eq(by.size(), 3, "every file is reported (loaded or skipped)")
	assert_not_null(by["cool_mission"]["level"], "a valid level loads")
	assert_eq(by["cool_mission"]["error"], "")
	assert_eq((by["cool_mission"]["level"] as LevelDef).id, "cool_mission", "id = filename stem")
	assert_null(by["broken"]["level"], "malformed JSON is skipped")
	assert_ne(by["broken"]["error"], "")
	assert_null(by["bad_body"]["level"], "an invalid (unknown body) level is skipped")
	assert_true(by["bad_body"]["error"].contains("PLANET_X"))


func test_first_dir_wins_on_id_clash() -> void:
	_write("dup.json", GOOD)
	var second := "user://test_mods2"
	DirAccess.open("user://").make_dir("test_mods2")
	var f := FileAccess.open(second.path_join("dup.json"), FileAccess.WRITE)
	f.store_string(GOOD); f.close()
	var levels := CommunityLevels.load_from_dirs([DIR, second])
	var count := 0
	for e: Dictionary in levels:
		if e["id"] == "dup":
			count += 1
	assert_eq(count, 1, "a duplicate id across folders is loaded once (first wins)")

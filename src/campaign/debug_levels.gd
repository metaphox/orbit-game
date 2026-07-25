class_name DebugLevels
extends RefCounted
## Bundled, DEBUG-ONLY performance test levels (res://levels/debug), loaded through
## the same LevelLoader the built-ins and community levels use. Present only in a
## debug build (OS.has_feature("debug")) so they never appear in a release mission
## list; surfaced as a DEBUG section in LevelSelect and flown via the custom-level
## launch path (no campaign progression). See .claude/plans/debug-perf-test-levels.md.

## A fixed list (not a res:// dir scan) so it's export-safe and obvious.
const PATHS := [
	"res://levels/debug/solar_system.json",
	"res://levels/debug/pathological_12moon.json",
]

static var _cache: Array = []
static var _loaded := false


## [{id, level: LevelDef|null, dir, error}] per bundled debug level, or [] in a
## non-debug build. Cached until reload().
static func all() -> Array:
	if not _loaded:
		_cache = _scan() if OS.has_feature("debug") else []
		_loaded = true
	return _cache


static func reload() -> void:
	_loaded = false


## Test seam: force the debug set (bypassing the gate + filesystem) so LevelSelect
## rendering is deterministic regardless of build flags. Pair with reload() in teardown.
static func override_for_test(entries: Array) -> void:
	_cache = entries
	_loaded = true


static func _scan() -> Array:
	var out: Array = []
	for path: String in PATHS:
		out.append(_load_one(path))
	return out


static func _load_one(path: String) -> Dictionary:
	var id := path.get_file().get_basename()
	var dir := path.get_base_dir()
	if not FileAccess.file_exists(path):
		return {"id": id, "level": null, "dir": dir, "error": "not found"}
	var json := JSON.new()  # instance parse: no engine-error spam on a bad file
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return {"id": id, "level": null, "dir": dir, "error": "not valid JSON (line %d)" % json.get_error_line()}
	var r := LevelLoader.from_dict(json.data, id)
	if r.error != "":
		push_warning("debug level '%s' skipped: %s" % [id, r.error])
	return {"id": id, "level": r.level, "dir": dir, "error": r.error}

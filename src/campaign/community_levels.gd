class_name CommunityLevels
extends RefCounted
## Loads drop-in community levels from the ModPaths folders through the same
## LevelLoader the built-ins use. Each level gets a string ID (its filename
## stem); a file that fails to parse/validate is skipped with a logged reason,
## not fatal. Results are cached until reload().

## A level file is tiny (a few KB); cap reads so a stray huge/binary file dropped
## in the mods folder can't be slurped whole into memory.
const MAX_FILE_KB := 256
const MAX_FILE_BYTES := MAX_FILE_KB * 1024

static var _cache: Array = []
static var _loaded := false


## [{id, level: LevelDef|null, dir, error}] for every *.json found, cached.
static func all() -> Array:
	if not _loaded:
		_cache = load_from_dirs(ModPaths.dirs())
		_loaded = true
	return _cache


static func reload() -> void:
	_loaded = false


## Test seam: force the community set (bypassing the filesystem scan) so tests
## that exercise the mission list are deterministic regardless of the dev
## machine's real mods folder. Pair with reload() in teardown to restore scanning.
static func override_for_test(entries: Array) -> void:
	_cache = entries
	_loaded = true


static func level_for(id: String) -> LevelDef:
	for e: Dictionary in all():
		if e["id"] == id:
			return e["level"]
	return null


## Testable core: scan the given dirs, load each JSON. First dir wins on id clash.
static func load_from_dirs(dirs: Array) -> Array:
	var out: Array = []
	var seen := {}
	for dir: String in dirs:
		for entry: Dictionary in ModPaths.scan_dir(dir):
			var id: String = entry["id"]
			if seen.has(id):
				continue
			seen[id] = true
			out.append(_load_one(id, entry["path"], dir))
	return out


static func _load_one(id: String, path: String, dir: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:  # permission / race / vanished between scan and read
		return {"id": id, "level": null, "dir": dir,
			"error": "could not open (error %d)" % FileAccess.get_open_error()}
	if f.get_length() > MAX_FILE_BYTES:
		return {"id": id, "level": null, "dir": dir,
			"error": "file too large (> %d KB) to be a level" % MAX_FILE_KB}
	var text := f.get_as_text()
	var json := JSON.new()  # instance parse: no engine-error spam on a bad mod file
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {"id": id, "level": null, "dir": dir, "error": "not valid JSON (line %d)" % json.get_error_line()}
	var r := LevelLoader.from_dict(json.data, id)
	if r.error != "":
		push_warning("community level '%s' skipped: %s" % [id, r.error])
	return {"id": id, "level": r.level, "dir": dir, "error": r.error}
